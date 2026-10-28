#!/usr/bin/env python3
"""Install the decoration items of client pair 49 (the Map Studio biomes celestial and cursed) into a base server: one
items.otb node and one items.xml entry per row of the manifest.

usage: python3 -I install_decor49_items.py DATA_DIR [--dry-run] [--manifest CSV]
       python3 -I install_decor49_items.py --kit-json OUT.json [--manifest CSV]   (biome -> [{server_id, client_id, size, kind,
                                                                                    blocks, name}])

The manifest (default server/data/items/decor49_items.csv) is written by client/tools/sprites/gen_decor49.py: 87 items,
client ids 39111..39197, server ids 43111..43197 (client id + 4000, like pair 48). The key is decor49_<biome>_<client id>
(biome celestial or cursed). Every item is a decoration: none is pickupable, moveable or a container; trees, statues, pillars,
graves, altars, tables and crystals block (otb solid, the dat flag notwalkable), clutter, birds, clouds and ground glyphs do
not. Light items carry the light level and colour of the manifest, animated ones (rune circles, sparkle, taint pools) have 4
phases. Without the matching client pair (pair 49) the items show as nothing in the client, so install both. No manifest or an
empty one: nothing to do (exit 0).

The node and items.xml rules are those of install_donor_items.py (same layout as install_dark_tiles.py): a node already
there with the same bytes is left alone, one with other bytes is replaced, a server id that belongs to another client
id stops the script (nothing written); items.otb.bak keeps the original the first time; the written file is parsed
again and every node checked. items.xml: a block between two marker comments before </items>, rewritten when the
manifest changed; an id with an entry outside the block stops the script.

Nothing on the server places these items by itself: the map studio kits and map makers use them (--kit-json writes the
biome lists). Idempotent: a second run changes nothing.
"""
import csv
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_dark_tiles import read_manifest, verify_otb, xml_escape  # noqa: E402
from install_donor_items import patch_otb  # noqa: E402

DEFAULT_MANIFEST = os.path.join(os.path.dirname(HERE), 'data', 'items', 'decor49_items.csv')
XML_BEGIN = '\t<!-- Chaos decoration of pair 49 (server/tools/install_decor49_items.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos decoration of pair 49 -->\n'
BIOMES = ('celestial', 'cursed')
KEY = re.compile(r'^decor49_(celestial|cursed)_(\d+)$')
# Stock items called "witch broom" and "witch hat" (ids 10569, 10570) are the Witch's loot, which monster XML names by
# item name: a second item of the same name made the engine refuse the whole loot of the Witch ("Non-unique loot item").
# The manifest is written by gen_decor49.py, so the install gives these (and the stock "pumpkin", loot of the Mutated Pumpkin) their own names (server/README.md
# "Pair 49 items", "Unique loot names").
RENAMES = {'decor49_cursed_39171': 'Cursed witch broom', 'decor49_cursed_39174': 'Cursed witch hat',
           'decor49_cursed_39194': 'Cursed pumpkin'}


def rows_of(path):
    rows = read_manifest(path)
    for r in rows:
        r['name'] = RENAMES.get(r['key'], r['name'])
        m = KEY.match(r['key'])
        assert m, 'key %r is not decor49_<biome>_<client id>' % r['key']
        assert int(m.group(2)) == r['client_id'], '%s: key and client id differ' % r['key']
        assert r['server_id'] == r['client_id'] + 4000, '%s: server id must be client id + 4000' % r['key']
        assert r['otb_group'] == 0 and r['kind'] == 'object', '%s: decoration is a plain object' % r['key']
        assert not r['otb_flags'] & 32 and 'pickupable' not in r['dat_flags'].split(), '%s: not pickupable' % r['key']
        assert 'container' not in r['dat_flags'].split() and 'stackable' not in r['dat_flags'].split(), r['key']
    sids = [r['server_id'] for r in rows]
    assert len(set(sids)) == len(sids), 'duplicate server ids in the manifest'
    keys = [r['key'] for r in rows]
    assert len(set(keys)) == len(keys), 'duplicate keys in the manifest'
    return rows


def biome_of(r):
    return KEY.match(r['key']).group(1)


def kit_json(rows):
    """biome -> [{server_id, client_id, size, kind (static / animated / light), blocks, name}] in manifest order"""
    out = {b: [] for b in BIOMES}
    for r in rows:
        kind = 'animated' if r['phases'] not in ('1', '', 1) else 'light' if r['light_level'] else 'static'
        out[biome_of(r)].append({'server_id': r['server_id'], 'client_id': r['client_id'], 'size': r['size'], 'kind': kind,
                                 'blocks': bool({'notwalkable', 'blockpath'} & set(r['dat_flags'].split())),
                                 'name': r['name']})
    return out


def patch_xml(text, rows):
    block = XML_BEGIN + ''.join('\t<item id="%d" name="%s" />\n' % (r['server_id'], xml_escape(r['name'])) for r in rows) \
        + XML_END
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: pair 49 decoration start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in rows:
        sid = r['server_id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the pair 49 decoration block; nothing written'
                             % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: pair 49 decoration block up to date (%d items)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: pair 49 decoration block rewritten (%d items)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: pair 49 decoration block added (%d items)' % len(rows)


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    manifest = DEFAULT_MANIFEST
    if '--manifest' in args:
        i = args.index('--manifest'); manifest = args[i + 1]; del args[i:i + 2]
    if '--kit-json' in args:
        i = args.index('--kit-json'); out = args[i + 1]; del args[i:i + 2]
        with open(out, 'w') as fh:
            json.dump(kit_json(rows_of(manifest)), fh, indent=1)
            fh.write('\n')
        print('wrote', out)
        return 0
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    if not os.path.exists(manifest):
        print('no pair 49 decoration manifest (%s): nothing to install' % manifest)
        return 0
    rows = rows_of(manifest)
    if not rows:
        print('pair 49 decoration manifest is empty: nothing to install')
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
        print(line.replace('donor item', 'pair 49 decoration'))
    print('items.otb: verified (%d item nodes, every pair 49 decoration node as in the manifest)' % n)
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
