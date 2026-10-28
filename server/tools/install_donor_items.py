#!/usr/bin/env python3
"""Install the items imported from donor B (the 64px donor) into a base server: one items.otb node and one items.xml entry
per row of the manifest.

usage: python3 -I install_donor_items.py DATA_DIR [--dry-run] [--manifest CSV]

The manifest (default server/data/items/donor_items.csv) is written by
client/tools/sprites/import_donor_things.py import (OUT/donor_items.csv; copy it here when the live pair is rebuilt).
Same columns as dark_tiles.csv; client ids from 28000 (the importer runs with --first-item 28000), server id = client id
+ 12000 (40000..; the base items.otb uses up to 29926, the dark tiles 30484.., other Chaos items 32000..).
Without the matching client pair the items show as nothing in the client, so install both.  No manifest or an empty
one: nothing to do (exit 0).

1. data/items/items.otb: a node per row, appended at the end of the root (same node layout as install_dark_tiles.py).
   A node already there with the same bytes is left alone; one with other bytes is replaced; a server id that belongs
   to a different client id stops the script (nothing written).  items.otb.bak keeps the original the first time.
   The written file is parsed again and every node checked.
2. data/items/items.xml: one <item id=.. name=..> per row inside a block between two marker comments, before
   </items>; rewritten when the manifest changed; an id with an entry outside the block stops the script.
   Exception: the ids of data/items/fist_claws.csv (the Monk's claw weapons, server ids 40000..40012) get their items.otb
   node here but no bare items.xml entry; install_fist_weapons.py writes their full entries (and drops an old bare one).
   The rows of mode `repoint` (40003-40012, new looks since pair 56) get no node here either: install_fist_weapons.py writes
   those nodes with the new client ids.

Idempotent: a second run changes nothing.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_dark_tiles import read_manifest, scan, node_bytes, verify_otb, xml_escape  # noqa: E402

DEFAULT_MANIFEST = os.path.join(os.path.dirname(HERE), 'data', 'items', 'donor_items.csv')
FIST_CLAWS = os.path.join(os.path.dirname(HERE), 'data', 'items', 'fist_claws.csv')
XML_BEGIN = '\t<!-- Chaos donor item set (server/tools/install_donor_items.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos donor item set -->\n'


def patch_otb(data, rows):
    kids, root_end = scan(data)
    by_sid = {k[2]: k for k in kids}
    replace, append = [], []
    for r in rows:
        want = node_bytes(r)
        k = by_sid.get(r['server_id'])
        if k is None:
            append.append(want)
        elif k[3] != r['client_id']:
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (r['server_id'], k[3], r['client_id']))
        elif data[k[0]:k[1]] != want:
            replace.append((k[0], k[1], want))
    out = bytearray(data)
    for s, e, b in sorted(replace, reverse=True):
        out[s:e] = b
    shift = sum(len(b) - (e - s) for s, e, b in replace)
    at = root_end + shift
    out[at:at] = b''.join(append)
    notes = []
    if replace:
        notes.append('items.otb: %d donor item nodes updated' % len(replace))
    if append:
        notes.append('items.otb: %d donor item nodes added' % len(append))
    if not replace and not append:
        notes.append('items.otb: all %d donor item nodes present' % len(rows))
    return bytes(out), notes


def claimed_ids(path=FIST_CLAWS):
    """server ids of the donor looks that install_fist_weapons.py turns into the Monk's claw weapons (data/items/
    fist_claws.csv): their items.otb nodes stay with this tool, their items.xml entries are the fist weapons' own"""
    if not os.path.exists(path):
        return set()
    with open(path, newline='') as f:
        return {int(r['server_id']) for r in csv.DictReader(f)}


def repointed_ids(path=FIST_CLAWS):
    """server ids of the claws that wear a look of their own since pair 56 (mode `repoint` in fist_claws.csv): this tool no
    longer writes their items.otb nodes either (they would point at the old donor look); install_fist_weapons.py does"""
    if not os.path.exists(path):
        return set()
    with open(path, newline='') as f:
        return {int(r['server_id']) for r in csv.DictReader(f) if r['mode'] == 'repoint'}


def patch_xml(text, rows):
    claimed = claimed_ids()
    rows = [r for r in rows if r['server_id'] not in claimed]
    block = XML_BEGIN + ''.join('\t<item id="%d" name="%s" />\n' % (r['server_id'], xml_escape(r['name'])) for r in rows) \
        + XML_END
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: donor item start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in rows:
        sid = r['server_id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the donor item block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: donor item block up to date (%d items)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: donor item block rewritten (%d items)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: donor item block added (%d items)' % len(rows)


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    manifest = DEFAULT_MANIFEST
    if '--manifest' in args:
        i = args.index('--manifest'); manifest = args[i + 1]; del args[i:i + 2]
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    if not os.path.exists(manifest):
        print('no donor item manifest (%s): nothing to install' % manifest)
        return 0
    rows = read_manifest(manifest)
    if not rows:
        print('donor item manifest is empty: nothing to install')
        return 0
    sids = [r['server_id'] for r in rows]
    assert len(set(sids)) == len(sids), 'duplicate server ids in the manifest'
    if manifest == DEFAULT_MANIFEST:
        skip = repointed_ids()
        rows = [r for r in rows if r['server_id'] not in skip]
    for r in rows:
        assert 0 < r['client_id'] < r['server_id'] <= 0xFFFF, r['key']
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(data_dir, 'items'))
        return 1
    raw = open(otb, 'rb').read()
    new, notes = patch_otb(raw, rows)
    n = verify_otb(new, rows)
    for line in notes:
        print(line)
    print('items.otb: verified (%d item nodes, every donor item node as in the manifest)' % n)
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
