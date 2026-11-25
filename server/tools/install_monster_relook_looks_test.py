#!/usr/bin/env python3
"""python3 -I server/tools/install_monster_relook_looks_test.py : install_monster_relook_looks.py (O768; install step `monsterrelooklooks`)
on the shipped map and on a synthetic server folder: the map (the owner's five picks: Banshee, Werelion, Leaf Golem on the outfits
3744-3746 of gen_relook_monsters.py, White Lion on the stock look 1041, Hellhound on 3280; each a hunt monster of the committed pool, its
old look the pool's), the client pair guard end to end (pair 85 or missing: nothing written and a WARNING line; pair 86: a base XML, a
base Lua monster and the pool rows move, colours stay), a monster on its donor or purchased look of an earlier pair moves on, idempotent,
a file with another look stops the step, a missing file stops it, --dry-run writes nothing, gen_bounty_pool.py turns a new look back to the
old one, the audits read the map at pair 86 (no shared look, every look moves while it stands or walks in place, none crowded), the step
runs right after monsterdrivelooks. No base server needed."""
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
import install_monster_relook_looks as M  # noqa: E402
import gen_bounty_pool as G  # noqa: E402
import audit_shared_looks as S  # noqa: E402
import audit_idle_looks as I  # noqa: E402
import gen_relook_monsters as P  # noqa: E402

TOOL = os.path.join(HERE, 'install_monster_relook_looks.py')
TMP = tempfile.mkdtemp(prefix='relooklooks_')
failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def run(*args):
    p = subprocess.run([sys.executable, '-I', TOOL] + list(args), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return p.returncode, p.stdout


def xml(name, look):
    return '<?xml version="1.0"?>\n<monster name="%s" nameDescription="a %s" race="blood" experience="5" speed="100">\n' \
           '\t<health now="100" max="100"/>\n\t<look type="%d" head="10" body="20" corpse="6068"/>\n</monster>\n' % (name, name, look)


def lua(name, look):
    return 'local mType = Game.createMonsterType("%s")\nlocal monster = {}\nmonster.description = "a %s"\n' \
           'monster.outfit = {\n\tlookType = %d,\n\tlookHead = 10,\n\tlookAddons = 0,\n}\nmonster.health = 100\nmType:register(monster)\n' % (name, name, look)


def pool_text(rows_):
    return 'return {\n\thunt = {\n' + ''.join(
        '\t\t{name = "%s", level = 5, exp = 1, health = 9, spawns = 9, look = %d%s},\n' % r for r in rows_) + '\t},\n\tbosses = {\n\t},\n}\n'


def server(pair, base_xml, base_lua, pool=None):
    d = tempfile.mkdtemp(dir=TMP)
    if pair is not None:
        open(os.path.join(d, 'config.lua'), 'w').write('chaosClientPair = %d\n' % pair)
    mon = os.path.join(d, 'data', 'monster')
    for sub, items, make in (('monsters/misc', base_xml, xml), ('lua/lions', base_lua, lua)):
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


# ---- the shipped map: the owner's five picks
rows = M.read_map()
check([r[0] for r in rows] == ['Banshee', 'Werelion', 'Leaf Golem', 'White Lion', 'Hellhound'], 'the five monsters of the owner, in order')
check([r[2] for r in rows] == [3744, 3745, 3746, 1041, 3280], 'the new looks: outfits 3744-3746, stock 1041 and 3280')
check(C.PAIR_RELOOK_MONSTERS == 86 and P.PAIR == 86 and P.FIRST_NEW == 3744, 'the step needs pair 86, whose new outfits start at 3744')
check([int(r['new']) for r in P.rows()] == [r[2] for r in rows[:3]], 'the outfits are the table rows of gen_relook_monsters.py')
pool_rows = {r['name']: r for r in S.pool_rows()}
lv = P.D.P.pool_levels()
for name, old, new in rows:
    check(name in pool_rows and pool_rows[name]['look'] == old, '%s: a hunt monster of the pool on look %d' % (name, old))
    check(name in lv, '%s: on the hunt list of the pool (no boss)' % name)
earlier = M.earlier_looks()
check(earlier.get('Banshee') == {3408} and earlier.get('White Lion') == {3414} and earlier.get('Hellhound') == {3441}
      and earlier.get('Werelion') == {3444} and earlier.get('Leaf Golem') == {3472}, 'the looks of today: donor and purchased (%s)' % earlier)

# ---- the audits read the map: the earlier look below pair 86, the new one from it
rc_ = S.load_recolour()
for name, old, new in rows:
    at = S.look_at_pair(name, old, 85, rc_)
    check(at in earlier[name] and S.look_at_pair(name, old, 86, rc_) == new and S.look_at_pair(name, at, 86, rc_) == new,
          'audit_shared_looks: %s wears %d at pair 85 and %d at pair 86' % (name, at, new))
    check(S.look_at_pair(name, new, 85, rc_) == at or new == old, 'a file written for pair 86 reads as the pair 85 look for pair 85 (%s)' % name)
for pair in (85, C.PAIR_RELOOK_MONSTERS):
    check(S.check_pool(pair=pair) == [], 'no shared look at pair %d: %s' % (pair, S.check_pool(pair=pair)))
    check(I.check_pool(pair=pair) == [], 'every hunt monster moves while it stands at pair %d: %s' % (pair, I.check_pool(pair=pair)))
    check(I.check_crowded(pair=pair) == [], 'no crowded look at pair %d' % pair)
idle = I.load_idle()
for n in (3744, 3745, 3746):
    check(idle.get(n, (False,))[0] and idle[n][1] == 4, 'look_idle.csv: %d has an idle group of 4 that moves' % n)
walk = I.load_walklist()
check(1041 in walk and 3280 in walk, 'the stock looks 1041 and 3280 walk in place while they stand (game_bossanimate, O534)')
at86 = {r['name']: r['look'] for r in I.donor_rows(S.pool_rows(), C.PAIR_RELOOK_MONSTERS)[0]}
at85 = {r['name']: r['look'] for r in I.donor_rows(S.pool_rows(), 85)[0]}
check({n for n in at86 if at86[n] != at85[n]} == {r[0] for r in rows} and all(at86[n] == new for n, _o, new in rows),
      'the pool reads the same at pair 85 and 86 but for the five monsters')
worn = {}
for n, lk in at86.items():
    worn.setdefault(lk, []).append(n)
check(all(worn[new] == [name] for name, _o, new in rows), 'every new look is worn by its monster alone at pair 86')

# ---- the guard and the step end to end (synthetic server: base XML and Lua monsters on today's looks, the committed look, another)
BX = [('Banshee', 3408), ('Hellhound', 3441), ('Leaf Golem', 567), ('Wilting Leaf Golem', 3473)]
BL = [('White Lion', 3414), ('Werelion', 3444), ('Werelioness', 3446)]
ptext = pool_text([('Banshee', 3408, ''), ('White Lion', 3414, ''), ('Werelion', 3444, ', head = 58, body = 2'), ('Werelioness', 3446, ''),
                   ('Leaf Golem', 567, ''), ('Hellhound', 3441, '')])
for pair in (None, 81, 85):
    d = server(pair, BX, BL, ptext)
    before = snapshot(d)
    rc, out = run(os.path.join(d, 'data'))
    check(rc == 0 and 'WARNING: monsterrelooklooks skipped' in out and 'client pair 86' in out and snapshot(d) == before,
          'pair %s: warning, exit 0, nothing written' % pair)
d = server(86, BX, BL, ptext)
before = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--dry-run')
check(rc == 0 and 'dry run' in out and snapshot(d) == before, 'pair 86 --dry-run writes nothing')
rc, out = run(os.path.join(d, 'data'))
check(rc == 0 and '5 moved to their new look' in out and '5 rows moved' in out, 'pair 86: five files and five pool rows move (%s)' % out.strip())
mon = os.path.join(d, 'data', 'monster')
check(looks(mon) == {'Banshee': 3744, 'Werelion': 3745, 'Leaf Golem': 3746, 'White Lion': 1041, 'Hellhound': 3280,
                     'Wilting Leaf Golem': 3473, 'Werelioness': 3446}, 'the monsters wear their new looks, the others keep theirs: %s' % looks(mon))
check('head="10"' in open(os.path.join(mon, 'monsters', 'misc', 'banshee.xml')).read(), 'a base XML keeps its colour fields')
got = open(os.path.join(d, 'data', 'scripts', 'chaos', 'bounty_pool.lua')).read()
check('look = 3745, head = 58' in got and 'look = 1041}' in got and 'look = 3280}' in got and re.search(r'"Werelioness".*look = 3446\}', got),
      'the pool rows follow')
after = snapshot(d)
rc, out = run(os.path.join(d, 'data'))
check(rc == 0 and '0 moved to their new look, 5 already there' in out and snapshot(d) == after, 'a second run changes nothing')
rc, out = run(os.path.join(server(90, BX, BL, ptext), 'data'))
check(rc == 0 and '5 moved' in out, 'pair 90 installs')
d3 = server(86, [('Banshee', 777)] + BX[1:], BL, ptext)
b3 = snapshot(d3)
rc, out = run(os.path.join(d3, 'data'))
check(rc == 1 and 'ERROR Banshee' in out and 'has look 777' in out and snapshot(d3) == b3, 'a look that is none of the known ones stops the step')
rc, out = run(os.path.join(server(86, BX, [], ptext), 'data'))
check(rc == 1 and 'ERROR White Lion: no monster file' in out, 'a missing monster file stops the step')
rc, out = run(os.path.join(server(86, BX, BL, None), 'data'))
check(rc == 0 and 'bounty_pool.lua: not installed' in out and '5 moved' in out, 'no installed pool: skipped, the files move')

# ---- the pool generator gives the committed pool back from a server that wears the new looks
for name, old, new in rows:
    check(G.committed_look(name, new) == old and G.committed_look(name, old) == old, 'gen_bounty_pool: %s turns back from %d to %d' % (name, new, old))
check(G.committed_look('Werelioness', 3745) == 3745, 'gen_bounty_pool: another monster is untouched')

# ---- the install step is wired after the Drive looks
import install_all as A  # noqa: E402
check(A.STEPS.index('monsterrelooklooks') == A.STEPS.index('monsterdrivelooks') + 1, 'install_all: the step runs right after monsterdrivelooks')
check(callable(getattr(A, 'step_monsterrelooklooks', None)), 'the step function exists')

shutil.rmtree(TMP, ignore_errors=True)
print('install_monster_relook_looks_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
