#!/usr/bin/env python3
"""Make the items.otb nodes of data/items/item_wire.csv write the bytes the client pair reads (install_all step itemwire;
server/README.md "Item wire bytes").

usage: python3 -I patch_item_wire.py DATA_DIR [--dry-run] [--table CSV]

One item with a phase byte the client does not read (FLAG_ANIMATION on a one-phase dat thing) or a fluid byte the client
reads and the server does not write (a splash / fluid dat thing on a plain node) cuts a tile, map or container packet short
for the client: the rest of that server message is dropped, a creature removal in it too (a dead monster that stays drawn).
The table says per node what the dat wants (item_wire_table.py): FLAG_ANIMATION off / on, group splash / fluid. The item
installers (install_dark_tiles.py, install_pack_items.py) apply the same table to their manifest rows, so their nodes are
written right the first time; this step fixes every other node (the base's own shallow water and cauldrons, the gems) and
any node an installer wrote before the table existed. A node is changed only when its server id AND client id are the
row's. A server id the table lists that items.otb lacks is skipped (a partial install). items.otb.bak keeps the original
the first time. Idempotent: a second run changes nothing.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_dark_tiles import scan, escape, ESC, START, END  # noqa: E402
from item_wire_table import read_table, adjust, TABLE  # noqa: E402


def unescape(raw):
    out = bytearray()
    j = 0
    while j < len(raw):
        if raw[j] == ESC:
            j += 1
        out.append(raw[j])
        j += 1
    return bytes(out)


def rewrite(node, group, flags):
    """an items.otb node (START .. END, no children) with the new group and flags; its attributes stay"""
    assert node[0] == START and node[-1] == END
    props = bytearray(unescape(node[1:-1]))
    props[0] = group
    props[1:5] = struct.pack('<I', flags)
    return bytes([START]) + escape(bytes(props)) + bytes([END])


def patch_otb(data, table):
    """(new items.otb bytes, notes, [(server id, what changed)])"""
    kids, _root_end = scan(data)
    by_sid = {k[2]: k for k in kids}
    replace, changes, absent = [], [], 0
    for sid, (cid, _anim, _grp) in sorted(table.items()):
        k = by_sid.get(sid)
        if k is None:
            absent += 1
            continue
        if k[3] != cid:
            continue
        group, flags = adjust(sid, cid, k[4], k[5], table)
        if (group, flags) == (k[4], k[5]):
            continue
        replace.append((k[0], k[1], rewrite(data[k[0]:k[1]], group, flags)))
        what = []
        if flags != k[5]:
            what.append('FLAG_ANIMATION %s' % ('on' if flags > k[5] else 'off'))
        if group != k[4]:
            what.append('group %d -> %d' % (k[4], group))
        changes.append((sid, ', '.join(what)))
    out = bytearray(data)
    for s, e, b in sorted(replace, reverse=True):
        out[s:e] = b
    notes = []
    if replace:
        anim = sum(1 for _s, w in changes if 'FLAG_ANIMATION' in w)
        grp = sum(1 for _s, w in changes if 'group' in w)
        notes.append('items.otb: %d nodes follow the client pair (%d animation flags, %d groups)' % (len(replace), anim, grp))
    else:
        notes.append('items.otb: all %d listed nodes write the bytes the client reads' % (len(table) - absent))
    if absent:
        notes.append('items.otb: %d listed server ids not present (a partial install), skipped' % absent)
    return bytes(out), notes, changes


def verify(data, table):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for sid, (cid, _a, _g) in table.items():
        k = by_sid.get(sid)
        if k is not None and k[3] == cid:
            assert adjust(sid, cid, k[4], k[5], table) == (k[4], k[5]), 'server id %d' % sid
    assert len(by_sid) == len(kids), 'duplicate server ids in items.otb'
    return len(kids)


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    table_path = TABLE
    if '--table' in args:
        i = args.index('--table')
        table_path = args[i + 1]
        del args[i:i + 2]
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    table = read_table(table_path)
    if not table:
        print('no item wire table (%s): nothing to do' % table_path)
        return 0
    otb = os.path.join(args[0], 'items', 'items.otb')
    if not os.path.exists(otb):
        print('items.otb not found in', os.path.join(args[0], 'items'))
        return 1
    raw = open(otb, 'rb').read()
    new, notes, _changes = patch_otb(raw, table)
    n = verify(new, table)
    for line in notes:
        print(line)
    print('items.otb: verified (%d item nodes)' % n)
    if dry:
        print('dry run: nothing written')
        return 0
    if new != raw:
        if not os.path.exists(otb + '.bak'):
            open(otb + '.bak', 'wb').write(raw)
        open(otb, 'wb').write(new)
    return 0


if __name__ == '__main__':
    sys.exit(main())
