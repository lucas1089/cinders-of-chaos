#!/usr/bin/env python3
"""Test of patch_monster_flat_defence.py (O505) on synthetic monster files: the engine's mean bite, the cap by level (normal and boss),
XML and Lua files, the level of a monster (own level range, bounty pool, estimate from experience and health), boss flags, values at or
below the cap left alone, pets and test dummies skipped, --check, --dry-run, idempotence, and a later lower cap still applies.

usage: python3 -I server/tools/patch_monster_flat_defence_test.py
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_monster_flat_defence as P  # noqa: E402

TOOL = os.path.join(HERE, 'patch_monster_flat_defence.py')
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


def eq(a, b, what):
    check(a == b, '%s: %r != %r' % (what, a, b))


# a synthetic config: the median roll is 20 at level 1, 100 at level 100, 1000 at level 1000 (a straight line in log level and log roll
# between the rows), 10% normal and 20% boss
CONFIG = '''return {
	flatShare = {normal = 10, boss = 20},
	flatRollCurve = {
		{level = 1, hit = 20},
		{level = 100, hit = 100},
		{level = 1000, hit = 1000}
	},
}
'''
POOL = '''return {
	hunt = {
		{name = "Troll", level = 7, exp = 20, health = 50, spawns = 684, look = 15},
		{name = "Wyrm", level = 100, exp = 1600, health = 1800, spawns = 12, look = 291},
		{name = "Hornet", level = 58, exp = 1296, health = 2000, spawns = 12, look = 1},
	},
	bosses = {
		{name = "Warlord", level = 100, exp = 5000, health = 9000, spawns = 1, look = 2},
	}
}
'''


def xml(name, armor, defense, level=None, exp=10, hp=100, boss=False, attrs='armor="%d" defense="%d"'):
    return ('<?xml version="1.0"?>\n<monster name="%s" nameDescription="a thing" race="blood" experience="%d" speed="100">\n'
            '\t<health now="%d" max="%d"/>\n%s\t<flags>\n%s\t</flags>\n\t<defenses %s>\n\t\t<defense name="healing" interval="1000"/>\n\t</defenses>\n'
            '</monster>\n' % (name, exp, hp, hp, ('\t<level min="%d" max="%d"/>\n' % level) if level else '',
                             '\t\t<flag isboss="1"/>\n' if boss else '', attrs % (armor, defense)))


def lua(name, armor, defense, exp=10, hp=100, extra=''):
    return ('local mType = Game.createMonsterType("%s")\nlocal monster = {}\nmonster.experience = %d\nmonster.health = %d\nmonster.maxHealth = %d\n%s'
            'monster.defenses = {\n\tdefense = %d,\n\tarmor = %d\n}\n\nmonster.elements = {\n}\n' % (name, exp, hp, hp, extra, defense, armor))


def num(text, attr):
    import re
    m = re.search(r'\b%s\s*=\s*"?(\d+)' % attr, text)
    return int(m.group(1)) if m else None


tmp =tempfile.mkdtemp(prefix='flatdef')
data = os.path.join(tmp, 'data')
os.makedirs(os.path.join(data, 'scripts', 'chaos'))
open(os.path.join(data, 'scripts', 'chaos', 'monster_defence_config.lua'), 'w').write(CONFIG)
open(os.path.join(data, 'scripts', 'chaos', 'bounty_pool.lua'), 'w').write(POOL)
cfg = P.read_config(os.path.join(data, 'scripts', 'chaos', 'monster_defence_config.lua'))
pool = P.Pool(os.path.join(data, 'scripts', 'chaos', 'bounty_pool.lua'))

# ---- the engine's mean bite and the cap -----------------------------------------------------------------------------------------
eq(P.armour_bite(0), 0.0, 'armour 0 takes nothing')
eq((P.armour_bite(1), P.armour_bite(3)), (1.0, 1.0), 'armour 1 to 3 takes 1')
eq(P.armour_bite(4), 2.5, 'armour 4 is uniform 2..3')
eq(P.armour_bite(30), (15 + 29) / 2.0, 'armour 30 is uniform 15..29')
eq(P.defence_bite(30), 22.5, 'defense 30 is uniform 15..30')
eq(P.defence_bite(1), 0.5, 'defense 1 is uniform 0..1')
check(abs(P.hit_at(cfg['roll'], 100) - 100) < 1e-9, 'the roll curve passes its rows')
check(abs(P.hit_at(cfg['roll'], 1) - 20) < 1e-9 and abs(P.hit_at(cfg['roll'], 1000) - 1000) < 1e-9, 'the roll curve passes the first and last rows')
check(abs(P.hit_at(cfg['roll'], 5000) - 5000) < 1e-6, 'beyond the last row the slope of the last two rows goes on (the rows are a straight line of slope 1 there)')
# level 100: 10 percent of a roll of 100 is 10
for c in range(1, 40):
    b = P.armour_bite(c) + P.defence_bite(c)
    check(b >= P.armour_bite(c - 1) + P.defence_bite(c - 1), 'the bite grows with the value (%d)' % c)
c100 = P.cap_for(100, False, cfg)
check(P.armour_bite(c100) + P.defence_bite(c100) <= 10.0 < P.armour_bite(c100 + 1) + P.defence_bite(c100 + 1), 'level 100: the cap is the largest value with a bite of at most 10 percent of the roll (%d)' % c100)
c100b = P.cap_for(100, True, cfg)
check(P.armour_bite(c100b) + P.defence_bite(c100b) <= 20.0 < P.armour_bite(c100b + 1) + P.defence_bite(c100b + 1), 'level 100 boss: 20 percent (%d)' % c100b)
check(c100b > c100 >= 5, 'a boss keeps more than a normal monster (%d, %d)' % (c100b, c100))
check(P.cap_for(1, False, cfg) == 1 and P.cap_for(1, True, cfg) == 3, 'level 1: normal cap 1 (bite 1.5 of 2), boss cap 3 (bite 3 of 4)')
check(P.cap_for(500, False, cfg) > P.cap_for(100, False, cfg) > P.cap_for(10, False, cfg), 'the cap grows with the level')
check(P.cap_for(0, False, cfg) == P.cap_for(1, False, cfg), 'level 0 is read as level 1')

# ---- the level of a monster -------------------------------------------------------------------------------------------------------
eq(P.estimate_level(20, 50), 7, 'estimate: experience 20, health 50 -> 7 (the pool row of a Troll)')
eq(P.estimate_level(0, 0), 2, "estimate: a monster without experience is level 2 (1.6 x sqrt 1)")
eq(pool.level_of({'name': 'troll', 'boss': False, 'own': 0, 'exp': 1, 'hp': 1}), (7, False), 'the pool level wins, names are case blind')
eq(pool.level_of({'name': 'Warlord', 'boss': False, 'own': 0, 'exp': 1, 'hp': 1}), (100, True), 'a monster of the bosses list is a boss')
eq(pool.level_of({'name': 'Wyrm', 'boss': False, 'own': 500, 'exp': 1600, 'hp': 1800}), (500, False), 'a real level range beats the pool')
eq(pool.level_of({'name': 'Hornet', 'boss': False, 'own': 5, 'exp': 1296, 'hp': 5400}), (58, False), 'a stock range 1 to 10 of a type that is not level scaled (pool level = the estimate) is ignored')
eq(pool.level_of({'name': 'Unknown', 'boss': False, 'own': 0, 'exp': 20, 'hp': 50}), (7, False), 'no pool row: the estimate')
eq(pool.level_of({'name': 'Unknown', 'boss': True, 'own': 300, 'exp': 20, 'hp': 50}), (300, True), 'no pool row: the own level, the file flag')

# ---- an XML file ------------------------------------------------------------------------------------------------------------------
t = xml('Troll', 10, 10)                                  # level 7 by the pool: normal cap
new, counts, notes = P.xml(t, pool, cfg)
c7 = P.cap_for(7, False, cfg)
eq((num(new, 'armor'), num(new, 'defense')), (c7, c7), 'XML: a level 7 monster with 10 / 10 is capped to the cap of level 7 (%d)' % c7)
eq((counts['files'], counts['armor'], counts['defense'], counts['left']), (1, 1, 1, 0), 'XML: counts')
check(len(notes) == 2 and 'armor 10 -> %d' % c7 in notes[0], 'XML: one note per value')
eq(new.replace('armor="%d" defense="%d"' % (c7, c7), 'armor="10" defense="10"'), t, 'XML: only the two numbers changed')
new2, counts2, _ = P.xml(new, pool, cfg)
eq(new2, new, 'XML: a second pass changes nothing')
eq((counts2['files'], counts2['left']), (0, 1), 'XML: the second pass leaves it alone')
t = xml('Troll', c7, 0)
eq(P.xml(t, pool, cfg)[0], t, 'XML: values at or below the cap stay (and a lower one is never raised)')
t = xml('Troll', 1, 3)
eq(P.xml(t, pool, cfg)[0], t, 'XML: 1 / 3 stays at level 7')
t = xml('Troll', 50, 2)
new = P.xml(t, pool, cfg)[0]
eq((num(new, 'armor'), num(new, 'defense')), (c7, 2), 'XML: only the value over the cap is lowered')
t = xml('Troll', 40, 40, attrs='defense="%d" armor="%d"')   # the attributes in the other order: defense = 40, armor = 40
new = P.xml(t, pool, cfg)[0]
eq((num(new, 'armor'), num(new, 'defense')), (c7, c7), 'XML: attribute order does not matter')
t = xml('Wyrm', 120, 90)
new = P.xml(t, pool, cfg)[0]
eq((num(new, 'armor'), num(new, 'defense')), (c100, c100), 'XML: a level 100 pool monster takes the cap of level 100 (%d)' % c100)
t = xml('Wyrm', 120, 90, boss=True)
new = P.xml(t, pool, cfg)[0]
eq((num(new, 'armor'), num(new, 'defense')), (c100b, c100b), 'XML: a monster with the isboss flag takes the boss cap (%d)' % c100b)
t = xml('Warlord', 120, 90)
eq(num(P.xml(t, pool, cfg)[0], 'armor'), c100b, 'XML: a monster of the pool bosses list takes the boss cap')
t = xml('Scaled', 500, 500, level=(900, 1000))
new = P.xml(t, pool, cfg)[0]
c950 = P.cap_for(950, False, cfg)
eq(num(new, 'armor'), c950, 'XML: a level scaled monster uses the middle of its <level> range (950): cap %d' % c950)
t = xml('Mystery', 200, 200, exp=1600, hp=1800)
eq(num(P.xml(t, pool, cfg)[0], 'armor'), P.cap_for(P.estimate_level(1600, 1800), False, cfg), 'XML: a monster the pool does not know uses the estimate')
t = '<monster name="Plain" experience="1"><health now="1" max="1"/><defenses>\n</defenses></monster>\n'
eq(P.xml(t, pool, cfg)[0], t, 'XML: <defenses> without numbers is left alone')
t = '<monster name="NoDef" experience="1"><health now="1" max="1"/></monster>\n'
eq(P.xml(t, pool, cfg)[2], [], 'XML: no <defenses> at all is left alone')
# a comment that looks like a flag does not make a boss
t = xml('Troll', 40, 40).replace('<flags>', '<!-- <flag isboss="1"/> -->\n\t<flags>')
eq(num(P.xml(t, pool, cfg)[0], 'armor'), c7, 'XML: a boss flag inside a comment is no boss flag')

# ---- a Lua file -------------------------------------------------------------------------------------------------------------------
t = lua('Wyrm', 82, 40)
new, counts, notes = P.lua(t, pool, cfg)
eq((num(new, 'armor'), num(new, 'defense')), (c100, c100), 'Lua: armor 82 and defense 40 at level 100 are capped (%d)' % c100)
eq((counts['files'], counts['armor'], counts['defense']), (1, 1, 1), 'Lua: counts')
eq(new.replace('defense = %d,\n\tarmor = %d' % (c100, c100), 'defense = 40,\n\tarmor = 82'), t, 'Lua: only the two numbers changed')
eq(P.lua(new, pool, cfg)[0], new, 'Lua: a second pass changes nothing')
t = lua('Wyrm', 3, 2)
eq(P.lua(t, pool, cfg)[0], t, 'Lua: values under the cap stay')
t = lua('Wyrm', 82, 40).replace('\tdefense = 40,\n\tarmor = 82', '\tarmor = 82,\n\tdefense = 40')
new = P.lua(t, pool, cfg)[0]
eq((num(new, 'armor'), num(new, 'defense')), (c100, c100), 'Lua: armor before defense')
t = lua('Warlord', 120, 120, extra='monster.flags = {\n\trewardBoss = true\n}\n')
eq(num(P.lua(t, pool, cfg)[0], 'armor'), c100b, 'Lua: a monster of the pool bosses list takes the boss cap')
t = lua('Nobody', 90, 90, extra='monster.flags = {\n\trewardBoss = true\n}\n')
eq(num(P.lua(t, pool, cfg)[0], 'armor'), P.cap_for(P.estimate_level(10, 100), True, cfg), 'Lua: rewardBoss = true is a boss flag')
t = lua('Wyrm', 82, 40, extra='-- isBoss = true\n')
eq(num(P.lua(t, pool, cfg)[0], 'armor'), c100, 'Lua: a boss flag in a comment is none')
t = 'local monster = {}\nmonster.health = 1\n'
eq(P.lua(t, pool, cfg)[2], [], 'Lua: no monster.defenses is left alone')

# ---- a server data folder: the tool, --check, --dry-run, idempotence, a later lower cap --------------------------------------------
mon = os.path.join(data, 'monster', 'monsters')
os.makedirs(os.path.join(mon, 'pets'))
os.makedirs(os.path.join(mon, 'zo'))
os.makedirs(os.path.join(data, 'monster', 'lua', 'a'))
FILES = {
    'monsters/troll.xml': xml('Troll', 10, 10),
    'monsters/wyrm.xml': xml('Wyrm', 120, 90),
    'monsters/small.xml': xml('Troll', 1, 1),
    'monsters/pets/wolf.xml': xml('Wolf Pet', 90, 90),
    'monsters/zo/dummy.xml': xml('Zo N100', 90, 90),
    'lua/a/boss.lua': lua('Warlord', 120, 100),
}
for rel, text in FILES.items():
    open(os.path.join(data, 'monster', rel), 'w').write(text)
open(os.path.join(data, 'monster', 'monsters.xml'), 'w').write('<monsters><monster name="Troll" file="monsters/troll.xml"/></monsters>\n')


def snapshot():
    return {rel: open(os.path.join(data, 'monster', rel)).read() for rel in FILES}


def run(*args):
    r = subprocess.run([sys.executable, '-I', TOOL, data] + list(args), capture_output=True, text=True)
    return r.returncode, r.stdout


before = snapshot()
rc, out = run('--check')
eq(rc, 1, '--check exits 1 while a file is not up to date')
check('troll.xml' in out and 'wyrm.xml' in out and 'boss.lua' in out, '--check names the files to change')
check('small.xml' not in out and 'wolf.xml' not in out and 'dummy.xml' not in out, '--check leaves the capped, pet and dummy files out')
eq(snapshot(), before, '--check changes nothing')
rc, out = run('--dry-run')
eq(rc, 0, '--dry-run exits 0')
check('would change' in out and '3 file(s) to change' in out, '--dry-run says what it would change: ' + out.splitlines()[-1])
eq(snapshot(), before, '--dry-run changes nothing')
rc, out = run('--quiet')
eq(rc, 0, 'a run exits 0')
check(out.strip().endswith('3 file(s) changed; armor lowered 3, defense lowered 3, left alone 1'), 'the report line counts files, values and files left alone: ' + out.strip())
after = snapshot()
eq(after['monsters/pets/wolf.xml'], before['monsters/pets/wolf.xml'], 'a pet is left alone')
eq(after['monsters/zo/dummy.xml'], before['monsters/zo/dummy.xml'], 'a test dummy is left alone')
eq(after['monsters/small.xml'], before['monsters/small.xml'], 'a file under the cap is left alone')
eq(num(after['monsters/troll.xml'], 'armor'), c7, 'the Troll is capped on disk')
eq(num(after['lua/a/boss.lua'], 'armor'), c100b, 'the Lua boss is capped on disk with the boss cap')
rc, out = run('--check')
eq(rc, 0, '--check exits 0 when everything is done')
rc, out = run('--quiet')
check(out.strip().endswith('0 file(s) changed; armor lowered 0, defense lowered 0, left alone 4'), 'a second run changes nothing: ' + out.strip())
eq(snapshot(), after, 'a second run leaves every file as it was')
# a later, lower share still applies
lower = CONFIG.replace('normal = 10', 'normal = 5')
open(os.path.join(data, 'scripts', 'chaos', 'monster_defence_config.lua'), 'w').write(lower)
rc, out = run('--quiet')
eq(rc, 0, 'a run with a lower share exits 0')
check(num(open(os.path.join(data, 'monster', 'monsters/wyrm.xml')).read(), 'armor') < c100, 'a lower share lowers the cap again: the Wyrm goes under %d' % c100)
for rel in ('monsters/pets/wolf.xml', 'monsters/zo/dummy.xml'):
    eq(open(os.path.join(data, 'monster', rel)).read(), before[rel], 'still left alone: ' + rel)
rc, out = run('--quiet')
check(out.strip().startswith('monster flat defence: 0 file(s) changed'), 'and a run after that changes nothing')
# the usage text without a data folder
r = subprocess.run([sys.executable, '-I', TOOL], capture_output=True, text=True)
eq(r.returncode, 2, 'no data folder: exit 2')
# the repository's own numbers are the shipped config: the tool reads them without a server folder around
repo_cfg = P.read_config()
eq(repo_cfg['share'], {'normal': 10.0, 'boss': 20.0}, 'the shipped config has the 10 / 20 share')
check(len(repo_cfg['roll']) == 13 and P.cap_for(20, False, repo_cfg) == 2 and P.cap_for(100, False, repo_cfg) == 8, 'the shipped config gives the cap 2 at level 20 and 8 at 100')

if fails:
    print('%d failed' % fails)
    sys.exit(1)
print('monster flat defence tests: ok')
