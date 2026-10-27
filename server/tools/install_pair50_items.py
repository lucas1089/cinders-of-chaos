#!/usr/bin/env python3
"""Install the items of client pair 50 (ground, walls, stairs and decoration of two purchased sprite sources, "source G" and
"source F") into a base server: one items.otb node and one items.xml entry per row of the manifest, the floor changes of
the stairs, holes and ladders, and the corpses.

usage: python3 -I install_pair50_items.py DATA_DIR [--dry-run] [--manifest CSV]
       python3 -I install_pair50_items.py --lua [--manifest CSV]     (rewrites server/data/lib/chaos_pair50_items.lua)

The manifest (default server/data/items/pair50_items.csv) is written by client/tools/sprites/import_pair50.py: 5198 items,
client ids 39198..44395, server ids 43198..48395 (client id + 4000, directly after pair 49's block), key
pair50_<category>_<client id> with category ground, wall, stairs, decor or corpse. Same node layout as install_decor49_items.py
(ground group, ground speed, solid / missile / path / pickup / stack / top-order / hangable / animation flags, light); the
base's own handling is reused, nothing of the base data is edited by hand:

1. data/items/items.otb: a node per row (a node already there with the same bytes is left alone, one with other bytes is
   replaced, a server id of another client id stops the script; items.otb.bak keeps the original the first time; the written
   file is parsed again and every node checked).
2. data/items/items.xml: one <item> per row inside a block between two marker comments before </items>, rewritten when the
   manifest changed; an id with an entry outside the block stops the script. Attributes:
   - stairs up: floorchange north or west (the way the steps climb on screen; the base uses the same attribute for its
     stairs), stairs down and holes: floorchange down;
   - corpses: containerSize 20, decayTo 0, duration 600, corpseType (undead for bones, else blood) and fluidSource blood, the
     way the pack corpses of install_pack_items.py are written;
   - decoration, walls and stairs that are containers in the dat (chests, cupboards): containerSize 8.
3. data/lib/chaos_pair50_items.lua (--lua): the server ids of the ladders, for data/scripts/chaos/pair50_items.lua. The base
   registers its ladders with the action other/teleport.lua by item id and an id list inside that script; ours get the same
   behaviour from a revscript Action (Position:moveUpstairs() of the base lib, the protection zone rule of the base).

Source G's own steps and pits and its doors carry no floor change and no use: the selection gives no direction or up / down for
them (README "Pair 50 items"). Without the matching client pair (pair 50) the items show as nothing in the client, so install
both. No manifest or an empty one: nothing to do (exit 0). Idempotent: a second run changes nothing.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_dark_tiles import read_manifest, verify_otb, xml_escape  # noqa: E402
from install_donor_items import patch_otb  # noqa: E402

DATA = os.path.join(os.path.dirname(HERE), 'data')
DEFAULT_MANIFEST = os.path.join(DATA, 'items', 'pair50_items.csv')
LUA_OUT = os.path.join(DATA, 'lib', 'chaos_pair50_items.lua')
XML_BEGIN = '\t<!-- Chaos ground, walls, stairs and decoration of pair 50 (server/tools/install_pair50_items.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos ground, walls, stairs and decoration of pair 50 -->\n'
CATEGORIES = ('ground', 'wall', 'stairs', 'decor', 'corpse')
KEY = re.compile(r'^pair50_(ground|wall|stairs|decor|corpse)_(\d+)$')
FLOORCHANGE = ('', 'north', 'south', 'east', 'west', 'down')
OTB_CONTAINER_GROUP = 2
OTB_FORCEUSE = 1 << 26


def rows_of(path):
    rows = read_manifest(path)
    for r in rows:
        m = KEY.match(r['key'])
        assert m, 'key %r is not pair50_<category>_<client id>' % r['key']
        assert int(m.group(2)) == r['client_id'], '%s: key and client id differ' % r['key']
        assert r['category'] == m.group(1), '%s: category column differs from the key' % r['key']
        assert r['server_id'] == r['client_id'] + 4000, '%s: server id must be client id + 4000' % r['key']
        assert r['floorchange'] in FLOORCHANGE, '%s: floorchange %r' % (r['key'], r['floorchange'])
        assert r['use'] in ('', 'ladder'), '%s: use %r' % (r['key'], r['use'])
        assert r['category'] == 'stairs' or not (r['floorchange'] or r['use']), '%s: floor change only on stairs' % r['key']
        assert r['corpse'] in ('0', '1') and (r['corpse'] == '1') == (r['category'] == 'corpse'), '%s: corpse flag' % r['key']
        assert (r['otb_group'] == 1) == (r['kind'] == 'ground'), '%s: ground kind and group' % r['key']
        if r['corpse'] == '1':
            assert r['otb_group'] == OTB_CONTAINER_GROUP and r['otb_flags'] & OTB_FORCEUSE, '%s: corpse is a force-use container' % r['key']
    sids = [r['server_id'] for r in rows]
    assert len(set(sids)) == len(sids), 'duplicate server ids in the manifest'
    keys = [r['key'] for r in rows]
    assert len(set(keys)) == len(keys), 'duplicate keys in the manifest'
    return rows


def xml_item(r):
    inner = []
    if r['floorchange']:
        inner.append(('floorchange', r['floorchange']))
    if r['corpse'] == '1':
        undead = 'bone' in r['name'].lower() or 'skeleton' in r['name'].lower() or 'skull' in r['name'].lower()
        inner += [('containerSize', '20'), ('decayTo', '0'), ('duration', '600'), ('corpseType', 'undead' if undead else 'blood')]
        if not undead:
            inner.append(('fluidSource', 'blood'))
    elif 'container' in r['dat_flags'].split():
        inner.append(('containerSize', '8'))
    head = '\t<item id="%d" name="%s"' % (r['server_id'], xml_escape(r['name']))
    if not inner:
        return head + ' />\n'
    return head + '>\n' + ''.join('\t\t<attribute key="%s" value="%s" />\n' % (k, v) for k, v in inner) + '\t</item>\n'


def patch_xml(text, rows):
    block = XML_BEGIN + ''.join(xml_item(r) for r in rows) + XML_END
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: pair 50 item start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    taken = {int(x) for x in re.findall(r'<item\s+id="(\d+)"', outside)}
    for r in rows:
        sid = r['server_id']
        if sid in taken or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the pair 50 block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: pair 50 block up to date (%d items)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: pair 50 block rewritten (%d items)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: pair 50 block added (%d items)' % len(rows)


def lua_text(rows):
    ladders = [r for r in rows if r['use'] == 'ladder']
    L = ['-- Server ids of the pair 50 items that need a script (server/tools/install_pair50_items.py --lua, from',
         '-- server/data/items/pair50_items.csv). Generated; do not edit by hand. They exist after the "pair50items" install step',
         '-- and need the matching client pair (client/tools/sprites/import_pair50.py).', '', 'ChaosPair50 = {',
         '\t-- ladders: using one moves the player one floor up (data/scripts/chaos/pair50_items.lua)', '\tladders = {']
    L += ['\t\t%d, -- %s (client %d)' % (r['server_id'], r['name'], r['client_id']) for r in ladders]
    L += ['\t},', '}', '']
    return '\n'.join(L)


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    manifest = DEFAULT_MANIFEST
    if '--manifest' in args:
        i = args.index('--manifest'); manifest = args[i + 1]; del args[i:i + 2]
    if '--lua' in args:
        with open(LUA_OUT, 'w', newline='\n') as fh:
            fh.write(lua_text(rows_of(manifest)))
        print('wrote', LUA_OUT)
        return 0
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    if not os.path.exists(manifest):
        print('no pair 50 item manifest (%s): nothing to install' % manifest)
        return 0
    rows = rows_of(manifest)
    if not rows:
        print('pair 50 item manifest is empty: nothing to install')
        return 0
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(data_dir, 'items'))
        return 1
    raw = open(otb, 'rb').read()
    new, notes = patch_otb(raw, rows)
    n = verify_otb(new, rows)
    for line in notes:
        print(line.replace('donor item', 'pair 50 item'))
    print('items.otb: verified (%d item nodes, every pair 50 node as in the manifest)' % n)
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
