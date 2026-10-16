#!/usr/bin/env python3
"""python3 -I server/tools/patch_mystic_stock_fx_test.py: patch_mystic_stock_fx.py on synthetic base scripts (the
lines it changes are as in the base server): the blocks are added once, the ids are wrapped, a second run changes
nothing, a missing script or line is refused without writing anything, and the patched scripts still load in Lua."""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_mystic_stock_fx as P

HEX = '''local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_ARCANEDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, 218)
combat:setParameter(COMBAT_PARAM_DISTANCEEFFECT, 84)

function onCastSpell(creature, variant)
    local target = Creature(variant:getNumber())
    if not target then
        return false
    end
    return combat:execute(creature, variant)
end
'''
WAVE = '''local combat0_Brush = createCombatObject()
setCombatParam(combat0_Brush, COMBAT_PARAM_EFFECT, 244)

function onCastSpell(creature, var)
    return true
end
'''
fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def tree(hex_text=HEX, wave_text=WAVE):
    d = tempfile.mkdtemp()
    base = os.path.join(d, 'spells', 'scripts', 'custom', 'illusionist_class')
    os.makedirs(base)
    if hex_text is not None:
        open(os.path.join(base, 'bewitched_curse.lua'), 'w').write(hex_text)
    if wave_text is not None:
        open(os.path.join(base, 'arcane_wave.lua'), 'w').write(wave_text)
    return d, base


d, base = tree()
try:
    ok(P.main([d, '--dry-run']) == 0, 'dry run')
    ok(open(os.path.join(base, 'bewitched_curse.lua')).read() == HEX, 'dry run writes nothing')
    ok(P.main([d]) == 0, 'first run')
    hx = open(os.path.join(base, 'bewitched_curse.lua')).read()
    wv = open(os.path.join(base, 'arcane_wave.lua')).read()
    ok(hx.startswith(P.HEAD_BEGIN), 'hex: load at the top')
    ok('ChaosMysticFx.stockEffect("bewitching_hex", 218) or 218)' in hx, 'hex: effect wrapped')
    ok('ChaosMysticFx.stockMissile("bewitching_hex", 84) or 84)' in hx, 'hex: missile wrapped')
    ok('wrapStock("bewitching_hex", onCastSpell)' in hx and hx.rstrip().endswith(P.TAIL_END), 'hex: wrap at the end')
    ok('wrapStock("arcane_ripple", onCastSpell)' in wv and wv.startswith(P.HEAD_BEGIN), 'ripple: load and wrap')
    ok('COMBAT_PARAM_EFFECT, 244)' in wv, 'ripple: its wave untouched')
    ok(P.main([d]) == 0, 'second run')
    ok(open(os.path.join(base, 'bewitched_curse.lua')).read() == hx, 'second run: hex unchanged')
    ok(open(os.path.join(base, 'arcane_wave.lua')).read() == wv, 'second run: ripple unchanged')
    ok(hx.count(P.HEAD_BEGIN) == 1 and hx.count(P.TAIL_BEGIN) == 1, 'blocks once')
    # the patched scripts parse in Lua (luajit and lua5.3 when present)
    for lua in ('luajit', 'lua5.3'):
        if shutil.which(lua):
            for f in ('bewitched_curse.lua', 'arcane_wave.lua'):
                r = subprocess.run([lua, '-e', 'assert(loadfile("%s"))' % os.path.join(base, f)],
                                   capture_output=True)
                ok(r.returncode == 0, '%s parses %s: %s' % (lua, f, r.stderr[:200]))
finally:
    shutil.rmtree(d)

# refusals: nothing written
d, base = tree(wave_text=None)
try:
    ok(P.main([d]) == 1, 'missing script refused')
    ok(open(os.path.join(base, 'bewitched_curse.lua')).read() == HEX, 'missing script: nothing written')
finally:
    shutil.rmtree(d)
d, base = tree(hex_text=HEX.replace('COMBAT_PARAM_DISTANCEEFFECT, 84', 'COMBAT_PARAM_DISTANCEEFFECT, CONST_ANI_X'))
try:
    ok(P.main([d]) == 1, 'missing line refused')
    ok(open(os.path.join(base, 'arcane_wave.lua')).read() == WAVE, 'missing line: nothing written')
finally:
    shutil.rmtree(d)
ok(P.main([]) == 2, 'usage')

print('patch_mystic_stock_fx_test: %s' % ('ok' if not fails else '%d failed' % fails))
sys.exit(1 if fails else 0)
