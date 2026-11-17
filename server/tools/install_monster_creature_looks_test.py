#!/usr/bin/env python3
"""python3 -I server/tools/install_monster_creature_looks_test.py : install_monster_creature_looks.py (O605, install step
`monstercreaturelooks`) on the shipped map and on a synthetic server folder: the map (11 rows, ids 3527-3535, the old looks are our
files' and the committed pool's, at most 2 monsters on a look, the hunt monsters each on a look of their own), the client pair guard
end to end (pair 72 or missing: nothing written and a WARNING line; pair 73: our XML, a base XML, a base Lua monster and the pool
rows move, colours stay, a boss with no pool row moves too), a monster that wears its hue shifted copy (Rimecairn, pair 69) moves on
from it and the recolour step then leaves it alone, idempotent, a file with another look stops the step, a missing file stops it,
--dry-run writes nothing, gen_bounty_pool.py turns a new look back to the old one, the audits read the map at pair 73. No base
server needed."""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair as C  # noqa: E402
import install_monster_creature_looks as M  # noqa: E402
import install_monster_recolour as R  # noqa: E402
import gen_bounty_pool as G  # noqa: E402
import audit_shared_looks as S  # noqa: E402
import audit_idle_looks as I  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(HERE, 'install_monster_creature_looks.py')
RECOLOUR_TOOL = os.path.join(HERE, 'install_monster_recolour.py')
failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def run(*args, tool=TOOL):
    p = subprocess.run([sys.executable, '-I', tool] + list(args), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return p.returncode, p.stdout


def xml(name, look, extra=' head="10" body="20"'):
    return '<?xml version="1.0"?>\n<monster name="%s" nameDescription="a %s" race="blood" experience="5" speed="100">\n' \
           '\t<health now="100" max="100"/>\n\t<look type="%d"%s corpse="6068"/>\n</monster>\n' % (name, name, look, extra)


def lua(name, look):
    return 'local mType = Game.createMonsterType("%s")\nlocal monster = {}\nmonster.description = "a %s"\n' \
           'monster.outfit = {\n\tlookType = %d,\n\tlookHead = 10,\n\tlookAddons = 0,\n}\nmonster.health = 100\nmType:register(monster)\n' % (name, name, look)


def pool_text(rows):
    return 'return {\n\thunt = {\n' + ''.join(
        '\t\t{name = "%s", level = 5, exp = 1, health = 9, spawns = 9, look = %d%s},\n' % r for r in rows) + '\t},\n\tbosses = {\n\t},\n}\n'


def server(pair, ours, base_xml, base_lua, pool=None):
    d = tempfile.mkdtemp(prefix='creaturelooks_')
    if pair is not None:
        open(os.path.join(d, 'config.lua'), 'w').write('chaosClientPair = %d\n' % pair)
    mon = os.path.join(d, 'data', 'monster')
    for sub, items, make in (('monsters/chaos/pack30', ours, xml), ('monsters/dragons', base_xml, xml), ('lua/misc', base_lua, lua)):
        os.makedirs(os.path.join(mon, sub))
        for name, look in items:
            open(os.path.join(mon, sub, name.lower().replace(' ', '_') + ('.xml' if make is xml else '.lua')), 'w').write(make(name, look))
    if pool is not None:
        os.makedirs(os.path.join(d, 'data', 'scripts', 'chaos'))
        open(os.path.join(d, 'data', 'scripts', 'chaos', 'bounty_pool.lua'), 'w').write(pool)
    return d


def snapshot(d):
    out = {}
    for dp, _dn, fs in os.walk(d):
        for f in fs:
            out[os.path.join(dp, f)] = open(os.path.join(dp, f), 'rb').read()
    return out


def looks(mon):
    out = {}
    for dp, _dn, fs in os.walk(mon):
        for f in fs:
            text = open(os.path.join(dp, f)).read()
            m = re.search(r'<look type="(\d+)"', text) or re.search(r'lookType = (\d+)', text)
            n = re.search(r'<monster name="([^"]+)"', text) or re.search(r'createMonsterType\("([^"]+)"', text)
            if m and n:
                out[n.group(1)] = int(m.group(1))
    return out


# ---- the shipped map
rows = M.read_map()
check(len(rows) == 11, 'the map has 11 rows (%d)' % len(rows))
check(sorted({r[2] for r in rows}) == list(range(3527, 3536)), 'the new looks are the outfits 3527-3535, every one worn')
check(len({r[0] for r in rows}) == len(rows), 'one row per monster')
per = {}
for _n, _o, new in rows:
    per[new] = per.get(new, 0) + 1
check(max(per.values()) <= 2, 'at most 2 monsters on one new look')
check(C.PAIR_CREATURE == 73 and C.PAIR_CREATURE > C.PAIR_FUN and C.PAIR_ASSETS < C.PAIR_CREATURE, 'the step needs pair 73, which is not on windows-assets')
pool = G.read(G.DEFAULT_OUT)
chaos = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos')
files = R.monster_files(chaos)
hunt = []
for name, old, new in rows:
    m = re.search(r'\{name = "%s",[^}]*?\blook = (\d+)' % re.escape(name), pool)
    check(m or name in files, '%s is a monster of ours or of the pool' % name)
    if m:
        hunt.append((name, new))
        check(int(m.group(1)) == old, '%s: the committed pool keeps look %d' % (name, old))
    if name in files:
        check(R.LOOK_TAG.search(open(files[name], encoding='utf-8').read()).group(2) == str(old), '%s: the repository file keeps look %d' % (name, old))
check(len(hunt) == 6 and len({n for _m, n in hunt}) == 6, 'six hunt monsters, each on a look of its own (%s)' % hunt)
check(dict((r[0], r[2]) for r in rows)['Elite Ice Witch'] != dict((r[0], r[2]) for r in rows)['Frost Maiden'], 'the elite has its own look')
both = {r[0] for r in rows} & {r[0] for r in R.read_map()}
check(both == {'Rimecairn'}, 'one monster of the recolour map takes a creature look over its copy: %s' % sorted(both))
check(not {r[0] for r in rows} & (set(S.load_donor()) | set(S.load_purchased())), 'no monster of the donor or the purchased map')

# ---- the audits read the map: the old look below pair 73, the new one from it (Rimecairn: old, copy, new)
check(S.look_at_pair('Frost Maiden', 149, 72, S.load_recolour()) == 149 and S.look_at_pair('Frost Maiden', 149, 73, S.load_recolour()) == 3532,
      'audit_shared_looks: the Frost Maiden wears 149 at pair 72 and 3532 at pair 73')
rc_ = S.load_recolour()
check([S.look_at_pair('Rimecairn', 1531, p, rc_) for p in (68, 69, 72, 73)] == [1531, rc_['Rimecairn'][1], rc_['Rimecairn'][1], 3529],
      'audit_shared_looks: Rimecairn goes old look, copy, copy, creature look')
check(S.look_at_pair('Rimecairn', 3529, 68, rc_) == 1531, 'a file written for pair 73 reads as the old look for pair 68')
check(S.check_pool(pair=C.PAIR_CREATURE) == [], 'no shared look at pair 73: %s' % S.check_pool(pair=C.PAIR_CREATURE))
check(I.check_pool(pair=C.PAIR_CREATURE) == [], 'every hunt monster moves while it stands at pair 73: %s' % I.check_pool(pair=C.PAIR_CREATURE))
check(I.check_crowded(pair=C.PAIR_CREATURE) == [], 'no crowded look at pair 73')
idle = I.load_idle()
check(all(idle.get(n, (False,))[0] and idle[n][3] == 'idle group' for n in range(3527, 3536)), 'look_idle.csv: the nine looks have an idle group that moves')
moved = {r['name']: r['look'] for r in I.donor_rows(S.pool_rows(), C.PAIR_CREATURE)[0]}
check(all(moved[n] == new for n, new in hunt), 'the pool read at pair 73 wears the new looks')
check(all(r['look'] != new for r in I.donor_rows(S.pool_rows(), C.PAIR_FUN)[0] for _n, new in hunt), 'and none of them at pair 72')

# ---- the guard and the step end to end (synthetic server: our files, a base XML, a base Lua monster, a boss with no pool row)
mp = os.path.join(tempfile.mkdtemp(prefix='creaturelooks_map_'), 'map.csv')
open(mp, 'w').write('monster,look,new_look\nAlpha,100,3527\nBravo,100,3528\nCharlie,200,3529\nEcho,300,3530\nBoss,400,3531\n')
OURS, BX, BL = [('Alpha', 100), ('Zulu', 100), ('Echo', 300), ('Boss', 400)], [('Bravo', 100), ('Delta', 100)], [('Charlie', 200)]
ptext = pool_text([('Alpha', 100, ''), ('Bravo', 100, ', head = 3'), ('Charlie', 200, ''), ('Delta', 100, ''), ('Echo', 300, '')])
for pair in (None, 54, 72):
    d = server(pair, OURS, BX, BL, ptext)
    before = snapshot(d)
    rc, out = run(os.path.join(d, 'data'), '--map', mp)
    check(rc == 0 and 'WARNING: monstercreaturelooks skipped' in out and 'client pair 73' in out and snapshot(d) == before,
          'pair %s: warning, exit 0, nothing written' % pair)
d = server(73, OURS, BX, BL, ptext)
before = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp, '--dry-run')
check(rc == 0 and 'dry run' in out and snapshot(d) == before, 'pair 73 --dry-run writes nothing')
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '5 moved to their new look' in out and '4 rows moved' in out, 'pair 73: five files and four pool rows move (%s)' % out.strip())
mon = os.path.join(d, 'data', 'monster')
check(looks(mon) == {'Alpha': 3527, 'Bravo': 3528, 'Charlie': 3529, 'Echo': 3530, 'Boss': 3531, 'Zulu': 100, 'Delta': 100},
      'the monsters wear their new looks (the others keep theirs): %s' % looks(mon))
check('head="10"' in open(os.path.join(mon, 'monsters', 'dragons', 'bravo.xml')).read(), 'a base XML keeps its colour fields')
got = open(os.path.join(d, 'data', 'scripts', 'chaos', 'bounty_pool.lua')).read()
check('look = 3527}' in got and 'look = 3528, head = 3' in got and 'look = 3529}' in got and re.search(r'"Delta".*look = 100\}', got),
      'the pool rows follow')
after = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '0 moved to their new look, 5 already there' in out and snapshot(d) == after, 'a second run changes nothing')
rc, out = run(os.path.join(server(80, OURS, BX, BL, ptext), 'data'), '--map', mp)
check(rc == 0 and '5 moved' in out, 'pair 80 installs')

# Rimecairn (the shipped maps: 1531 -> its copy at pair 69 -> 3529 at pair 73): from the copy and straight from the old look; then the
# recolour step leaves a monster that wears its creature look alone
copy = rc_['Rimecairn'][1]
for start in (copy, 1531):
    dn = server(73, [('Rimecairn', start)], [], [], pool_text([('Rimecairn', start, '')]))
    rc, out = run(os.path.join(dn, 'data'))
    check(rc == 1 and 'no monster file' in out, 'the shipped map on a folder with one monster stops (the others are missing)')
    one = os.path.join(tempfile.mkdtemp(prefix='creaturelooks_one_'), 'map.csv')
    open(one, 'w').write('monster,look,new_look\nRimecairn,1531,3529\n')
    rc, out = run(os.path.join(dn, 'data'), '--map', one)
    check(rc == 0 and '1 moved to their new look' in out and '1 rows moved' in out and looks(os.path.join(dn, 'data', 'monster')) == {'Rimecairn': 3529},
          'Rimecairn on look %d moves to 3529 (%s)' % (start, out.strip()))
    rmap = os.path.join(tempfile.mkdtemp(prefix='creaturelooks_rec_'), 'rec.csv')
    open(rmap, 'w').write('monster,look,new_look\nRimecairn,1531,%d\n' % copy)
    snap = snapshot(dn)
    rc, out = run(os.path.join(dn, 'data'), '--map', rmap, tool=RECOLOUR_TOOL)
    check(rc == 0 and '0 moved to their copy, 1 already there' in out and snapshot(dn) == snap,
          'the recolour step leaves a monster that wears its creature look alone (%s)' % out.strip())
check(R.creature_looks().get('Rimecairn') == 3529, 'the recolour step reads the creature map')
check(M.retype_pool(pool_text([('A', 3394, '')]), [('A', 100, 3529)], {'A': {3394}})[1:] == (1, 0), 'pool: an earlier pair\'s look moves too')
check(M.retype_pool(pool_text([('A', 7, '')]), [('A', 100, 3529)], {})[1:] == (0, 0), 'pool: another look stays')

# a file with another look, and a missing file, stop the step before anything is written
d3 = server(73, OURS, [('Bravo', 777)], BL, ptext)
b3 = snapshot(d3)
rc, out = run(os.path.join(d3, 'data'), '--map', mp)
check(rc == 1 and 'ERROR Bravo' in out and 'has look 777' in out and snapshot(d3) == b3, 'a look that is none of the known ones stops the step, nothing written')
rc, out = run(os.path.join(server(73, OURS, BX, [], ptext), 'data'), '--map', mp)
check(rc == 1 and 'ERROR Charlie: no monster file' in out, 'a missing monster file stops the step')
rc, out = run(os.path.join(server(73, OURS, BX, BL, None), 'data'), '--map', mp)
check(rc == 0 and 'bounty_pool.lua: not installed' in out and '5 moved' in out, 'no installed pool: skipped, the files move')

# ---- the pool generator gives the committed pool back from a server that wears the creature looks
check(G.committed_look('Frost Maiden', 3532) == 149 and G.committed_look('Frost Maiden', 149) == 149 and G.committed_look('Zulu', 3532) == 3532,
      'gen_bounty_pool: a creature look is turned back to the old one, others untouched')
check(G.committed_look('Rimecairn', 3529) == 1531 and G.committed_look('Rimecairn', copy) == 1531, 'gen_bounty_pool: Rimecairn goes back from its copy and from its creature look')

# ---- the install step is wired after the fun looks
import install_all as A  # noqa: E402
check('monstercreaturelooks' in A.STEPS and A.STEPS.index('monstercreaturelooks') == A.STEPS.index('funlooks') + 1
      and A.STEPS.index('monstercreaturelooks') > A.STEPS.index('monsterrecolour'), 'install_all: the step runs right after funlooks, past monsterrecolour')

print('install_monster_creature_looks_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
