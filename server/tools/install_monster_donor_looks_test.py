#!/usr/bin/env python3
"""python3 -I server/tools/install_monster_donor_looks_test.py : install_monster_donor_looks.py (O538, install step `monsterdonorlooks`)
on the shipped map and on a synthetic server folder: the map (33 rows, ids 3406-3438, the old looks are the committed pool's and our
files'), the client pair guard end to end (pair 69 or missing: nothing written and a WARNING line; pair 70: our XML, a base XML, a base
Lua monster and the pool rows move, colours stay), idempotent, a file with another look stops the step, a missing file stops it,
--dry-run writes nothing, gen_bounty_pool.py turns a new look back to the old one. No base server needed."""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair as C  # noqa: E402
import install_monster_donor_looks as M  # noqa: E402
import install_monster_recolour as R  # noqa: E402
import gen_bounty_pool as G  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(HERE, 'install_monster_donor_looks.py')
failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def run(*args):
    p = subprocess.run([sys.executable, '-I', TOOL] + list(args), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
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
    d = tempfile.mkdtemp(prefix='donorlooks_')
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


# ---- the shipped map
rows = M.read_map()
check(len(rows) == 33, 'the map has 33 rows (%d)' % len(rows))
check(sorted(r[2] for r in rows) == list(range(3406, 3439)), 'the new looks are 3406..3438, each once')
check(len({r[0] for r in rows}) == len(rows), 'one row per monster')
check(all(r[1] < 3406 for r in rows), 'the old looks are below the new pair')
check(C.PAIR_DONOR == 70, 'the step needs pair 70')
pool = G.read(G.DEFAULT_OUT)
for name, old, new in rows:
    m = re.search(r'\{name = "%s",[^}]*?\blook = (\d+)' % re.escape(name), pool)
    check(m and int(m.group(1)) == old, '%s: the committed pool keeps look %d' % (name, old))
chaos = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos')
files = R.monster_files(chaos)
for name, old, new in rows:
    if name in files:
        check(R.LOOK_TAG.search(open(files[name], encoding='utf-8').read()).group(2) == str(old), '%s: the repository file keeps look %d' % (name, old))
recol = {r[0] for r in R.read_map()}
check(not recol & {r[0] for r in rows}, 'no monster is in the recolour map as well (its copy would be a second new look)')

# ---- text helpers
t, st = M.retype_lua(lua('A', 100), 100, 3406)
check(st == 'moved' and 'lookType = 3406' in t and 'lookHead = 10' in t, 'lua: old -> new, the colour field stays')
check(M.retype_lua(t, 100, 3406) == (t, 'done') and M.retype_lua(lua('A', 101), 100, 3406)[1] == 'other', 'lua: already new, another look')
check(M.retype_lua('local x = 1\n', 1, 2)[1] == 'other', 'lua: no outfit')

# ---- the guard and the step end to end (synthetic server: our file, a base XML, a base Lua monster, and one that stays)
mp = os.path.join(tempfile.mkdtemp(prefix='donorlooks_map_'), 'map.csv')
open(mp, 'w').write('monster,look,new_look\nAlpha,100,3406\nBravo,100,3407\nCharlie,200,3408\n')
OURS, BX, BL = [('Alpha', 100), ('Zulu', 100)], [('Bravo', 100), ('Delta', 100)], [('Charlie', 200)]
pool = pool_text([('Alpha', 100, ''), ('Bravo', 100, ', head = 3'), ('Charlie', 200, ''), ('Delta', 100, '')])
for pair in (None, 54, 69):
    d = server(pair, OURS, BX, BL, pool)
    before = snapshot(d)
    rc, out = run(os.path.join(d, 'data'), '--map', mp)
    check(rc == 0 and 'WARNING: monsterdonorlooks skipped' in out and 'client pair 70' in out and snapshot(d) == before,
          'pair %s: warning, exit 0, nothing written' % pair)
d = server(70, OURS, BX, BL, pool)
before = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp, '--dry-run')
check(rc == 0 and 'dry run' in out and snapshot(d) == before, 'pair 70 --dry-run writes nothing')
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '3 moved to their new look' in out and '3 rows moved' in out, 'pair 70: three files and three pool rows move (%s)' % out.strip())
mon = os.path.join(d, 'data', 'monster')
look = {}
for dp, _dn, fs in os.walk(mon):
    for f in fs:
        text = open(os.path.join(dp, f)).read()
        m = re.search(r'<look type="(\d+)"', text) or re.search(r'lookType = (\d+)', text)
        n = re.search(r'<monster name="([^"]+)"', text) or re.search(r'createMonsterType\("([^"]+)"', text)
        if m and n:
            look[n.group(1)] = int(m.group(1))
check(look == {'Alpha': 3406, 'Bravo': 3407, 'Charlie': 3408, 'Zulu': 100, 'Delta': 100}, 'the monsters wear their new looks (the others keep theirs): %s' % look)
check('head="10"' in open(os.path.join(mon, 'monsters', 'dragons', 'bravo.xml')).read(), 'a base XML keeps its colour fields')
ptxt = open(os.path.join(d, 'data', 'scripts', 'chaos', 'bounty_pool.lua')).read()
check('look = 3406}' in ptxt and 'look = 3407, head = 3' in ptxt and 'look = 3408}' in ptxt and re.search(r'"Delta".*look = 100\}', ptxt), 'the pool rows follow')
after = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '0 moved to their new look, 3 already there' in out and snapshot(d) == after, 'a second run changes nothing')
d2 = server(75, OURS, BX, BL, pool)
rc, out = run(os.path.join(d2, 'data'), '--map', mp)
check(rc == 0 and '3 moved' in out, 'pair 75 installs')
# a file with another look, and a missing file, stop the step before anything is written
d3 = server(70, OURS, [('Bravo', 777)], BL, pool)
b3 = snapshot(d3)
rc, out = run(os.path.join(d3, 'data'), '--map', mp)
check(rc == 1 and 'ERROR Bravo' in out and 'has look 777' in out and snapshot(d3) == b3, 'a look that is neither the old nor the new one stops the step, nothing written')
d4 = server(70, OURS, BX, [], pool)
rc, out = run(os.path.join(d4, 'data'), '--map', mp)
check(rc == 1 and 'ERROR Charlie: no monster file' in out, 'a missing monster file stops the step')
d5 = server(70, OURS, BX, BL, None)
rc, out = run(os.path.join(d5, 'data'), '--map', mp)
check(rc == 0 and 'bounty_pool.lua: not installed' in out and '3 moved' in out, 'no installed pool: skipped, the files move')
# a name defined by our file and by the base: both move
d6 = server(70, [('Alpha', 100)], [('Alpha', 100), ('Bravo', 100)], BL, pool)
rc, out = run(os.path.join(d6, 'data'), '--map', mp)
check(rc == 0 and '4 moved' in out, 'a name defined twice moves in both files (%s)' % out.strip())

# ---- the pool generator gives the committed pool back from a server that wears the new looks
G.DONOR = G._donor_looks(mp)
check(G.committed_look('Alpha', 3406) == 100 and G.committed_look('Alpha', 100) == 100 and G.committed_look('Zulu', 3406) == 3406,
      'gen_bounty_pool: a new look is turned back to the old one, others untouched')
text, n = G.relook(pool_text([('Alpha', 100, ''), ('Bravo', 100, ', head = 3')]),
                   {'alpha': {'look': 3406}, 'bravo': {'look': 3407, 'look_head': 3}})
check(n == 0 and 'look = 100}' in text and 'look = 100, head = 3' in text, 'gen_bounty_pool --relook keeps the committed pool on a server at pair 70 (%s)' % text)
text, n = G.relook(pool_text([('Alpha', 100, '')]), {'alpha': {'look': 555}})
check(n == 1 and 'look = 555}' in text, 'gen_bounty_pool --relook still writes a real look change')

print('install_monster_donor_looks_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
