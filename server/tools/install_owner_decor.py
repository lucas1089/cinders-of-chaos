#!/usr/bin/env python3
"""Install the decoration items of client pair 26 (the owner's art) into a base server: items.otb and items.xml.

usage: python3 -I install_owner_decor.py DATA_DIR [--dry-run] [--manifest CSV]
       python3 -I install_owner_decor.py --lua [--check] [--manifest CSV]   (server/data/lib/chaos_owner_decor.lua)

The manifest (default server/data/items/owner_decor.csv) is written by client/tools/sprites/import_art_things.py
(--manifest-out) from client/tools/sprites/art_import/owner_art.csv (gen_owner_art.py): client ids 33940..33985,
server id = client id + 3000 (36940..36985). Rows:
  - 45 plants (key cactus_01..cactus_45, extra family=cacti, block=0|1): the bigger potted cacti block a tile (kind
    stump: otb SOLID, on the bottom of the stack like the stock trees), the small plants do not (kind decor);
  - the waypoint seal (key waypoint_seal, kind decor): a 3x3 floor seal with 60 animation phases and a cyan light,
    walkable. The item draws up and left of its tile: put it on the south-east tile of the 3x3 square it covers.
None is moveable or pickupable; items.xml gives each a name and nothing else. otb group, flags, top order and light
come from the manifest. Same node rules as install_theme_items.py / install_pack_items.py: a node already there with
the same bytes is left alone, one of the same group and flags is replaced, anything else with that server id stops
the script; items.otb.bak keeps the original the first time; the written file is parsed again and every node checked.
items.xml: a block between two marker comments before </items>, rewritten when the manifest changed; an id with an
entry outside the block stops it.

The items exist only in client pair 26 (things_custom26, on windows-assets since 2026-10-15). ChaosOwnerArt.PAIR26
(data/lib/chaos_owner_art.lua) is on: the area planner adds them to its kits and map makers may place them. Off, the
items may be installed, but nothing in the game uses them. Idempotent: a second run changes nothing.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_pack_items import read_manifest, patch_otb, verify_otb  # noqa: E402
from install_dark_tiles import xml_escape  # noqa: E402

REPO_DATA = os.path.join(os.path.dirname(HERE), 'data')
DEFAULT_MANIFEST = os.path.join(REPO_DATA, 'items', 'owner_decor.csv')
LUA_OUT = os.path.join(REPO_DATA, 'lib', 'chaos_owner_decor.lua')
SWITCH = os.path.join(REPO_DATA, 'lib', 'chaos_owner_art.lua')
XML_BEGIN = '\t<!-- Chaos owner decoration (server/tools/install_owner_decor.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos owner decoration -->\n'
FIRST, LAST = 36940, 36985
# a stock item is "prickly pear" (loot of the Ogre Shaman, named by item name in monster XML): a second item of that name
# makes the engine refuse the whole loot ("Non-unique loot item"). The art sheet names stay, the install renames.
RENAMES = {'cactus_38': 'prickly pear cactus'}


def pair26_on(path=SWITCH):
    """the server switch, read from the Lua module"""
    if not os.path.isfile(path):
        return False
    return re.search(r'^M\.PAIR26\s*=\s*true\b', open(path, encoding='utf-8').read(), re.M) is not None


def rows_of(path):
    rows = read_manifest(path)
    for r in rows:
        r['name'] = RENAMES.get(r['key'], r['name'])
        assert r['mode'] == 'new', r['key']
        assert r['server_id'] == r['client_id'] + 3000, 'server id must be client id + 3000 (%s)' % r['key']
        assert FIRST <= r['server_id'] <= LAST, '%s: server id %d outside %d..%d' % (r['key'], r['server_id'], FIRST, LAST)
        assert r['kind'] in ('stump', 'decor'), r['key']
        assert r['ex'].get('family') in ('cacti', 'waypoint'), r['key']
    return rows


def article(name):
    return 'an' if name[0] in 'aeiou' else 'a'


def xml_item(r):
    return '\t<item id="%d" article="%s" name="%s" />\n' % (r['server_id'], article(r['name']), xml_escape(r['name']))


def patch_xml(text, rows):
    block = XML_BEGIN + ''.join(xml_item(r) for r in rows) + XML_END
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: owner decoration start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in rows:
        sid = r['server_id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the owner decoration block; nothing written'
                             % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: owner decoration block up to date (%d items)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: owner decoration block rewritten (%d items)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: owner decoration block added (%d items)' % len(rows)


def lua_text(rows):
    L = ['-- Server ids of the decoration items of client pair 26 (server/tools/install_owner_decor.py --lua, from',
         '-- server/data/items/owner_decor.csv). Generated; do not edit by hand. Used by data/lib/chaos_owner_art.lua, and',
         '-- only while its switch ChaosOwnerArt.PAIR26 is on.', '',
         'return {', '\tfirst = %d,' % FIRST, '\tlast = %d,' % LAST,
         '\t-- the plants in sheet order: key, server id, blocks a tile, name', '\tplants = {']
    wp = None
    for r in rows:
        if r['ex']['family'] == 'waypoint':
            wp = r['server_id']
            continue
        L.append('\t\t{key = "%s", id = %d, block = %s, name = "%s"},' % (
            r['key'], r['server_id'], 'true' if r['ex'].get('block') == '1' else 'false', r['name']))
    L += ['\t},', '\t-- the 3x3 waypoint seal (put it on the south-east tile of the square it covers)',
          '\twaypoint = %s' % (wp if wp else 'nil'), '}', '']
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
                print('%s is stale: run install_owner_decor.py --lua' % LUA_OUT)
                return 1
            print('chaos_owner_decor.lua up to date')
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
    print('switch ChaosOwnerArt.PAIR26 is %s' % ('on' if pair26_on() else 'off (the items exist but nothing uses them)'))
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
