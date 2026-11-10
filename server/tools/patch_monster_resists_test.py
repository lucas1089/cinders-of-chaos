#!/usr/bin/env python3
"""Test of patch_monster_resists.py (O462) on synthetic monster files: the caps (40 normal, 75 boss), immunities, the
flat 30 on seven types, weaknesses, Lua files, pets and invulnerable monsters, --check, --dry-run, idempotence.

usage: python3 -I server/tools/patch_monster_resists_test.py
"""
import hashlib
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_monster_resists as P  # noqa: E402

TOOL = os.path.join(HERE, 'patch_monster_resists.py')
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


def eq(a, b, what):
    check(a == b, '%s: %r != %r' % (what, a, b))


def pct(text, attr):
    import re
    m = re.search(r'%s\s*=\s*"(-?\d+)"' % attr, text)
    return int(m.group(1)) if m else None


def monster(name, elements='', immunities='', flags='', attackable=True):
    return ('<?xml version="1.0"?>\n<monster name="%s" nameDescription="a thing" race="blood" experience="10" speed="100">\n'
            '\t<health now="100" max="100"/>\n\t<flags>\n\t\t<flag attackable="%d"/>\n%s\t</flags>\n%s%s\t<loot>\n\t</loot>\n</monster>\n'
            % (name, 1 if attackable else 0, flags, ('\t<elements>\n%s\t</elements>\n' % elements) if elements else '',
               ('\t<immunities>\n%s\t</immunities>\n' % immunities) if immunities else ''))


def rows(**kw):
    return ''.join('\t\t<element %sPercent="%d"/>\n' % (k, v) for k, v in kw.items())


# ---- XML: a normal monster ----------------------------------------------------------------------------------------------
t = monster('Plain Thing', rows(fire=90, ice=40, energy=41, earth=-30, physical=100, holy=0, death=25))
new, c, notes = P.xml(t)
eq(pct(new, 'firePercent'), 40, 'normal: 90 -> 40')
eq(pct(new, 'icePercent'), 40, 'normal: 40 stays')
eq(pct(new, 'energyPercent'), 40, 'normal: 41 -> 40')
eq(pct(new, 'earthPercent'), -30, 'a weakness stays')
eq(pct(new, 'physicalPercent'), 40, 'normal: a percent of 100 is an immunity: 40')
eq(pct(new, 'holyPercent'), 0, '0 stays')
eq(pct(new, 'deathPercent'), 25, 'under the cap stays')
eq((c['capped'], c['immunity'], c['flat30']), (2, 1, 0), 'counts: two capped, one immunity')
eq(P.xml(new)[0], new, 'idempotent')

# ---- XML: a boss ---------------------------------------------------------------------------------------------------------
t = monster('Big Boss', rows(fire=90, ice=75, energy=76, physical=100), flags='\t\t<flag isboss="1"/>\n')
new, c, _ = P.xml(t)
eq(pct(new, 'firePercent'), 75, 'boss: 90 -> 75')
eq(pct(new, 'icePercent'), 75, 'boss: 75 stays')
eq(pct(new, 'energyPercent'), 75, 'boss: 76 -> 75')
eq(pct(new, 'physicalPercent'), 75, 'boss: 100 -> 75')
eq(P.xml(new)[0], new, 'boss: idempotent')
check(P.xml_is_boss(t) and not P.xml_is_boss(monster('x')), 'isboss flag')
check(not P.xml_is_boss('<monster name="x"><!-- <flag isboss="1"/> --></monster>'), 'a commented flag is no flag')

# ---- XML: immunities -----------------------------------------------------------------------------------------------------
t = monster('Immune Thing', rows(ice=10), immunities='\t\t<immunity earth="1"/>\n\t\t<immunity name="fire"/>\n'
            '\t\t<immunity physical="1"/>\n\t\t<immunity paralyze="1"/>\n\t\t<immunity ice="1"/>\n')
new, c, notes = P.xml(t)
eq(pct(new, 'earthPercent'), 40, 'immunity earth -> an earth row of 40')
eq(pct(new, 'firePercent'), 40, 'immunity name="fire" -> 40')
eq(pct(new, 'physicalPercent'), 40, 'immunity physical -> 40')
eq(pct(new, 'icePercent'), 40, 'the row of the immune type becomes the cap (the immunity beat the 10)')
check('earth="1"' not in new and 'name="fire"' not in new, 'the immunity attributes go')
check('bleed="1"' in new, 'physical immunity leaves the bleed immunity')
check('paralyze="1"' in new, 'a condition immunity stays')
eq(c['immunity'], 4, 'counts: four immunities (earth, fire, physical, ice)')
eq(P.xml(new)[0], new, 'immunities: idempotent')
# the immunities block goes when empty
t = monster('Only Fire', immunities='\t\t<immunity fire="1"/>\n')
new, c, _ = P.xml(t)
check('<immunities>' not in new and pct(new, 'firePercent') == 40, 'an emptied immunities block goes, the row is added')
# a boss immunity
t = monster('Boss Immune', immunities='\t\t<immunity holy="1"/>\n', flags='\t\t<flag isboss="1"/>\n')
eq(pct(P.xml(t)[0], 'holyPercent'), 75, 'boss: immunity -> 75')

# ---- XML: the flat 30 on seven types --------------------------------------------------------------------------------------
flat = rows(fire=30, earth=30, energy=30, death=30, physical=30, holy=30, ice=30)
t = monster('Acid Hydra', flat)
new, c, _ = P.xml(t)
kept = [k for k in ('fire', 'earth', 'energy', 'death', 'physical', 'holy', 'ice') if pct(new, k + 'Percent') == 30]
zero = [k for k in ('fire', 'earth', 'energy', 'death', 'physical', 'holy', 'ice') if pct(new, k + 'Percent') == 0]
eq(len(kept), 3, 'flat 30: three types keep 30')
eq(len(zero), 4, 'flat 30: four become 0')
eq(c['flat30'], 1, 'counts: one flat set')
want = sorted(P.SEVEN, key=lambda k: hashlib.sha256(('acid hydra:' + k).encode()).hexdigest())[:3]
eq(sorted(kept), sorted('earth' if k == 'earth' else k for k in want), 'flat 30: the hash of the lower case name picks the types')
eq(P.keep_types('Acid Hydra'), P.keep_types('ACID HYDRA'), 'the name is lower cased')
eq(P.keep_types('Acid Hydra'), P.keep_types('Acid Hydra'), 'stable')
check(P.keep_types('Acid Hydra') != P.keep_types('Black Stag') or P.keep_types('Black Stag') != P.keep_types('Dark Sorcerer'),
      'different names pick different sets (at least two of three)')
eq(P.xml(new)[0], new, 'flat 30: idempotent')
# six of seven at 30 is no flat set
t = monster('Almost Flat', rows(fire=30, earth=30, energy=30, death=30, physical=30, holy=30))
eq(P.xml(t)[0], t, 'six types at 30: untouched')
# flat 30 plus a weakness elsewhere is still a flat set only when all seven are 30
t = monster('Not Flat', rows(fire=30, earth=30, energy=30, death=30, physical=30, holy=30, ice=-10))
eq(P.xml(t)[0], t, 'a weakness in the seventh: untouched')

# ---- XML: left alone ------------------------------------------------------------------------------------------------------
t = monster('Trap', rows(fire=90), attackable=False)
eq(P.xml(t)[0], t, 'a monster that is not attackable is left alone')
t = monster('Invulnerable', '', immunities=''.join('\t\t<immunity %s="1"/>\n' % k for k in
                                                   ('physical', 'energy', 'earth', 'ice', 'holy', 'death')))
eq(P.xml(t)[0], t, 'a monster immune to every damage type (but fire) is left alone')
# life drain and mana drain are no element for the rule
t = monster('Drainer', rows(lifedrain=100, manadrain=100))
eq(P.xml(t)[0], t, 'life drain and mana drain are untouched')
# poison percent is the earth type
t = monster('Poison Thing', '\t\t<element poisonPercent="90"/>\n')
eq(pct(P.xml(t)[0], 'poisonPercent'), 40, 'poisonPercent is capped')

# ---- Lua ----------------------------------------------------------------------------------------------------------------
LUA = '''local mType = Game.createMonsterType("%s")
local monster = {}
monster.flags = {
	attackable = true,
	%s
}
monster.elements = {
%s}
monster.immunities = {
%s}
mType:register(monster)
'''


def lrow(const, v):
    return '\t{type = COMBAT_%sDAMAGE, percent = %d},\n' % (const, v)


t = LUA % ('Lua Thing', '', lrow('FIRE', 90) + lrow('ICE', 35) + lrow('ENERGY', -20) + lrow('PHYSICAL', 100),
           '\t{type = "earth", combat = true, condition = true},\n\t{type = "paralyze", condition = true},\n')
new, c, notes = P.lua(t)
check('percent = 40}' in new and lrow('FIRE', 40) in new, 'lua: fire 90 -> 40')
check(lrow('ICE', 35) in new, 'lua: 35 stays')
check(lrow('ENERGY', -20) in new, 'lua: a weakness stays')
check(lrow('PHYSICAL', 40) in new, 'lua: physical 100 -> 40')
check(lrow('EARTH', 40) in new, 'lua: the earth immunity became a row of 40')
check('type = "earth", combat = false, condition = true' in new, 'lua: the immunity keeps its condition part, combat = false')
check('{type = "paralyze", condition = true}' in new, 'lua: a condition immunity stays')
eq(P.lua(new)[0], new, 'lua: idempotent')
t = LUA % ('Lua Boss', 'isBoss = true,', lrow('FIRE', 90), '')
check(lrow('FIRE', 75) in P.lua(t)[0], 'lua boss: 90 -> 75')
t = LUA % ('Lua Flat', '', ''.join(lrow(k, 30) for k in ('FIRE', 'ICE', 'ENERGY', 'EARTH', 'DEATH', 'HOLY', 'PHYSICAL')), '')
new, c, _ = P.lua(t)
eq(new.count('percent = 30}'), 3, 'lua flat 30: three keep 30')
eq(new.count('percent = 0}'), 4, 'lua flat 30: four become 0')
eq(c['flat30'], 1, 'lua: counts')
want = P.keep_types('Lua Flat')
for k in want:
    check(lrow(k.upper(), 30) in new, 'lua flat 30: %s kept' % k)
eq(P.lua(new)[0], new, 'lua flat 30: idempotent')
t = (LUA % ('Lua Trap', '', lrow('FIRE', 90), '')).replace('attackable = true', 'attackable = false')
eq(P.lua(t)[0], t, 'lua: not attackable, left alone')
# no elements block: an immunity makes one
t = '''local mType = Game.createMonsterType("Bare")
local monster = {}
monster.immunities = {
	{type = "holy", combat = true},
}
mType:register(monster)
'''
new, c, _ = P.lua(t)
check('monster.elements = {\n\t{type = COMBAT_HOLYDAMAGE, percent = 40},\n}' in new, 'lua: an elements block is added for an immunity')

# ---- the command line -----------------------------------------------------------------------------------------------------
with tempfile.TemporaryDirectory() as tmp:
    data = os.path.join(tmp, 'data')
    base = os.path.join(data, 'monster', 'monsters', 'chaos')
    os.makedirs(os.path.join(base, 'pets'))
    os.makedirs(os.path.join(data, 'monster', 'lua'))
    files = {
        os.path.join(base, 'a.xml'): monster('A Normal', rows(fire=90)),
        os.path.join(base, 'b.xml'): monster('B Boss', rows(fire=90), flags='\t\t<flag isboss="1"/>\n'),
        os.path.join(base, 'pets', 'p.xml'): monster('Pet', rows(fire=90)),
        os.path.join(base, 'ok.xml'): monster('Fine', rows(fire=40)),
        os.path.join(data, 'monster', 'lua', 'l.lua'): LUA % ('L Thing', '', lrow('FIRE', 90), ''),
        os.path.join(data, 'monster', 'monsters.xml'): '<monsters><monster name="A Normal" file="chaos/a.xml"/></monsters>\n',
    }
    for p, text in files.items():
        with open(p, 'w', encoding='utf-8', newline='') as f:
            f.write(text)

    def run(*args):
        r = subprocess.run([sys.executable, '-I', TOOL, data] + list(args), capture_output=True, text=True)
        return r.returncode, r.stdout

    def read(p):
        with open(p, encoding='utf-8', newline='') as f:
            return f.read()
    code, out = run('--check')
    eq(code, 1, '--check: exit 1 while files are not up to date')
    check('a.xml' in out and 'b.xml' in out and 'l.lua' in out and 'ok.xml' not in out and 'p.xml' not in out,
          '--check names the files to change, not the fine one or the pet')
    for p, text in files.items():
        eq(read(p), text, '--check writes nothing: ' + os.path.basename(p))
    code, out = run('--dry-run')
    eq(code, 0, '--dry-run: exit 0')
    check('would change' in out and 'fire 90 -> 40' in out, '--dry-run prints what it would change')
    for p, text in files.items():
        eq(read(p), text, '--dry-run writes nothing: ' + os.path.basename(p))
    code, out = run()
    eq(code, 0, 'a run: exit 0')
    check('3 file(s) changed' in out and 'capped 3' in out, 'a run: the summary counts the three files: ' + out.strip().splitlines()[-1])
    eq(pct(read(os.path.join(base, 'a.xml')), 'firePercent'), 40, 'run: normal 40')
    eq(pct(read(os.path.join(base, 'b.xml')), 'firePercent'), 75, 'run: boss 75')
    eq(read(os.path.join(base, 'pets', 'p.xml')), files[os.path.join(base, 'pets', 'p.xml')], 'run: the pet is left alone')
    eq(read(os.path.join(data, 'monster', 'monsters.xml')), files[os.path.join(data, 'monster', 'monsters.xml')], 'run: monsters.xml untouched')
    check(lrow('FIRE', 40) in read(os.path.join(data, 'monster', 'lua', 'l.lua')), 'run: the Lua monster')
    code, out = run('--check')
    eq(code, 0, '--check: exit 0 after a run')
    code, out = run()
    check('0 file(s) changed' in out, 'a second run changes nothing')
    r = subprocess.run([sys.executable, '-I', TOOL], capture_output=True, text=True)
    eq(r.returncode, 2, 'no argument: usage')

if fails:
    print('%d failed' % fails)
    sys.exit(1)
print('patch_monster_resists tests: ok')
