#!/usr/bin/env python3
"""Test of install_apex_hunts.py (O763, step `apexhunts`): python3 -I server/tools/install_apex_hunts_test.py

The committed swaps against the six O759 plans (every plan, old monster and pack count exists; the new monsters are the files of ours of
gen_apex_monsters.py, levels 2100-2500, inside each hunt's band by the audit's slack), then the step on a synthetic server folder: below
pair 84 nothing changes (a WARNING), at 84 the chosen packs of each plan move by the share (file order, whole blocks only, a mixed block and
another plan's blocks untouched), the bounty pool gets the counts of the spawn file and a row for each new monster in its order, a second
run changes nothing, a rerun after `contentareas` wrote the plain blocks again moves the same blocks, --dry-run writes nothing, a plan
without blocks, a new monster without a file and a file whose look is neither of its map row stop the step; the monster files move
from their stand-in look to the new one."""
import collections
import csv
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_apex_hunts as X  # noqa: E402

PLANS = os.path.join(HERE, 'areaplan', 'plans')
failed = 0


def check(cond, what):
    global failed
    if not cond:
        failed += 1
        print('FAIL', what)


def block(plan, name, cx, n=3):
    mons = ''.join('\t\t<monster name="%s" x="%d" y="0" z="7" spawntime="75" />\n' % (name, i) for i in range(n))
    tag = ' chaoscontent="%s"' % plan if plan else ''
    return '\t<spawn centerx="%d" centery="100" centerz="7" radius="1"%s>\n%s\t</spawn>\n' % (cx, tag, mons)


MONSTER = '''<?xml version="1.0" encoding="UTF-8"?>
<monster name="%s" nameDescription="x" race="blood" experience="%d" speed="33" manacost="0">
	<health now="%d" max="%d"/>
	<look type="%d" corpse="6068"/>
	<level min="%d" max="%d"/>
</monster>
'''
POOL = '''return {
	hunt = {
		{name = "Rat", level = 4, exp = 5, health = 20, spawns = 548, look = 21},
		{name = "Old A", level = 1800, exp = 1, health = 1, spawns = 99, look = 10},
		{name = "Old B", level = 1900, exp = 1, health = 1, spawns = 99, look = 11},
		{name = "Zed", level = 3000, exp = 1, health = 1, spawns = 9, look = 12},
	},
	bosses = {
	},
}
'''


def setup(root, pair):
    data = os.path.join(root, 'data')
    os.makedirs(os.path.join(data, 'world'))
    os.makedirs(os.path.join(data, 'monster', 'monsters', 'chaos', 'sub'))
    os.makedirs(os.path.join(data, 'scripts', 'chaos'))
    open(os.path.join(root, 'config.lua'), 'w').write('mapName = "m"\n' + ('chaosClientPair = %d\n' % pair if pair else ''))
    open(os.path.join(data, 'world', 'm.otbm'), 'wb').write(b'')
    sp = ('<?xml version="1.0"?>\n<spawns>\n' + block(None, 'Old A', 1) + ''.join(block('p1', 'Old A', 10 + i) for i in range(4))
          + block('p1', 'Old B', 20) + block('p2', 'Old A', 30) + block('p1', 'Old A', 40).replace('x="1"', 'x="1" ', 1)
          .replace('<monster name="Old A" x="2"', '<monster name="Old B" x="2"') + '</spawns>\n')
    open(os.path.join(data, 'world', 'm-spawn.xml'), 'w', encoding='latin-1').write(sp)
    for f, (name, lv, look) in (('n1.xml', ('New One', 2100, 900)), ('sub/n2.xml', ('New Two', 2500, 901))):
        open(os.path.join(data, 'monster', 'monsters', 'chaos', f), 'w').write(MONSTER % (name, 70000, 35000, 35000, look, lv - 20, lv + 20))
    X.MAP = os.path.join(root, 'looks.csv')
    with open(X.MAP, 'w', newline='') as f:
        f.write('monster,look,new_look\nNew One,900,3734\nNew Two,901,3743\n')
    open(os.path.join(data, 'scripts', 'chaos', 'bounty_pool.lua'), 'w').write(POOL)
    sw = os.path.join(root, 'swaps.csv')
    with open(sw, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['plan', 'old', 'new', 'share'])
        w.writerows([['p1', 'Old A', 'New One', '0.5'], ['p1', 'Old B', 'New Two', '1'], ['p2', 'Old A', 'New Two', '1']])
    return data, sw


def read(p):
    return open(p, encoding='latin-1').read()


def main():
    # ---- the committed swaps against the plans
    swaps = X.read_swaps()
    plans = {}
    for name in os.listdir(PLANS):
        p = json.load(open(os.path.join(PLANS, name), encoding='utf-8'))
        plans[p['id']] = p
    six = ('rimewrath_steppe', 'sorrowmere_crossing', 'ashfall_hamlet', 'cindervein_hollows', 'gravelight_necropolis', 'umbral_maw')
    check(sorted({s[0] for s in swaps}) == sorted(six), 'the six O759 hunts and no other')
    sys.path.insert(0, os.path.join(X.REPO, 'client', 'tools', 'sprites'))
    import gen_apex_monsters as A
    lv = {m: l for _k, m, l, _f in A.MONSTERS}
    check(sorted({s[2] for s in swaps}) == sorted(lv), 'every new monster of gen_apex_monsters.py spawns')
    for plan, old, new, share in swaps:
        p = plans[plan]
        c = collections.Counter()
        for s in p['spawns']:
            c[s['monster']] += s['count']
        check(c[old] > 0, '%s: %s is a monster of the plan' % (plan, old))
        lo, hi = p['level']
        check(lo * 0.8 <= lv[new] <= hi * 1.2 and lv[new] <= 2500, '%s: %s (%d) inside the band %d-%d by the slack 0.2' % (plan, new, lv[new], lo, hi))
    check(X.chosen(0, 0.5) is False and X.chosen(1, 0.5) is True and all(X.chosen(i, 1) for i in range(5)), 'the share rule')
    check(sum(X.chosen(i, 0.34) for i in range(30)) == 10, 'a third of 30 packs')

    tmp = tempfile.mkdtemp(prefix='o763apex')
    try:
        # ---- below pair 84
        r83 = os.path.join(tmp, 's83')
        data, sw = setup(r83, 83)
        before = read(os.path.join(data, 'world', 'm-spawn.xml'))
        check(X.main([data, '--swaps', sw]) == 0, 'below 84: exit 0')
        check(read(os.path.join(data, 'world', 'm-spawn.xml')) == before, 'below 84: nothing written')
        # ---- at pair 84
        r = os.path.join(tmp, 's84')
        data, sw = setup(r, 84)
        spf, pool = os.path.join(data, 'world', 'm-spawn.xml'), os.path.join(data, 'scripts', 'chaos', 'bounty_pool.lua')
        before = read(spf)
        check(X.main([data, '--swaps', sw, '--dry-run']) == 0 and read(spf) == before, 'dry run writes nothing')
        check(X.main([data, '--swaps', sw]) == 0, 'the step runs')
        n1 = os.path.join(data, 'monster', 'monsters', 'chaos', 'n1.xml')
        n2 = os.path.join(data, 'monster', 'monsters', 'chaos', 'sub', 'n2.xml')
        check('<look type="3734"' in read(n1) and '<look type="3743"' in read(n2), 'the monster files wear the new looks')
        t = read(spf)
        blocks = X.BLOCK.findall(t)
        names = [sorted(set(n for _a, n, _c in X.MON.findall(b))) for b in blocks]
        check(names == [['Old A'], ['Old A'], ['New One'], ['Old A'], ['New One'], ['New Two'], ['New Two'], ['Old A', 'Old B']],
              'the moved blocks: %s' % names)
        check('chaosapex="Old A"' in blocks[2] and 'chaosapex="Old B"' in blocks[5] and 'chaosapex' not in blocks[0], 'the mark')
        pt = open(pool, encoding='utf-8').read()
        rows = [(m.group(1), int(m.group(2)), int(m.group(5)), int(m.group(6))) for m in X.POOL_ROW.finditer(pt)]
        check(rows == [('Rat', 4, 548, 21), ('Old A', 1800, 11, 10), ('Old B', 1900, 1, 11), ('New One', 2100, 6, 3734),
                       ('New Two', 2500, 6, 3743), ('Zed', 3000, 9, 12)], 'the pool: %s' % rows)
        t1, p1 = read(spf), open(pool, encoding='utf-8').read()
        check(X.main([data, '--swaps', sw]) == 0 and read(spf) == t1 and open(pool, encoding='utf-8').read() == p1, 'a second run changes nothing')
        # contentareas writes the plain blocks again (at the end of the file)
        plain = before
        open(spf, 'w', encoding='latin-1').write(plain)
        check(X.main([data, '--swaps', sw]) == 0 and read(spf) == t1, 'the same blocks move again')
        # ---- refusals
        with open(sw, 'a') as f:
            f.write('p9,Old A,New One,1\n')
        check(X.main([data, '--swaps', sw]) == 1, 'a plan without blocks stops the step')
        data2, sw2 = setup(os.path.join(tmp, 'nofile'), 84)
        os.remove(os.path.join(data2, 'monster', 'monsters', 'chaos', 'sub', 'n2.xml'))
        check(X.main([data2, '--swaps', sw2]) == 1, 'a new monster without a file stops the step')
        data3, sw3 = setup(os.path.join(tmp, 'otherlook'), 84)
        n1 = os.path.join(data3, 'monster', 'monsters', 'chaos', 'n1.xml')
        n1t = read(n1).replace('type="900"', 'type="77"')
        open(n1, 'w').write(n1t)
        before3 = read(os.path.join(data3, 'world', 'm-spawn.xml'))
        check(X.main([data3, '--swaps', sw3]) == 1 and read(os.path.join(data3, 'world', 'm-spawn.xml')) == before3,
              'a file with another look stops the step, nothing written')
        committed = os.path.join(X.REPO, 'server', 'data', 'monster', 'monster_apex_looks.csv')
        check(X.read_map(committed)['Umbral Devourer'] == (1532, 3743), 'the committed map')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('install_apex_hunts_test: %s' % ('ok' if not failed else '%d failed' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
