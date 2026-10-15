#!/usr/bin/env python3
"""Install the catacomb decoration items of the pair 27 trial (the owner's licensed kit) into a base server.

usage: python3 -I install_assets_decor.py DATA_DIR [--dry-run] [--manifest CSV]
       python3 -I install_assets_decor.py --lua [--check] [--manifest CSV]   (server/data/lib/chaos_assets_decor.lua)

The manifest (default server/data/items/assets_decor.csv) is written by client/tools/sprites/import_art_things.py
(--manifest-out) from client/tools/sprites/art_import/assets_art.csv (gen_assets_art.py): client ids 33986..33994,
server id = client id + 3000 (36986..36994). Rows (extra family=catacomb, block=0|1):
  - crypt_portal (3x3, 8 phases, purple light), crypt_portal_collapse (4x4, 8 phases), crypt_portal_husk (4x4);
  - crypt_seal (3x3, blocks), crypt_seal_breaking (3x3, 8 phases, blocks), crypt_seal_open (3x3, walkable);
  - sarcophagus, sarcophagus_opening (8 phases), sarcophagus_open (2x3, all block).
Each item draws up and left of its tile: put it on the south-east tile of the square it covers.
None is moveable or pickupable; items.xml gives each a name. Node rules as install_owner_decor.py (same helpers):
a node already there with the same bytes is left alone, one of the same group and flags is replaced, anything else
with that server id stops the script; items.otb.bak keeps the original the first time; items.xml holds a block
between two marker comments before </items>.

The items exist since pair 27 (windows-assets 51a26d26). ChaosAssetsArt.PAIR27 (data/lib/chaos_assets_art.lua) is
off: the items may be installed, but nothing in the game uses them (the area planner's overlay
server/tools/areaplan/decor_assets_art.json is merged only while the switch is on). Idempotent.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_pack_items import read_manifest, patch_otb, verify_otb  # noqa: E402
from install_dark_tiles import xml_escape  # noqa: E402

REPO_DATA = os.path.join(os.path.dirname(HERE), 'data')
DEFAULT_MANIFEST = os.path.join(REPO_DATA, 'items', 'assets_decor.csv')
LUA_OUT = os.path.join(REPO_DATA, 'lib', 'chaos_assets_decor.lua')
SWITCH = os.path.join(REPO_DATA, 'lib', 'chaos_assets_art.lua')
XML_BEGIN = '\t<!-- Chaos catacomb kit decoration (server/tools/install_assets_decor.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos catacomb kit decoration -->\n'
FIRST, LAST = 36986, 36994


def pair27_on(path=SWITCH):
    if not os.path.isfile(path):
        return False
    return re.search(r'^M\.PAIR27\s*=\s*true\b', open(path, encoding='utf-8').read(), re.M) is not None


def rows_of(path):
    rows = read_manifest(path)
    for r in rows:
        assert r['mode'] == 'new', r['key']
        assert r['server_id'] == r['client_id'] + 3000, 'server id must be client id + 3000 (%s)' % r['key']
        assert FIRST <= r['server_id'] <= LAST, '%s: server id %d outside %d..%d' % (r['key'], r['server_id'], FIRST,
                                                                                     LAST)
        assert r['kind'] in ('stump', 'decor'), r['key']
        assert r['ex'].get('family') == 'catacomb', r['key']
    return rows


def article(name):
    return 'an' if name[0] in 'aeiou' else 'a'


def patch_xml(text, rows):
    block = XML_BEGIN + ''.join('\t<item id="%d" article="%s" name="%s" />\n' % (
        r['server_id'], article(r['name']), xml_escape(r['name'])) for r in rows) + XML_END
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: catacomb kit start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in rows:
        sid = r['server_id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the catacomb kit block; nothing written'
                             % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: catacomb kit block up to date (%d items)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: catacomb kit block rewritten (%d items)' % len(
            rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: catacomb kit block added (%d items)' % len(rows)


def lua_text(rows):
    L = ['-- Server ids of the catacomb kit decoration of the pair 27 trial (server/tools/install_assets_decor.py --lua,',
         '-- from server/data/items/assets_decor.csv). Generated; do not edit by hand. Used by data/lib/chaos_assets_art.lua,',
         '-- and only while its switch ChaosAssetsArt.PAIR27 is on.', '',
         'return {', '\tfirst = %d,' % FIRST, '\tlast = %d,' % LAST,
         '\t-- key = {id, size w x h, blocks a tile, animated, name}', '\titems = {']
    for r in rows:
        w, h = r['size'].split('x')
        L.append('\t\t%s = {id = %d, w = %s, h = %s, block = %s, animated = %s, name = "%s"},' % (
            r['key'], r['server_id'], w, h, 'true' if r['ex'].get('block') == '1' else 'false',
            'true' if 'ms' in r['ex'] else 'false', r['name']))
    L += ['\t}', '}', '']
    return '\n'.join(L)


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    manifest = DEFAULT_MANIFEST
    if '--manifest' in args:
        i = args.index('--manifest')
        manifest = args[i + 1]
        del args[i:i + 2]
    rows = rows_of(manifest)
    if '--lua' in args:
        text = lua_text(rows)
        if '--check' in args:
            if not os.path.isfile(LUA_OUT) or open(LUA_OUT).read() != text:
                print('%s is stale: run install_assets_decor.py --lua' % LUA_OUT)
                return 1
            print('chaos_assets_decor.lua up to date')
            return 0
        open(LUA_OUT, 'w').write(text)
        print('wrote', LUA_OUT)
        return 0
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    otb = os.path.join(args[0], 'items', 'items.otb')
    xml = os.path.join(args[0], 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(args[0], 'items'))
        return 1
    raw = open(otb, 'rb').read()
    new, c = patch_otb(raw, rows)
    n = verify_otb(new, rows)
    print('items.otb: %d nodes added, %d updated; verified (%d item nodes)' % (c['new'], c['updated'], n))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, note = patch_xml(text, rows)
    print(note)
    print('switch ChaosAssetsArt.PAIR27 is %s' % ('on' if pair27_on() else 'off (the items exist but nothing uses them)'))
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
