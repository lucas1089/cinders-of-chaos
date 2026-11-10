#!/usr/bin/env python3
"""Test of patch_base_absorb_player.py: the patch on the shape of the base absorb event (the Chaos ceiling patch applied), what
the patched event does with the layer on, off and missing (run in Lua against a mock), idempotent, CRLF, dry run, a refusal on
unknown code, the install_all.py step. When CHAOS_BASE_DATA names a base server data folder the real file is patched too.
Run: python3 -I server/tools/patch_base_absorb_player_test.py"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_base_absorb_player as P  # noqa: E402

BASE = os.environ.get('CHAOS_BASE_DATA', '')
fails = 0


def ok(c, m):
    global fails
    if not c:
        fails += 1
        print('FAIL', m)


EVENT = '''-- Chaos: absorb ceiling (patch_absorb_ceiling.py)
local function getCombinedAbsorb(target, storageIds)
    local total = 0
    for _, storageId in ipairs(storageIds) do
        local v = target:getStorageValue(storageId) or 0
        if v < 0 then v = 0 end
        total = total + v
    end
    return math.min(total, 75) -- Chaos: the ceiling
end

local creatureEvent = CreatureEvent("rarity_onHealthChangeAbsorb")
function creatureEvent.onHealthChange(target, source, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)

    if not target or not target:isPlayer() then
        return primaryDamage, primaryType, secondaryDamage, secondaryType
    end
    local absorbTypes = {
        { type = 8, name = "Fire", storages = {977544, 977562} },
    }
    for _, absorb in ipairs(absorbTypes) do
        local sum = getCombinedAbsorb(target, absorb.storages)
        if sum > 0 and primaryType == absorb.type then
            primaryDamage = math.floor(primaryDamage * (1 - sum / 100))
        end
    end
    return primaryDamage, primaryType, secondaryDamage, secondaryType
end
creatureEvent:register()
'''

new, ch = P.patch(EVENT)
ok(len(ch) == 1 and P.MARKER in new, 'patched')
ok(new.count('ChaosPlayerDefence.active()') == 1, 'one guard')
again, ch2 = P.patch(new)
ok(again == new and ch2 == [], 'idempotent')
ok(P.patch('function onUse() end')[1][0].startswith('REFUSED'), 'refused on unknown code')
ok(P.patch(EVENT + EVENT)[1][0].startswith('REFUSED'), 'refused when the anchor is not unique')

HARNESS = r'''
local text = io.open(arg[1]):read("*a")
local registered
function CreatureEvent(name) local e = {}; function e.register() registered = e end; return e end
local storages = {[977544] = 30, [977562] = 20}
local target = {isPlayer = function() return true end, getStorageValue = function(_, k) return storages[k] end}
registered = nil
assert((loadstring or load)(text))()
local ev = registered
ChaosPlayerDefence = nil
local d = ev.onHealthChange(target, nil, -100, 8, 0, 0, 0)
assert(d == -50, "no layer: the absorb is taken, got " .. tostring(d))
ChaosPlayerDefence = {active = function() return true end}
d = ev.onHealthChange(target, nil, -100, 8, 0, 0, 0)
assert(d == -100, "layer on: the hit is left alone, got " .. tostring(d))
ChaosPlayerDefence = {active = function() return false end}
d = ev.onHealthChange(target, nil, -100, 8, 0, 0, 0)
assert(d == -50, "layer off: the absorb is taken, got " .. tostring(d))
print("lua ok")
'''


def lua_check(text, label):
    interp = shutil.which('luajit') or shutil.which('lua5.3') or shutil.which('lua')
    if not interp:
        print('no Lua interpreter: the run of %s skipped' % label)
        return
    d = tempfile.mkdtemp()
    try:
        f = os.path.join(d, 'event.lua')
        h = os.path.join(d, 'harness.lua')
        with open(f, 'w') as fh:
            fh.write(text)
        with open(h, 'w') as fh:
            fh.write(HARNESS)
        p = subprocess.run([interp, h, f], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        ok(p.returncode == 0 and b'lua ok' in p.stdout, '%s runs: %s' % (label, p.stdout.decode()[-300:]))
    finally:
        shutil.rmtree(d)


lua_check(new, 'the patched event')

d = tempfile.mkdtemp()
try:
    path = os.path.join(d, P.TARGET)
    os.makedirs(os.path.dirname(path))
    with open(path, 'w', newline='') as fh:
        fh.write(EVENT.replace('\n', '\r\n'))
    ok(P.main([d, '--dry-run']) == 0 and P.MARKER not in open(path).read(), 'dry run writes nothing')
    ok(P.main([d]) == 0 and P.MARKER in open(path).read(), 'writes')
    ok('\r\n' in open(path, newline='').read(), 'CRLF kept')
    ok(P.main([d]) == 0, 'second run')
    ok(P.main([os.path.join(d, 'none')]) == 0, 'missing file skipped')
    ok(P.main([]) == 1, 'bad args')
finally:
    shutil.rmtree(d)

real = os.path.join(BASE, P.TARGET) if BASE else ''
if real and os.path.isfile(real):
    text = open(real, newline='').read().replace('\r\n', '\n')
    pt, chr_ = P.patch(text)
    ok(len(chr_) == 1 or P.MARKER in text, 'applies to the real base file')

with open(os.path.join(HERE, 'install_all.py'), encoding='utf-8') as f:
    inst = f.read()
ok('def step_absorbplayer(' in inst and 'patch_base_absorb_player.py' in inst, 'install_all.py has the step')
ok("'absorbplayer'" in inst and '  absorbplayer ' in inst, 'the step is in the docstring and the order')

print('patch_base_absorb_player_test:', 'OK' if not fails else '%d failure(s)' % fails)
sys.exit(1 if fails else 0)
