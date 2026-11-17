#!/usr/bin/env python3
"""python3 -I server/tools/install_monster_swap_looks_test.py : install_monster_swap_looks.py (O619; install step `monsterswaplooks`) and the
mount swap of install_outfits.py on the shipped tables and on a synthetic server folder: the map (23 monsters, none in the donor, the
purchased or the creature map, the old looks are the files' and the pool's, a new look is worn by at most 2 monsters and by no other), the
facts file (every old look fails the stock bar of the O610 audit, every new look passes it, the same rules applied to the numbers), the
audits read the map at pair 73 (no shared look, every hunt monster moves while it stands, none crowded), the client pair guard end to end
(pair 72 or missing: nothing written and a WARNING line; pair 73: our XML, a base XML, a base Lua monster, the pool rows and the quest and
trial tables move, colours stay), a monster of the recolour map moves on from its copy, idempotent, a file with another look stops the
step, --dry-run writes nothing, gen_bounty_pool.py turns a new look back to the old one, the step is wired after the creature looks,
the five mounts wear looks that pass the bar and no monster wears. No base server needed."""
import csv
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import audit_idle_looks as I  # noqa: E402
import audit_shared_looks as S  # noqa: E402
import client_pair as C  # noqa: E402
import gen_bounty_pool as G  # noqa: E402
import install_monster_recolour as R  # noqa: E402
import install_monster_swap_looks as M  # noqa: E402
import install_outfits as O  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(HERE, 'install_monster_swap_looks.py')
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


QUEST = 'return {\n\tdefault = {name = "Warden", look = {lookType = 100},\n\t\tadd = {name = "Bones", look = {lookType = 200}}},\n' \
        '\t[17] = {name = "Still", look = {lookType = 57},\n\t\tadd = {name = "Acolyte", look = {lookType = 57}}},\n}\n'
TRIALS = 'return {\n\tadd = {name = "Tithed Dead", look = {lookType = 200}},\n\tboss = {name = "Tithe", look = {lookType = 99}},\n}\n'


def server(pair, ours, base_xml, base_lua, pool=None, configs=True):
    d = tempfile.mkdtemp(prefix='swaplooks_')
    if pair is not None:
        open(os.path.join(d, 'config.lua'), 'w').write('chaosClientPair = %d\n' % pair)
    mon = os.path.join(d, 'data', 'monster')
    for sub, items, make in (('monsters/chaos/pack30', ours, xml), ('monsters/dragons', base_xml, xml), ('lua/misc', base_lua, lua)):
        os.makedirs(os.path.join(mon, sub))
        for name, look in items:
            open(os.path.join(mon, sub, name.lower().replace(' ', '_') + ('.xml' if make is xml else '.lua')), 'w').write(make(name, look))
    sc = os.path.join(d, 'data', 'scripts', 'chaos')
    os.makedirs(sc)
    if pool is not None:
        open(os.path.join(sc, 'bounty_pool.lua'), 'w').write(pool)
    if configs:
        open(os.path.join(sc, 'ascension_quest_config.lua'), 'w').write(QUEST)
        open(os.path.join(sc, 'trials_config.lua'), 'w').write(TRIALS)
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
names = [r[0] for r in rows]
check(len(rows) == 23 and len(set(names)) == 23, 'the map has 23 monsters, once each (%d)' % len(rows))
check(C.PAIR_SWAP == 73 and C.PAIR_SWAP > C.PAIR_FUN and C.PAIR_ASSETS < C.PAIR_SWAP, 'the step needs pair 73, which is not on windows-assets')
pool = G.read(G.DEFAULT_OUT)
pool_old = {r['name']: r['look'] for r in S.pool_rows()}
chaos = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos')
files = R.monster_files(chaos)
for name, old, new in rows:
    check(name in files, '%s is a monster of ours' % name)
    if name in files:
        check(R.LOOK_TAG.search(open(files[name], encoding='utf-8').read()).group(2) == str(old), '%s: the repository file keeps look %d' % (name, old))
    if name in pool_old:
        check(pool_old[name] == old, '%s: the committed pool has look %d' % (name, old))
    check(old != new, '%s: the look changes' % name)
for other in (S.load_donor(), S.load_purchased(), S.load_creature()):
    check(not set(names) & set(other), 'no monster of the donor, the purchased or the creature map')
check(sorted(n for n in names if n in S.load_recolour()) == ['Gildguard Revenant', 'Ironmask Taskmaster', 'Pyre Stork', 'Rimecairn',
                                                          'Rootbound Pilgrim', 'Thornveil Wraith'], 'six monsters of the recolour map leave their copy')
count = {}
for name, _old, new in rows:
    count[new] = count.get(new, 0) + 1
check(max(count.values()) <= 2 and sorted(k for k, v in count.items() if v == 2) == [2991, 3297], 'a new look is on one monster, two on 2991 (the wardens) and 3297 (the ice dragons)')
bosses = {'Kaelgor the Infernal Warlord', 'Vharok the Blood Colossus', 'Nyxareth the Void Archon'}
check(bosses <= set(names), 'three donor B world bosses are in (Skaldra keeps 1534: owner, 2026-11-17)')
check(not set(names) & {'The Rotmother', 'Vhoss the Hexmaw', 'Talath'}, 'the three creature pack bosses (O616) are not')
new_looks = {r[2] for r in rows}
earlier = ({n for _o, n in S.load_recolour().values()} | {n for _o, n in S.load_donor().values()} | {n for _o, n in S.load_purchased().values()}
           | {n for _o, n in S.load_creature().values()})
check(not new_looks & earlier, 'no new look is a look an earlier step gives')
player = {int(r[0]) for r in csv.reader(open(os.path.join(REPO, 'server', 'data', 'monster', 'player_looks.csv'), encoding='utf-8')) if r[0].isdigit()}
check(not new_looks & player, 'no new look is a look a player wears')

# ---- the facts: the old looks fail the bar, the new ones pass it, by the same rules
facts = M.read_facts()
check({l for l, r in facts.items() if r['role'] == 'old'} == {r[1] for r in rows}, 'facts: every old look is measured')
check({l for l, r in facts.items() if r['role'] == 'new'} == new_looks, 'facts: every new look is measured')
for look, r in sorted(facts.items()):
    problems = M.bar_problems(r)
    if r['role'] in ('new', 'mount'):
        check(not problems and not r['reasons'] and r['layers'] == '1', 'look %d (%s) passes the bar (%s)' % (look, r['role'], problems))
    else:
        check(problems and r['reasons'], 'look %d (%s) fails the bar' % (look, r['role']))
check(M.bar_problems({'dirs': '4', 'east_mirror': '1.0', 'lean': '0', 'soft_alpha': '0', 'rim_dark': '1', 'walk_pictures': '8', 'layers': '1'}) != [],
      'bar: an east that is a mirrored west fails')
check(M.bar_problems({'dirs': '4', 'east_mirror': '0.7', 'lean': '14', 'soft_alpha': '0', 'rim_dark': '1', 'walk_pictures': '8', 'layers': '1'}) == [],
      'bar: a stock lean passes')
check(len(M.bar_problems({'dirs': '1', 'east_mirror': '0.2', 'lean': '14', 'soft_alpha': '0.3', 'rim_dark': '0.1', 'walk_pictures': '2', 'layers': '2'})) == 5,
      'bar: five other reasons')

# ---- the audits read the map: the old look below pair 73 (the copy from 69), the new one from it
rc_ = S.load_recolour()
check(S.look_at_pair('Golden Dragon', 1530, 72, rc_) == 1530 and S.look_at_pair('Golden Dragon', 1530, 73, rc_) == 3315, 'Golden Dragon wears 1530 at 72 and 3315 at 73')
check([S.look_at_pair('Gildguard Revenant', 1530, p, rc_) for p in (68, 69, 72, 73)] == [1530, rc_['Gildguard Revenant'][1], rc_['Gildguard Revenant'][1], 3309],
      'Gildguard Revenant: its copy from 69, the new look from 73')
check(S.look_at_pair('Golden Dragon', 3315, 68, rc_) == 1530, 'a file written for pair 73 reads as the old look for pair 68')
for p in (68, 69, 70, 71, 72, 73):
    check(S.check_pool(pair=p) == [], 'no shared look at pair %d: %s' % (p, S.check_pool(pair=p)))
    check(I.check_pool(pair=p) == [], 'every hunt monster moves while it stands at pair %d: %s' % (p, I.check_pool(pair=p)))
    check(I.check_crowded(pair=p) == [], 'no crowded look at pair %d' % p)
idle, walk, walked = I.load_idle(), I.load_walk(), I.load_walklist()
for new in sorted(new_looks):
    check(new in idle and (idle[new][0] or new in walked), 'look %d moves while it stands (idle group or the walk in place list)' % new)
check(I.check_walk() == [], 'the walk in place list is up to date')
check(not (walked & player), 'no player look walks in place')
check(any(r['look'] != o for r, o in zip(I.donor_rows(S.pool_rows(), C.PAIR_SWAP)[0], S.pool_rows())), 'the pool reads other looks at pair 73')
_sw = S.load_swap()
check([r['look'] for r in I.donor_rows(S.pool_rows(), C.PAIR_FUN)[0] if r['name'] in _sw] == [r['look'] for r in S.pool_rows() if r['name'] in _sw],
      'and the committed ones below it')

# ---- the guard and the step end to end (synthetic server: our files, a base XML, a base Lua monster, a boss with no pool row, the tables)
mp = os.path.join(tempfile.mkdtemp(prefix='swaplooks_map_'), 'map.csv')
open(mp, 'w').write('monster,look,new_look\nAlpha,100,3001\nBravo,100,3002\nCharlie,200,3003\nEcho,300,3004\nBoss,400,3005\nWarden,100,3006\n')
OURS, BX, BL = [('Alpha', 100), ('Zulu', 100), ('Echo', 300), ('Boss', 400), ('Warden', 100)], [('Bravo', 100), ('Delta', 100)], [('Charlie', 200)]
ptext = pool_text([('Alpha', 100, ''), ('Bravo', 100, ', head = 3'), ('Charlie', 200, ''), ('Delta', 100, ''), ('Echo', 300, '')])
for pair in (None, 54, 72):
    d = server(pair, OURS, BX, BL, ptext)
    before = snapshot(d)
    rc, out = run(os.path.join(d, 'data'), '--map', mp)
    check(rc == 0 and 'WARNING: monsterswaplooks skipped' in out and 'client pair 73' in out and snapshot(d) == before, 'pair %s: warning, exit 0, nothing written' % pair)
d = server(73, OURS, BX, BL, ptext)
before = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp, '--dry-run')
check(rc == 0 and 'dry run' in out and snapshot(d) == before, 'pair 73 --dry-run writes nothing')
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '6 moved to their new look' in out and '4 rows moved' in out, 'pair 73: six files and four pool rows move (%s)' % out.strip())
mon = os.path.join(d, 'data', 'monster')
check(looks(mon) == {'Alpha': 3001, 'Bravo': 3002, 'Charlie': 3003, 'Echo': 3004, 'Boss': 3005, 'Warden': 3006, 'Zulu': 100, 'Delta': 100},
      'the monsters wear their new looks (the others keep theirs): %s' % looks(mon))
check('head="10"' in open(os.path.join(mon, 'monsters', 'dragons', 'bravo.xml')).read(), 'a base XML keeps its colour fields')
got = open(os.path.join(d, 'data', 'scripts', 'chaos', 'bounty_pool.lua')).read()
check('look = 3001}' in got and 'look = 3002, head = 3' in got and 'look = 3003}' in got and re.search(r'"Delta".*look = 100\}', got), 'the pool rows follow')
# the tables: 100 has two rows (Alpha, Bravo, Warden send it to three looks): ambiguous, left alone; 200 has one (Charlie 3003), 57 and 99 are not in the map
q = open(os.path.join(d, 'data', 'scripts', 'chaos', 'ascension_quest_config.lua')).read()
t = open(os.path.join(d, 'data', 'scripts', 'chaos', 'trials_config.lua')).read()
check('look = {lookType = 100}' in q and 'look = {lookType = 3003}' in q and 'look = {lookType = 57}' in q, 'the quest table: 200 -> 3003, an ambiguous or unknown look stays')
check('look = {lookType = 3003}' in t and 'look = {lookType = 99}' in t, 'the trial table: 200 -> 3003, 99 stays')
after = snapshot(d)
rc, out = run(os.path.join(d, 'data'), '--map', mp)
check(rc == 0 and '0 moved to their new look, 6 already there' in out and snapshot(d) == after, 'a second run changes nothing')
rc, out = run(os.path.join(server(80, OURS, BX, BL, ptext), 'data'), '--map', mp)
check(rc == 0 and '6 moved' in out, 'pair 80 installs')
check(M.config_looks([('a', 1, 2), ('b', 1, 2), ('c', 3, 4), ('d', 3, 5)]) == {1: 2}, 'config_looks: a look every row sends to one new look')
check(M.retype_config('look = {lookType = 1}, look={ lookType = 9}, lookType = 1', {1: 2})[:2] == ('look = {lookType = 2}, look={ lookType = 9}, lookType = 1', 1),
      'retype_config: only the look rows of a table')

# a monster of the recolour map wears its copy at pair 69 and more: it moves on from the copy and straight from the old look
copy = rc_['Rimecairn'][1]
for start in (copy, 1531):
    dn = server(73, [('Rimecairn', start)], [], [], pool_text([('Rimecairn', start, '')]))
    rc, out = run(os.path.join(dn, 'data'))
    check(rc == 1 and 'no monster file' in out, 'the shipped map on a folder without the monsters stops')
    one = os.path.join(tempfile.mkdtemp(prefix='swaplooks_one_'), 'map.csv')
    open(one, 'w').write('monster,look,new_look\nRimecairn,1531,3039\n')
    rc, out = run(os.path.join(dn, 'data'), '--map', one)
    check(rc == 0 and '1 moved to their new look' in out and '1 rows moved' in out and looks(os.path.join(dn, 'data', 'monster')) == {'Rimecairn': 3039},
          'a monster on look %d moves to 3039 (%s)' % (start, out.strip()))
# the recolour step meets a monster that already wears the swapped look (a run of install_all after this step) and leaves it
check(R.swap_looks()['Rimecairn'] == 3039 and R.swap_looks(one) == {'Rimecairn': 3039}, 'the recolour step reads the swap map')
dr = server(69, [('Rimecairn', 3039)], [], [], pool_text([('Rimecairn', 3039, '')]), configs=False)
os.makedirs(os.path.join(dr, 'data', 'monster', 'monsters', 'chaos'), exist_ok=True)
rmap = os.path.join(tempfile.mkdtemp(prefix='swaplooks_rec_'), 'map.csv')
open(rmap, 'w').write('monster,look,new_look\nRimecairn,1531,%d\n' % copy)
rc, out = run(os.path.join(dr, 'data'), '--map', rmap, tool=RECOLOUR_TOOL)
check(rc == 0 and 'ERROR' not in out, 'the recolour step leaves a monster that wears its swapped look (%s)' % out.strip().replace('\n', ' | '))

# a file with another look, and a missing file, stop the step before anything is written
d3 = server(73, OURS, [('Bravo', 777)], BL, ptext)
b3 = snapshot(d3)
rc, out = run(os.path.join(d3, 'data'), '--map', mp)
check(rc == 1 and 'ERROR Bravo' in out and 'has look 777' in out and snapshot(d3) == b3, 'a look that is none of the known ones stops the step, nothing written')
rc, out = run(os.path.join(server(73, OURS, BX, [], ptext), 'data'), '--map', mp)
check(rc == 1 and 'ERROR Charlie: no monster file' in out, 'a missing monster file stops the step')
rc, out = run(os.path.join(server(73, OURS, BX, BL, None, configs=False), 'data'), '--map', mp)
check(rc == 0 and 'bounty_pool.lua: not installed' in out and '6 moved' in out, 'no installed pool and no tables: skipped, the files move')

# ---- the pool generator gives the committed pool back from a server that wears the swapped looks
check(G.committed_look('Golden Dragon', 3315) == 1530 and G.committed_look('Golden Dragon', 1530) == 1530 and G.committed_look('Zulu', 3315) == 3315,
      'gen_bounty_pool: a swapped look is turned back to the old one, others untouched')
check(G.committed_look('Rimecairn', 3394) == 1531 and G.committed_look('Rimecairn', 3039) == 1531, 'gen_bounty_pool: its copy and its new look both read as the committed one')

# ---- the install step is wired after the creature looks; the mounts
import install_all as A  # noqa: E402
check('monsterswaplooks' in A.STEPS and A.STEPS.index('monsterswaplooks') == A.STEPS.index('monstercreaturelooks') + 1
      and A.STEPS.index('monsterswaplooks') > A.STEPS.index('monsterrecolour'), 'install_all: the step runs right after monstercreaturelooks, past monsterrecolour')
mounts = {m[0]: m[1] for m in O.MOUNTS}
check(mounts == {141: 2999, 142: 3096, 143: 3121, 144: 3314, 145: 3207}, 'mounts 141..145 wear the five new looks (%s)' % mounts)
check(len(set(mounts.values())) == 5, 'five different looks')
check({l for l, r in facts.items() if r['role'] == 'mount'} == set(mounts.values()), 'facts: the five mount looks are measured')
check(not set(mounts.values()) & (new_looks | set(pool_old.values())), 'no monster wears a mount look')
shop = open(os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'shop_cosmetics.lua'), encoding='utf-8').read()
check('{key = "mount:141", id = 141, clientid = 2999, name = "Bone Steed"' in shop, 'the store row of the Bone Steed shows the new look')

print('install_monster_swap_looks_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
