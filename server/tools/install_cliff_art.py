#!/usr/bin/env python3
"""Install the 42 cliff pieces of our own (O746; client pair 83) into a base server: items.otb and items.xml, so the area planner's
maps and the map editor can hold them.

usage: python3 -I install_cliff_art.py DATA_DIR [--dry-run] [--table CSV]

The rows come from the table of client/tools/sprites/gen_cliff_art.py (default client/tools/sprites/art_import/cliff_art.csv; the art is
drawn by that script, nothing else is read): client ids 44564..44605, appended to pair 83 after the 44,563 items of pair 82, server
id = client id + 4000 (48564..48605, the decor flames rule). Two palettes (stone, earth) of 21 pieces: nine of the rock face (two south
faces, two east faces, three outer corners, two inner corners) and the twelve lip pieces of the planner's border order. Every row is a
border piece: items.otb group 0, flag ONTOP, top order 1; not moveable or pickupable, not solid (the cliff ground under a face blocks,
and the lip pieces block the planner's tiles by its own rule). items.xml gives each a name ("cliff stone south face a", ...) and nothing
else; names start with "cliff ".

Same node rules as install_decor_flames.py: a node already there with the same bytes is left alone, one of the same group and flags is
replaced, anything else with that server id stops the script; items.otb.bak keeps the original the first time; the written file is
parsed again and every node checked. items.xml: a block between two marker comments before </items>, rewritten when the table changed;
an id with an entry outside the block stops it.

Client pair guard (server/README.md "Client pair guard"): the items need the pair 83 client (client_pair.PAIR_CLIFF). While config.lua's
chaosClientPair is lower than 83 or missing the step prints a warning and writes nothing; from 83 on it installs. Nothing on the server
places these items by itself: the area planner lays them when a compile is told pair 83 (plan field plateaus.pair). Idempotent.
"""
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
from install_pack_items import patch_otb, verify_otb  # noqa: E402
from install_dark_tiles import xml_escape  # noqa: E402
from item_wire_table import adjust_rows  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_TABLE = os.path.join(ROOT, 'client', 'tools', 'sprites', 'art_import', 'cliff_art.csv')
XML_BEGIN = '\t<!-- Chaos cliff pieces of pair 83 (server/tools/install_cliff_art.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos cliff pieces of pair 83 -->\n'
FIRST_CLIENT, LAST_CLIENT = 44564, 44605
SERVER_OFFSET = 4000
ONTOP = 1 << 13


def rows_of(path=DEFAULT_TABLE):
    """the rows of the table in install_pack_items' manifest shape"""
    rows = []
    with open(path, encoding='utf-8', newline='') as f:
        for r in csv.DictReader(f):
            rows.append(dict(client_id=int(r['client_id']), server_id=int(r['server_id']), key=r['key'], kind=r['kind'], mode='new',
                             name=r['name'], size='1x1', otb_group=int(r['otb_group']), otb_flags=int(r['otb_flags']),
                             top_order=int(r['top_order']), speed=0, light_level=0, light_color=0,
                             extra='family=cliff|palette=%s|piece=%s' % (r['palette'], r['piece']),
                             ex=dict(family='cliff', palette=r['palette'], piece=r['piece'])))
    assert len(rows) == LAST_CLIENT - FIRST_CLIENT + 1, 'the cliff table holds %d rows, want %d' % (len(rows), LAST_CLIENT - FIRST_CLIENT + 1)
    for k, r in enumerate(rows):
        assert r['client_id'] == FIRST_CLIENT + k, '%s: client ids %d.. in order' % (r['key'], FIRST_CLIENT)
        assert r['server_id'] == r['client_id'] + SERVER_OFFSET, '%s: server id must be client id + %d' % (r['key'], SERVER_OFFSET)
        assert r['kind'] == 'border', r['key']
        assert (r['otb_group'], r['otb_flags'], r['top_order']) == (0, ONTOP, 1), '%s: a border piece (ONTOP, top order 1)' % r['key']
        assert r['name'].startswith('cliff '), '%s: the name must start with "cliff "' % r['key']
    assert len({r['key'] for r in rows}) == len(rows) and len({r['name'] for r in rows}) == len(rows), 'duplicate keys or names'
    return adjust_rows(rows)


def article(name):
    return 'an' if name[0] in 'aeiou' else 'a'


def xml_item(r):
    return '\t<item id="%d" article="%s" name="%s" />\n' % (r['server_id'], article(r['name']), xml_escape(r['name']))


def patch_xml(text, rows):
    import re
    block = XML_BEGIN + ''.join(xml_item(r) for r in rows) + XML_END
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: cliff pieces start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in rows:
        sid = r['server_id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the cliff pieces block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: cliff pieces block up to date (%d items)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: cliff pieces block rewritten (%d items)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: cliff pieces block added (%d items)' % len(rows)


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    table = DEFAULT_TABLE
    if '--table' in args:
        i = args.index('--table')
        table = args[i + 1]
        del args[i:i + 2]
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_CLIFF, 'cliffart')
    print(why)
    if not ok:
        return 0
    rows = rows_of(table)
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
