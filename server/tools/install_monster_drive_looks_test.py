#!/usr/bin/env python3
"""python3 -I server/tools/install_monster_drive_looks_test.py : install_monster_drive_looks.py (O726; install step `monsterdrivelooks`)
on the shipped map and on a synthetic server folder: the map (28 rows, ids 3561-3588, one hunt monster on each look, every one a hunt
monster of the committed pool (no boss); O726's today share or crowd their look and are in no earlier map, O729's (the redraws of the upright
third-party looks) may be in one with the same committed look), the client pair guard end to end (pair 80 or missing: nothing written and a WARNING line; pair 81: our
XML, a base XML, a base Lua monster and the pool rows move, colours stay), a monster that wears the PixelLab look of pair 74 moves on from
it, an O729 monster on its recolour or donor look moves on, idempotent, a file with another look stops the step, a missing file stops it, --dry-run writes nothing, gen_bounty_pool.py turns a new
look back to the old one, the audits read the map at pair 81 (no shared look, every look moves while it stands or is a still redraw with a TEMPORARY row of
no_idle_allow.csv, none crowded).
No base server needed."""
import csv
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'client', 'tools', 'sprites'))
import client_pair as C  # noqa: E402
import install_monster_drive_looks as M  # noqa: E402
import install_monster_recolour as R  # noqa: E402
import gen_bounty_pool as G  # noqa: E402
import audit_shared_looks as S  # noqa: E402
import audit_idle_looks as I  # noqa: E402
import gen_drive_monsters as P  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(HERE, 'install_monster_drive_looks.py')
TMP = tempfile.mkdtemp(prefix='drivelooks_')
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


def pool_text(rows_):
    return 'return {\n\thunt = {\n' + ''.join(
        '\t\t{name = "%s", level = 5, exp = 1, health = 9, spawns = 9, look = %d%s},\n' % r for r in rows_) + '\t},\n\tbosses = {\n\t},\n}\n'


def server(pair, ours, base_xml, base_lua, pool=None):
    d = tempfile.mkdtemp(dir=TMP)
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


# ---- the shipped map: 28 hunt monsters, one on each outfit 3561-3588 (O726: 3561-3571, O729: 3572-3588)
rows = M.read_map()
check(len(rows) == 28 and [r[2] for r in rows] == list(range(3561, 3589)), 'the map has 28 rows, the new looks are the outfits 3561-3588 in order')
check(len({r[0] for r in rows}) == 28 and len({r[2] for r in rows}) == 28, 'each monster once, each look once: no two hunt monsters share a look')
O729 = {m for k, m in P.PICKS if k in P.O729_KEYS}
check(len(O729) == 17 and {r[0] for r in rows[11:]} == O729, 'O729: the last 17 rows are the redraws of the upright third-party looks')
check(C.PAIR_DRIVE_MONSTERS == 81 and C.PAIR_ASSETS >= C.PAIR_DRIVE_MONSTERS, 'the step needs pair 81, which windows-assets carries (2026-11-23)')
check(P.FIRST_NEW == 3561 and [int(r['new']) for r in P.rows()] == [r[2] for r in rows], 'monster i wears outfit 3561 + i, the table row i')
check([m for _k, m in P.PICKS] == [r[0] for r in rows], 'the map is PICKS of gen_drive_monsters.py, in order')
pool_rows = {r['name']: r for r in S.pool_rows()}
lv = P.P.pool_levels()
chaos = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos')
files = R.monster_files(chaos)
crowd = {}
for f in ('crowded_looks_allow.csv', 'shared_looks_allow.csv'):
    for r in csv.DictReader(open(os.path.join(REPO, 'server', 'data', 'monster', f), newline='', encoding='utf-8')):
        crowd.setdefault(int(r['look']), set()).update(n.strip() for n in r['names'].split('|'))
for name, old, new in rows:
    check(name in pool_rows and pool_rows[name]['look'] == old, '%s: a hunt monster of the pool on look %d' % (name, old))
    check(name in lv, '%s: on the hunt list of the pool (no boss)' % name)
    if name not in O729:    # O726 took looks that are crowded or shared; O729 takes upright third-party looks (any)
        check(name in crowd.get(old, set()), '%s: its look %d is crowded or shared today' % (name, old))
    if name in files:
        check(R.LOOK_TAG.search(open(files[name], encoding='utf-8').read()).group(2) == str(old), '%s: the repository file keeps look %d' % (name, old))
earlier = {}
for f in ('monster_recolour_looks.csv', 'monster_donor_looks.csv', 'monster_wst_looks.csv', 'monster_creature_looks.csv', 'monster_o619_looks.csv',
          'monster_pixellab_looks.csv'):
    for r in csv.DictReader(open(os.path.join(os.path.dirname(R.MAP), f), newline='', encoding='utf-8')):
        earlier.setdefault(r['monster'], set()).add(int(r['look']))
check(not {r[0] for r in rows[:11]} & set(earlier), 'O726: no monster of an earlier map')
check({r[0] for r in rows if r[0] in earlier} == {'Deepforge Fiend', 'Rootbound Pilgrim', 'Thornveil Wraith', 'Infernal Phantom'},
      'O729: four monsters of earlier maps, whose earlier look the new one replaces')
for name, old, new in rows:
    if name in earlier:
        check(earlier[name] == {old}, '%s: the earlier maps name the same committed look %d' % (name, old))

# ---- the audits read the map: the old look below pair 81, the new one from it
rc_ = S.load_recolour()
for name, old, new in rows:
    at = S.look_at_pair(name, old, 80, rc_)
    check((at == old or name in earlier) and at != new and S.look_at_pair(name, old, 81, rc_) == new,
          'audit_shared_looks: %s wears %d at pair 80 and %d at pair 81' % (name, at, new))
    check(S.look_at_pair(name, new, 74, rc_) == S.look_at_pair(name, old, 74, rc_), 'a file written for pair 81 reads as the pair 74 look for pair 74 (%s)' % name)
for pair in (80, C.PAIR_DRIVE_MONSTERS):
    check(S.check_pool(pair=pair) == [], 'no shared look at pair %d: %s' % (pair, S.check_pool(pair=pair)))
    check(I.check_pool(pair=pair) == [], 'every hunt monster moves while it stands at pair %d: %s' % (pair, I.check_pool(pair=pair)))
    check(I.check_crowded(pair=pair) == [], 'no crowded look at pair %d' % pair)
idle = I.load_idle()
temp = I.load_temporary()
for r in P.rows():
    n, name = int(r['new']), dict((k, m) for k, m in P.PICKS)[r['key']]
    if r['idle'] == '1':
        check(idle.get(n, (True,))[0] is False and (name, n) in temp, 'look_idle.csv: %d stands still and %s has a TEMPORARY row' % (n, name))
    else:
        check(idle.get(n, (False,))[0] and idle[n][3] == 'idle group', 'look_idle.csv: %d has an idle group that moves' % n)
        check((name, n) not in temp, '%s: no TEMPORARY row for a look that moves' % name)
check([idle[int(r['new'])][1] for r in P.rows()] == [int(r['idle']) for r in P.rows()], "look_idle.csv: the phases of each idle group are the table's")
check(temp == {}, 'no TEMPORARY row left: every look moves while it stands (%s)' % sorted(temp))
# the TEMPORARY rule on a synthetic allow file: a still new look needs its row, the row leaves the old row in place, and it is stale
# once the look moves
tmpd = tempfile.mkdtemp(prefix='o726allow')
withrow = os.path.join(tmpd, 'allow.csv')
with open(I.ALLOW, encoding='utf-8') as f_in, open(withrow, 'w', encoding='utf-8') as f_out:
    f_out.write(f_in.read() + "Paladin's Apparition,3561,TEMPORARY (test): frames not drawn yet\n")
still = {**idle, 3561: (False, 1, 1, 'none')}
check(I.load_allow(withrow).get("Paladin's Apparition", (0,))[0] == 129, 'a TEMPORARY row leaves the old row of the same monster in place')
check(I.load_temporary(withrow) == {("Paladin's Apparition", 3561): 'TEMPORARY (test): frames not drawn yet'}, 'load_temporary reads it')
check(I.check_pool(pair=C.PAIR_DRIVE_MONSTERS, idle=still, allow_path=withrow) == [], 'a still look with its TEMPORARY row passes')
check(any('3561' in x and 'must move' in x for x in I.check_pool(pair=C.PAIR_DRIVE_MONSTERS, idle=still)),
      'a still look without its TEMPORARY row fails')
check(any('remove its TEMPORARY row' in x for x in I.check_pool(pair=C.PAIR_DRIVE_MONSTERS, allow_path=withrow)),
      'a TEMPORARY row of a look that moves is stale')
shutil.rmtree(tmpd, ignore_errors=True)
at81 = {r['name']: r['look'] for r in I.donor_rows(S.pool_rows(), C.PAIR_DRIVE_MONSTERS)[0]}
at80 = {r['name']: r['look'] for r in I.donor_rows(S.pool_rows(), 80)[0]}
check({n for n in at81 if at81[n] != at80[n]} == {r[0] for r in rows} and all(at81[n] == new for n, _o, new in rows),
      'the pool reads the same at pair 80 and 81 but for the 28 monsters')
worn = {}
for n, lk in at81.items():
    worn.setdefault(lk, []).append(n)
check(all(worn[new] == [name] for name, _o, new in rows), 'every new look is worn by its monster alone at pair 81')

# ---- the guard and the step end to end (synthetic server: our files, a base XML, a base Lua monster)
mp = os.path.join(TMP, 'map.csv')
open(mp, 'w').write('monster,look,new_look\nAlpha,100,3561\nBravo,100,3562\nCharlie,200,3563\nEcho,300,3564\n')
OURS, BX, BL = [('Alpha', 100), ('Zulu', 100), ('Echo', 300)], [('Bravo', 100), ('Delta', 100)], [('Charlie', 200)]
ptext = pool_text([('Alpha', 100, ''), ('Bravo', 100, ', head = 3'), ('Charlie', 200, ''), ('Delta', 100, ''), ('Echo', 300, '')])
for pair in (None, 74, 80):
    d = server(pair, OURS, BX, BL, ptext)
    before = snapshot(d)
    rc, out = run(os.path.join(d, 'data'), '--map', mp)
    check(rc == 0 and 'WARNING: monsterdrivelooks skipped' in out and 'client pair 81' in out and snapshot(d) == before,
          'pair %s: warning, exit 0, nothing written' % pair)
d = server(81, OURS, BX, BL, ptext)
before = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp, '--dry-run')
check(rc == 0 and 'dry run' in out and snapshot(d) == before, 'pair 81 --dry-run writes nothing')
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '4 moved to their new look' in out and '4 rows moved' in out, 'pair 81: four files and four pool rows move (%s)' % out.strip())
mon = os.path.join(d, 'data', 'monster')
check(looks(mon) == {'Alpha': 3561, 'Bravo': 3562, 'Charlie': 3563, 'Echo': 3564, 'Zulu': 100, 'Delta': 100},
      'the monsters wear their new looks (the others keep theirs): %s' % looks(mon))
check('head="10"' in open(os.path.join(mon, 'monsters', 'dragons', 'bravo.xml')).read(), 'a base XML keeps its colour fields')
got = open(os.path.join(d, 'data', 'scripts', 'chaos', 'bounty_pool.lua')).read()
check('look = 3561}' in got and 'look = 3562, head = 3' in got and 'look = 3563}' in got and re.search(r'"Delta".*look = 100\}', got),
      'the pool rows follow')
after = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '0 moved to their new look, 4 already there' in out and snapshot(d) == after, 'a second run changes nothing')
rc, out = run(os.path.join(server(90, OURS, BX, BL, ptext), 'data'), '--map', mp)
check(rc == 0 and '4 moved' in out, 'pair 90 installs')

# a monster that wears the PixelLab look of pair 74 moves on from it
name, (old, new) = sorted(S.load_pixellab().items())[0]
dn = server(81, [(name, new)], [], [], pool_text([(name, new, '')]))
one = os.path.join(TMP, 'one.csv')
open(one, 'w').write('monster,look,new_look\n%s,%d,3565\n' % (name, old))
rc, out = run(os.path.join(dn, 'data'), '--map', one)
check(rc == 0 and '1 moved to their new look' in out and looks(os.path.join(dn, 'data', 'monster')) == {name: 3565},
      '%s: the PixelLab look moves on to 3565 (%s)' % (name, out.strip()))
check(M.earlier_looks().get(name) and new in M.earlier_looks()[name], 'earlier_looks reads the PixelLab map too')
# O729: a monster of the shipped map that wears its recolour copy (pair 69) or its donor look (pair 70) moves on to its O729 look
for name in ('Deepforge Fiend', 'Infernal Phantom'):
    old, new = [(o, n) for m, o, n in rows if m == name][0]
    was = [n for m_, (o, n) in list(S.load_recolour().items()) + list(S.load_donor().items()) if m_ == name][0]
    dn = server(81, [(name, was)], [], [], pool_text([(name, was, '')]))
    mp1 = os.path.join(TMP, 'o729.csv')
    open(mp1, 'w').write('monster,look,new_look\n%s,%d,%d\n' % (name, old, new))
    rc, out = run(os.path.join(dn, 'data'), '--map', mp1)
    check(rc == 0 and '1 moved to their new look' in out and looks(os.path.join(dn, 'data', 'monster')) == {name: new},
          '%s: look %d of an earlier pair moves on to %d (%s)' % (name, was, new, out.strip()))

# the shipped map on a folder without the monsters stops; a file with another look, and a missing file, stop the step before anything is written
rc, out = run(os.path.join(server(81, [], [], [], None), 'data'))
check(rc == 1 and "ERROR Paladin's Apparition: no monster file" in out, 'the shipped map on a folder without the monsters stops')
d3 = server(81, OURS, [('Bravo', 777), ('Delta', 100)], BL, ptext)
b3 = snapshot(d3)
rc, out = run(os.path.join(d3, 'data'), '--map', mp)
check(rc == 1 and 'ERROR Bravo' in out and 'has look 777' in out and snapshot(d3) == b3, 'a look that is none of the known ones stops the step, nothing written')
rc, out = run(os.path.join(server(81, OURS, BX, [], ptext), 'data'), '--map', mp)
check(rc == 1 and 'ERROR Charlie: no monster file' in out, 'a missing monster file stops the step')
rc, out = run(os.path.join(server(81, OURS, BX, BL, None), 'data'), '--map', mp)
check(rc == 0 and 'bounty_pool.lua: not installed' in out and '4 moved' in out, 'no installed pool: skipped, the files move')

# ---- the pool generator gives the committed pool back from a server that wears the new looks
for name, old, new in rows:
    check(G.committed_look(name, new) == old and G.committed_look(name, old) == old, 'gen_bounty_pool: %s turns back from %d to %d' % (name, new, old))
check(G.committed_look('Zulu', 3561) == 3561, 'gen_bounty_pool: another monster is untouched')

# ---- the install step is wired after the PixelLab looks
import install_all as A  # noqa: E402
check('monsterdrivelooks' in A.STEPS and A.STEPS.index('monsterdrivelooks') == A.STEPS.index('monsterpixellablooks') + 1,
      'install_all: the step runs right after monsterpixellablooks')
check(callable(getattr(A, 'step_monsterdrivelooks', None)), 'the step function exists')

shutil.rmtree(TMP, ignore_errors=True)
print('install_monster_drive_looks_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
