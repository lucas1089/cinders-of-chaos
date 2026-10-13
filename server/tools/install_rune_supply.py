#!/usr/bin/env python3
"""Rune supply: no spell conjures a rune; runes come from NPC vendors and the crafting tables (server/README.md
"Rune supply"; owner: "Tire as spells de fazer runa. Deixa as runas serem de vendedores e craft.").

usage: python3 -I install_rune_supply.py DATA_DIR [--dry-run]

Everything is read from server/data/lib/chaos_rune_supply.lua (runes, prices, vendors, crafting category), the same file
the base crafting script loads at startup (install step "files" copies it to DATA_DIR/lib).

1. spells/spells.xml: every <instant>/<conjure> whose script is one of the removed conjure scripts (conjuring/<name>.lua
   of the runes and blank_rune.lua; R.otherConjures: support/food.lua, conjuring/enchant_spear.lua,
   conjuring/enchant_staff.lua) is commented out (marker "Chaos: no conjuring"), wherever it is and whatever it is
   called by then (rename_spells.py may have renamed it). The <rune> entries (using a rune) stay. The scripts stay on
   disk, unregistered. The ammunition conjure spells belong to patch_base_archery.py. An entry an earlier version
   commented out ("Chaos: no rune conjuring") stays as it is.
2. NPC shops: every NPC that sells one of the runes or the unscribed rune sells it at the config's price
   (data/npc/**/*.xml shop_buyable "name,id,price[,subtype]"; data/npc/**/*.lua shopModule:addBuyableItem({...}, id,
   price, ...) and {..., id = n, ..., buy = price} tables). The vendors of the config (by their Chaos name, or before the
   npcnames step by the sha256 of the old name in data/npc/base_npc_names.csv) get every rune and the unscribed rune
   they do not list yet ("<chaos name>,id,price;"). A vendor that is missing or has no shop_buyable list is an error.
3. The crafting category file (data/scripts/customs/crafting/<category>.lua) gets a loader block at its end: it runs
   ChaosRuneSupply.addRecipes(Crafting.<category>) from data/lib/chaos_rune_supply.lua, so the recipes follow the config
   without another install. No such file (no base crafting): skipped and listed.

Idempotent: a second run changes nothing. Exit 1 when a vendor cannot be stocked (nothing is written then).
"""
import csv, glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
CONFIG = os.path.join(HERE, '..', 'data', 'lib', 'chaos_rune_supply.lua')
NPC_NAMES = os.path.join(HERE, '..', 'data', 'npc', 'base_npc_names.csv')
SPELL_MARK = 'Chaos: no conjuring (install_rune_supply.py): '
CRAFT_MARK = '-- Chaos: rune recipes (install_rune_supply.py) v1'


# ------------------------------------------------------------------------------------------------ config
def load_config(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    cfg = {'runes': []}
    for m in re.finditer(r'\{id = (\d+), name = "([^"]+)", level = (\d+), script = "([^"]+)", mana = (\d+), '
                         r'soul = (\d+), count = (\d+), price = (\d+), old = (\d+)\}', text):
        cfg['runes'].append({'id': int(m.group(1)), 'name': m.group(2), 'level': int(m.group(3)),
                             'script': m.group(4), 'price': int(m.group(8))})
    b = re.search(r'R\.blankRune = \{id = (\d+), name = "([^"]+)", script = "([^"]+)", price = (\d+)\}', text)
    assert b, 'chaos_rune_supply.lua: no R.blankRune'
    cfg['blank'] = {'id': int(b.group(1)), 'name': b.group(2), 'script': b.group(3), 'price': int(b.group(4))}
    vend = re.search(r'R\.vendors = \{(.*?)\n\}', text, re.S)
    cfg['vendors'] = [(n, int(t)) for n, t in re.findall(r'\{name = "([^"]+)", town = (\d+)\}', vend.group(1) if vend else '')]
    cat = re.search(r'category = "(\w+)"', text)
    cfg['category'] = cat.group(1) if cat else None
    assert cfg['runes'] and cfg['vendors'] and cfg['category'], 'chaos_rune_supply.lua: runes, vendors or category missing'
    others = re.search(r'R\.otherConjures = \{(.*?)\n\}', text, re.S)
    cfg['others'] = re.findall(r'\{script = "([^"]+)", name = "([^"]+)"\}', others.group(1) if others else '')
    assert cfg['others'], 'chaos_rune_supply.lua: no R.otherConjures'
    # spells.xml script paths (relative to data/spells/scripts) of every spell that goes
    cfg['scripts'] = ({'conjuring/' + cfg['blank']['script']} | {'conjuring/' + r['script'] for r in cfg['runes']}
                      | {s for s, _n in cfg['others']})
    cfg['prices'] = {r['id']: r['price'] for r in cfg['runes']}
    cfg['prices'][cfg['blank']['id']] = cfg['blank']['price']
    cfg['stock'] = [(r['id'], r['name'].lower(), r['price']) for r in [cfg['blank']] + cfg['runes']]
    return cfg


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


# ------------------------------------------------------------------------------------------------ spells.xml
def patch_spells(text, cfg):
    comments = [(m.start(), m.end()) for m in re.finditer(r'<!--.*?-->', text, re.S)]

    def inside(pos):
        return any(s <= pos < e for s, e in comments)
    n = [0]

    def spell(m):
        script = re.search(r'\bscript="([^"]+)"', m.group(1))
        if not script or script.group(1).replace('\\', '/').lstrip('./') not in cfg['scripts'] or inside(m.start()):
            return m.group(0)
        n[0] += 1
        return '<!-- ' + SPELL_MARK + m.group(0).replace('--', '- -') + ' -->'
    out = re.sub(r'<(?:instant|conjure)\s([^>]*?)(?:/>|>.*?</(?:instant|conjure)>)', spell, text, flags=re.S)
    return out, ('spells.xml: %d conjure spell(s) switched off' % n[0] if n[0] else
                 'spells.xml: no removed conjure spell is active')


# ------------------------------------------------------------------------------------------------ NPC shops
SHOP_ENTRY = re.compile(r'(^|;)(\s*[^,;"]*?\s*,\s*)(\d+)(\s*,\s*)(\d+)')
LUA_ADD = re.compile(r'(addBuyableItem\s*\(\s*(?:\{[^}]*\}|nil|"[^"]*"|\'[^\']*\')\s*,\s*)(\d+)(\s*,\s*)(\d+)')
LUA_TABLE = re.compile(r'\{[^{}]*?\bid\s*=\s*(\d+)[^{}]*?\bbuy\s*=\s*\d+[^{}]*?\}')


def reprice_list(value, prices):
    n = [0]

    def entry(m):
        iid = int(m.group(3))
        if iid not in prices or int(m.group(5)) == prices[iid]:
            return m.group(0)
        n[0] += 1
        return m.group(1) + m.group(2) + m.group(3) + m.group(4) + str(prices[iid])
    return SHOP_ENTRY.sub(entry, value), n[0]


def reprice_xml(text, prices):
    m = re.search(r'(<parameter\s+key="shop_buyable"\s+value=")([^"]*)(")', text)
    if not m:
        return text, 0
    val, n = reprice_list(m.group(2), prices)
    return text[:m.start(2)] + val + text[m.end(2):], n


def reprice_lua(text, prices):
    n = [0]

    def add(m):
        iid = int(m.group(2))
        if iid not in prices or int(m.group(4)) == prices[iid]:
            return m.group(0)
        n[0] += 1
        return m.group(1) + m.group(2) + m.group(3) + str(prices[iid])

    def table(m):
        iid = int(m.group(1))
        if iid not in prices:
            return m.group(0)
        new = re.sub(r'(\bbuy\s*=\s*)(\d+)', lambda b: b.group(1) + str(prices[iid]), m.group(0), count=1)
        if new != m.group(0):
            n[0] += 1
        return new
    text = LUA_ADD.sub(add, text)
    text = LUA_TABLE.sub(table, text)
    return text, n[0]


def stock_vendor(text, stock):
    """append 'name,id,price;' for every rune the shop_buyable list does not have; None when there is no such list"""
    m = re.search(r'(<parameter\s+key="shop_buyable"\s+value=")([^"]*)(")', text)
    if not m:
        return None, 0
    val = m.group(2)
    have = {int(i) for i in re.findall(r'(?:^|;)\s*[^,;]*?\s*,\s*(\d+)\s*,', val)}
    new = [(iid, name, price) for iid, name, price in stock if iid not in have]
    if not new:
        return text, 0
    stripped = val.rstrip()
    sep = '' if not stripped or stripped.endswith(';') else ';'
    val2 = stripped + sep + ''.join('%s,%d,%d;' % (name, iid, price) for iid, name, price in new) + val[len(stripped):]
    return text[:m.start(2)] + val2 + text[m.end(2):], len(new)


def old_hashes(path=NPC_NAMES):
    out = {}
    if os.path.isfile(path):
        for r in csv.DictReader(open(path, encoding='utf-8')):
            out.setdefault(r['name'], r['sha256'])
    return out


def patch_npcs(npc_dir, cfg):
    """returns (notes, errors, {path: new text})"""
    import base_rename_lib
    notes, errors, changed = [], [], {}
    if not os.path.isdir(npc_dir):
        return ['npc: no data/npc folder, shops skipped'], ['npc: no data/npc folder, no vendor stocked'], changed
    prices = cfg['prices']
    files = sorted(glob.glob(os.path.join(npc_dir, '**', '*.xml'), recursive=True)
                   + glob.glob(os.path.join(npc_dir, '**', '*.lua'), recursive=True))
    texts = {p: read(p) for p in files}
    repriced = 0
    for path in files:
        fn = reprice_xml if path.endswith('.xml') else reprice_lua
        new, n = fn(texts[path], prices)
        if n:
            texts[path] = new
            changed[path] = new
            repriced += n
    notes.append('npc: %d rune prices set' % repriced if repriced else 'npc: every rune price is set')
    hashes = old_hashes()
    for name, town in cfg['vendors']:
        fn = base_rename_lib.npc_file(npc_dir, name, hashes.get(name, ''))
        if not fn:
            errors.append('vendor %s (town %d): no NPC file' % (name, town))
            continue
        path = os.path.join(npc_dir, fn)
        new, n = stock_vendor(texts[path], cfg['stock'])
        if new is None:
            errors.append('vendor %s (%s): no shop_buyable list' % (name, fn))
            continue
        if n:
            texts[path] = new
            changed[path] = new
        notes.append('npc %s (town %d): %s' % (name, town, '%d rune(s) added' % n if n else 'sells every rune'))
    return notes, errors, changed


# ------------------------------------------------------------------------------------------------ crafting
def craft_block(category, nl):
    lines = ['', CRAFT_MARK + ': the runes no spell conjures any more (data/lib/chaos_rune_supply.lua)', 'do',
             '\tlocal ok, runes = pcall(dofile, "data/lib/chaos_rune_supply.lua")',
             '\tif ok and type(runes) == "table" and runes.addRecipes and Crafting and Crafting.%s then' % category,
             '\t\trunes.addRecipes(Crafting.%s)' % category,
             '\telse',
             '\t\tprint("[Crafting] rune recipes not loaded: " .. tostring(runes))',
             '\tend',
             'end', '']
    return nl.join(lines)


def patch_crafting(data, cfg):
    path = os.path.join(data, 'scripts', 'customs', 'crafting', cfg['category'] + '.lua')
    if not os.path.isfile(path):
        return None, None, 'crafting: no %s.lua (no base crafting), recipes skipped' % cfg['category']
    text = read(path)
    if CRAFT_MARK in text:
        return path, None, 'crafting: rune recipes loaded by %s.lua' % cfg['category']
    nl = '\r\n' if '\r\n' in text else '\n'
    out = text if text.endswith(nl) or not text else text + nl
    return path, out + craft_block(cfg['category'], nl), 'crafting: rune recipe loader added to %s.lua' % cfg['category']


# ------------------------------------------------------------------------------------------------ main
def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry = '--dry-run' in sys.argv
    if len(args) != 1:
        print(__doc__)
        return 1
    data = args[0]
    cfg = load_config()
    changed, notes = {}, []
    sp = os.path.join(data, 'spells', 'spells.xml')
    if os.path.isfile(sp):
        text = read(sp)
        out, note = patch_spells(text, cfg)
        notes.append(note)
        if out != text:
            changed[sp] = out
    else:
        notes.append('spells.xml: not found, skipped')
    more, errors, npc_changed = patch_npcs(os.path.join(data, 'npc'), cfg)
    notes += more
    changed.update(npc_changed)
    path, out, note = patch_crafting(data, cfg)
    notes.append(note)
    if out is not None:
        changed[path] = out
    for n in notes:
        print(n)
    if errors:
        for e in errors:
            print('ERROR ' + e)
        print('nothing written')
        return 1
    for path in sorted(changed):
        print('%s %s' % ('would change' if dry else 'changed', os.path.relpath(path, data)))
        if not dry:
            write(path, changed[path])
    if not changed:
        print('nothing to do')
    return 0


if __name__ == '__main__':
    sys.exit(main())
