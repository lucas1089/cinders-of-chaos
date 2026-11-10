#!/usr/bin/env python3
"""Test of patch_stock_spell_inputs.py (O468) on copies of the two base scripts (as an installed server has them, with the
Mystic effects blocks of patch_mystic_stock_fx.py around the Hex): the numbers of a typical caster at the level each
spell is learned stay (Kindling Spark 10 to 20, Bewitching Hex 128 + 256 + 384 + 512), they grow with level and magic
level, nothing else changes, idempotent, CRLF, --dry-run, a missing file or line refused, install_all.py runs the step.
Run: python3 -I server/tools/patch_stock_spell_inputs_test.py"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'patch_stock_spell_inputs.py')
sys.path.insert(0, HERE)
import patch_stock_spell_inputs as P  # noqa: E402

SPARK = '''local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_FIREDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, CONST_ME_FIREATTACK)
combat:setParameter(COMBAT_PARAM_DISTANCEEFFECT, CONST_ANI_FIRE)

function onGetFormulaValues(player, level, magicLevel)
	return -10, -20
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")

function onCastSpell(creature, variant)
	playSound(creature, "fire.ogg")
	return combat:execute(creature, variant)
end
'''

HEX = '''-- >>> chaos mystic fx (server/tools/patch_mystic_stock_fx.py)
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end
-- <<< chaos mystic fx
local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_ARCANEDAMAGE)

local function applyPeriodicDamage(creature, target, baseDamage, damageIncrement, interval, duration)
    local iterations = math.floor(duration / interval)
    local currentDamage = baseDamage

    for i = 1, iterations do
        addEvent(function()
            if target and target:isCreature() and target:getHealth() > 0 then
                doTargetCombatHealth(creature.uid, target.uid, COMBAT_ARCANEDAMAGE, -currentDamage, -currentDamage, 2)
                currentDamage = currentDamage + damageIncrement
            end
        end, i * interval)
    end
end

function onCastSpell(creature, variant)
    local target = Creature(variant:getNumber())
    if not target then
        return false
    end

    local baseDamage = 128
    local damageIncrement = 128
    local interval = 2000
    local duration = 8000
    playSound(creature, "arcane_4.ogg")
    -- Start applying periodic damage
    applyPeriodicDamage(creature, target, baseDamage, damageIncrement, interval, duration)

    return true
end
-- >>> chaos mystic fx wrap (server/tools/patch_mystic_stock_fx.py)
if ChaosMysticFx and ChaosMysticFx.wrapStock and onCastSpell then
	onCastSpell = ChaosMysticFx.wrapStock("bewitching_hex", onCastSpell)
end
-- <<< chaos mystic fx wrap
'''

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def interp(points, x):
    if x <= points[0][0]:
        return points[0][1]
    for a, b in zip(points, points[1:]):
        if x <= b[0]:
            return a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0])
    return points[-1][1]


def caster_ml(level):
    """the typical caster's magic level: rotation_sim.py ANCHORS 'ml_caster'"""
    text = open(os.path.join(HERE, 'rotation_sim.py'), encoding='utf-8').read()
    row = re.search(r"'ml_caster':\s*(\[[^\]]*\])", text).group(1)
    return interp([(int(a), int(b)) for a, b in re.findall(r'\((\d+),\s*(\d+)\)', row)], level)


def make(spark=SPARK, hex_=HEX, eol='\n'):
    d = tempfile.mkdtemp()
    for name, text in ((P.SPARK, spark), (P.HEX, hex_)):
        path = os.path.join(d, 'spells', 'scripts', *name.split('/'))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(text.replace('\n', eol))
    return d


def read(d, name):
    with open(os.path.join(d, 'spells', 'scripts', *name.split('/')), encoding='utf-8', newline='') as f:
        return f.read()


def run(d, *extra):
    p = subprocess.run([sys.executable, '-I', TOOL, d] + list(extra), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout.decode()


# ---- Kindling Spark
new, changed, err = P.patch_text(P.SPARK, SPARK)
check(err is None and changed, 'the spark is changed')
check(new.replace(re.search(r'return -\(level.*', new).group(0), 'return -10, -20') == SPARK, 'nothing else of the spark changed')
expr = re.search(r'return (-\(level.*?\)), (-\(level.*?\)) --', new)
check(expr is not None, 'the spark returns the two formulas')
lo_f, hi_f = expr.group(1), expr.group(2)


def spark(level, ml):
    return -eval(lo_f, {}, {'level': level, 'magicLevel': ml}), -eval(hi_f, {}, {'level': level, 'magicLevel': ml})


lo, hi = spark(8, caster_ml(8))
check(abs(lo - 10) < 0.5 and abs(hi - 20) < 0.5, 'the spark of a typical caster at level 8 is the old 10 to 20: %.1f to %.1f' % (lo, hi))
check(spark(100, 60)[0] > spark(8, 60)[0] and spark(8, 30)[0] > spark(8, 4)[0], 'the spark grows with level and magic level')
check(spark(1000, 140)[1] < 400, 'the spark stays a cheap opener at level 1000: %.0f' % spark(1000, 140)[1])
check(P.patch_text(P.SPARK, new) == (new, False, None), 'idempotent (spark)')

# ---- Bewitching Hex
new, changed, err = P.patch_text(P.HEX, HEX)
check(err is None and changed, 'the hex is changed')
check('local baseDamage = 128' not in new.replace('or 128', ''), 'the base line is gone')
check('-- >>> chaos mystic fx wrap' in new and 'chaos mystic fx (server' in new, 'the Mystic effects blocks are kept')
m = re.search(r'local baseDamage = caster and (math\.floor\(.*\)) or 128', new)
check(m is not None, 'the hex first tick formula')
unit = m.group(1).replace('math.floor', 'int').replace('caster:getLevel()', 'level').replace('caster:getMagicLevel()', 'ml')


def hexunit(level, ml):
    return eval(unit, {'int': lambda x: int(x // 1)}, {'level': level, 'ml': ml})


check(abs(hexunit(60, caster_ml(60)) - 128) <= 1, 'the first tick of a typical caster at level 60 is the old 128: %d' % hexunit(60, caster_ml(60)))
check('local damageIncrement = baseDamage' in new, 'each tick adds the first again (128, 256, 384, 512 shape)')
check(hexunit(500, 113) > 2 * hexunit(60, 36), 'the hex grows with level and magic level')
check(P.patch_text(P.HEX, new) == (new, False, None), 'idempotent (hex)')
check(new.count('chaos spell scaling (O468') == 1, 'one marker in the hex')

# ---- the tool on folders
d = make()
code, out = run(d, '--dry-run')
check(code == 0 and read(d, P.SPARK) == SPARK and read(d, P.HEX) == HEX, '--dry-run writes nothing: ' + out)
code, out = run(d)
check(code == 0 and 'reads the level' in out, 'the run: ' + out)
a, b = read(d, P.SPARK), read(d, P.HEX)
check(a != SPARK and b != HEX, 'both files changed')
code, out = run(d)
check(code == 0 and read(d, P.SPARK) == a and read(d, P.HEX) == b and out.count('already') == 2, 'a second run changes nothing: ' + out)

d = make(eol='\r\n')
code, out = run(d)
check(code == 0 and '\r\n' in read(d, P.SPARK) and '\n' not in read(d, P.SPARK).replace('\r\n', ''), 'CRLF kept (spark)')
check(code == 0 and '\n' not in read(d, P.HEX).replace('\r\n', ''), 'CRLF kept (hex)')
code, out = run(d)
check(code == 0 and out.count('already') == 2, 'CRLF idempotent')

d = make(spark=SPARK.replace('return -10, -20', 'return -11, -21'))
code, out = run(d)
check(code == 1 and read(d, P.HEX) == HEX, 'a changed base line is refused and nothing is written: ' + out)
d = make()
os.remove(os.path.join(d, 'spells', 'scripts', *P.HEX.split('/')))
code, out = run(d)
check(code == 1 and 'missing file' in out and read(d, P.SPARK) == SPARK, 'a missing script is refused: ' + out)
check(run(tempfile.mkdtemp(), 'x', 'y')[0] == 2, 'bad args')

# ---- wired
src = open(os.path.join(HERE, 'install_all.py'), encoding='utf-8').read()
check("tool('patch_stock_spell_inputs.py')" in src, 'install_all.py runs the step')
check('patch_stock_spell_inputs.py' in src.split('def ')[0], 'the docstring of install_all.py lists the step')

if fails:
    sys.exit(1)
print('patch_stock_spell_inputs_test: ok')
