#!/usr/bin/env python3
"""Install the seven equipment sets of client pair 28 into a base server: items.otb, items.xml, the equip entries in
movements.xml and the weapon entries in weapons.xml.

usage: python3 -I install_gear_sets.py DATA_DIR [--dry-run] [--manifest CSV]
       python3 -I install_gear_sets.py --lua [--check] [--manifest CSV]  (server/data/lib/chaos_gear_sets_items.lua)

The manifest (default server/data/items/gear_sets.csv) is written by client/tools/sprites/import_art_things.py
(--manifest-out) from client/tools/sprites/art_import/gear_sets.csv (gen_gear_sets_art.py): client ids 33995..34442,
server id = client id + 3000 (36995..37442), 64 pieces per set; `extra` holds set, kind, fit (H heavy, M medium,
C cloth, A anyone; 1 / 2 hands for melee weapons), the piece's number in its kind and its cell on the sheet.

Everything a piece is comes from here (server/README.md "Equipment sets (pair 28)"):
  * the level: each set has a level band (SETS). The pieces of one track (kind and fit, e.g. the cloth helmets or the
    two-handed swords) spread over the band in sheet order, rounded to 5: the first at the bottom, the last at the top,
    a lone piece at the bottom. So every class finds the next piece of its slot a little higher: no big jumps.
  * the stats: fixed, from the level along CURVES (anchored to the stock gear of the same level, which stops growing
    after 1000; above it they grow slowly) and the set's elements. Rarity, item level and modifiers come on top when a
    piece drops (ChaosCrafting.forge): the base is the same for everybody, the roll decides only how far above it a
    copy goes.
  * who may wear it (FITS): heavy armour the Warrior and Templar lines, medium the Ranger, Thief and Monk lines, cloth
    the Mystic and Necromancer lines, boots, rings, amulets and A pieces everyone; weapons as the stock ones of their
    kind after add_vocations.py (swords, axes and clubs, one- and two-handed, every melee class: the Warrior, Thief,
    Monk and Templar lines, the Berserker only the two-handed ones; bows the Beastmaster, wands and rods the
    Necromancer line, shields the Warrior without the Berserker and the Templar line).

1. items.otb: one node per row (install_pack_items.py's node rules; refused when a server id belongs to another item).
2. items.xml: the entries between two marker comments before </items>, rewritten when the manifest or a number changed.
3. movements.xml: an Equip / DeEquip pair per piece (its slot, level and classes) in a marked block before
   </movements>. Run after the vocations step: the lists name the Chaos classes.
4. weapons.xml: a melee / distance / wand entry per weapon (level, classes; wands and rods their damage, mana and
   element) in a marked block before </weapons>. Bows and crossbows have no ammunition type: they fire on their own
   like every launcher after patch_base_archery.py, with the attack and hit chance of their level here.
An id with an entry outside a block stops the script. Idempotent: a second run changes nothing.

Without the matching client pair (pair 28) the items show as nothing. ChaosGearSets.PAIR28 (data/lib/chaos_gear_sets.lua)
is OFF as shipped: installed, the items exist but nothing drops them (data/scripts/chaos/gear_sets.lua adds the loot
only when it is on) and the transmog catalogue skips their ids.
"""
import os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_pack_items import read_manifest, patch_otb, verify_otb  # noqa: E402
from install_dark_tiles import xml_escape  # noqa: E402
from install_fist_weapons import replace_block as _replace_block  # noqa: E402

REPO_DATA = os.path.join(os.path.dirname(HERE), 'data')
DEFAULT_MANIFEST = os.path.join(REPO_DATA, 'items', 'gear_sets.csv')
LUA_OUT = os.path.join(REPO_DATA, 'lib', 'chaos_gear_sets_items.lua')
SWITCH = os.path.join(REPO_DATA, 'lib', 'chaos_gear_sets.lua')
FIRST, LAST = 36995, 37442
BEGIN = {'xml': '\t<!-- Chaos equipment sets of pair 28 (server/tools/install_gear_sets.py, do not edit by hand) -->\n'}
END = '\t<!-- end of the Chaos equipment sets of pair 28 -->\n'
for _k in ('moves', 'weapons'):
    BEGIN[_k] = BEGIN['xml']

# key, name, level band, damage element, resisted element, weak element, wand missile, bow missile, crossbow missile
SETS = [
    ('cinderwrought', 'Cinderwrought', (120, 450), 'fire', 'fire', 'ice', 'fire', 'flammingarrow', 'infernalbolt'),
    ('wyrmscale', 'Wyrmscale', (40, 220), 'earth', 'fire', 'ice', 'smallearth', 'eartharrow', 'drillbolt'),
    ('rimewraith', 'Rimewraith', (450, 1000), 'ice', 'ice', 'fire', 'smallice', 'shiverarrow', 'prismaticbolt'),
    ('azurevigil', 'Azure Vigil', (800, 1350), 'holy', 'death', 'earth', 'smallholy', 'crystallinearrow',
     'prismaticbolt'),
    ('bloodmoon', 'Bloodmoon', (300, 650), 'death', 'death', 'holy', 'suddendeath', 'onyxarrow', 'drillbolt'),
    ('gildcrown', 'Gildcrown', (1250, 2000), 'energy', 'energy', 'earth', 'energy', 'crystallinearrow', 'vortexbolt'),
    ('blightfang', 'Blightfang', (8, 150), 'earth', 'earth', 'fire', 'poison', 'poisonarrow', 'drillbolt'),
]
SET_BY_KEY = {s[0]: s for s in SETS}
ELEMENT_KEY = {'fire': 'Fire', 'ice': 'Ice', 'earth': 'Earth', 'energy': 'Energy', 'death': 'Death', 'holy': 'Holy'}

# ------------------------------------------------------------------------------------------------ classes
WARRIOR = ['Warrior', 'Juggernaut', 'Berserker']
RANGER = ['Ranger', 'Deadeye', 'Beastmaster']
MYSTIC = ['Mystic', 'Elementalist', 'Illusionist']
THIEF = ['Thief', 'Ninja', 'Samurai']
NECRO = ['Necromancer', 'Lich', 'Bone Lord']
MONK = ['Monk', 'Shadowfist', 'Iron Sage']
TEMPLAR = ['Templar', 'Inquisitor', 'Sentinel']
BASES = {line[0]: line for line in (WARRIOR, RANGER, MYSTIC, THIEF, NECRO, MONK, TEMPLAR)}
FITS = {   # track -> the classes that may wear it ([] = everyone)
    'H': WARRIOR + TEMPLAR, 'M': RANGER + THIEF + MONK, 'C': MYSTIC + NECRO, 'A': [],
    'boots': [], 'amulet': [], 'ring': [],
    'shield': WARRIOR[:2] + TEMPLAR, 'spellbook': MYSTIC + NECRO,
    # melee items serve every melee class (owner debug item 46): the Berserker only the two-handed ones
    'sword1': WARRIOR[:2] + TEMPLAR + THIEF + MONK, 'sword2': WARRIOR + TEMPLAR + THIEF + MONK,
    'axe1': WARRIOR[:2] + TEMPLAR + THIEF + MONK, 'axe2': WARRIOR + TEMPLAR + THIEF + MONK,
    'club1': WARRIOR[:2] + TEMPLAR + THIEF + MONK, 'club2': WARRIOR + TEMPLAR + THIEF + MONK,
    'bow': RANGER, 'crossbow': RANGER[:2],
    'wand': MYSTIC[:2] + NECRO, 'rod': [MYSTIC[0], MYSTIC[2]] + NECRO,
}
SLOT = {'helmet': 'head', 'armor': 'armor', 'legs': 'legs', 'boots': 'feet', 'amulet': 'necklace', 'ring': 'ring'}

# ------------------------------------------------------------------------------------------------ numbers
ANCHORS = (8, 50, 100, 200, 400, 700, 1000, 1500, 2000)
CURVES = {   # value at each anchor level; linear between them, flat outside
    'armor': (7, 11, 13, 16, 19, 22, 25, 28, 31),      # body, heavy (stock: 13 at 100, 16-18 at 200-400, 25-32 at 1000)
    'helmet': (3, 5, 7, 8, 10, 12, 14, 16, 18),        # heavy (stock: 7-11 at 230-400, 15-20 at 1000)
    'legs': (3, 6, 7, 8, 10, 12, 14, 16, 18),
    'boots': (1, 2, 2, 3, 3, 4, 5, 6, 7),
    'speed': (0, 5, 10, 15, 20, 25, 30, 35, 40),       # boots
    'shield': (14, 24, 30, 35, 39, 43, 47, 51, 55),    # defense (stock: 37-39 at 150-300, 53 at 350)
    'spellbook': (8, 12, 15, 18, 21, 24, 27, 30, 33),  # defense (stock: 20-27 at 220-400)
    'attack': (16, 40, 46, 49, 53, 57, 61, 65, 69),    # one-handed melee (stock: 43-54 at 55-120, 56 at 300, 71 at 1000)
    'defense': (10, 20, 25, 28, 30, 32, 34, 36, 38),   # one-handed melee
    'bow': (31, 38, 68, 71, 73, 76, 79, 82, 85),       # launcher attack (archery bands: 29-38 below 90, 65 + own from 90)
    'hit': (90, 93, 95, 95, 96, 96, 97, 97, 98),       # launcher hit chance
    'wand': (16, 40, 62, 85, 98, 108, 118, 128, 138),  # mean wand damage (stock: 80-100 at 150, 87-125 at 220-400)
    'mana': (2, 7, 13, 18, 21, 24, 27, 30, 33),        # mana per wand shot (stock: 19-22 at 150-400)
    'absorb': (2, 3, 4, 5, 6, 7, 8, 9, 10),            # % of the set's element on body and amulet (half on others)
    'jewel': (1, 1, 2, 2, 3, 3, 4, 4, 5),              # amulet armour; ring armour and physical % one lower (min 0)
}
FIT_SHARE = {'H': 1.0, 'M': 0.9, 'C': 0.8, 'A': 0.9}   # armour of a fit against heavy
ELEMENT_SHARE = 0.35                                    # melee: this share of the attack is the set's element
STEPS = {   # bonus = how many of these levels the piece has reached
    'skill': (50, 200, 500, 1000, 1600),       # weapon skill (+1 per step)
    'magic': (8, 100, 250, 500, 1000),         # spellbook magic level
    'robe': (50, 200, 500, 1000, 1600),        # cloth body armour magic level
    'cloth': (100, 400, 1000, 1600),           # cloth helmet and legs magic level
    'wandml': (100, 300, 700, 1500),           # wand / rod magic level
    'armorskill': (200, 700, 1500),            # heavy / medium body armour skills
    'shieldskill': (200, 700, 1500),           # shield skill on shields
    'extradef': (50, 200, 700),                # one-handed melee extra defense
    'leech': (50, 300, 800, 1500),             # Bloodmoon weapons: life leech chance and amount +1 per step from 2
}
WEIGHT = {'helmet': {'H': 4200, 'M': 3200, 'C': 1600, 'A': 3200}, 'armor': {'H': 9600, 'M': 7200, 'C': 2600, 'A': 7200},
          'legs': {'H': 6000, 'M': 4200, 'C': 2000, 'A': 4800}, 'boots': 1500, 'shield': 6000, 'spellbook': 1800,
          'sword': {'1': 3500, '2': 6500}, 'axe': {'1': 4200, '2': 7000}, 'club': {'1': 4800, '2': 7500},
          'bow': 3100, 'crossbow': 4000, 'wand': 1900, 'rod': 2400, 'amulet': 500, 'ring': 100}
PLURAL_NOUNS = ('boots', 'sabatons', 'treads', 'striders', 'sollerets', 'walkers', 'steps', 'legplates', 'tassets',
                'cuisses', 'greaves', 'leggings', 'chausses', 'breeches', 'legguards', 'trousers', 'legwraps')


def curve(name, level):
    ys = CURVES[name]
    if level <= ANCHORS[0]:
        return float(ys[0])
    for (x0, y0), (x1, y1) in zip(zip(ANCHORS, ys), zip(ANCHORS[1:], ys[1:])):
        if level <= x1:
            return y0 + (y1 - y0) * (level - x0) / float(x1 - x0)
    return float(ys[-1])


def rnd(x):
    return int(x + 0.5)


def steps(name, level):
    return sum(1 for s in STEPS[name] if level >= s)


def track(r):
    """the track of a piece: armour kinds by fit, melee by hands, the rest by kind"""
    k, fit = r['kind'], r['ex']['fit']
    if k in ('helmet', 'armor', 'legs'):
        return '%s/%s' % (k, fit)
    if k in ('sword', 'axe', 'club'):
        return k + fit
    return k


def classes_of(r):
    k, fit = r['kind'], r['ex']['fit']
    if k in ('helmet', 'armor', 'legs'):
        return FITS[fit]
    return FITS[track(r)]


def assign_levels(rows):
    """level of every piece: its track spread over its set's band in manifest (sheet) order, rounded to 5"""
    by = {}
    for r in rows:
        by.setdefault((r['ex']['set'], track(r)), []).append(r)
    for (setkey, _t), rs in by.items():
        lo, hi = SET_BY_KEY[setkey][2]
        for i, r in enumerate(rs):
            lv = lo if len(rs) == 1 else lo + (hi - lo) * i / float(len(rs) - 1)
            r['level'] = max(lo, min(hi, 5 * rnd(lv / 5.0))) if i else lo
    return rows


def rows_of(path):
    rows = read_manifest(path)
    for r in rows:
        assert r['mode'] == 'new', r['key']
        assert r['server_id'] == r['client_id'] + 3000, 'server id must be client id + 3000 (%s)' % r['key']
        assert FIRST <= r['server_id'] <= LAST, '%s: server id %d outside %d..%d' % (r['key'], r['server_id'], FIRST, LAST)
        assert r['ex']['set'] in SET_BY_KEY and r['kind'] == r['ex']['kind'], r['key']
    assign_levels(rows)
    for r in rows:
        r['stats'] = stats_of(r)
        r['classes'] = classes_of(r)
    return rows


def stats_of(r):
    """the piece's numbers: [(items.xml key, value)] in a fixed order, and r['wand'] = (min, max, mana) for wands"""
    k, fit, lv = r['kind'], r['ex']['fit'], r['level']
    s = SET_BY_KEY[r['ex']['set']]
    dmg, res, weak = ELEMENT_KEY[s[3]], ELEMENT_KEY[s[4]], ELEMENT_KEY[s[5]]
    ab = curve('absorb', lv)
    half = max(1, rnd(ab / 2))
    out = []
    if k in ('helmet', 'armor', 'legs'):
        out.append(('armor', max(1, rnd(curve(k, lv) * FIT_SHARE[fit]))))
        if k == 'armor':
            n = steps('armorskill', lv)
            if fit == 'H' and n:
                out += [('skillSword', n), ('skillAxe', n), ('skillClub', n)]
            elif fit == 'M' and n:
                out += [('skillDist', n), ('skillSword', n), ('skillFist', n)]
            elif fit == 'C' and steps('robe', lv):
                out.append(('magiclevelpoints', steps('robe', lv)))
            out += [('absorbPercent' + res, rnd(ab)), ('absorbPercent' + weak, -half)]
        else:
            if fit == 'C' and steps('cloth', lv):
                out.append(('magiclevelpoints', steps('cloth', lv)))
            out.append(('absorbPercent' + res, half))
    elif k == 'boots':
        out.append(('armor', rnd(curve('boots', lv))))
        if rnd(curve('speed', lv)):
            out.append(('speed', rnd(curve('speed', lv))))
    elif k == 'shield':
        out.append(('defense', rnd(curve('shield', lv))))
        if steps('shieldskill', lv):
            out.append(('skillShield', steps('shieldskill', lv)))
        out.append(('absorbPercent' + res, half))
    elif k == 'spellbook':
        out += [('defense', rnd(curve('spellbook', lv))), ('magiclevelpoints', steps('magic', lv)),
                ('absorbPercent' + res, half)]
    elif k in ('sword', 'axe', 'club'):
        two = fit == '2'
        total = rnd(curve('attack', lv)) + (3 if two else 0)
        elem = rnd(total * ELEMENT_SHARE)
        out += [('attack', total - elem), ('element' + dmg, elem),
                ('defense', rnd(curve('defense', lv)) + (4 if two else 0))]
        if not two and steps('extradef', lv):
            out.append(('extradef', steps('extradef', lv)))
        if steps('skill', lv):
            out.append(('skill' + k.capitalize(), steps('skill', lv)))
        if two:
            out.append(('attackspeed', 3000))
    elif k in ('bow', 'crossbow'):
        out += [('attack', rnd(curve('bow', lv)) + (3 if k == 'crossbow' else 0)), ('hitChance', rnd(curve('hit', lv))),
                ('shootType', s[7] if k == 'bow' else s[8]), ('range', 6)]
        if steps('skill', lv):
            out.append(('skillDist', steps('skill', lv)))
        out.append(('attackspeed', 3000))
    elif k in ('wand', 'rod'):
        mean = curve('wand', lv)
        r['wand'] = (rnd(mean * 0.85), rnd(mean * 1.15), rnd(curve('mana', lv)), s[3])
        out += [('shootType', s[6]), ('range', 5 if lv < 100 else 6)]
        if steps('wandml', lv):
            out.append(('magiclevelpoints', steps('wandml', lv)))
    elif k == 'amulet':
        out += [('armor', rnd(curve('jewel', lv))), ('absorbPercent' + res, rnd(ab))]
    elif k == 'ring':
        j = rnd(curve('jewel', lv)) - 1
        if j > 0:
            out.append(('armor', j))
        out.append(('absorbPercentPhysical', max(1, j)))
    if s[0] == 'bloodmoon' and k in ('sword', 'axe', 'club', 'bow', 'crossbow', 'wand', 'rod'):
        n = 2 + steps('leech', lv)
        out += [('lifeleechchance', n), ('lifeleechamount', n)]
    return out


# ------------------------------------------------------------------------------------------------ items.xml
def weapon_type(k):
    return {'sword': 'sword', 'axe': 'axe', 'club': 'club', 'bow': 'distance', 'crossbow': 'distance', 'wand': 'wand',
            'rod': 'wand', 'shield': 'shield', 'spellbook': 'shield'}.get(k)


def article_of(name):
    if name.split()[-1] in PLURAL_NOUNS:
        return ''
    return 'an' if name[0] in 'aeiou' else 'a'


def weight_of(r):
    w = WEIGHT[r['kind']]
    return w[r['ex']['fit']] if isinstance(w, dict) else w


def description(r):
    s = SET_BY_KEY[r['ex']['set']]
    return 'A piece of the %s set (levels %d-%d).' % (s[1], s[2][0], s[2][1])


def xml_item(r):
    k = r['kind']
    art = article_of(r['name'])
    head = 'id="%d"%s name="%s"' % (r['server_id'], ' article="%s"' % art if art else '', xml_escape(r['name']))
    attrs = [('description', description(r)), ('weight', weight_of(r))]
    if weapon_type(k):
        attrs.append(('weaponType', weapon_type(k)))
    if k in SLOT:
        attrs.append(('slotType', SLOT[k] if k != 'armor' else 'body'))
    if k in ('bow', 'crossbow') or r['ex']['fit'] == '2':
        attrs.append(('slotType', 'two-handed'))
    attrs += r['stats']
    body = ''.join('\t\t<attribute key="%s" value="%s" />\n' % (key, xml_escape(str(v))) for key, v in attrs)
    return '\t<item %s>\n%s\t</item>\n' % (head, body)


def patch_xml(text, rows):
    block = BEGIN['xml'] + ''.join(xml_item(r) for r in rows) + END
    return replace_block(text, BEGIN['xml'], END, block, '</items>', [r['server_id'] for r in rows], 'items.xml')


def replace_block(text, begin, end, block, root, ids, what):
    """install_fist_weapons.py's block rules (an id outside the block or in a range entry stops the script)"""
    try:
        new, note = _replace_block(text, begin, end, block, root, ids, what)
    except SystemExit as e:
        raise SystemExit(str(e).replace('fist weapon block', 'equipment set block'))
    return new, note.replace('fist weapon block', 'equipment set block')


# ------------------------------------------------------------------------------------------------ movements / weapons
def vocation_lines(classes, pad='\t\t'):
    out = []
    for v in classes:
        base = next(b for b, line in BASES.items() if v in line)
        shown = v == base or base not in classes
        out.append('%s<vocation name="%s"%s />\n' % (pad, v, '' if shown else ' showInDescription="0"'))
    return ''.join(out)


def equip_slot(r):
    k = r['kind']
    if k in SLOT:
        return SLOT[k]
    if k in ('shield', 'spellbook'):
        return 'shield'
    return 'two-handed' if k in ('bow', 'crossbow') or r['ex']['fit'] == '2' else 'hand'


def move_entries(r):
    slot, voc = equip_slot(r), vocation_lines(r['classes'])
    if slot == 'two-handed':
        slot = 'hand'
    if voc:
        eq = ('\t<movevent event="Equip" itemid="%d" slot="%s" level="%d" function="onEquipItem">\n%s\t</movevent>\n'
              % (r['server_id'], slot, r['level'], voc))
    else:
        eq = '\t<movevent event="Equip" itemid="%d" slot="%s" level="%d" function="onEquipItem" />\n' % (
            r['server_id'], slot, r['level'])
    return eq + '\t<movevent event="DeEquip" itemid="%d" slot="%s" function="onDeEquipItem" />\n' % (r['server_id'], slot)


def patch_moves(text, rows):
    block = BEGIN['moves'] + ''.join(move_entries(r) for r in rows) + END
    return replace_block(text, BEGIN['moves'], END, block, '</movements>', [r['server_id'] for r in rows],
                         'movements.xml')


def weapon_entry(r):
    k, voc = r['kind'], vocation_lines(r['classes'])
    if k in ('wand', 'rod'):
        mn, mx, mana, elem = r['wand']
        return ('\t<wand id="%d" level="%d" mana="%d" min="%d" max="%d" type="%s"> <!-- %s -->\n%s\t</wand>\n'
                % (r['server_id'], r['level'], mana, mn, mx, elem, r['name'], voc))
    tag = 'distance' if k in ('bow', 'crossbow') else 'melee'
    return '\t<%s id="%d" level="%d" unproperly="1"> <!-- %s -->\n%s\t</%s>\n' % (tag, r['server_id'], r['level'],
                                                                               r['name'], voc, tag)


def weapon_rows(rows):
    return [r for r in rows if r['kind'] in ('sword', 'axe', 'club', 'bow', 'crossbow', 'wand', 'rod')]


def patch_weapons(text, rows):
    ws = weapon_rows(rows)
    block = BEGIN['weapons'] + ''.join(weapon_entry(r) for r in ws) + END
    return replace_block(text, BEGIN['weapons'], END, block, '</weapons>', [r['server_id'] for r in ws], 'weapons.xml')


# ------------------------------------------------------------------------------------------------ Lua data
def lua_value(v):
    return '"%s"' % v if isinstance(v, str) else str(v)


def lua_text(rows):
    L = ['-- The pieces of the equipment sets of client pair 28 (server/tools/install_gear_sets.py --lua, from',
         '-- server/data/items/gear_sets.csv). Generated; do not edit by hand. Read by data/lib/chaos_gear_sets.lua.',
         '-- sets: key -> {name, band = {from, to}, element, resist}; pieces in id order: id, key, set, kind, fit (H / M /',
         '-- C / A armour, 1 / 2 hands), level, name, classes ({} = everyone), stats (the items.xml numbers).',
         '', 'return {', '\tfirst = %d,' % FIRST, '\tlast = %d,' % LAST, '\tsets = {']
    for key, name, (lo, hi), dmg, res, *_r in SETS:
        L.append('\t\t%s = {name = "%s", band = {%d, %d}, element = "%s", resist = "%s"},' % (key, name, lo, hi, dmg, res))
    L += ['\t},', '\tpieces = {']
    for r in rows:
        st = ', '.join('%s = %s' % (k, lua_value(v)) for k, v in r['stats'])
        if r.get('wand'):
            st += ', wandMin = %d, wandMax = %d, mana = %d' % r['wand'][:3]
        L.append('\t\t{id = %d, key = "%s", set = "%s", kind = "%s", fit = "%s", level = %d, name = "%s", classes = {%s},'
                 % (r['server_id'], r['key'], r['ex']['set'], r['kind'], r['ex']['fit'], r['level'], r['name'],
                    ', '.join('"%s"' % c for c in r['classes'])))
        L.append('\t\t\tstats = {%s}},' % st)
    L += ['\t}', '}', '']
    return '\n'.join(L)


def pair28_on(path=SWITCH):
    if not os.path.isfile(path):
        return False
    return re.search(r'^M\.PAIR28\s*=\s*true\b', open(path, encoding='utf-8').read(), re.M) is not None


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    manifest = DEFAULT_MANIFEST
    if '--manifest' in args:
        i = args.index('--manifest'); manifest = args[i + 1]; del args[i:i + 2]
    rows = rows_of(manifest)
    if '--lua' in args:
        text = lua_text(rows)
        if '--check' in args:
            if not os.path.isfile(LUA_OUT) or open(LUA_OUT).read() != text:
                print('%s is stale: run install_gear_sets.py --lua' % LUA_OUT)
                return 1
            print('chaos_gear_sets_items.lua up to date')
            return 0
        open(LUA_OUT, 'w').write(text)
        print('wrote', LUA_OUT)
        return 0
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    paths = {'otb': os.path.join(data_dir, 'items', 'items.otb'), 'xml': os.path.join(data_dir, 'items', 'items.xml'),
             'moves': os.path.join(data_dir, 'movements', 'movements.xml'),
             'weapons': os.path.join(data_dir, 'weapons', 'weapons.xml')}
    for p in paths.values():
        if not os.path.exists(p):
            print('not found:', p)
            return 1
    raw = open(paths['otb'], 'rb').read()
    new_otb, c = patch_otb(raw, rows)
    n = verify_otb(new_otb, rows)
    print('items.otb: %d nodes added, %d updated; verified (%d item nodes)' % (c['new'], c['updated'], n))
    texts, news = {}, {}
    for key, fn in (('xml', patch_xml), ('moves', patch_moves), ('weapons', patch_weapons)):
        texts[key] = open(paths[key], encoding='utf-8', errors='surrogateescape').read()
        news[key], note = fn(texts[key], rows)
        print(note)
    print('switch ChaosGearSets.PAIR28 is %s' % ('on' if pair28_on() else 'off (the items exist but nothing drops them)'))
    if dry:
        print('dry run: nothing written')
        return 0
    if new_otb != raw:
        if not os.path.exists(paths['otb'] + '.bak'):
            shutil.copy2(paths['otb'], paths['otb'] + '.bak')
        open(paths['otb'], 'wb').write(new_otb)
    for key in news:
        if news[key] != texts[key]:
            open(paths[key], 'w', encoding='utf-8', errors='surrogateescape', newline='').write(news[key])
    return 0


if __name__ == '__main__':
    sys.exit(main())
