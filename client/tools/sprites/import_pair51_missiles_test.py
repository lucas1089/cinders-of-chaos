#!/usr/bin/env python3
"""python3 -I client/tools/sprites/import_pair51_missiles_test.py : the selection of import_pair51_missiles.py (no source art
needed): the committed pair51_missiles.csv fills exactly the freed missile ids of pair51_removed.csv, once each, names and
source rows unique, 23 source G + 39 source F rows, 3x3 direction missiles only."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import import_pair51_missiles as M  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


rows = M.read_selection()
free = M.removed_missiles()
check(len(rows) == 62 and len(free) == 62, '62 rows, 62 freed ids')
M.check_selection(rows, free)
check(sum(r['tag'] == 'G' for r in rows) == 23 and sum(r["tag"] == "F" for r in rows) == 39, "23 source G, 39 source F")
check(max(r['id'] for r in rows) <= M.MAX_MISSILE, 'no id above 253')
try:
    M.check_selection(rows[:-1], free)
    check(False, 'a short selection is refused')
except SystemExit:
    pass
try:
    M.check_selection(rows[:-1] + [dict(rows[0])], free)
    check(False, 'a duplicate row is refused')
except SystemExit:
    pass
blank = bytes([1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0])


class T:
    raw = (0, 0)


d = bytes([0xff]) + blank
t = T(); t.raw = (0, len(d))
check(M.is_blank(d, t), 'blank entry recognised')
d2 = bytes([0xff, 1, 1, 1, 1, 1, 1, 1, 5, 0, 0, 0])
t.raw = (0, len(d2))
check(not M.is_blank(d2, t), 'an entry with a sprite is not blank')
sys.exit(1 if failed else 0)
