#!/usr/bin/env python3
"""Install the temple tileset (owner 2026-11-06, O431; client pair 60) into a base server: items.otb and items.xml, so the map
editor can place the pieces by name.

usage: python3 -I install_temple_art.py DATA_DIR [--dry-run] [--manifest CSV]

The manifest (default server/data/items/temple_art.csv) is client/tools/sprites/import_art_things.py's --manifest-out of
client/tools/sprites/art_import/temple.csv (gen_temple_art.py, which writes the same file): client ids 44511..44549 (appended to
pair 60), server id = client id + 4000 (48511..48549, the pair 50 rule; after the relic sets' 48446..48510). 39 items:
  - 11 ground items (otb group 1, speed 100): the marble floor, the black marble floor, the blue rune pad, four gilded border
    pieces (north, east, south, west) and four gilded corners;
  - 6 decor items (walkable, drawn over a floor): the mosaic floor (3x3, put it on the south-east tile of the square it covers), the
    red carpet (3x4, same rule) and four blood stains (1x1 to 2x2);
  - 22 stump items (otb solid, the tile is blocked), all 2x2, drawn up and left of their base, which is their bottom right edge: 12
    wall pieces (straight east-west and north-south, thick, corner, end), four pillars, four statue pedestals, the gargoyle and the
    temple torch (light 6, colour 206).
None is moveable or pickupable; items.xml gives each a name ("temple marble floor", "temple pillar", "temple torch", ...) and nothing
else. otb group, flags, speed and light come from the manifest. Names all start with "temple " (a stock item of the same name
would make the engine refuse a monster's loot: "Non-unique loot item").

Same node rules as install_owner_decor.py / install_pack_items.py: a node already there with the same bytes is left alone, one
of the same group and flags is replaced, anything else with that server id stops the script; items.otb.bak keeps the original
the first time; the written file is parsed again and every node checked. items.xml: a block between two marker comments before
</items>, rewritten when the manifest changed; an id with an entry outside the block stops it.

Client pair guard (server/README.md "Client pair guard"): the items need the pair 60 client (client ids 44511-44549). While
config.lua's chaosClientPair is lower than 60 or missing the step prints a warning and writes nothing; from 60 on it installs.
Nothing on the server places these items by itself: map makers and the map editor do. Idempotent: a second run changes nothing.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
from install_pack_items import read_manifest, patch_otb, verify_otb  # noqa: E402
from install_dark_tiles import xml_escape  # noqa: E402

REPO_DATA = os.path.join(os.path.dirname(HERE), 'data')
DEFAULT_MANIFEST = os.path.join(REPO_DATA, 'items', 'temple_art.csv')
XML_BEGIN = '\t<!-- Chaos temple tileset of pair 60 (server/tools/install_temple_art.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos temple tileset of pair 60 -->\n'
FIRST_CLIENT, LAST_CLIENT = 44511, 44549
SERVER_OFFSET = 4000


def rows_of(path=DEFAULT_MANIFEST):
    rows = read_manifest(path)
    assert rows, 'the temple manifest is empty'
    for r in rows:
        assert r['mode'] == 'new', r['key']
        assert r['server_id'] == r['client_id'] + SERVER_OFFSET, '%s: server id must be client id + %d' % (r['key'], SERVER_OFFSET)
        assert FIRST_CLIENT <= r['client_id'] <= LAST_CLIENT, '%s: client id %d outside %d..%d' % (
            r['key'], r['client_id'], FIRST_CLIENT, LAST_CLIENT)
        assert r['kind'] in ('ground', 'decor', 'stump'), r['key']
        assert r['ex'].get('family') == 'temple', r['key']
        assert r['name'].startswith('temple '), '%s: the name must start with "temple "' % r['key']
        assert not r['otb_flags'] & 32 and not r['otb_flags'] & 64, '%s: not pickupable or moveable' % r['key']
    assert len({r['server_id'] for r in rows}) == len(rows), 'duplicate server ids'
    assert len({r['key'] for r in rows}) == len(rows), 'duplicate keys'
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
            raise SystemExit('items.xml: temple tileset start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in rows:
        sid = r['server_id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the temple tileset block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: temple tileset block up to date (%d items)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: temple tileset block rewritten (%d items)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: temple tileset block added (%d items)' % len(rows)


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    manifest = DEFAULT_MANIFEST
    if '--manifest' in args:
        i = args.index('--manifest')
        manifest = args[i + 1]
        del args[i:i + 2]
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_TEMPLE, 'templeart')
    print(why)
    if not ok:
        return 0
    rows = rows_of(manifest)
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
