#!/usr/bin/env python3
"""python3 -I server/tools/install_monster_creature_looks_test.py : install_monster_creature_looks.py (O608, after O605; install step
`monstercreaturelooks`) on the shipped map and on a synthetic server folder: the map (3 rows, ids 3527-3529, three bosses of ours,
each on a look of its own, the old looks are our files', none of them a hunt monster of the pool or a monster of an earlier map),
the client pair guard end to end (pair 72 or missing: nothing written and a WARNING line; pair 73: our XML, a base XML, a base Lua
monster and the pool rows move, colours stay, a boss with no pool row moves too), a monster that wears the look an earlier pair's
step gave it moves on from it, idempotent, a file with another look stops the step, a missing file stops it, --dry-run writes
nothing, gen_bounty_pool.py turns a new look back to the old one, the audits read the map at pair 73. No base server needed."""
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


# ---- the shipped map: three bosses (owner, O608: the hunt monsters of O605 keep their old looks)
rows = M.read_map()
check([r[0] for r in rows] == ['The Rotmother', 'Vhoss the Hexmaw', 'Talath'], 'the map has the three bosses (%s)' % [r[0] for r in rows])
check([r[2] for r in rows] == [3527, 3528, 3529], 'the new looks are the outfits 3527-3529, one boss on each')
check(C.PAIR_CREATURE == 73 and C.PAIR_CREATURE > C.PAIR_FUN and C.PAIR_ASSETS >= C.PAIR_CREATURE, 'the step needs pair 73, which windows-assets carries')
pool = G.read(G.DEFAULT_OUT)
chaos = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos')
files = R.monster_files(chaos)
for name, old, new in rows:
    check(not re.search(r'\{name = "%s",' % re.escape(name), pool), '%s is no hunt monster of the pool' % name)
    check(name in files, '%s is a monster of ours' % name)
    if name in files:
        check(R.LOOK_TAG.search(open(files[name], encoding='utf-8').read()).group(2) == str(old), '%s: the repository file keeps look %d' % (name, old))
gone = ('Ink Blob', 'Aberration of the Depths', 'Rimecairn', 'Ashmaw Warlord', 'Thalcyra the Stormbound Seer', 'Ascended Thalcyra', 'Frost Maiden',
        'Vaelith the Fallen Seraph', 'Sangrith the Bloodmoon Herald', 'Ascended Sangrith', 'Elite Ice Witch')
check(not {r[0] for r in rows} & set(gone), 'the eleven monsters of O605 keep their old looks')
check(not {r[0] for r in rows} & ({r[0] for r in R.read_map()} | set(S.load_donor()) | set(S.load_purchased())),
      'no monster of the recolour, the donor or the purchased map')

# ---- the audits read the map: the old look below pair 73, the new one from it; a boss is no row of the pool, so the pool reads the same
rc_ = S.load_recolour()
check(S.look_at_pair('The Rotmother', 238, 72, rc_) == 238 and S.look_at_pair('The Rotmother', 238, 73, rc_) == 3527,
      'audit_shared_looks: the Rotmother wears 238 at pair 72 and 3527 at pair 73')
check(S.look_at_pair('The Rotmother', 3527, 68, rc_) == 238, 'a file written for pair 73 reads as the old look for pair 68')
check([S.look_at_pair('Rimecairn', 1531, p, rc_, swap={}) for p in (68, 69, 73)] == [1531, rc_['Rimecairn'][1], rc_['Rimecairn'][1]],
      'audit_shared_looks: Rimecairn keeps the copy of pair 69 at pair 73')
check(S.check_pool(pair=C.PAIR_CREATURE) == [], 'no shared look at pair 73: %s' % S.check_pool(pair=C.PAIR_CREATURE))
check(I.check_pool(pair=C.PAIR_CREATURE) == [], 'every hunt monster moves while it stands at pair 73: %s' % I.check_pool(pair=C.PAIR_CREATURE))
check(I.check_crowded(pair=C.PAIR_CREATURE) == [], 'no crowded look at pair 73')
idle = I.load_idle()
check(all(idle.get(n, (False,))[0] and idle[n][3] == 'idle group' for n in range(3527, 3530)), 'look_idle.csv: the three looks have an idle group that moves')
check(3530 not in idle, 'look_idle.csv: outfit 3530 (Malgrath, O637, no hunt monster) has no row; the six outfits of O605 that are gone left their ids to Malgrath and the PixelLab monsters (O640)')
_swapped = set(S.load_swap())   # the look swaps of O619 ride with pair 73 as well: they are not this map's monsters
check([r['look'] for r in I.donor_rows(S.pool_rows(), C.PAIR_CREATURE)[0] if r['name'] not in _swapped]
      == [r['look'] for r in I.donor_rows(S.pool_rows(), C.PAIR_FUN)[0] if r['name'] not in _swapped],
      'the pool reads the same at pair 72 and 73: no hunt monster of this map changes')

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

# a monster that wears the look an earlier pair's step gave it (a row of the recolour map: Rimecairn, 1531 -> its copy at pair 69) would
# move on from the copy and straight from the old look; no row of the shipped map is such a monster now, the rule stays for a later one
copy = rc_['Rimecairn'][1]
for start in (copy, 1531):
    dn = server(73, [('Rimecairn', start)], [], [], pool_text([('Rimecairn', start, '')]))
    rc, out = run(os.path.join(dn, 'data'))
    check(rc == 1 and 'no monster file' in out, 'the shipped map on a folder without the bosses stops')
    one = os.path.join(tempfile.mkdtemp(prefix='creaturelooks_one_'), 'map.csv')
    open(one, 'w').write('monster,look,new_look\nRimecairn,1531,3529\n')
    rc, out = run(os.path.join(dn, 'data'), '--map', one)
    check(rc == 0 and '1 moved to their new look' in out and '1 rows moved' in out and looks(os.path.join(dn, 'data', 'monster')) == {'Rimecairn': 3529},
          'a monster on look %d moves to 3529 (%s)' % (start, out.strip()))
check(R.creature_looks() == {'The Rotmother': 3527, 'Vhoss the Hexmaw': 3528, 'Talath': 3529}, 'the recolour step reads the creature map')
check(R.creature_looks(one) == {'Rimecairn': 3529}, 'and a map it is given')
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
check(G.committed_look('The Rotmother', 3527) == 238 and G.committed_look('The Rotmother', 238) == 238 and G.committed_look('Zulu', 3527) == 3527,
      'gen_bounty_pool: a creature look is turned back to the old one, others untouched')
check(G.committed_look('Rimecairn', copy) == 1531 and G.committed_look('Frost Maiden', 149) == 149, 'gen_bounty_pool: the monsters of O605 read as before')

# ---- the install step is wired after the fun looks
import install_all as A  # noqa: E402
check('monstercreaturelooks' in A.STEPS and A.STEPS.index('monstercreaturelooks') == A.STEPS.index('funlooks') + 1
      and A.STEPS.index('monstercreaturelooks') > A.STEPS.index('monsterrecolour'), 'install_all: the step runs right after funlooks, past monsterrecolour')

print('install_monster_creature_looks_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
