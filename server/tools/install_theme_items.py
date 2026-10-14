#!/usr/bin/env python3
"""Install the themed items of client pair things_custom24 into a base server: items.otb and items.xml.

usage: python3 -I install_theme_items.py DATA_DIR [--dry-run] [--manifest CSV]
       python3 -I install_theme_items.py --lua [--manifest CSV]   (rewrites server/data/lib/chaos_theme_items.lua)

The manifest (default server/data/items/theme_items.csv) is written by client/tools/sprites/import_art_things.py
(--manifest-out) from client/tools/sprites/art_import/theme_things.csv (gen_theme_art.py): client ids 33660..33903,
server id = client id + 3000 (36660..36903). Rows:
  - set pieces (kind sword, axe, club, bow, crossbow, wand, rod, shield, spellbook, helmet, armor, legs, boots, amulet,
    ring, backpack, arrow, bolt; extra set=, kit=): appearance items of the ten themed sets. items.xml gives each the
    weapon type / slot of its kind and nothing else: no attack, armour or other stat, no shop, no loot, no equip
    rules. They are transmog looks (data/lib/chaos_theme_art.lua), not gear.
  - grounds and border pieces (kind ground / border; extra family=, piece=): swamp, acid pool, lava, deep water.
    The liquids are blocking grounds (otb flag SOLID from the dat's notwalkable), lava and acid give light.
otb group, flags, top order, speed and light come from the manifest (the importer's table, from the stock item of
each kind). Same node rules as install_pack_items.py: a node already there with the same bytes is left alone, one of
the same group and flags is replaced, anything else with that server id stops the script; items.otb.bak keeps the
original the first time; the written file is parsed again and every node checked. items.xml: a block between two
marker comments before </items>, rewritten when the manifest changed; an id with an entry outside the block stops it.

Without the matching client pair (things_custom24) the items show as nothing in the client. ChaosThemeArt.PAIR24
(data/lib/chaos_theme_art.lua) is on since 2026-10-13 (pair 24 at 407ad9b6): the transmog sets use them. Off
(rollback), nothing in the game uses them: the transmog catalogue skips their ids and no set, exclusive or area names
them. Idempotent: a second run changes nothing.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_pack_items import read_manifest, patch_otb, verify_otb  # noqa: E402
from install_dark_tiles import xml_escape  # noqa: E402

REPO_DATA = os.path.join(os.path.dirname(HERE), 'data')
DEFAULT_MANIFEST = os.path.join(REPO_DATA, 'items', 'theme_items.csv')
LUA_OUT = os.path.join(REPO_DATA, 'lib', 'chaos_theme_items.lua')
SWITCH = os.path.join(REPO_DATA, 'lib', 'chaos_theme_art.lua')
XML_BEGIN = '\t<!-- Chaos themed items (server/tools/install_theme_items.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos themed items -->\n'
FIRST, LAST = 36660, 36903

# items.xml attributes per kind: (weight in oz/100, [(key, value)])
KIND = {
    'sword': (3500, [('weaponType', 'sword')]),
    'axe': (4200, [('weaponType', 'axe')]),
    'club': (4800, [('weaponType', 'club')]),
    'bow': (3100, [('weaponType', 'distance'), ('slotType', 'two-handed'), ('ammoType', 'arrow'), ('range', '6')]),
    'crossbow': (4000, [('weaponType', 'distance'), ('slotType', 'two-handed'), ('ammoType', 'bolt'), ('range', '6')]),
    'wand': (1900, [('weaponType', 'wand')]),
    'rod': (2400, [('weaponType', 'wand')]),
    'shield': (5500, [('weaponType', 'shield')]),
    'spellbook': (1800, [('weaponType', 'shield')]),
    'helmet': (3200, [('slotType', 'head')]),
    'armor': (8000, [('slotType', 'body')]),
    'legs': (5000, [('slotType', 'legs')]),
    'boots': (1500, [('slotType', 'feet')]),
    'amulet': (500, [('slotType', 'necklace')]),
    'ring': (100, [('slotType', 'ring')]),
    'backpack': (1800, [('containerSize', '20'), ('slotType', 'backpack')]),
    'arrow': (70, [('weaponType', 'ammunition'), ('ammoType', 'arrow'), ('slotType', 'ammo')]),
    'bolt': (90, [('weaponType', 'ammunition'), ('ammoType', 'bolt'), ('slotType', 'ammo')]),
}
PLURAL = {'arrow': 'arrows', 'bolt': 'bolts'}


def pair24_on(path=SWITCH):
    """the server switch, read from the Lua module (installers that write XML only for the pair)"""
    if not os.path.isfile(path):
        return False
    return re.search(r'^M\.PAIR24\s*=\s*true\b', open(path, encoding='utf-8').read(), re.M) is not None


def rows_of(path):
    rows = read_manifest(path)
    for r in rows:
        assert r['mode'] == 'new', r['key']
        assert r['server_id'] == r['client_id'] + 3000, 'server id must be client id + 3000 (%s)' % r['key']
        assert FIRST <= r['server_id'] <= LAST, '%s: server id %d outside %d..%d' % (r['key'], r['server_id'], FIRST, LAST)
        assert r['kind'] in KIND or r['kind'] in ('ground', 'border'), r['key']
    return rows


def article(name):
    return 'an' if name[0] in 'aeiou' else 'a'


def xml_item(r):
    kind, name, ex = r['kind'], r['name'], r['ex']
    if kind in ('ground', 'border'):
        return '\t<item id="%d" name="%s" />\n' % (r['server_id'], xml_escape(name))
    head = 'id="%d" article="%s" name="%s"' % (r['server_id'], article(name), xml_escape(name))
    if kind in PLURAL:
        head += ' plural="%s"' % xml_escape(name[:-len(kind)] + PLURAL[kind])
    weight, attrs = KIND[kind]
    desc = 'An appearance piece of the %s set.' % ex['set'].capitalize()
    attrs = [('description', desc), ('weight', str(weight))] + attrs
    body = ''.join('\t\t<attribute key="%s" value="%s" />\n' % (k, xml_escape(v)) for k, v in attrs)
    return '\t<item %s>\n%s\t</item>\n' % (head, body)


def patch_xml(text, rows):
    block = XML_BEGIN + ''.join(xml_item(r) for r in rows) + XML_END
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: themed item start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in rows:
        sid = r['server_id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the themed item block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: themed item block up to date (%d items)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: themed item block rewritten (%d items)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: themed item block added (%d items)' % len(rows)


def lua_text(rows):
    L = ['-- Server ids of the themed items of client pair things_custom24 (server/tools/install_theme_items.py --lua, from',
         '-- server/data/items/theme_items.csv). Generated; do not edit by hand. Used by data/lib/chaos_theme_art.lua, and',
         '-- only while its switch ChaosThemeArt.PAIR24 is on.', '',
         'return {', '\tfirst = %d,' % FIRST, '\tlast = %d,' % LAST,
         '\t-- set pieces in atlas order: key, server id, set, kit ("" for the full sets), kind', '\tpieces = {']
    for r in rows:
        if r['kind'] in ('ground', 'border'):
            continue
        ex = r['ex']
        L.append('\t\t{key = "%s", id = %d, set = "%s", kit = "%s", kind = "%s", name = "%s"},' % (
            r['key'], r['server_id'], ex['set'], ex.get('kit', ''), r['kind'], r['name']))
    L += ['\t},', '\t-- grounds: family -> {ground = id, <border piece> = id} (pieces named by where the family lies)',
          '\tgrounds = {']
    fams = {}
    for r in rows:
        if r['kind'] in ('ground', 'border'):
            fams.setdefault(r['ex']['family'], []).append(r)
    for fam, rs in fams.items():
        parts = ['%s = %d' % ('ground' if r['kind'] == 'ground' else r['ex']['piece'], r['server_id']) for r in rs]
        L.append('\t\t%s = {%s},' % (fam, ', '.join(parts)))
    L += ['\t}', '}', '']
    return '\n'.join(L)


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
                print('%s is stale: run install_theme_items.py --lua' % LUA_OUT)
                return 1
            print('chaos_theme_items.lua up to date')
            return 0
        open(LUA_OUT, 'w').write(text)
        print('wrote', LUA_OUT)
        return 0
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(data_dir, 'items'))
        return 1
    raw = open(otb, 'rb').read()
    new, c = patch_otb(raw, rows)
    n = verify_otb(new, rows)
    print('items.otb: %d nodes added, %d updated; verified (%d item nodes)' % (c['new'], c['updated'], n))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, note = patch_xml(text, rows)
    print(note)
    print('switch ChaosThemeArt.PAIR24 is %s' % ('on' if pair24_on() else 'off (the items exist but nothing uses them)'))
    if dry:
        print('dry run: nothing written')
        return 0
    if new != raw:
        if not os.path.exists(otb + '.bak'):
            open(otb + '.bak', 'wb').write(raw)
        open(otb, 'wb').write(new)
    if new_text != text:
        open(xml, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
