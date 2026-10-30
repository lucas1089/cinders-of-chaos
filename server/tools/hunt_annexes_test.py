#!/usr/bin/env python3
"""The hunt annexes (server/README.md "Hunt annexes (O337)"): every plan in server/tools/areaplan/annexes/ validates and
compiles with the area planner without a QA error, is asymmetric, sits inside the annex row of the map and clear of every
other plan, has an exit portal that leads back to the `back` tile of tools/hunt_annexes.json, and the row's `dest` is the
plan's arrival. Every row names a hall hunt of tools/hall_hunts.csv, its monsters are the hunt's own (a monster of the plan is
one the hunt's room shows or its spawns hold), the annex's level band lies inside the hunt's band and the portal and back tiles
are inside the hunt's neighbourhood (60 tiles of its arrival, one floor).

    python3 -I server/tools/hunt_annexes_test.py
Needs LuaJIT (LUAJIT=... to point elsewhere), like the area planner."""
import csv, glob, json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import area_plan_core as C  # noqa: E402

ANNEXES = os.path.join(HERE, 'areaplan', 'annexes')
failures = []


def check(cond, what):
    if not cond:
        failures.append(what)
        print('FAIL ' + what)


def main():
    rows = json.load(open(os.path.join(HERE, 'hunt_annexes.json'), encoding='utf-8'))['annexes']
    plans = {}
    for p in sorted(glob.glob(os.path.join(ANNEXES, '*.json'))):
        d = json.load(open(p, encoding='utf-8'))
        plans[d['id']] = (p, d)
    check(sorted(r['id'] for r in rows) == sorted(plans), 'one row per annex plan: %s vs %s' % (sorted(r['id'] for r in rows), sorted(plans)))
    hunts = {}
    for line in csv.reader(l for l in open(os.path.join(HERE, 'hall_hunts.csv'), encoding='utf-8') if not l.startswith('#')):
        hunts[line[0]] = line
    boxes = []
    for r in rows:
        path, plan = plans[r['id']]
        hunt = hunts.get(r['hunt'])
        check(hunt is not None, '%s: hunt %s is in hall_hunts.csv' % (r['id'], r['hunt']))
        if hunt:
            dest = (int(hunt[4]), int(hunt[5]), int(hunt[6]))
            lo, hi = int(hunt[10]), int(hunt[11])
            check(plan['level'][0] >= lo - 30 and plan['level'][1] <= hi + 30, '%s: level %s inside the hunt band %d-%d' % (r['id'], plan['level'], lo, hi))
            names = {m.strip().lower() for m in hunt[14].split('|')} | {hunt[8].lower(), hunt[12].lower()}
            mons = {s['monster'].lower() for s in plan['spawns']}
            check(len(mons & names) >= 1, '%s: the annex holds monsters of the hunt (%s)' % (r['id'], sorted(mons)))
            for k in ('portal', 'back'):
                p = r[k]
                check(p[2] == dest[2] and abs(p[0] - dest[0]) <= 60 and abs(p[1] - dest[1]) <= 60,
                      '%s: %s %s is on the hunt\'s floor within 60 tiles of its arrival %s' % (r['id'], k, p, dest))
        o = plan['origin']
        w, h = plan['size']
        check(14336 <= o['x'] and o['x'] + w - 1 <= 17663 and 15400 <= o['y'] and o['y'] + h - 1 <= 16383,
              '%s: inside the annex row of the map (x 14336-17663, y 15400-16383)' % r['id'])
        boxes.append((r['id'], o['x'], o['y'], o['x'] + w - 1, o['y'] + h - 1))
        check(plan['exit'].get('to') == dict(x=r['back'][0], y=r['back'][1], z=r['back'][2]), '%s: exit.to is the back tile' % r['id'])
        check(plan['exit']['zone'] == plan['entry']['zone'], '%s: the exit portal is in the arrival zone' % r['id'])
        check('legacy' not in plan.get('notes', '').lower(), '%s: not a legacy plan' % r['id'])
        out = tempfile.mkdtemp(prefix='annex_test_')
        try:
            proc = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'area_planner.py'), 'compile', path, out],
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
            check(proc.returncode == 0, '%s: compiles: %s' % (r['id'], proc.stdout.strip()[-300:]))
            if proc.returncode:
                continue
            check('ERROR' not in proc.stdout, '%s: no QA error: %s' % (r['id'], proc.stdout.strip()[-300:]))
            man = json.load(open(os.path.join(out, r['id'] + '.json'), encoding='utf-8'))
            check(list(man['arrival']) == r['dest'], '%s: dest %s is the arrival %s' % (r['id'], r['dest'], man['arrival']))
            check(list(man['exit']['to']) == r['back'], '%s: the compiled exit portal leads to %s' % (r['id'], r['back']))
            ar = man['stats'].get('walkable') if isinstance(man.get('stats'), dict) else None
            check(ar is None or ar >= 400, '%s: a real area (%s walkable)' % (r['id'], ar))
        finally:
            shutil.rmtree(out, ignore_errors=True)
    for i, a in enumerate(boxes):
        for b in boxes[i + 1:]:
            apart = a[3] + 10 < b[1] or b[3] + 10 < a[1] or a[4] + 10 < b[2] or b[4] + 10 < a[2]
            check(apart, '%s and %s are 10+ tiles apart' % (a[0], b[0]))
    if failures:
        print('%d failure(s)' % len(failures))
        return 1
    print('hunt_annexes_test: ok (%d annexes)' % len(rows))
    return 0


if __name__ == '__main__':
    sys.exit(main())
