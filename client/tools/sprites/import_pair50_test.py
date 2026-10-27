#!/usr/bin/env python3
"""python3 -I client/tools/sprites/import_pair50_test.py : the pure helpers of import_pair50.py (selection reading, dedupe,
classify, otb_of, fx_offset) and the committed tables (selections, import report, effects) agree with each other. No
sources and no pair needed."""
import csv
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import import_pair50 as P  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def row(cat, notes='', name='X', tag='F', sid=1):
    return {'tag': tag, 'cat': cat, 'kind': 'item', 'src_id': sid, 'name': name, 'biome': '', 'size': '1x1', 'notes': notes}


# classify
check(P.classify(row('ground')) == ('ground', '', '', '', False), 'classify: ground')
check(P.classify(row('wall', 'role=wall_n'))[0] == 'wall', 'classify: wall')
check(P.classify(row('stairs', 'role=stairs_up; treads horizontal'))[2:4] == ('north', ''), 'classify: horizontal up goes north')
check(P.classify(row('stairs', 'role=stairs_up; treads vertical'))[2] == 'west', 'classify: vertical up goes west')
check(P.classify(row('stairs', 'role=stairs_up'))[2] == '', 'classify: up without treads has no direction')
check(P.classify(row('stairs', 'role=stairs_down'))[2] == 'down', 'classify: down')
check(P.classify(row('stairs', 'role=hole'))[2] == 'down', 'classify: hole')
check(P.classify(row('stairs', 'role=ladder'))[2:4] == ('', 'ladder'), 'classify: ladder uses')
check(P.classify(row('stairs', '', 'Ladder 3', 'G'))[3] == 'ladder', 'classify: source G ladder by name')
check(P.classify(row('stairs', '', 'Stone step 3', 'G'))[2:4] == ('', ''), 'classify: source G step has no floor change')
check(P.classify(row('decor', 'corpse of a thing'))[0] == 'corpse' and P.classify(row('decor', 'corpse'))[4], 'classify: corpse')
check(P.classify(row('decor', '', 'Dead rat corpse'))[0] == 'corpse', 'classify: corpse by name')
check(P.classify(row('decor', '', 'Candle'))[0] == 'decor', 'classify: decor')

# dedupe: stairs wins, the first wins otherwise, different sources do not clash
a, b = row('wall', sid=7), row('stairs', sid=7)
kept, dropped = P.dedupe([a, b, row('wall', sid=8)])
check(b in kept and a not in kept and len(kept) == 2 and dropped == [(a, b)], 'dedupe: stairs wins')
kept, dropped = P.dedupe([row('wall', sid=7), row('decor', sid=7)])
check(len(kept) == 1 and kept[0]['cat'] == 'wall', 'dedupe: first row wins')
kept, dropped = P.dedupe([row('wall', sid=7, tag='F'), row('wall', sid=7, tag='G')])
check(len(kept) == 2 and not dropped, 'dedupe: sources are separate')

# otb_of
g, fl, top = P.otb_of({'ground'}, 1, ('ground', '', '', '', False))
check(g == 1 and fl == 0 and top == 0, 'otb: plain ground')
g, fl, top = P.otb_of({'notwalkable', 'blockmissile'}, 1, ('wall', '', '', '', False))
check(fl == P.SOLID | P.PATH | P.MISSILE, 'otb: solid wall')
g, fl, top = P.otb_of({'blockpath'}, 1, ('stairs', '', '', '', False))
check(fl == P.PATH, 'otb: blockpath alone is not solid')
g, fl, top = P.otb_of({'clip'}, 4, ('ground', '', '', '', False))
check(top == 1 and fl == P.ONTOP | P.ANIM, 'otb: border on top and animated')
g, fl, top = P.otb_of(set(), 1, ('stairs', 'ladder', '', 'ladder', False))
check(fl == P.USEABLE, 'otb: ladder is useable')
g, fl, top = P.otb_of({'container'}, 1, ('corpse', '', '', '', True))
check(g == 2 and fl == P.FORCEUSE, 'otb: corpse is a force-use container')
g, fl, top = P.otb_of({'pickupable', 'stackable'}, 1, ('decor', '', '', '', False))
check(fl == P.PICKUP | P.MOVE | P.STACK, 'otb: pickup, move, stack')
g, fl, top = P.otb_of({'hangable'}, 1, ('decor', '', '', '', False))
check(fl == P.HANG, 'otb: hangable')

check(P.fx_offset(1, 1) == (0, 0) and P.fx_offset(2, 2) == (1, 1) and P.fx_offset(3, 3) == (1, 1) and P.fx_offset(4, 4) == (2, 2),
      'fx_offset')
check(P.slug('Grey Smoke, puff 1!') == 'grey_smoke_puff_1', 'slug')

# read_selection: bad rows stop
with tempfile.TemporaryDirectory() as td:
    p = os.path.join(td, 's.csv')
    open(p, 'w').write('category,src_kind,src_id,name,biome,size,notes\ndecoration,item,5,Lamp,x,1x1,\nground,item,6,Floor,x,1x1,\n')
    r = P.read_selection(p, 'G')
    check([x['cat'] for x in r] == ['decor', 'ground'] and r[0]['src_id'] == 5 and r[0]['tag'] == 'G', 'read_selection')
    for label, body in (('unknown category', 'sea,item,5,A,x,1x1,\n'), ('kind mismatch', 'ground,monster,5,A,x,1x1,\n')):
        open(p, 'w').write('category,src_kind,src_id,name,biome,size,notes\n' + body)
        try:
            P.read_selection(p, 'G')
            check(False, 'read_selection refuses ' + label)
        except SystemExit:
            pass

# committed tables
def table(path):
    with open(path, newline='', encoding='utf-8') as fh:
        return list(csv.DictReader(fh))


sel = table(os.path.join(HERE, 'pair50_G_selection.csv')) + table(os.path.join(HERE, 'pair50_F_selection.csv'))
imp = table(os.path.join(HERE, 'pair50_import.csv'))
check(len(imp) == len(sel), 'report has a row per selected thing (%d of %d)' % (len(imp), len(sel)))
check(all(r['status'] in ('imported', 'skipped') for r in imp), 'report: status is imported or skipped')
check(all(r['reason'] for r in imp if r['status'] == 'skipped'), 'report: every skipped row has a reason')
check(all(r['new_id'] for r in imp if r['status'] == 'imported'), 'report: every imported row has a new id')
check(all(r['source'] in ('G', 'F') for r in imp), 'report: sources are G or F')
txt = open(os.path.join(HERE, 'pair50_G_selection.csv')).read() + open(os.path.join(HERE, 'pair50_F_selection.csv')).read()
check('.zip' not in txt.lower() and '.rar' not in txt.lower(), 'selections name no archive')

print('import_pair50_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
