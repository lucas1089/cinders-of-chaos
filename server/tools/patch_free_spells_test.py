#!/usr/bin/env python3
"""python3 -I server/tools/patch_free_spells_test.py: patch_free_spells.py on a synthetic base data folder (the lines it
changes are as in the base server): premium spells and runes become free, the Chaos block and the other premium tests
stay, a second run changes nothing, a dry run writes nothing, and the patched NPC library still parses in Lua."""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_free_spells as P

XML = '''<?xml version="1.0" encoding="UTF-8"?>
<spells>
	<instant group="attack" spellid="61" name="Brutal Strike" words="exori ico" level="16" mana="30" premium="1" range="1" needtarget="1" script="attack/brutal_strike.lua">
		<vocation name="Knight" />
	</instant>
	<instant group="healing" spellid="1" name="Light Healing" words="exura" level="8" mana="20" premium="0" script="healing/light_healing.lua" />
	<rune group="attack" spellid="4" name="Sudden Death" id="2268" level="45" magiclevel="15" premium="true" script="attack/sudden_death.lua" />
	<conjure name="Conjure Arrow" words="exevo con" level="13" mana="100" premium="yes" script="conjuring/arrow.lua" />
	<!-- BEGIN chaos spells (tools/register_spells.py) -->
	<instant group="attack" spellid="200" name="Rime Bloom" words="drai hyr rhim" level="20" mana="120" premium="1" script="chaos/sorcerer/frost_nova.lua" />
	<!-- END chaos spells -->
</spells>
'''
REVSCRIPT = '''local spell = Spell(SPELL_INSTANT)
function spell.onCastSpell(creature, variant)
	if creature:isPlayer() and creature:isPremium() then
		return true
	end
	return true
end
spell:name("Test")
spell:isPremium(true)
spell:register()
'''
MODULES = '''StdModule = {}
function StdModule.promotePlayer(cid, message, keywords, parameters, node)
	local player = Player(cid)
	if player:isPremium() or not parameters.premium then
		return true
	end
	return false
end

function StdModule.learnSpell(cid, message, keywords, parameters, node)
	local player = Player(cid)
	if player:isPremium() or not parameters.premium then
		player:learnSpell(parameters.spellName)
	else
		npcHandler:say("You need a premium account in order to buy " .. parameters.spellName .. ".", cid)
	end
	return true
end

function StdModule.bless(cid, message, keywords, parameters, node)
	local player = Player(cid)
	if player:isPremium() or not parameters.premium then
		return true
	end
	return false
end
'''
fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def tree():
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, 'spells'))
    os.makedirs(os.path.join(d, 'scripts', 'spells'))
    os.makedirs(os.path.join(d, 'npc', 'lib', 'npcsystem'))
    open(os.path.join(d, 'spells', 'spells.xml'), 'w').write(XML)
    open(os.path.join(d, 'scripts', 'spells', 'test.lua'), 'w').write(REVSCRIPT)
    open(os.path.join(d, 'npc', 'lib', 'npcsystem', 'modules.lua'), 'w').write(MODULES)
    return d


def snapshot(d):
    out = {}
    for root, _, files in os.walk(d):
        for name in files:
            p = os.path.join(root, name)
            out[p] = open(p).read()
    return out


def lua_parses(path):
    for lua in ('luajit', 'lua5.3', 'lua'):
        exe = shutil.which(lua)
        if exe:
            r = subprocess.run([exe, '-e', 'assert(loadfile(%r))' % path], stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT)
            return r.returncode == 0
    return True  # no Lua here: the parse check is skipped


d = tree()
try:
    before = snapshot(d)
    ok(P.main([d, '--dry-run']) == 0, 'dry run')
    ok(snapshot(d) == before, 'dry run writes nothing')
    ok(P.main([d]) == 0, 'first run')
    xml = open(os.path.join(d, 'spells', 'spells.xml')).read()
    ok('name="Brutal Strike" words="exori ico" level="16" mana="30" premium="0"' in xml, 'instant made free')
    ok('id="2268" level="45" magiclevel="15" premium="0"' in xml, 'rune made free')
    ok('words="exevo con" level="13" mana="100" premium="0"' in xml, 'conjure made free')
    ok('name="Rime Bloom" words="drai hyr rhim" level="20" mana="120" premium="1"' in xml, 'Chaos block untouched')
    ok(xml.count('premium=') == 5, 'no attribute added or removed')
    rev = open(os.path.join(d, 'scripts', 'spells', 'test.lua')).read()
    ok('spell:isPremium(false)' in rev and 'isPremium(true)' not in rev, 'revscript made free')
    ok('creature:isPremium()' in rev, 'player premium test kept')
    mod = open(os.path.join(d, 'npc', 'lib', 'npcsystem', 'modules.lua')).read()
    ok(mod.count('if player:isPremium() or not parameters.premium then') == 2, 'promotion and blessing tests kept')
    ok(mod.count(P.LEARN_MARK) == 1, 'learnSpell test removed once')
    learn = mod[mod.index('StdModule.learnSpell'):mod.index('StdModule.bless')]
    ok('isPremium' not in learn, 'learnSpell asks no premium')
    ok(lua_parses(os.path.join(d, 'npc', 'lib', 'npcsystem', 'modules.lua')), 'modules.lua parses')
    after = snapshot(d)
    ok(P.main([d]) == 0, 'second run')
    ok(snapshot(d) == after, 'second run changes nothing')
    # a base without the learnSpell test is reported, not refused
    open(os.path.join(d, 'npc', 'lib', 'npcsystem', 'modules.lua'), 'w').write('StdModule = {}\n')
    ok(P.main([d]) == 0, 'missing learnSpell is not an error')
    # no spells.xml: refused
    os.remove(os.path.join(d, 'spells', 'spells.xml'))
    ok(P.main([d]) == 1, 'missing spells.xml refused')
finally:
    shutil.rmtree(d)

print('patch_free_spells_test: %s' % ('ok' if not fails else '%d failure(s)' % fails))
sys.exit(1 if fails else 0)
