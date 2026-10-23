#!/usr/bin/env python3
"""The NPC item price table: one source of truth for what an NPC pays for an item (server/README.md "Item prices").

usage:
  python3 -I server/tools/gen_item_prices.py                  write the generated files (below)
  python3 -I server/tools/gen_item_prices.py --check          CI: exit 1 when a generated file is out of date or a rule
                                                              fails (coverage, arbitrage, the Auto Seller's table)
  python3 -I server/tools/gen_item_prices.py report [--base BASE_DATA]
                                                              the problem counts (before: the base NPC prices, needs
                                                              BASE_DATA; after: this table) and the price bands
  python3 -I server/tools/gen_item_prices.py income BASE_DATA  hunting gold per hour per level band, old and new prices
  python3 -I server/tools/gen_item_prices.py survey BASE_DATA  rewrite the committed snapshot of the base server
                                                              (data/items/base_item_values.csv, base_recipes.csv)

Inputs (all in the repo; the base server is read only by `survey`, `income` and `report --base`):
  data/items/base_item_values.csv   snapshot of every base item a monster drops, a recipe makes, an NPC trades or a Chaos
                                    reward hands out: category, slot, level requirement, NPC sell / buy prices, loot
                                    sources (no names: the base names are not ours)
  data/items/base_recipes.csv       the base crafting recipes (product, count, gold cost, materials)
  data/items/item_price_rules.csv   overrides: id, category, price, note (a fixed price or a category such as quest)
  the Chaos sources: art_items.csv (creature products, food), fist_items.csv, gear_sets.csv (pair 28), the gems, supports and charms configs,
  the uniques (chaos_items.xml), the professions, orbs, omens, Ascended items, faction tokens, pouches, the Everfull
  Ration, the store's items (shop_config.lua) and every Chaos monster's loot (monsters/chaos, monster/lua/chaos)
Outputs (generated, committed, CI diffs them):
  data/lib/chaos_item_prices_data.lua    prices, unsellable ids with their reason, the multipliers;
                                         read by data/lib/chaos_item_prices.lua (ChaosItemPrices)
  data/scripts/chaos/sell_prices.lua     the same id prices as a flat table, for the Auto Seller (autosell.lua)

The rules (README "Item prices"):
  base(id)  price of a plain copy:
    - not sellable: currency (coins, orbs, tokens, shards), keys, quest items, store and store-bound items, the
      professions' materials (the Material Broker buys those at its weekly price), uniques (salvage or market)
    - a fixed price from item_price_rules.csv or a Chaos source (creature products, fist weapons, gems, supports,
      charms) when one is set
    - else the base server's NPC price (the highest an NPC in the game pays: spawned or created by a script) when there
      is one ("keep the base where it is sane")
    - else a formula: equipment by its level requirement and slot (EQUIP_CURVE x SLOT_FACTOR); everything else by the
      level of the lowest monster that drops it and its best drop chance (LOOT_CURVE x CHANCE_FACTOR: rarer is worth
      more)
    - equipment (not fixed): x GEAR_SCALE = 1 / the expected rarity multiplier of a monster's gear drop, so an average
      drop is worth what it was and a rarer copy more
    - floors: a drop of monsters of level 200+ is worth at least LATE_FLOOR of its formula value (no late-game drop
      below early trash); a crafted item at least what its materials sell for (equipment: CRAFT_GEAR_SHARE of it);
      MIN_PRICE for anything sellable
    - caps: crafted equipment at most CRAFT_HOURS of hunting gold at its level band; equipment so low that the
      Wandering Merchant's rarity orbs (Gilding, Fate) on a plain copy do not pay (MERCHANT_MARGIN); a base the Gambler sells: its expected sale stays under his price at every level (GAMBLE_MARGIN); at most
      BUY_SHARE of what the NPCs ask for it (median of their gold prices), SUPPLY_SHARE for supplies (potions, runes,
      ammunition). install_item_prices.py raises every NPC buy price below twice the sell price.
  price of an instance = base(id) x R(rarity) x L(item level)  (ChaosItemPrices.sellPrice(item))
    R: plain 1, Common 1, Uncommon 1.5, Magic 3, Rare 6, Legendary 12, Divine 24 (the seven rarities of 2026-10-18; it was
       Common 1 .. Legendary 12, then +2 a tier up to Transcendent 32 over 15 rarities); charms
       Faint 1, Glowing 1.5, Radiant 3; a unique copy is not sold (0)
    L: 1 + item level / ILVL_DIV for equipment and charms (item level 150: x1.75), else 1
"""
import argparse
import csv
import io
import math
import os
import re
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
DATA = os.path.join(SERVER, 'data')
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import item_prices_base as B  # noqa: E402

SNAPSHOT = os.path.join(DATA, 'items', 'base_item_values.csv')
RECIPES = os.path.join(DATA, 'items', 'base_recipes.csv')
RULES = os.path.join(DATA, 'items', 'item_price_rules.csv')
OUT_LUA = os.path.join(DATA, 'lib', 'chaos_item_prices_data.lua')
OUT_SELL = os.path.join(DATA, 'scripts', 'chaos', 'sell_prices.lua')

# ------------------------------------------------------------------------------------------------ the numbers
RARITY_MULT = [1, 1.5, 3, 6, 12, 24]  # by place: Common, Uncommon, Magic, Rare, Legendary, Divine (data/lib/chaos_rarity.lua)
# stored rarity id -> place; an old item may carry 6 .. 9 (they became Legendary) and 11 .. 15 (Divine)
LEGACY_TO_STORED = [1, 2, 3, 4, 5, 5, 5, 5, 5, 10, 10, 10, 10, 10, 10]
STORED_IDS = [1, 2, 3, 4, 5, 10]


def rank_of(rarity):
    """place 1..6 of a rarity id (0 = none)"""
    rarity = int(rarity)
    if rarity < 1 or rarity > 15:
        return 0
    return STORED_IDS.index(LEGACY_TO_STORED[rarity - 1]) + 1
CHARM_MULT = [1, 1.5, 3]  # charm rarity 1..3 (Faint, Glowing, Radiant)
ILVL_DIV = 200  # L = 1 + item level / ILVL_DIV (item level 150: x1.75)
# Plain equipment sells for GEAR_SCALE of the price it had (base NPC price or formula): 42% of the gear monsters drop
# carries a rarity (loot_config.lua gear), and the rarity multipliers bring the average drop back to about the old
# value. Computed from the loot layer's odds: 1 / the expected rarity multiplier of a normal monster's gear drop.
GEAR_SCALE = None  # set in main() from expected_rarity_mult(); fixed prices of item_price_rules.csv are not scaled
BUY_SHARE = 0.5  # sell <= this x the NPCs' asking price
SUPPLY_SHARE = 0.2  # potions, runes, ammunition: sell <= this x the asking price
LATE_LEVEL, LATE_FLOOR = 200, 0.25
MIN_PRICE = 2
GAMBLE_MARGIN = 0.9  # a Gambler base sells to an NPC for at most 90% of its expected value at the Gambler's price
# a crafted item sells for at least this share of what its materials sell for: 1.0 for materials made of materials,
# CRAFT_GEAR_SHARE for equipment, whose copies roll a rarity and item level on top (craft_bonus_config.lua: the
# expected R x L of a crafted copy is at most ~1.9 (craft_ev), so 0.4 keeps the expected sale under the materials)
CRAFT_GEAR_SHARE = 0.2  # owner 2026-10-14 (was 0.4)
# crafted equipment: a plain copy is worth at most CRAFT_HOURS of hunting gold at its level band (gamble_config.lua
# balance.hunting; the band: its level requirement or the highest lowest-monster level of its materials)
CRAFT_HOURS = 1.0
# the Wandering Merchant's rarity orbs (invasion_config.lua): gilding or re-rolling a plain item and selling it must not
# pay; every equipment price is capped so the expected gain at item level 150 stays under MERCHANT_MARGIN of the orb
MERCHANT_MARGIN = 0.9
# plain equipment without an NPC price, by its level requirement (gold at item level 0)
EQUIP_CURVE = [(0, 200), (20, 1000), (50, 8000), (80, 20000), (120, 30000), (200, 45000), (300, 60000), (500, 90000),
               (800, 130000), (1000, 160000), (1500, 220000)]
SLOT_FACTOR = {'two-handed': 1.2, 'weapon': 1.0, 'shield': 0.9, 'body': 1.1, 'head': 0.9, 'legs': 0.9, 'feet': 0.8,
               'necklace': 0.8, 'ring': 0.8, 'beltgloves': 0.7, 'backpack': 0.3, 'deckbadge': 0.5, 'ship': 0.5,
               'right-hand': 0.9, 'ammo': 0.02, 'equip': 1.0}
# other loot without an NPC price, by the level of the lowest monster that drops it
LOOT_CURVE = [(1, 15), (20, 50), (50, 150), (100, 350), (200, 900), (300, 2500), (500, 6000), (800, 12000),
              (1200, 20000), (2000, 30000)]
CHANCE_FACTOR = [(25000, 0.5), (5000, 1.0), (1000, 2.0), (200, 4.0), (0, 8.0)]  # best chance (1/100000) -> factor
GEM_PRICES = [400, 1200, 3600, 10800, 32400]  # Chipped .. Perfect: three combine into one, so at most x3 a tier
SUPPORT_PRICES = [500, 1500, 4500, 13500, 40500]  # support levels 1..5
CHARM_PRICES = {'small': 2000, 'tall': 4000, 'wide': 4000, 'grand': 8000}

UNSELLABLE = ('currency', 'key', 'quest', 'store', 'bound', 'broker', 'unique')
REASON_TEXT = {
    'currency': 'currency: coins, orbs, tokens and shards keep their own value (bank, Orb Exchange, the systems that spend them)',
    'key': 'a key or a key part: used up by the content it opens',
    'quest': 'a quest item',
    'store': 'sold in the Chaos store for coins: no coin -> gold path through an NPC',
    'bound': 'store-bound: cannot be traded, sold or dropped',
    'broker': 'a profession material: the Material Broker buys it at its weekly price (Professions)',
    'unique': 'unique: salvage or market (owner 2026-10-14: a chase item, no NPC floor)',
}
COINS = {2148, 2152, 2160, 28872, 28873}
SUPPLY_WEAPONS = ('ammunition',)


def curve(points, x):
    if x <= points[0][0]:
        return points[0][1]
    for (x1, y1), (x2, y2) in zip(points, points[1:]):
        if x <= x2:
            return y1 + (y2 - y1) * (x - x1) / float(x2 - x1)
    return points[-1][1]


def chance_factor(chance):
    for lo, f in CHANCE_FACTOR:
        if chance >= lo:
            return f
    return CHANCE_FACTOR[-1][1]


def nice(v):
    """round a computed price to two significant digits (5 under 100)"""
    v = int(round(v))
    if v < 10:
        return max(v, 1)
    if v < 100:
        return int(round(v / 5.0)) * 5
    step = 10 ** (len(str(v)) - 2)
    return int(round(v / float(step))) * step


def read(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


# ------------------------------------------------------------------------------------------------ survey (base data)
EQUIP_SLOTS = {'head', 'body', 'legs', 'feet', 'necklace', 'ring', 'two-handed', 'beltgloves', 'backpack', 'deckbadge',
               'ship', 'right-hand'}
WEAPONS = {'sword', 'axe', 'club', 'wand', 'shield', 'distance'}
QUEST_PATTERNS = ()  # quest items are listed by id in item_price_rules.csv


def survey_category(iid, info):
    name = info['name'].lower()
    a = info['attrs']
    if iid in COINS or (re.search(r'\bcoins?$', name) and 'chocolate' not in name):
        return 'currency'
    if re.search(r'\btokens?\b|\btickets?\b', name):
        return 'currency'
    if re.search(r'\bkeys?\b', name):
        return 'key'
    if a.get('weapontype') == 'ammunition' or a.get('slottype') == 'ammo':
        return 'supply'
    if name.endswith(' potion') or a.get('type') == 'rune' or name.endswith(' rune'):
        return 'supply'
    if a.get('weapontype') == 'distance' and 'ammotype' not in a and a.get('slottype') != 'two-handed':
        return 'supply'  # spears and stars
    if a.get('slottype') in EQUIP_SLOTS or a.get('weapontype') in WEAPONS:
        return 'equip'
    return 'material'


def survey_slot(info):
    a = info['attrs']
    if a.get('slottype') in EQUIP_SLOTS:
        return a['slottype']
    if a.get('weapontype') == 'shield':
        return 'shield'
    if a.get('weapontype') in WEAPONS:
        return 'weapon'
    if a.get('slottype') == 'ammo' or a.get('weapontype') == 'ammunition':
        return 'ammo'
    return ''


def reward_ids():
    """item ids the Chaos reward configs hand out (raids, Descent, factions, journey, new players)"""
    ids = set()
    for f in ('raid_config', 'descent_config', 'factions_config', 'season_journey_config', 'newplayer_config',
              'invasion_config', 'battleground_config', 'pvpzone_config', 'mentor_config', 'referral_config'):
        p = os.path.join(DATA, 'scripts', 'chaos', f + '.lua')
        if os.path.exists(p):
            ids.update(int(x) for x in re.findall(r'\b(?:item[iI]d|id)\s*=\s*(\d{4,5})\b', read(p)))
    return ids


SNAP_COLS = ['id', 'cat', 'slot', 'level', 'sell_max', 'sell_min', 'sellers', 'buy_min', 'buy_med', 'buyers', 'loot_n',
             'loot_lv_min', 'loot_lv_max', 'chance_max', 'reward']


def survey(base):
    info = B.items(base)
    lv = B.levels(base)
    shops = B.shops(base, active_only=True)  # NPCs in the game (spawned or created by a script)
    names = {}
    for i, v in sorted(info.items()):
        names.setdefault(v['name'].lower(), i)
    mons = B.monsters(base, names)
    recs = B.recipes(base)
    loot = {}
    for m in mons:
        for iid, _c, ch in m['loot']:
            loot.setdefault(iid, []).append((m['level'], ch))
    rewards = {i for i in reward_ids() if i in info and 'weight' in info[i]['attrs']}
    crafted = {r['id'] for r in recs} | {mid for r in recs for mid, _ in r['materials']}
    wanted = (set(loot) | crafted | rewards | {i for i, s in shops.items() if s['sell'] or s['buy']}) & set(info)
    rows = []
    for iid in sorted(wanted):
        s = shops.get(iid, {'sell': [], 'buy': []})
        sells = [p for _, p in s['sell']]
        buys = [p for _, p in s['buy']]
        src = loot.get(iid, [])
        rows.append({
            'id': iid, 'cat': survey_category(iid, info[iid]), 'slot': survey_slot(info[iid]), 'level': lv.get(iid, 0),
            'sell_max': max(sells) if sells else 0, 'sell_min': min(sells) if sells else 0, 'sellers': len(sells),
            'buy_min': min(buys) if buys else 0, 'buy_med': int(statistics.median(buys)) if buys else 0,
            'buyers': len(buys), 'loot_n': len(src), 'loot_lv_min': min(l for l, _ in src) if src else 0,
            'loot_lv_max': max(l for l, _ in src) if src else 0, 'chance_max': max(c for _, c in src) if src else 0,
            'reward': 1 if iid in rewards else 0})
    buf = io.StringIO()
    w = csv.DictWriter(buf, SNAP_COLS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    with open(SNAPSHOT, 'w', encoding='utf-8') as f:
        f.write(buf.getvalue())
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator='\n')
    w.writerow(['id', 'count', 'cost', 'level', 'book', 'materials'])
    for r in recs:
        w.writerow([r['id'], r['count'], r['cost'], r['level'], r['book'],
                    ' '.join('%dx%d' % (n, m) for m, n in r['materials'])])
    with open(RECIPES, 'w', encoding='utf-8') as f:
        f.write(buf.getvalue())
    print('%s: %d items; %s: %d recipes' % (os.path.relpath(SNAPSHOT, SERVER), len(rows), os.path.relpath(RECIPES, SERVER), len(recs)))
    return rows


# ------------------------------------------------------------------------------------------------ repo sources
def load_snapshot():
    rows = {}
    with open(SNAPSHOT, encoding='utf-8') as f:
        for r in csv.DictReader(f):
            rows[int(r['id'])] = {k: (v if k in ('cat', 'slot') else int(v)) for k, v in r.items()}
    return rows


def load_recipes():
    out = []
    with open(RECIPES, encoding='utf-8') as f:
        for r in csv.DictReader(f):
            mats = [(int(m), int(n)) for n, m in (x.split('x') for x in r['materials'].split())]
            out.append({'id': int(r['id']), 'count': int(r['count']), 'cost': int(r['cost']), 'level': int(r['level']),
                        'book': r['book'], 'materials': mats})
    return out


def load_rules():
    out = {}
    with open(RULES, encoding='utf-8') as f:
        for r in csv.DictReader(l for l in f if not l.startswith('#')):
            out[int(r['id'])] = {'cat': r['category'].strip(), 'price': int(r['price'] or 0), 'note': r['note'].strip()}
    return out


def csv_rows(name):
    with open(os.path.join(DATA, 'items', name), encoding='utf-8') as f:
        return list(csv.DictReader(f))


def extra(text):
    out = {}
    for part in (text or '').split('|'):
        if '=' in part:
            k, v = part.split('=', 1)
            out[k.strip()] = v.strip()
    return out


def chaos_monsters():
    """loot of the Chaos monsters: [(level, [(id, countmax, chance)])]"""
    out = []
    root = os.path.join(DATA, 'monster', 'monsters', 'chaos')
    for d, _, fs in os.walk(root):
        for f in sorted(fs):
            if f.endswith('.xml'):
                m = B.parse_monster(read(os.path.join(d, f)), False, {})
                if m:
                    out.append(m)
    root = os.path.join(DATA, 'monster', 'lua')
    for d, _, fs in os.walk(root):
        for f in sorted(fs):
            if f.endswith('.lua'):
                m = B.parse_monster(read(os.path.join(d, f)), True, {})
                if m:
                    out.append(m)
    return out


def store_ids():
    text = read(os.path.join(DATA, 'scripts', 'chaos', 'shop_config.lua'))
    ids = {int(x) for x in re.findall(r'kind\s*=\s*"item"\s*,\s*id\s*=\s*(\d+)', text)}
    # the potion packs are built from POTION_PACKS rows {id, coins, name, text} (2026-10-23)
    m = re.search(r'local POTION_PACKS = \{(.*?)\n\}', text, re.S)
    if m:
        ids |= {int(x) for x in re.findall(r'^\s*\{(\d+),', m.group(1), re.M)}
    return ids


def uniques():
    """[(base id, name, level)] from chaos_items.xml"""
    out = []
    text = read(os.path.join(DATA, 'items', 'chaos_items.xml'))
    for m in re.finditer(r'<item\s+id="(\d+)"[^>]*name="([^"]+)"[^>]*>(.*?)</item>', text, re.S):
        body = m.group(3)
        lv = re.search(r'key="equipLevel"\s+value="(\d+)"', body) or re.search(r'[Rr]equires level (\d+)', body)
        out.append((int(m.group(1)), m.group(2), int(lv.group(1)) if lv else 0))
    return out


def chaos_items():
    """{id: {'name', 'cat', 'price' (fixed or None), 'slot', 'level', 'src'}} for the Chaos item ids"""
    items = {}

    def put(i, name, cat, price=None, slot='', level=0, src=''):
        items[i] = {'name': name, 'cat': cat, 'price': price, 'slot': slot, 'level': level, 'src': src}

    for r in csv_rows('art_items.csv'):
        ex = extra(r.get('extra'))
        sid = int(r['server_id'])
        if r['kind'] == 'product':
            put(sid, r['name'], 'material', int(ex['sell']) if ex.get('sell') else None, src='art_items.csv product')
        elif r['kind'] == 'food':
            put(sid, r['name'], 'food', None, src='art_items.csv food')
    for r in csv_rows('fist_items.csv'):
        ex = extra(r.get('extra'))
        put(int(r['server_id']), r['name'], 'equip', int(ex['sell']) if ex.get('sell') else None, 'weapon',
            int(ex.get('level', 0)), 'fist_items.csv')
    # the equipment sets of pair 28: plain gear priced by the equipment formula at the level install_gear_sets.py gives
    import install_gear_sets as GS
    for r in GS.rows_of(os.path.join(DATA, 'items', 'gear_sets.csv')):
        k, two = r['kind'], r['ex']['fit'] == '2' or r['kind'] in ('bow', 'crossbow')
        slot = {'helmet': 'head', 'armor': 'body', 'legs': 'legs', 'boots': 'feet', 'amulet': 'necklace', 'ring': 'ring',
                'shield': 'shield', 'spellbook': 'shield'}.get(k, 'two-handed' if two else 'weapon')
        put(r['server_id'], r['name'], 'equip', None, slot, r['level'], 'gear_sets.csv')
    gem = read(os.path.join(DATA, 'lib', 'chaos_gems_config.lua'))
    first = int(re.search(r'firstId\s*=\s*(\d+)', gem).group(1))
    gem_types = len(re.findall(r'clientIdHigh\s*=', gem)) or 7
    for t in range(gem_types):
        for tier in range(5):
            put(first + t * 5 + tier, 'gem %d tier %d' % (t + 1, tier + 1), 'gem', GEM_PRICES[tier], src='chaos_gems_config.lua')
    sup = read(os.path.join(DATA, 'lib', 'chaos_supports_config.lua'))
    sfirst = int(re.search(r'firstId\s*=\s*(\d+)', sup).group(1))
    for i in range(sfirst, 32201):
        put(i, 'support %d level %d' % ((i - sfirst) // 5 + 1, (i - sfirst) % 5 + 1), 'support',
            SUPPORT_PRICES[(i - sfirst) % 5], src='chaos_supports_config.lua')
    ch = read(os.path.join(DATA, 'scripts', 'chaos', 'charms_config.lua'))
    for m in re.finditer(r'\{id = (\d+), key = "(\w+)", shape = "(\w+)"(, unique = true)?[^}]*?name = "([^"]+)"', ch):
        if m.group(4):
            put(int(m.group(1)), m.group(5), 'unique', src='charms_config.lua (unique charm)')
        else:
            put(int(m.group(1)), m.group(5), 'charm', CHARM_PRICES[m.group(3)], src='charms_config.lua')
    shard = re.search(r'\{id = (\d+), key = "shard"', ch)
    if shard:
        put(int(shard.group(1)), 'charm shard', 'currency', src='charms_config.lua')
    po = read(os.path.join(DATA, 'scripts', 'chaos', 'pouches_config.lua'))
    for i in re.findall(r'\d{5}', re.search(r'orbIds\s*=\s*\{(.*?)\}', po, re.S).group(1)):
        put(int(i), 'orb', 'currency', src='pouches_config.lua orbIds')
    for i in re.findall(r'\d{5}', re.search(r'coinIds\s*=\s*\{(.*?)\}', po, re.S).group(1)):
        put(int(i), 'coin', 'currency', src='pouches_config.lua coinIds')
    for key in ('loot', 'orbs', 'keys'):
        m = re.search(r'\b%s = \{id = (\d+)' % key, po)
        if m:
            put(int(m.group(1)), key + ' pouch', 'bound', src='pouches_config.lua')
    for i in re.findall(r'\d{5}', re.search(r'omenIds\s*=\s*\{(.*?)\}', po, re.S).group(1)):
        put(int(i), 'omen item', 'key', src='pouches_config.lua omenIds')
    rk = re.search(r'riftKey\s*=\s*\{itemId\s*=\s*(\d+)', po)
    if rk:
        put(int(rk.group(1)), 'rift key', 'key', src='pouches_config.lua riftKey')
    orbs = read(os.path.join(DATA, 'lib', 'chaos_orbs_config.lua'))
    for i in re.findall(r'\{id = (\d+), key = "', orbs):
        put(int(i), 'orb', 'currency', src='chaos_orbs_config.lua')
    sf = re.search(r'item\s*=\s*\{id\s*=\s*(\d+)', read(os.path.join(DATA, 'scripts', 'chaos', 'store_food_config.lua')))
    put(int(sf.group(1)), 'Everfull Ration', 'bound', src='store_food_config.lua')
    pc = read(os.path.join(DATA, 'scripts', 'chaos', 'potions_config.lua'))
    for i, name in re.findall(r'\{key = "\w+", id = (\d+),[^}]*?\bname = "([^"]+)"', pc, re.S):
        put(int(i), name, 'bound', src='potions_config.lua')
    # the Stamina Extension left the store on 2026-10-15 but is still given free (the level 100 kit,
    # newplayer_config.lua): it stays unsellable, so a free item is no gold path
    put(27990, 'Stamina Extension', 'store', src='newplayer_config.lua (former store item)')
    sal = re.search(r'shard\s*=\s*\{[^}]*?\bid\s*=\s*(\d+)', read(os.path.join(DATA, 'scripts', 'chaos', 'salvage_config.lua')), re.S)
    if sal:
        put(int(sal.group(1)), 'rune shard', 'currency', src='salvage_config.lua')
    for i in re.findall(r'\bid = (\d+), sourceId', read(os.path.join(DATA, 'scripts', 'chaos', 'uber_config.lua'))):
        put(int(i), 'ascended item', 'key', src='uber_config.lua')
    for i in re.findall(r'\bid = (\d+), sourceId', read(os.path.join(DATA, 'scripts', 'chaos', 'factions_config.lua'))):
        put(int(i), 'faction token', 'currency', src='factions_config.lua')
    for m in re.finditer(r'\n\tm\((\d+), "(\w+)", (\d+), \d+, "([^"]+)"', read(os.path.join(DATA, 'scripts', 'chaos', 'professions_config.lua'))):
        put(int(m.group(1)), m.group(4), 'broker', src='professions_config.lua')
    for i in re.findall(r'\{id = (\d+), sourceId', read(os.path.join(DATA, 'scripts', 'chaos', 'rift_config.lua'))):
        put(int(i), 'omen item', 'key', src='rift_config.lua')
    return items


# ------------------------------------------------------------------------------------------------ the table
def build():
    """-> (table, notes): table[id] = {'price', 'cat', 'why', 'src', ...}"""
    snap = load_snapshot()
    rules = load_rules()
    ours = chaos_items()
    store = store_ids()
    recipes = load_recipes()
    cm = chaos_monsters()
    # loot sources of the Chaos monsters (base ids and ours)
    cloot = {}
    for m in cm:
        for iid, _c, ch in m['loot']:
            cloot.setdefault(iid, []).append((m['level'], ch))
    # fist weapons are added to base monsters' loot by install_fist_weapons.py (loot=Name:chance;...)
    for r in csv_rows('fist_items.csv'):
        ex = extra(r.get('extra'))
        if ex.get('loot'):
            for part in ex['loot'].split(';'):
                cloot.setdefault(int(r['server_id']), []).append((int(ex.get('level', 0)), int(part.split(':')[1])))
    table = {}

    def entry(iid):
        return table.setdefault(iid, {'id': iid, 'price': 0, 'cat': 'material', 'why': '', 'src': '', 'slot': '',
                                      'level': 0, 'buy_med': 0, 'buy_min': 0, 'lootable': False, 'crafted': False,
                                      'loot_lv_min': 0, 'chance_max': 0, 'base_sell': 0})

    for iid, r in snap.items():
        e = entry(iid)
        e.update(cat=r['cat'], slot=r['slot'], level=r['level'], buy_med=r['buy_med'], buy_min=r['buy_min'],
                 base_sell=r['sell_max'], lootable=r['loot_n'] > 0 or bool(r['reward']), loot_lv_min=r['loot_lv_min'],
                 chance_max=r['chance_max'], src='base')
    for r in recipes:
        entry(r['id'])['crafted'] = True
    for iid, srcs in cloot.items():
        e = entry(iid)
        e['lootable'] = True
        lvmin = min(l for l, _ in srcs)
        if not e['loot_lv_min'] or lvmin < e['loot_lv_min']:
            e['loot_lv_min'] = lvmin
        e['chance_max'] = max(e['chance_max'], max(c for _, c in srcs))
        if e['src'] == '':
            e['src'] = 'chaos monster'
    for iid, o in ours.items():
        e = entry(iid)
        e.update(cat=o['cat'], src=o['src'], name=o['name'])
        if o['slot']:
            e['slot'], e['level'] = o['slot'], o['level']
        if o['price'] is not None:
            e['fixed'] = o['price']
        if o['cat'] in ('gem', 'support', 'charm', 'currency', 'key', 'bound', 'broker', 'unique'):
            e['lootable'] = True  # Chaos loot layer, rewards and pouches: in scope for coverage
    for iid in store:
        entry(iid)['cat'] = 'store'
    for iid in COINS:
        entry(iid)['cat'] = 'currency'
    for iid, r in rules.items():
        e = entry(iid)
        e['cat'] = r['cat'] or e['cat']
        if r['price'] > 0:
            e['fixed'] = r['price']
            e['rule_price'] = True
        e['rule'] = r['note']
    # uniques (chaos_items.xml): copies of base items, never sold to an NPC (ChaosItemPrices reads chaos_unique)
    uq = [name for _, name, _ in uniques()]

    # pass 1: the plain price
    for iid, e in table.items():
        cat = e['cat']
        if cat in UNSELLABLE:
            e['price'], e['why'] = 0, cat
            continue
        if 'fixed' in e:
            p, why = e['fixed'], 'fixed'
        elif e['base_sell'] > 0:
            p, why = e['base_sell'], 'npc'
        elif cat == 'equip':
            p, why = curve(EQUIP_CURVE, e['level']) * SLOT_FACTOR.get(e['slot'] or 'equip', 1.0), 'equip formula'
        elif cat == 'supply' and e['buy_med'] > 0:
            p, why = max(1, int(e['buy_med'] * SUPPLY_SHARE)), 'supply share'
        else:
            lv = e['loot_lv_min'] or 1
            p, why = nice(curve(LOOT_CURVE, lv) * chance_factor(e['chance_max'] or 1)), 'loot formula'
        if cat == 'equip' and 'fixed' not in e:
            p, why = max(1, nice(p * GEAR_SCALE)), why + ' x gear scale'
        if e['lootable'] and e['loot_lv_min'] >= LATE_LEVEL and cat not in ('supply',):
            floor = nice(curve(LOOT_CURVE, e['loot_lv_min']) * chance_factor(e['chance_max'] or 1) * LATE_FLOOR)
            if p < floor:
                p, why = floor, why + ' + late floor'
        e['price'], e['why'] = int(p), why
    # crafted items are worth at least (a share of) their materials; twice, for materials made of crafted materials
    for _ in range(2):
        for r in recipes:
            e = table.get(r['id'])
            if not e or e['price'] <= 0 or 'fixed' in e:
                continue
            share = CRAFT_GEAR_SHARE if e['cat'] == 'equip' else 1.0
            mats = sum(table.get(m, {}).get('price', 0) * n for m, n in r['materials'])
            per = int(math.ceil(mats * share / float(r['count'])))
            if per > e['price']:
                e['price'] = per
                if 'craft floor' not in e['why']:
                    e['why'] += ' + craft floor'
    # crafted equipment: at most about an hour of hunting at its level band
    hunt = hunting_curve()
    for r in recipes:
        e = table.get(r['id'])
        if not e or e['cat'] != 'equip' or e['price'] <= 0 or 'fixed' in e:
            continue
        band = max([e['level']] + [table.get(m, {}).get('loot_lv_min', 0) for m, _ in r['materials']])
        cap = int(curve(hunt, max(band, 1)) * CRAFT_HOURS)
        if e['price'] > cap:
            e['price'], e['why'] = cap, e['why'] + ' + craft hour cap'
    # the Wandering Merchant's rarity orbs: gilding or re-rolling a plain copy and selling it does not pay
    mcap = merchant_cap()
    for iid, e in table.items():
        if e['cat'] == 'equip' and e['price'] > mcap:
            e['price'], e['why'] = mcap, e['why'] + ' + merchant orb cap'
    # the Gambler sells these bases sealed: their expected sale stays under his price
    for iid, cap in gamble_caps().items():
        e = table.get(iid)
        if e and e['price'] > cap:
            e['price'], e['why'] = max(cap, MIN_PRICE), e['why'] + ' + gambler cap'
    # caps: below the NPCs' asking price; MIN_PRICE for anything sellable an NPC does not sell for 1-2 gold
    for iid, e in table.items():
        if 0 < e['price'] < MIN_PRICE:
            e['price'] = MIN_PRICE
        if e['price'] <= 0 or e['buy_med'] <= 0:
            continue
        cap = buy_cap(e)
        if e['price'] > cap:
            e['price'], e['why'] = max(cap, 1), e['why'] + ' + buy cap'
    return table, uq


def hunting_curve():
    """hunting gold per hour by character level (gamble_config.lua balance.hunting, the "Respec" model)"""
    g = read(os.path.join(DATA, 'scripts', 'chaos', 'gamble_config.lua'))
    body = re.search(r'hunting = \{(.*?)\}\s*\n', g, re.S).group(1)
    return [(int(a), int(b)) for a, b in re.findall(r'\{(\d+), (\d+)\}', body)]


def merchant_orbs():
    """[(name, merchant price, expected gain factor on a plain copy)] for the merchant's orbs that change a rarity:
    the Orb of Gilding (chaos_crafting.lua alchemy weights) and the Orb of Fate (one step up: a plain copy becomes Common)"""
    inv = read(os.path.join(DATA, 'scripts', 'chaos', 'invasion_config.lua'))
    stock = {int(i): int(p) for i, p in re.findall(r'\{id = (\d+), price = (\d+)', inv)}
    cr = read(os.path.join(DATA, 'lib', 'chaos_crafting.lua'))
    keys = {k: int(i) for k, i in re.findall(r'\{key = "(\w+)", id = (\d+)', cr)}
    out = []
    w = [(int(r), int(x)) for r, x in re.findall(r'\{(\d+), (\d+)\}', re.search(r'\n\talchemy = \{(.*?)\}\s*,\s*\n', cr).group(1))]
    tot = float(sum(x for _, x in w))
    gild = sum(x / tot * RARITY_MULT[rank_of(r) - 1] for r, x in w) - 1
    if keys.get('alchemy') in stock:
        out.append(('Orb of Gilding', stock[keys['alchemy']], gild))
    fate = RARITY_MULT[0] - 1  # since 2026-10-22 the Orb of Fate raises a plain copy to Common, one step
    if keys.get('divine') in stock:
        out.append(('Orb of Fate', stock[keys['divine']], fate))
    return out


def merchant_cap():
    lmax = 1 + 150.0 / ILVL_DIV
    return min(int(price * MERCHANT_MARGIN / (gain * lmax)) for _, price, gain in merchant_orbs() if gain > 0)


def buy_cap(e):
    """the most an NPC may pay for an item the NPCs sell for buy_med: BUY_SHARE of it (SUPPLY_SHARE for supplies);
    cheap goods: 2 gold under an asking price of 3+, else 1"""
    share = SUPPLY_SHARE if e['cat'] == 'supply' else BUY_SHARE
    return max(int(e['buy_med'] * share), 2 if e['buy_med'] >= 3 else 1)


def lua_table_numbers(text, key):
    m = re.search(r'%s\s*=\s*\{(.*?)\}' % key, text, re.S)
    return [float(x) for x in re.findall(r'-?[\d.]+', m.group(1))] if m else []


def gamble_ev():
    """expected rarity multiplier of one sealed piece of the Gambler (a port of gamble_core.lua K.odds with
    loot_config.lua gear, all in places 0..6; tests/item_prices_test.lua recomputes it with the Lua code)"""
    g = read(os.path.join(DATA, 'scripts', 'chaos', 'gamble_config.lua'))
    lc = read(os.path.join(DATA, 'scripts', 'chaos', 'loot_config.lua'))
    o = re.search(r'C\.odds\s*=\s*\{draws = (\d+), floor = (\d+), tier = "(\w+)", find = ([\d.]+), maxRarity = (\d+)\}', g)
    draws, flo, tier, find, max_r = int(o.group(1)), rank_of(o.group(2)), o.group(3), float(o.group(4)), rank_of(o.group(5))

    def tier_value(key):
        m = re.search(r'%s\s*=\s*\{[^}]*?\b%s\s*=\s*([\d.]+)' % (key, tier), lc)
        return float(m.group(1)) if m else 0.0

    def pct(x):
        return 0.0 if x <= 0 else 1.0 if x >= 100 else min(1000000, math.floor(x * 10000 + 1e-9)) / 1000000.0

    top = len(STORED_IDS)
    roll = int(re.search(r'stockRollChance\s*=\s*(\d+)', lc).group(1))
    chances = lua_table_numbers(lc, 'stockChances')
    gear_cap = rank_of(re.search(r'maxRarity\s*=\s*(\d+)', lc).group(1))
    steps = [(int(a), int(b)) for a, b in re.findall(r'\{(\d+), (\d+)\}', re.search(r'bonusSteps\s*=\s*\{(.*?)\}\s*,\s*--', lc, re.S).group(1))]
    one = [0.0] * (top + 1)
    rest = min(100, max(0, roll)) / 100.0
    pas = rest
    for i, c in enumerate(chances, 1):
        h = math.floor(c) / 100.0
        one[i] += rest * h
        rest *= 1 - h
    one[0] = 1 - pas + rest
    cdf, acc = [], 0.0
    for r in range(top + 1):
        acc += one[r]
        cdf.append(acc ** draws)
    best = [cdf[r] - (cdf[r - 1] if r else 0) for r in range(top + 1)]
    cap = min(max_r, top)
    floor_tier = rank_of(tier_value('minRarity'))
    ensure = pct(tier_value('ensureChance'))
    bonus = pct(tier_value('bonusChance') * find)
    divine = pct(tier_value('divineChance') * find)
    total = sum(w for _, w in steps)
    out = [0.0] * (top + 1)

    def add(r, p):
        out[min(r, cap)] += p
    for r0 in range(top + 1):
        if best[r0] <= 0:
            continue
        cur = max(r0, flo)
        paths = [(floor_tier, ensure), (cur, 1 - ensure)] if floor_tier > 0 and cur < floor_tier else [(cur, 1.0)]
        for tt, pp in paths:
            if pp <= 0:
                continue

            def fin(v):
                if v > gear_cap:
                    v = max(gear_cap, cur)
                return max(v, cur)

            def put(v, p):
                v = fin(v)
                if v < top and divine > 0:
                    add(top, p * divine)
                    add(v, p * (1 - divine))
                else:
                    add(v, p)
            put(tt, best[r0] * pp * (1 - bonus))
            if bonus > 0 and total > 0:
                for s_, w in steps:
                    put(tt + s_, best[r0] * pp * bonus * w / total)
    return out[0] + sum(out[r] * RARITY_MULT[r - 1] for r in range(1, top + 1))


def gamble_caps():
    """{id: the most an NPC may pay for a plain copy of a Gambler base}: its expected sale (x the gamble rarity
    multiplier and the item level) stays under the Gambler's price at every level it is offered"""
    g = read(os.path.join(DATA, 'scripts', 'chaos', 'gamble_config.lua'))
    ev = gamble_ev()
    pcurve = [(int(a), int(b)) for a, b in re.findall(r'\{(\d+), (\d+)\}', re.search(r'C\.price = \{\s*curve = \{(.*?)\}\s*,\s*\n', g, re.S).group(1))]
    slots = {k: float(v) for k, v in re.findall(r'(\w+) = ([\d.]+)', re.search(r'\bslot = \{(.*?)\}', g, re.S).group(1))}
    rnd = int(re.search(r'C\.price = \{.*?round = (\d+)', g, re.S).group(1))
    spread = int(re.search(r'C\.itemLevel = \{tier = "\w+", spread = (\d+)\}', g).group(1))
    pool = re.search(r'C\.pool = \{(.*)\n\}', g, re.S).group(1)
    caps = {}
    for slot, body in re.findall(r'\n\t(\w+) = \{(.*?)\n\t\}', pool, re.S):
        for iid, lv in re.findall(r'\{(\d+), (\d+)\}', body):
            iid, lv = int(iid), int(lv)
            best = None
            for level in range(max(lv, 1), 1501, 7):
                gate = ilvl_of(level)
                low = max(1, gate - spread)
                price = max(rnd, math.floor(curve(pcurve, low) * slots.get(slot, 1.0) / rnd + 1e-9) * rnd)
                cap = int(price * GAMBLE_MARGIN / (ev * (1 + gate / float(ILVL_DIV))))
                best = cap if best is None else min(best, cap)
            caps[iid] = min(caps.get(iid, best), best)
    return caps


def our_buy_prices():
    """what Chaos NPCs and configs ask for an item: [(id, price, where)]"""
    out = []
    inv = read(os.path.join(DATA, 'scripts', 'chaos', 'invasion_config.lua'))
    for i, p in re.findall(r'\{id = (\d+), price = (\d+)', inv):
        out.append((int(i), int(p), 'Wandering Merchant'))
    for r in csv_rows('fist_items.csv'):
        ex = extra(r.get('extra'))
        if ex.get('buy'):
            out.append((int(r['server_id']), int(ex['buy']), 'fist weapon dealers'))
    pc = read(os.path.join(DATA, 'scripts', 'chaos', 'professions_config.lua'))
    for i, p in re.findall(r'\{id = (\d+), price = (\d+)\}', pc):
        out.append((int(i), int(p), 'Material Broker tools'))
    rs = os.path.join(DATA, 'lib', 'chaos_rune_supply.lua')
    if os.path.exists(rs):
        for i, p in re.findall(r'\{id\s*=\s*(\d+)[^{}]*?\bprice\s*=\s*(\d+)', read(rs)):
            out.append((int(i), int(p), 'rune supply'))
    return out


# ------------------------------------------------------------------------------------------------ checks
def problems(table, recipes, snap_rows=None, uq=None):
    """counts of the problems the README lists; with snap_rows: the base prices before this table"""
    out = {}
    lootable = [e for e in table.values() if e['lootable'] or e['crafted']]
    if snap_rows is None:
        price = {i: e['price'] for i, e in table.items()}
        buy = {}
        for i, e in table.items():
            if e['buy_min']:
                buy[i] = max(e['buy_min'], 2 * e['price'] if e['price'] > e['buy_min'] else e['buy_min'])
        for i, p, _ in our_buy_prices():
            buy[i] = min(buy.get(i, p), p)
        nobody = [e for e in lootable if e['cat'] not in UNSELLABLE and price[e['id']] <= 0]
        out['lootable or craftable items nobody buys'] = len(nobody)
        out['sell price above an NPC buy price (arbitrage)'] = sum(1 for i in buy if price.get(i, 0) > buy[i])
        out['1 gold or less for real loot'] = sum(1 for e in lootable if e['cat'] not in UNSELLABLE + ('supply',) and 0 < price[e['id']] <= 1)
        out['different prices for one item across NPCs'] = 0  # install_item_prices.py writes the one price everywhere
        late = [e for e in lootable if e['loot_lv_min'] >= 300 and 0 < price[e['id']] < 100 and e['cat'] != 'supply']
        out['late-game drops (monster level 300+) under 100 gold'] = len(late)
    else:
        price = {i: r['sell_max'] for i, r in snap_rows.items()}
        nobody = [r for r in snap_rows.values() if (r['loot_n'] or r['reward']) and r['cat'] not in UNSELLABLE and not r['sell_max']]
        crafted_nobody = {rc['id'] for rc in recipes if not price.get(rc['id'])}
        out['lootable or craftable items nobody buys'] = len({r['id'] for r in nobody} | crafted_nobody)
        out['sell price above an NPC buy price (arbitrage)'] = sum(1 for r in snap_rows.values() if r['buy_min'] and r['sell_max'] > r['buy_min'])
        out['1 gold or less for real loot'] = sum(1 for r in snap_rows.values() if r['loot_n'] and r['cat'] not in UNSELLABLE + ('supply',) and r['sell_max'] == 1)
        out['different prices for one item across NPCs'] = sum(1 for r in snap_rows.values() if r['sellers'] > 1 and r['sell_min'] != r['sell_max'])
        out['late-game drops (monster level 300+) under 100 gold'] = sum(1 for r in snap_rows.values() if r['loot_n'] and r['loot_lv_min'] >= 300 and r['sell_max'] < 100 and r['cat'] not in UNSELLABLE + ('supply',))
    destroys = printers = gambled = 0
    gearcat = {i for i, e in table.items() if e['cat'] == 'equip'}
    for r in recipes:
        mats = sum(price.get(m, 0) * n for m, n in r['materials'])
        prod = price.get(r['id'], 0) * r['count']
        gear = r['id'] in gearcat
        if mats and prod < mats * (CRAFT_GEAR_SHARE if gear else 1.0):
            if snap_rows is None and ('gambler' in table[r['id']]['why'] or 'hour cap' in table[r['id']]['why']
                                      or 'merchant' in table[r['id']]['why']):
                gambled += 1  # capped on purpose: the Gambler's price, an hour of hunting, the merchant's orbs
            else:
                destroys += 1
        if gear and prod * CRAFT_EV > mats + r['cost'] and mats:
            printers += 1
    out['recipes whose product sells for less than its materials (equipment: 20%)'] = destroys
    out['  (crafted equipment under 20% of its materials: capped on purpose, kept)'] = gambled
    out['crafted equipment whose expected sale beats materials + cost'] = printers
    out['crafting loops (NPC-bought materials + cost < product)'] = 0 if snap_rows is None else loops_before(snap_rows, recipes)
    return out


def craft_ev():
    """the expected R x L of a crafted copy at the best mastery (craft_bonus_config.lua gear)"""
    text = read(os.path.join(DATA, 'scripts', 'chaos', 'craft_bonus_config.lua'))
    odds = [(int(r), float(c)) for r, c in re.findall(r'\{rarity = (\d+), chance = ([\d.]+)\}', text)]
    bonus = 1 + float(re.search(r'maxBonus = ([\d.]+)', text).group(1))
    top = float(re.search(r'maxTotal = ([\d.]+)', text).group(1))
    ps = [(r, c * bonus) for r, c in odds]
    scale = min(1.0, top / sum(c for _, c in ps))
    ps = [(r, c * scale / 100.0) for r, c in ps]
    er = (1 - sum(p for _, p in ps)) + sum(p * RARITY_MULT[rank_of(r) - 1] for r, p in ps)
    ilmax = int(re.search(r'itemLevel = \{perMastery = [\d.]+, max = (\d+)\}', text).group(1))
    return er * (1 + ilmax / float(ILVL_DIV))


def loops_before(snap_rows, recipes):
    n = 0
    for r in recipes:
        if all(snap_rows.get(m, {}).get('buy_min') for m, _ in r['materials']):
            cost = sum(snap_rows[m]['buy_min'] * k for m, k in r['materials']) + r['cost']
            if snap_rows.get(r['id'], {}).get('sell_max', 0) * r['count'] > cost:
                n += 1
    return n


def check(table, uq, recipes):
    """the CI rules; returns a list of failures"""
    bad = []
    for e in table.values():
        if (e['lootable'] or e['crafted']) and e['cat'] not in UNSELLABLE and e['price'] <= 0:
            bad.append('item %d (%s): lootable or craftable, no price and not in an unsellable category' % (e['id'], e['src']))
        if e['cat'] in UNSELLABLE and e['price'] > 0:
            bad.append('item %d: %s but priced' % (e['id'], e['cat']))
        if e['buy_med'] and e['price'] > buy_cap(e):
            bad.append('item %d: sells for %d, above the cap %d of the NPCs\' asking price %d' % (e['id'], e['price'], buy_cap(e), e['buy_med']))
    lmax = 1 + 150.0 / ILVL_DIV
    for name, price, gain in merchant_orbs():
        top = max((e['price'] for e in table.values() if e['cat'] == 'equip'), default=0)
        if top * gain * lmax >= price:
            bad.append('%s (%d at the Wandering Merchant) on a plain copy worth %d adds %.0f at item level 150 (arbitrage)'
                       % (name, price, top, top * gain * lmax))
    for e in table.values():
        if e['cat'] == 'equip' and e['crafted'] and e['price'] > curve(hunting_curve(), 1500) * CRAFT_HOURS:
            bad.append('crafted item %d sells for %d, more than an hour of hunting at level 1500' % (e['id'], e['price']))
    for i, p, where in our_buy_prices():
        e = table.get(i)
        if e and e['price'] > p:
            bad.append('item %d: an NPC buys it for %d, %s sells it for %d (arbitrage)' % (i, e['price'], where, p))
    price = {i: e['price'] for i, e in table.items()}
    for r in recipes:
        mats = [(m, n) for m, n in r['materials']]
        buyable = all(table.get(m, {}).get('buy_min') for m, _ in mats)
        if buyable:
            cost = sum(table[m]['buy_min'] * n for m, n in mats) + r['cost']
            top = price.get(r['id'], 0) * r['count'] * RARITY_MULT[-1] * (1 + 150.0 / ILVL_DIV)
            if top > cost:
                bad.append('recipe %d: NPC materials + cost %d < the best sale %d (loop)' % (r['id'], cost, top))
    # the Chaos sources that write NPC shop entries themselves (install_pack_items.py, install_fist_weapons.py) must
    # agree with the table, or install_item_prices.py and they would rewrite each other's prices on every install
    for r in csv_rows('art_items.csv') + csv_rows('fist_items.csv'):
        ex = extra(r.get('extra'))
        e = table.get(int(r['server_id']))
        if ex.get('sell') and e and e['price'] != int(ex['sell']):
            bad.append('item %s: the csv sells it for %s, the table for %d (change the csv)' % (r['server_id'], ex['sell'], e['price']))
    # the Auto Seller's flat table must be this table
    if os.path.exists(OUT_SELL):
        flat = {int(k): int(v) for k, v in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', read(OUT_SELL))}
        want = {i: e['price'] for i, e in table.items() if e['price'] > 0}
        if flat != want:
            bad.append('sell_prices.lua is not the price table (run gen_item_prices.py)')
    return bad


# ------------------------------------------------------------------------------------------------ output
def render_lua(table, uq):
    prices = {i: e['price'] for i, e in table.items() if e['price'] > 0}
    unsell = {i: e['cat'] for i, e in table.items() if e['cat'] in UNSELLABLE}
    gear = sorted(i for i, e in table.items() if e['price'] > 0 and e['cat'] in ('equip', 'charm'))
    L = ['-- GENERATED by server/tools/gen_item_prices.py; do not edit by hand. The rules: that script and',
         '-- server/README.md "Item prices". Read by data/lib/chaos_item_prices.lua (ChaosItemPrices).',
         'return {',
         '\t-- price of an instance = prices[id] x rarity multiplier x (1 + item level / ilvlDiv)',
         '\trarityMult = {%s}, -- by place: Common, Uncommon, Magic, Rare, Legendary, Divine; no rarity = 1' % ', '.join('%g' % x for x in RARITY_MULT),
         '\tcharmMult = {%s}, -- charm rarity 1..3 (Faint, Glowing, Radiant)' % ', '.join('%g' % x for x in CHARM_MULT),
         '\tilvlDiv = %d,' % ILVL_DIV,
         '\tbuyShare = %g, -- an NPC asks at least sell / buyShare' % BUY_SHARE,
         '\treasons = {']
    for k in UNSELLABLE:
        L.append('\t\t%s = "%s",' % (k, REASON_TEXT[k]))
    L.append('\t},')
    L.append('\t-- [server id] = gold for a plain copy')
    L.append('\tprices = {')
    ids = sorted(prices)
    for i in range(0, len(ids), 8):
        L.append('\t\t' + ' '.join('[%d] = %d,' % (k, prices[k]) for k in ids[i:i + 8]))
    L.append('\t},')
    L.append('\t-- items whose price follows the rarity and item level of the copy (equipment and charms)')
    L.append('\tgear = {')
    for i in range(0, len(gear), 12):
        L.append('\t\t' + ' '.join('[%d] = true,' % k for k in gear[i:i + 12]))
    L.append('\t},')
    L.append('\t-- a unique copy (custom attribute chaos_unique) is never sold to an NPC: reasons.unique (%d uniques)' % len(uq))
    L.append('\t-- [server id] = reason: never sold to an NPC (keys of reasons)')
    L.append('\tunsellable = {')
    ids = sorted(unsell)
    for i in range(0, len(ids), 6):
        L.append('\t\t' + ' '.join('[%d] = "%s",' % (k, unsell[k]) for k in ids[i:i + 6]))
    L.append('\t},')
    L.append('}')
    return '\n'.join(L) + '\n'


def render_sell(table):
    prices = {i: e['price'] for i, e in table.items() if e['price'] > 0}
    L = ['-- NPC sell prices for the store\'s Auto Seller (autosell.lua): the plain-copy prices of the item price table.',
         '-- GENERATED by server/tools/gen_item_prices.py (README "Item prices"); do not edit by hand. Regenerate:',
         '--     python3 -I server/tools/gen_item_prices.py',
         '-- [server item id] = gold per item. A copy with a rarity or an item level is worth more, a unique is not sold:',
         '-- ChaosItemPrices.sellPrice(item) (data/lib/chaos_item_prices.lua).',
         'return {']
    ids = sorted(prices)
    for i in range(0, len(ids), 8):
        L.append('\t' + ' '.join('[%d] = %d,' % (k, prices[k]) for k in ids[i:i + 8]))
    L.append('}')
    return '\n'.join(L) + '\n'


CRAFT_EV = None


def write_or_check(path, text, check_only):
    old = read(path) if os.path.exists(path) else None
    if old == text:
        return True
    if check_only:
        print('%s is out of date (python3 -I server/tools/gen_item_prices.py)' % os.path.relpath(path, SERVER))
        return False
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
    print('wrote %s' % os.path.relpath(path, SERVER))
    return True


# ------------------------------------------------------------------------------------------------ income
def stock_rarity_odds():
    """P(rarity r) of a normal monster's gear drop (loot.lua stockRarity with loot_config.lua gear)"""
    text = read(os.path.join(DATA, 'scripts', 'chaos', 'loot_config.lua'))
    roll = int(re.search(r'stockRollChance\s*=\s*(\d+)', text).group(1))
    chances = [float(x) for x in re.search(r'stockChances\s*=\s*\{(.*?)\}', text, re.S).group(1).replace('\n', ' ').split(',') if x.strip()]
    odds, left = [], roll / 100.0
    for c in chances:
        p = math.floor(c) / 100.0  # rnd(1, 100) <= c
        odds.append(left * p)
        left *= 1 - p
    return odds  # index r-1; the rest has no rarity


def expected_rarity_mult():
    odds = stock_rarity_odds()
    return (1 - sum(odds)) + sum(p * RARITY_MULT[i] for i, p in enumerate(odds))


def ilvl_of(monster_level):
    text = read(os.path.join(DATA, 'lib', 'chaos_item_mods.lua'))
    pts = [(int(a), int(b)) for a, b in re.findall(r'\{(\d+), (\d+)\}', re.search(r'itemLevel = \{.*?curve = \{(.*?)\},\s*\n', text, re.S).group(1))]
    return min(150, int(curve(pts, max(monster_level, 1))))


def income(base, table, old_path=None):
    import respec_income as R
    names = R.item_names(base)
    files = R.monster_files(base)
    if old_path:  # an older sell_prices.lua (e.g. git show HEAD~1:server/data/scripts/chaos/sell_prices.lua)
        old = {int(k): int(v) for k, v in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', read(old_path))}
    else:  # the base NPC prices: the highest any NPC pays (what gen_sell_prices.py wrote before this table)
        old = {i: max(p for _, p in s['sell']) for i, s in B.shops(base).items() if s['sell']}
    er = expected_rarity_mult()
    hunts = [("Rotworms", 8, 1.0, ["Rotworm", "Carrion Worm"]),
             ("Cyclopes", 30, 1.0, ["Cyclops", "Cyclops Drone", "Cyclops Smith"])] + [h for h in R.HUNTS if h[1] < 800]
    levels = [8, 40, 100, 300, 500, 1000]
    print('expected rarity multiplier of a normal monster\'s gear drop: %.2f' % er)
    rows = []
    for level in levels:
        best = None
        for hname, minlevel, aoe, monsters in hunts:
            if minlevel > level:
                continue
            ms = []
            for name in monsters:
                p = files.get(name.lower())
                if not p:
                    continue
                health, mlevel, loot = R.parse_monster(p, names)
                text = read(p)
                exp = re.search(r'experience="(\d+)"', text) or re.search(r'experience\s*=\s*(\d+)', text)
                mlv = mlevel or B.estimate_level(int(exp.group(1)) if exp else 0, health)
                il = ilvl_of(mlv)
                new = {}
                for iid, _c, _ch in loot:
                    e = table.get(iid)
                    if not e:
                        continue
                    v = e['price']
                    if e['cat'] in ('equip',) and v > 0:
                        v = v * er * (1 + il / float(ILVL_DIV))
                    new[iid] = v
                c0, i0 = R.per_kill(loot, mlevel, old)
                _c1, i1 = R.per_kill(loot, mlevel, new)
                ms.append((health * (1 + R.HEALTH_BONUS * mlevel), c0, i0, i1))
            if not ms:
                continue
            dps = R.dps_at(level) * aoe * R.EFFICIENCY
            kills = 3600 / (sum(m[0] / dps for m in ms) / len(ms))
            mult = kills / len(ms) * (1 + R.CHAOS_EXTRA)
            coins = mult * sum(m[1] for m in ms)
            i_old = mult * sum(m[2] for m in ms)
            i_new = mult * sum(m[3] for m in ms)
            if not best or coins + i_old > best[1] + best[2]:
                best = (hname, coins, i_old, i_new, kills)
        rows.append((level, best))
    print('| Level | Best hunt | Kills / h | Coins / h | Items / h before | Items / h after | Total before | Total after | Change |')
    print('|---|---|---|---|---|---|---|---|---|')
    for level, (h, c, a, b, k) in rows:
        print('| %d | %s | %.0f | %s | %s | %s | %s | %s | %+.0f%% |' % (level, h, k, f'{c:,.0f}', f'{a:,.0f}', f'{b:,.0f}',
              f'{c + a:,.0f}', f'{c + b:,.0f}', 100.0 * (b - a) / (c + a)))
    return rows


# ------------------------------------------------------------------------------------------------ main
def band_table(table):
    bands = [(1, 49), (50, 99), (100, 199), (200, 299), (300, 499), (500, 799), (800, 99999)]
    print('| Lowest monster level | Items | Median price | 75th percentile | Highest |')
    print('|---|---|---|---|---|')
    for lo, hi in bands:
        ps = sorted(e['price'] for e in table.values() if e['lootable'] and e['price'] > 0 and lo <= e['loot_lv_min'] <= hi)
        if ps:
            print('| %d-%s | %d | %s | %s | %s |' % (lo, hi if hi < 99999 else '', len(ps), f'{int(statistics.median(ps)):,}',
                  f'{ps[3 * len(ps) // 4]:,}', f'{ps[-1]:,}'))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('command', nargs='?', default='write', choices=['write', 'report', 'income', 'survey'])
    ap.add_argument('base', nargs='?')
    ap.add_argument('--base', dest='base_opt')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--old', help='income: the sell price table to compare with (default: the base NPC prices)')
    a = ap.parse_args()
    base = a.base or a.base_opt
    if a.command == 'survey':
        if not base:
            sys.exit('survey needs BASE_DATA (the base server\'s data folder)')
        survey(base)
        return 0
    global CRAFT_EV, GEAR_SCALE
    CRAFT_EV = craft_ev()
    GEAR_SCALE = round(1.0 / expected_rarity_mult(), 2)
    table, uq = build()
    recipes = load_recipes()
    if a.command == 'income':
        if not base:
            sys.exit('income needs BASE_DATA')
        income(base, table, a.old)
        return 0
    if a.command == 'report':
        cats = {}
        for e in table.values():
            if e['lootable'] or e['crafted']:
                cats[e['cat']] = cats.get(e['cat'], 0) + 1
        print('lootable or craftable items by category:', ', '.join('%s %d' % kv for kv in sorted(cats.items())))
        after = problems(table, recipes)
        if base or True:
            before = problems(table, recipes, load_snapshot())
        print('| Problem | Before (base NPC prices) | After (this table) |')
        print('|---|---|---|')
        for k in after:
            print('| %s | %d | %d |' % (k, before.get(k, 0), after[k]))
        band_table(table)
        return 0
    ok = write_or_check(OUT_LUA, render_lua(table, uq), a.check)
    ok = write_or_check(OUT_SELL, render_sell(table), a.check) and ok
    bad = check(table, uq, recipes)
    for b in bad[:40]:
        print('FAIL', b)
    if len(bad) > 40:
        print('... %d more' % (len(bad) - 40))
    priced = sum(1 for e in table.values() if e['price'] > 0)
    unsell = sum(1 for e in table.values() if e['cat'] in UNSELLABLE)
    print('item prices: %d priced, %d unsellable, %d uniques, %d failures' % (priced, unsell, len(uq), len(bad)))
    return 0 if ok and not bad else 1


if __name__ == '__main__':
    sys.exit(main())
