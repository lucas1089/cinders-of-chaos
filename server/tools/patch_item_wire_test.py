#!/usr/bin/env python3
"""python3 -I server/tools/patch_item_wire_test.py : item_wire_table.py, patch_item_wire.py and the table side of
check_item_wire.py on a synthetic items.otb and synthetic dat things, plus the shipped data/items/item_wire.csv (valid,
no server id twice, rows only of the two kinds the table knows). No base server and no pair needed."""
import csv
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import item_wire_table as W  # noqa: E402
import patch_item_wire as P  # noqa: E402
import check_item_wire as C  # noqa: E402
from install_dark_tiles import scan, node_bytes  # noqa: E402
from install_gems import escape, attr, START, END, A_SERVERID, A_CLIENTID  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


A = W.FLAG_ANIMATION


def item_node(sid, cid, flags=0, group=0):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


def node_of(data, sid):
    return {k[2]: k for k in scan(data)[0]}[sid]


# the shipped table
table = W.read_table()
check(len(table) > 0, 'item_wire.csv is not empty')
with open(W.TABLE, newline='') as fh:
    raw = list(csv.DictReader(fh))
check(len(raw) == len(table), 'item_wire.csv: no server id twice')
check(all(r['group'] in ('', '11', '12') and r['animation'] in ('0', '1') for r in raw), 'item_wire.csv: only the known values')
check([int(r['server']) for r in raw] == sorted(int(r['server']) for r in raw), 'item_wire.csv is sorted by server id')
check(W.table_text([(s, c, a, g) for s, (c, a, g) in table.items()]) == open(W.TABLE).read(), 'item_wire.csv is in the written form')

# adjust
T = {10: (100, 0, None), 11: (101, 1, None), 12: (102, 1, 11), 13: (103, 0, 12)}
check(W.adjust(10, 100, 0, A | 5, T) == (0, 5), 'animation off clears only that bit')
check(W.adjust(11, 101, 0, 5, T) == (0, A | 5), 'animation on sets it')
check(W.adjust(12, 102, 0, 0, T) == (11, A), 'a splash group is set')
check(W.adjust(13, 103, 2, A, T) == (12, 0), 'a fluid group is set')
check(W.adjust(10, 999, 0, A, T) == (0, A), 'another client id is left alone')
check(W.adjust(99, 100, 0, A, T) == (0, A), 'a server id not in the table is left alone')
check(W.adjust(10, 100, None, None, T) == (None, None), 'a node taking only a new look has no flags to change')
rows = [{'server_id': 10, 'client_id': 100, 'otb_group': 0, 'otb_flags': A}]
W.adjust_rows(rows, T)
check(rows[0]['otb_flags'] == 0 and rows[0]['otb_flags_manifest'] == A, 'adjust_rows keeps the manifest flags aside')

# patch_otb
raw_otb = otb([item_node(9, 90, A), item_node(10, 100, A | 128), item_node(11, 101, 0), item_node(12, 102, 0),
               item_node(13, 103, 0, 2), item_node(14, 104, A)])
new, notes, changes = P.patch_otb(raw_otb, T)
check([c[0] for c in changes] == [10, 11, 12, 13], 'four nodes change: %s' % changes)
check((node_of(new, 10)[4], node_of(new, 10)[5]) == (0, 128), 'node 10: animation off, stackable kept')
check(node_of(new, 11)[5] == A, 'node 11: animation on')
check((node_of(new, 12)[4], node_of(new, 12)[5]) == (11, A), 'node 12: splash group and animation')
check((node_of(new, 13)[4], node_of(new, 13)[5]) == (12, 0), 'node 13: fluid group')
check(node_of(new, 9)[5] == A and node_of(new, 14)[5] == A, 'nodes outside the table keep their flags')
check(all(node_of(new, s)[3] == c for s, c in ((9, 90), (10, 100), (13, 103), (14, 104))), 'client ids stay')
new2, notes2, changes2 = P.patch_otb(new, T)
check(new2 == new and not changes2, 'a second run changes nothing')
check(P.verify(new, T) == 6, 'verify parses every node')
other = otb([item_node(10, 555, A)])
check(P.patch_otb(other, T)[0] == other, 'a node with another client id is not touched')
part = otb([item_node(10, 100, A)])
check('not present' in ' '.join(P.patch_otb(part, T)[1]), 'listed ids that are absent are noted')
# a node whose flags need escaping (0x FD, FE, FF bytes in the flags word) survives
esc = otb([item_node(10, 100, A | 0xFD | 0xFE00)])
res = P.patch_otb(esc, T)[0]
check(node_of(res, 10)[5] == 0xFD | 0xFE00, 'escaped flag bytes survive the rewrite')
check(res == otb([item_node(10, 100, 0xFD | 0xFE00)]), 'the node is the one a fresh write gives')
# the manifest node writer and the patch tool agree
row = {'server_id': 10, 'client_id': 100, 'otb_group': 0, 'otb_flags': A | 3, 'speed': 0, 'light_level': 0, 'light_color': 0,
       'top_order': 0}
check(P.patch_otb(otb([node_bytes(row)]), T)[0] == otb([node_bytes(dict(row, otb_flags=3))]),
      'patching an installer node equals writing it from the adjusted row')

# the CLI on a folder
with tempfile.TemporaryDirectory() as tmp:
    os.makedirs(os.path.join(tmp, 'items'))
    path = os.path.join(tmp, 'items', 'items.otb')
    open(path, 'wb').write(raw_otb)
    tpath = os.path.join(tmp, 'wire.csv')
    open(tpath, 'w').write(W.table_text([(s, c, a, g) for s, (c, a, g) in T.items()]))
    check(P.main([tmp, '--table', tpath, '--dry-run']) == 0 and open(path, 'rb').read() == raw_otb, '--dry-run writes nothing')
    check(P.main([tmp, '--table', tpath]) == 0 and open(path, 'rb').read() == new, 'the file is rewritten')
    check(open(path + '.bak', 'rb').read() == raw_otb, 'items.otb.bak keeps the original')
    P.main([tmp, '--table', tpath])
    check(open(path + '.bak', 'rb').read() == raw_otb, 'a second run leaves the backup')
    check(P.main([tmp, '--table', os.path.join(tmp, 'none.csv')]) == 0, 'no table: nothing to do')

# check_item_wire: write-table and table-check rules
# things: cid -> (stackable, fluid, splash, market, phases)
things = {100: (False, False, False, None, 1), 101: (False, False, False, None, 4), 102: (False, False, True, None, 1),
          103: (False, True, False, None, 1), 104: (False, False, False, None, 1), 105: (True, False, False, None, 1),
          106: (False, False, False, 25, 1)}
nodes = [(10, 100, 0, A), (11, 101, 0, 0), (12, 102, 0, 0), (13, 103, 0, 0), (14, 104, 0, 0), (15, 105, 0, 0),
         (16, 106, 0, 0), (17, 100, 0, 0)]
rows_, stuck = C.make_table(nodes, things, {})
check([(r[0], r[2], r[3]) for r in rows_] == [(10, 0, None), (11, 1, None), (12, 0, 11), (13, 0, 12)],
      'make_table lists the nodes that differ: %s' % rows_)
check([s[0] for s in stuck] == [15, 16], 'a stackable or quiver mismatch is not fixable by the table: %s' % stuck)
old = {17: (100, 0, None)}
rows2, _ = C.make_table(nodes, things, old)
check(17 in [r[0] for r in rows2], 'a node already in the table stays in it')
check(C.table_check([(10, 100, 0, None), (11, 101, 1, None), (12, 102, 0, 11)], things) == [], 'a right table passes')
bad = C.table_check([(11, 101, 0, None), (12, 102, 0, None), (13, 999, 0, None)], things)
check(len(bad) == 3, 'stale rows are found: %s' % bad)
applied = [(sid, cid) + W.adjust(sid, cid, grp, fl, {r[0]: (r[1], r[2], r[3]) for r in rows_}) for sid, cid, grp, fl in nodes]
check(C.compare([(s, c, g, f) for s, c, g, f in applied if s in (10, 11, 12, 13, 14, 17)], things) == [],
      'with the table applied every fixable node agrees with the dat')

print('patch_item_wire_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
sys.exit(1 if failed else 0)
