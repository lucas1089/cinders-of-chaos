#!/usr/bin/env python3
"""python3 -I server/tools/install_monster_pixellab_looks_test.py : install_monster_pixellab_looks.py (O640; install step
`monsterpixellablooks`) on the shipped map and on a synthetic server folder: the map (24 rows, ids 3531-3554, one hunt monster on each
look, each in the level band of its tier, the old looks are the files' or the committed pool's, none of them in the map of an earlier
pair), the client pair guard end to end (pair 73 or missing: nothing written and a WARNING line; pair 74: our XML, a base XML, a base
Lua monster and the pool rows move, colours stay), a monster that wears the look an earlier pair's step gave it moves on from it,
idempotent, a file with another look stops the step, a missing file stops it, --dry-run writes nothing, gen_bounty_pool.py turns a
new look back to the old one, the audits read the map at pair 74 (no shared look, every look moves while it stands, none crowded).
No base server needed."""
import csv
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'client', 'tools', 'sprites'))
import client_pair as C  # noqa: E402
import install_monster_pixellab_looks as M  # noqa: E402
import install_monster_recolour as R  # noqa: E402
import gen_bounty_pool as G  # noqa: E402
import audit_shared_looks as S  # noqa: E402
import audit_idle_looks as I  # noqa: E402
import gen_pixellab_monsters as P  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(HERE, 'install_monster_pixellab_looks.py')
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
    d = tempfile.mkdtemp(prefix='pixellablooks_')
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


# ---- the shipped map: 24 hunt monsters, one on each outfit 3531-3554
rows = M.read_map()
check(len(rows) == 24 and [r[2] for r in rows] == list(range(3531, 3555)), 'the map has 24 rows, the new looks are the outfits 3531-3554 in order')
check(len({r[0] for r in rows}) == 24 and len({r[2] for r in rows}) == 24, 'each monster once, each look once: no two hunt monsters share a look')
check(C.PAIR_PIXELLAB == 74 and C.PAIR_PIXELLAB > C.PAIR_ASSETS, 'the step needs pair 74, which windows-assets does not carry yet')
check(P.FIRST_NEW == 3531 and [r['key'] for r in P.rows()] == list(P.KEYS) and len(P.rows()) == 24, 'the table of the outfits has the same 24 rows')
check([int(r['new']) for r in P.rows()] == [r[2] for r in rows], 'monster i wears outfit 3531 + i, the table row i')
pool_rows = {r['name']: r for r in S.pool_rows()}
lv = P.pool_levels()
chaos = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos')
files = R.monster_files(chaos)
tiers = {int(r['new']): int(r['tier']) for r in P.rows()}
for name, old, new in rows:
    check(name in pool_rows and pool_rows[name]['look'] == old, '%s: a hunt monster of the pool on look %d' % (name, old))
    lo, hi = P.BANDS[tiers[new]]
    check(lo <= lv.get(name, 0) <= hi, '%s: level %s in the band of tier %d (%d to %d)' % (name, lv.get(name), tiers[new], lo, hi))
    if name in files:
        check(R.LOOK_TAG.search(open(files[name], encoding='utf-8').read()).group(2) == str(old), '%s: the repository file keeps look %d' % (name, old))
check(all(lv[n] >= 500 for n, _o, new in rows if tiers[new] == 4) and sum(1 for _n, _o, new in rows if tiers[new] == 4) == 5,
      'the five boss-like looks (tier 4) go to monsters of level 500 and more')
earlier = set()
for f in (R.MAP, os.path.join(os.path.dirname(R.MAP), 'monster_donor_looks.csv'), os.path.join(os.path.dirname(R.MAP), 'monster_wst_looks.csv'),
          os.path.join(os.path.dirname(R.MAP), 'monster_creature_looks.csv'), os.path.join(os.path.dirname(R.MAP), 'monster_o619_looks.csv')):
    earlier |= {r['monster'] for r in csv.DictReader(open(f, newline='', encoding='utf-8'))}
check(not {r[0] for r in rows} & earlier, 'no monster of the recolour, donor, purchased, creature or swap map')
check(not {r[2] for r in rows} & {n for _o, n in S.load_swap().values()}, 'no new look is a look of the swap map')

# ---- the audits read the map: the old look below pair 74, the new one from it
rc_ = S.load_recolour()
for name, old, new in rows:
    check(S.look_at_pair(name, old, 73, rc_) == old and S.look_at_pair(name, old, 74, rc_) == new, 'audit_shared_looks: %s wears %d at pair 73 and %d at pair 74' % (name, old, new))
    check(S.look_at_pair(name, new, 70, rc_) == old, 'a file written for pair 74 reads as the old look for pair 70 (%s)' % name)
for pair in (C.PAIR_ASSETS, C.PAIR_PIXELLAB):
    check(S.check_pool(pair=pair) == [], 'no shared look at pair %d: %s' % (pair, S.check_pool(pair=pair)))
    check(I.check_pool(pair=pair) == [], 'every hunt monster moves while it stands at pair %d: %s' % (pair, I.check_pool(pair=pair)))
    check(I.check_crowded(pair=pair) == [], 'no crowded look at pair %d' % pair)
idle = I.load_idle()
check(all(idle.get(n, (False,))[0] and idle[n][3] == 'idle group' for n in range(3531, 3555)), 'look_idle.csv: the 24 looks have an idle group that moves')
check([idle[int(r['new'])][1] for r in P.rows()] == [int(r['idle']) for r in P.rows()], 'look_idle.csv: the phases of each idle group are the table\'s')
at74 = {r['name']: r['look'] for r in I.donor_rows(S.pool_rows(), C.PAIR_PIXELLAB)[0]}
at73 = {r['name']: r['look'] for r in I.donor_rows(S.pool_rows(), C.PAIR_ASSETS)[0]}
check({n for n in at74 if at74[n] != at73[n]} == {r[0] for r in rows} and all(at74[n] == new for n, _o, new in rows),
      'the pool reads the same at pair 73 and 74 but for the 24 monsters')
# a look worn alone: the new looks are no look of any other monster of the pool at pair 74
worn = {}
for n, lk in at74.items():
    worn.setdefault(lk, []).append(n)
check(all(worn[new] == [name] for name, _o, new in rows), 'every new look is worn by its monster alone at pair 74')

# ---- the guard and the step end to end (synthetic server: our files, a base XML, a base Lua monster)
mp = os.path.join(tempfile.mkdtemp(prefix='pixellablooks_map_'), 'map.csv')
open(mp, 'w').write('monster,look,new_look\nAlpha,100,3531\nBravo,100,3532\nCharlie,200,3533\nEcho,300,3534\n')
OURS, BX, BL = [('Alpha', 100), ('Zulu', 100), ('Echo', 300)], [('Bravo', 100), ('Delta', 100)], [('Charlie', 200)]
ptext = pool_text([('Alpha', 100, ''), ('Bravo', 100, ', head = 3'), ('Charlie', 200, ''), ('Delta', 100, ''), ('Echo', 300, '')])
for pair in (None, 54, 73):
    d = server(pair, OURS, BX, BL, ptext)
    before = snapshot(d)
    rc, out = run(os.path.join(d, 'data'), '--map', mp)
    check(rc == 0 and 'WARNING: monsterpixellablooks skipped' in out and 'client pair 74' in out and snapshot(d) == before,
          'pair %s: warning, exit 0, nothing written' % pair)
d = server(74, OURS, BX, BL, ptext)
before = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp, '--dry-run')
check(rc == 0 and 'dry run' in out and snapshot(d) == before, 'pair 74 --dry-run writes nothing')
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '4 moved to their new look' in out and '4 rows moved' in out, 'pair 74: four files and four pool rows move (%s)' % out.strip())
mon = os.path.join(d, 'data', 'monster')
check(looks(mon) == {'Alpha': 3531, 'Bravo': 3532, 'Charlie': 3533, 'Echo': 3534, 'Zulu': 100, 'Delta': 100},
      'the monsters wear their new looks (the others keep theirs): %s' % looks(mon))
check('head="10"' in open(os.path.join(mon, 'monsters', 'dragons', 'bravo.xml')).read(), 'a base XML keeps its colour fields')
got = open(os.path.join(d, 'data', 'scripts', 'chaos', 'bounty_pool.lua')).read()
check('look = 3531}' in got and 'look = 3532, head = 3' in got and 'look = 3533}' in got and re.search(r'"Delta".*look = 100\}', got),
      'the pool rows follow')
after = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '0 moved to their new look, 4 already there' in out and snapshot(d) == after, 'a second run changes nothing')
rc, out = run(os.path.join(server(80, OURS, BX, BL, ptext), 'data'), '--map', mp)
check(rc == 0 and '4 moved' in out, 'pair 80 installs')

# a monster that wears the look an earlier pair's step gave it moves on from it (and straight from the old look): the copy of the recolour map,
# the swapped look of O619
copy = rc_['Rimecairn'][1]
for start, why in ((copy, 'its copy of pair 69'), (1531, 'its old look')):
    dn = server(74, [('Rimecairn', start)], [], [], pool_text([('Rimecairn', start, '')]))
    one = os.path.join(tempfile.mkdtemp(prefix='pixellablooks_one_'), 'map.csv')
    open(one, 'w').write('monster,look,new_look\nRimecairn,1531,3531\n')
    rc, out = run(os.path.join(dn, 'data'), '--map', one)
    check(rc == 0 and '1 moved to their new look' in out and '1 rows moved' in out and looks(os.path.join(dn, 'data', 'monster')) == {'Rimecairn': 3531},
          'a monster on %s moves to 3531 (%s)' % (why, out.strip()))
swapped = S.load_swap()
name, (old, new) = sorted(swapped.items())[0]
dn = server(74, [(name, new)], [], [], pool_text([(name, new, '')]))
one = os.path.join(tempfile.mkdtemp(prefix='pixellablooks_one_'), 'map.csv')
open(one, 'w').write('monster,look,new_look\n%s,%d,3532\n' % (name, old))
rc, out = run(os.path.join(dn, 'data'), '--map', one)
check(rc == 0 and '1 moved to their new look' in out and looks(os.path.join(dn, 'data', 'monster')) == {name: 3532}, '%s: the swapped look of O619 moves on to 3532 (%s)' % (name, out.strip()))
check(M.earlier_looks().get(name) and new in M.earlier_looks()[name], 'earlier_looks reads the swap map too')

# the shipped map on a folder without the monsters stops; a file with another look, and a missing file, stop the step before anything is written
rc, out = run(os.path.join(server(74, [], [], [], None), 'data'))
check(rc == 1 and 'ERROR Lesser Fire Devil: no monster file' in out, 'the shipped map on a folder without the monsters stops')
d3 = server(74, OURS, [('Bravo', 777), ('Delta', 100)], BL, ptext)
b3 = snapshot(d3)
rc, out = run(os.path.join(d3, 'data'), '--map', mp)
check(rc == 1 and 'ERROR Bravo' in out and 'has look 777' in out and snapshot(d3) == b3, 'a look that is none of the known ones stops the step, nothing written')
rc, out = run(os.path.join(server(74, OURS, BX, [], ptext), 'data'), '--map', mp)
check(rc == 1 and 'ERROR Charlie: no monster file' in out, 'a missing monster file stops the step')
rc, out = run(os.path.join(server(74, OURS, BX, BL, None), 'data'), '--map', mp)
check(rc == 0 and 'bounty_pool.lua: not installed' in out and '4 moved' in out, 'no installed pool: skipped, the files move')

# ---- the pool generator gives the committed pool back from a server that wears the PixelLab looks
for name, old, new in rows:
    check(G.committed_look(name, new) == old and G.committed_look(name, old) == old, 'gen_bounty_pool: %s turns back from %d to %d' % (name, new, old))
check(G.committed_look('Zulu', 3531) == 3531, 'gen_bounty_pool: another monster is untouched')

# ---- the install step is wired after Malgrath's look
import install_all as A  # noqa: E402
check('monsterpixellablooks' in A.STEPS and A.STEPS.index('monsterpixellablooks') == A.STEPS.index('monstermalgrathlook') + 1
      and A.STEPS.index('monsterpixellablooks') > A.STEPS.index('monsterswaplooks'), 'install_all: the step runs right after monstermalgrathlook, past monsterswaplooks')
check(callable(getattr(A, 'step_monsterpixellablooks', None)), 'the step function exists')

print('install_monster_pixellab_looks_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
