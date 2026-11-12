#!/usr/bin/env python3
"""python3 -I server/tools/install_monster_wst_looks_test.py : install_monster_wst_looks.py (O540, install step `monsterwstlooks`)
on the shipped map and on a synthetic server folder: the map (79 rows, ids 3434-3510, the old looks are the committed pool's and our
files', at most 2 monsters on a look, no monster of the recolour map), the client pair guard end to end (pair 70 or missing: nothing
written and a WARNING line; pair 71: our XML, a base XML, a base Lua monster and the pool rows move, colours stay), a monster that
wears its donor look (Bonepicker, Wan Sentry: pair 70) moves on from it, idempotent, the donor step leaves a monster that already wears
its purchased look alone, a file with another look stops the step, a missing file stops it, --dry-run writes nothing, gen_bounty_pool.py
turns a new look back to the old one. No base server needed."""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair as C  # noqa: E402
import install_monster_donor_looks as D  # noqa: E402
import install_monster_wst_looks as M  # noqa: E402
import install_monster_recolour as R  # noqa: E402
import gen_bounty_pool as G  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(HERE, 'install_monster_wst_looks.py')
DONOR_TOOL = os.path.join(HERE, 'install_monster_donor_looks.py')
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
    d = tempfile.mkdtemp(prefix='wstlooks_')
    if pair is not None:
        open(os.path.join(d, 'config.lua'), 'w').write('chaosClientPair = %d\n' % pair)
    mon = os.path.join(d, 'data', 'monster')
    for sub, items, make in (('monsters/chaos/pack30', ours, xml), ('monsters/dragons', base_xml, xml), ('lua/misc', base_lua, lua)):
        os.makedirs(os.path.join(mon, sub))
        for name, look in items:
            open(os.path.join(mon, sub, name.lower().replace(' ', '_') + ('.xml' if make is xml else '.lua')), 'w').write(make(name, look))
    # the registry of the base server names monsters too (a `<monster name=` line with no <look>): never a monster file
    open(os.path.join(mon, 'monsters.xml'), 'w').write('<monsters>\n\t<monster name="Delta" file="dragons/delta.xml"/>\n</monsters>\n')
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
check(len(rows) == 79, 'the map has 79 rows (%d)' % len(rows))
check(all(3434 <= r[2] <= 3510 for r in rows), 'the new looks are outfits 3434-3510')
check(len({r[0] for r in rows}) == len(rows), 'one row per monster')
per = {}
for _n, _o, new in rows:
    per[new] = per.get(new, 0) + 1
check(max(per.values()) <= 2, 'at most 2 monsters on one new look (owner rule of O533)')
check(all(r[1] < 3406 for r in rows), 'the old looks are below the new pairs')
check(C.PAIR_PURCHASED == 71, 'the step needs pair 71')
pool = G.read(G.DEFAULT_OUT)
for name, old, new in rows:
    m = re.search(r'\{name = "%s",[^}]*?\blook = (\d+)' % re.escape(name), pool)
    check(m and int(m.group(1)) == old, '%s: the committed pool keeps look %d' % (name, old))
chaos = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos')
files = R.monster_files(chaos)
for name, old, new in rows:
    if name in files:
        check(R.LOOK_TAG.search(open(files[name], encoding='utf-8').read()).group(2) == str(old), '%s: the repository file keeps look %d' % (name, old))
check(not {r[0] for r in R.read_map()} & {r[0] for r in rows}, 'no monster is in the recolour map as well')
both = {r[0] for r in rows} & set(M.donor_looks())
check(both == {'Bonepicker', 'Wan Sentry'}, 'two monsters of the donor map take a purchased look over it: %s' % sorted(both))

# ---- text helpers
t, st = M.retype_lua(lua('A', 100), {100, 3415}, 3450)
check(st == 'moved' and 'lookType = 3450' in t and 'lookHead = 10' in t, 'lua: old -> new, the colour field stays')
check(M.retype_lua(lua('A', 3415), {100, 3415}, 3450)[1] == 'moved', 'lua: the donor look moves too')
check(M.retype_lua(t, {100}, 3450) == (t, 'done') and M.retype_lua(lua('A', 101), {100}, 3450)[1] == 'other', 'lua: already new, another look')
check(M.retype_lua('local x = 1\n', {1}, 2)[1] == 'other', 'lua: no outfit')
x, st = M.retype_xml(xml('A', 3415), {100, 3415}, 3450)
check(st == 'moved' and 'type="3450"' in x and 'head="10"' in x, 'xml: the donor look moves, colours stay')
check(M.retype_pool(pool_text([('A', 3415, '')]), [('A', 100, 3450)], {'A': 3415})[1:] == (1, 0), 'pool: the donor look moves too')

# ---- the guard and the step end to end (synthetic server: our file, a base XML, a base Lua monster, one that stays)
mp = os.path.join(tempfile.mkdtemp(prefix='wstlooks_map_'), 'map.csv')
open(mp, 'w').write('monster,look,new_look\nAlpha,100,3450\nBravo,100,3451\nCharlie,200,3452\nEcho,300,3453\n')
OURS, BX, BL = [('Alpha', 100), ('Zulu', 100), ('Echo', 300)], [('Bravo', 100), ('Delta', 100)], [('Charlie', 200)]
pool = pool_text([('Alpha', 100, ''), ('Bravo', 100, ', head = 3'), ('Charlie', 200, ''), ('Delta', 100, ''), ('Echo', 300, '')])
for pair in (None, 54, 70):
    d = server(pair, OURS, BX, BL, pool)
    before = snapshot(d)
    rc, out = run(os.path.join(d, 'data'), '--map', mp)
    check(rc == 0 and 'WARNING: monsterwstlooks skipped' in out and 'client pair 71' in out and snapshot(d) == before,
          'pair %s: warning, exit 0, nothing written' % pair)
d = server(71, OURS, BX, BL, pool)
before = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp, '--dry-run')
check(rc == 0 and 'dry run' in out and snapshot(d) == before, 'pair 71 --dry-run writes nothing')
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '4 moved to their new look' in out and '4 rows moved' in out, 'pair 71: four files and four pool rows move (%s)' % out.strip())
mon = os.path.join(d, 'data', 'monster')
check(looks(mon) == {'Alpha': 3450, 'Bravo': 3451, 'Charlie': 3452, 'Echo': 3453, 'Zulu': 100, 'Delta': 100},
      'the monsters wear their new looks (the others keep theirs): %s' % looks(mon))
check('head="10"' in open(os.path.join(mon, 'monsters', 'dragons', 'bravo.xml')).read(), 'a base XML keeps its colour fields')
ptxt = open(os.path.join(d, 'data', 'scripts', 'chaos', 'bounty_pool.lua')).read()
check('look = 3450}' in ptxt and 'look = 3451, head = 3' in ptxt and 'look = 3452}' in ptxt and re.search(r'"Delta".*look = 100\}', ptxt),
      'the pool rows follow')
after = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '0 moved to their new look, 4 already there' in out and snapshot(d) == after, 'a second run changes nothing')
d2 = server(75, OURS, BX, BL, pool)
rc, out = run(os.path.join(d2, 'data'), '--map', mp)
check(rc == 0 and '4 moved' in out, 'pair 75 installs')

# a monster of both maps (the shipped donor map: Bonepicker 3354 -> 3415, Wan Sentry 3216 -> 3432): a server that wears the donor look
# moves on to the purchased look, one on the old look goes straight there, and the donor step then leaves the monster alone
real = os.path.join(tempfile.mkdtemp(prefix='wstlooks_real_'), 'map.csv')
open(real, 'w').write('monster,look,new_look\nBonepicker,3354,3453\nWan Sentry,3216,3454\n')
dn = server(71, [('Bonepicker', 3415), ('Wan Sentry', 3432)], [], [], pool_text([('Bonepicker', 3415, ''), ('Wan Sentry', 3432, '')]))
rc, out = run(os.path.join(dn, 'data'), '--map', real)
check(rc == 0 and '2 moved to their new look' in out and '2 rows moved' in out and looks(os.path.join(dn, 'data', 'monster')) == {'Bonepicker': 3453, 'Wan Sentry': 3454},
      'a monster that wears its donor look moves on to the purchased look (%s)' % out.strip())
dn2 = server(71, [('Bonepicker', 3354), ('Wan Sentry', 3216)], [], [], pool_text([('Bonepicker', 3354, ''), ('Wan Sentry', 3216, '')]))
rc, out = run(os.path.join(dn2, 'data'), '--map', real)
check(rc == 0 and '2 moved to their new look' in out and looks(os.path.join(dn2, 'data', 'monster')) == {'Bonepicker': 3453, 'Wan Sentry': 3454},
      'a monster on its old look goes straight to the purchased look')
# the donor step reads the purchased map: monsters that already wear their purchased look are no error for it (the shipped maps)
D_PURCHASED = D.purchased_looks()
check(D_PURCHASED.get('Bonepicker') and D_PURCHASED.get('Wan Sentry') and set(D_PURCHASED) == {r[0] for r in rows}, 'the donor step reads the purchased map')
dr = server(71, [('Bonepicker', D_PURCHASED['Bonepicker']), ('Wan Sentry', D_PURCHASED['Wan Sentry'])], [], [], None)
dmap = os.path.join(tempfile.mkdtemp(prefix='wstlooks_donor_'), 'donor.csv')
open(dmap, 'w').write('monster,look,new_look\nBonepicker,3354,3415\nWan Sentry,3216,3432\n')
rc, out = run(os.path.join(dr, 'data'), '--map', dmap, tool=DONOR_TOOL)
check(rc == 0 and '0 moved to their new look, 2 already there' in out, 'the donor step leaves a monster that wears its purchased look alone (%s)' % out.strip())

# a file with another look, and a missing file, stop the step before anything is written
d3 = server(71, OURS, [('Bravo', 777)], BL, pool)
b3 = snapshot(d3)
rc, out = run(os.path.join(d3, 'data'), '--map', mp)
check(rc == 1 and 'ERROR Bravo' in out and 'has look 777' in out and snapshot(d3) == b3, 'a look that is none of the old, donor and new ones stops the step, nothing written')
d4 = server(71, OURS, BX, [], pool)
rc, out = run(os.path.join(d4, 'data'), '--map', mp)
check(rc == 1 and 'ERROR Charlie: no monster file' in out, 'a missing monster file stops the step')
d5 = server(71, OURS, BX, BL, None)
rc, out = run(os.path.join(d5, 'data'), '--map', mp)
check(rc == 0 and 'bounty_pool.lua: not installed' in out and '4 moved' in out, 'no installed pool: skipped, the files move')
d6 = server(71, [('Alpha', 100), ('Echo', 300)], [('Alpha', 100), ('Bravo', 100)], BL, pool)
rc, out = run(os.path.join(d6, 'data'), '--map', mp)
check(rc == 0 and '5 moved' in out, 'a name defined twice moves in both files (%s)' % out.strip())

# ---- the pool generator gives the committed pool back from a server that wears the purchased looks
G.PURCHASED = G._donor_looks(mp)
G.DONOR = {'Echo': (300, 3415)}
check(G.committed_look('Alpha', 3450) == 100 and G.committed_look('Alpha', 100) == 100 and G.committed_look('Zulu', 3450) == 3450,
      'gen_bounty_pool: a purchased look is turned back to the old one, others untouched')
check(G.committed_look('Echo', 3453) == 300 and G.committed_look('Echo', 3415) == 300, 'gen_bounty_pool: a donor look and a purchased look both go back')
text, n = G.relook(pool_text([('Alpha', 100, ''), ('Bravo', 100, ', head = 3')]), {'alpha': {'look': 3450}, 'bravo': {'look': 3451, 'look_head': 3}})
check(n == 0 and 'look = 100}' in text and 'look = 100, head = 3' in text, 'gen_bounty_pool --relook keeps the committed pool on a server at pair 71 (%s)' % text)

print('install_monster_wst_looks_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
