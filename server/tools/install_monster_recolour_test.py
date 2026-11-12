#!/usr/bin/env python3
"""python3 -I server/tools/install_monster_recolour_test.py : install_monster_recolour.py (O531, install step `monsterrecolour`) on the
shipped map and on a synthetic server folder: the map (35 rows, ids 3371-3405 in table order, the old looks are the files' looks), the
client pair guard end to end (pair 68 or missing: nothing written and a WARNING line; pair 69: the 35 files and the pool rows move),
idempotent, a file with another look stops the step, a missing file stops it, --dry-run writes nothing, gen_bounty_pool.py turns a copy
back to the old look. No base server needed."""
import csv
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair as C  # noqa: E402
import install_monster_recolour as M  # noqa: E402
import gen_bounty_pool as G  # noqa: E402
import audit_shared_looks as A  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(HERE, 'install_monster_recolour.py')
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


def pool_text(rows):
    return 'return {\n\thunt = {\n' + ''.join(
        '\t\t{name = "%s", level = 5, exp = 1, health = 9, spawns = 9, look = %d%s},\n' % r for r in rows) + '\t},\n\tbosses = {\n\t},\n}\n'


def server(pair, files, pool=None):
    d = tempfile.mkdtemp(prefix='recolour_')
    if pair is not None:
        open(os.path.join(d, 'config.lua'), 'w').write('chaosClientPair = %d\n' % pair)
    root = os.path.join(d, 'data', 'monster', 'monsters', 'chaos', 'pack30')
    os.makedirs(root)
    for name, look in files:
        open(os.path.join(root, name.lower().replace(' ', '_') + '.xml'), 'w').write(xml(name, look))
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
with open(os.path.join(REPO, 'client', 'tools', 'sprites', 'art_import', 'monster_recolour.csv'), newline='') as f:
    table = list(csv.DictReader(f))
check(len(rows) == len(table) and len(rows) > 0, 'the map has a row for every row of the table (rows may be removed later)')
check([r[2] for r in rows] == list(range(3371, 3371 + len(rows))), 'new looks are 3371.. in table order')
check([(r[0], r[1]) for r in rows] == [(t['monster'], int(t['look'])) for t in table], 'monsters and old looks are the table\'s')
check(len({r[0] for r in rows}) == len(rows), 'one row per monster')
check(C.PAIR_RECOLOUR == 69, 'the step needs pair 69')

# ---- the repository files hold the old looks (the step moves them on an installed server only)
chaos = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos')
files = M.monster_files(chaos)
for name, old, new in rows:
    text = open(files[name], encoding='utf-8').read()
    check(M.LOOK_TAG.search(text).group(2) == str(old), '%s: the repository file keeps look %d' % (name, old))

# ---- text helpers
t, st = M.retype_xml(xml('A', 100), 100, 3371)
check(st == 'moved' and 'type="3371"' in t and 'head="10"' in t and 'body="20"' in t and 'corpse="6068"' in t, 'xml: old -> new, colours and corpse stay')
check(M.retype_xml(t, 100, 3371) == (t, 'done'), 'xml: already new')
check(M.retype_xml(xml('A', 101), 100, 3371)[1] == 'other', 'xml: another look is reported')
p, mv, dn = M.retype_pool(pool_text([('A', 100, ''), ('B', 100, ', head = 3, addons = 0')]), [('A', 100, 3371), ('B', 100, 3372)])
check(mv == 2 and dn == 0 and 'look = 3371}' in p and 'look = 3372, head = 3' in p, 'pool: both rows move, colours stay')
check(M.retype_pool(p, [('A', 100, 3371), ('B', 100, 3372)])[1:] == (0, 2) and M.retype_pool(p, [('A', 100, 3371)])[0] == p, 'pool: second run changes nothing')

# ---- the guard and the step end to end (synthetic server, 3 monsters of a synthetic map)
mp = os.path.join(tempfile.mkdtemp(prefix='recolour_map_'), 'map.csv')
open(mp, 'w').write('monster,look,new_look\nAlpha,100,3371\nBravo,100,3372\n')
fl = [('Alpha', 100), ('Bravo', 100), ('Charlie', 100)]
pool = pool_text([('Alpha', 100, ''), ('Bravo', 100, ', head = 3'), ('Charlie', 100, '')])
for pair in (None, 54, 68):
    d = server(pair, fl, pool)
    before = snapshot(d)
    rc, out = run(os.path.join(d, 'data'), '--map', mp)
    check(rc == 0 and 'WARNING: monsterrecolour skipped' in out and 'client pair 69' in out and snapshot(d) == before,
          'pair %s: warning, exit 0, nothing written' % pair)
d = server(69, fl, pool)
before = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp, '--dry-run')
check(rc == 0 and 'dry run' in out and snapshot(d) == before, 'pair 69 --dry-run writes nothing')
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '2 moved to their copy' in out and '2 rows moved' in out, 'pair 69: two files and two pool rows move (%s)' % out.strip())
look = {}
for name, path in M.monster_files(os.path.join(d, 'data', 'monster', 'monsters', 'chaos')).items():
    look[name] = int(M.LOOK_TAG.search(open(path).read()).group(2))
check(look == {'Alpha': 3371, 'Bravo': 3372, 'Charlie': 100}, 'the monsters wear their copies (Charlie, not in the map, keeps its look): %s' % look)
ptxt = open(os.path.join(d, 'data', 'scripts', 'chaos', 'bounty_pool.lua')).read()
check('look = 3371}' in ptxt and 'look = 3372, head = 3' in ptxt and re.search(r'"Charlie".*look = 100\}', ptxt), 'the pool rows follow')
after = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '0 moved to their copy, 2 already there' in out and snapshot(d) == after, 'a second run changes nothing')
# a newer pair than 69 installs too
d2 = server(75, fl, pool)
rc, out = run(os.path.join(d2, 'data'), '--map', mp)
check(rc == 0 and '2 moved' in out, 'pair 75 installs')
# a file with another look, and a missing file, stop the step before anything is written
d3 = server(69, [('Alpha', 100), ('Bravo', 777)], pool)
b3 = snapshot(d3)
rc, out = run(os.path.join(d3, 'data'), '--map', mp)
check(rc == 1 and 'ERROR Bravo' in out and 'has look 777' in out and snapshot(d3) == b3, 'a look that is neither the old nor the new one stops the step, nothing written')
d4 = server(69, [('Alpha', 100)], pool)
rc, out = run(os.path.join(d4, 'data'), '--map', mp)
check(rc == 1 and 'ERROR Bravo: no file' in out, 'a missing monster file stops the step')
# no pool installed: the files still move
d5 = server(69, fl, None)
rc, out = run(os.path.join(d5, 'data'), '--map', mp)
check(rc == 0 and 'bounty_pool.lua: not installed' in out and '2 moved' in out, 'no installed pool: skipped, the files move')
# the real map on the real files: copy the repository's monster folder into a synthetic server at pair 69
import shutil  # noqa: E402
d6 = tempfile.mkdtemp(prefix='recolour_real_')
open(os.path.join(d6, 'config.lua'), 'w').write('chaosClientPair = 69\n')
shutil.copytree(chaos, os.path.join(d6, 'data', 'monster', 'monsters', 'chaos'))
os.makedirs(os.path.join(d6, 'data', 'scripts', 'chaos'))
shutil.copy(os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'bounty_pool.lua'), os.path.join(d6, 'data', 'scripts', 'chaos', 'bounty_pool.lua'))
rc, out = run(os.path.join(d6, 'data'))
check(rc == 0 and '%d moved to their copy, 0 already there' % len(rows) in out, 'the real map moves every repository file (%s)' % out.strip())
m = re.search(r'bounty_pool.lua: (\d+) rows moved', out)
installed_pool = open(os.path.join(d6, 'data', 'scripts', 'chaos', 'bounty_pool.lua')).read()
pool_names = {r['name'] for r in A.pool_rows(os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'bounty_pool.lua'))}
in_pool = [r for r in rows if r[0] in pool_names]
check(m and int(m.group(1)) == len(in_pool) and len(in_pool) >= 1, 'the pool rows of the map\'s monsters move (%s rows)' % (m.group(1) if m else '?'))
# installed pool and files read at pair 69: no two hunt monsters share a look
check(A.check_pool(os.path.join(d6, 'data', 'scripts', 'chaos', 'bounty_pool.lua'), pair=69) == [], 'the installed pool at pair 69: no shared look')
# the generator turns a copy back to the old look
name, old, new = rows[1]
check(G.committed_look(name, new) == old and G.committed_look(name, old) == old, 'gen_bounty_pool.py writes the old look for a copy')
check(G.committed_look('Nobody', 3371) == 3371, 'gen_bounty_pool.py leaves other monsters alone')

print('install_monster_recolour_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
