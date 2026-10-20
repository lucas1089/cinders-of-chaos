#!/usr/bin/env python3
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_absorb_ceiling as P

BASE = os.environ.get('CHAOS_BASE_DATA', '')  # a base server data folder; the real-file checks are skipped when unset
fails = 0
def ok(c, m):
    global fails
    if not c:
        fails += 1
        print('FAIL', m)

synthetic = P.OLD_RETURN.join(['local function getCombinedAbsorb(target, storageIds)\n\tlocal total = 0\n', '\nlocal function x() end\n'])
new, ch = P.patch(synthetic)
ok(len(ch) == 1 and P.MARKER in new, 'patched')
ok('math.min(total, 75)' in new, 'content')
again, ch2 = P.patch(new)
ok(again == new and ch2 == [], 'idempotent')
_, ch3 = P.patch('function onUse() end')
ok(ch3 and ch3[0].startswith('REFUSED'), 'refused on unknown code')

d = tempfile.mkdtemp()
try:
    path = os.path.join(d, P.TARGET)
    os.makedirs(os.path.dirname(path))
    open(path, 'w', newline='').write(synthetic.replace('\n', '\r\n'))
    ok(P.main([d, '--dry-run']) == 0 and P.MARKER not in open(path).read(), 'dry run writes nothing')
    ok(P.main([d]) == 0 and P.MARKER in open(path).read(), 'writes')
    ok('\r\n' in open(path, newline='').read(), 'CRLF kept')
    ok(P.main([d]) == 0, 'second run')
    ok(P.main([os.path.join(d, 'none')]) == 0, 'missing file skipped')
finally:
    shutil.rmtree(d)

# the patched real base file: run the event against a mock and compare with ChaosItemMods.effectiveAbsorb
real = os.path.join(BASE, P.TARGET)
if os.path.isfile(real):
    text = open(real, newline='').read().replace('\r\n', '\n')
    pt, chr_ = P.patch(text)
    ok(len(chr_) == 1, 'applies to the real base file')
    d = tempfile.mkdtemp()
    try:
        f = os.path.join(d, 'a.lua')
        open(f, 'w').write(pt)
        lua = r'''
bit = {band = function(a, b) local r, bitv = 0, 1
  while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + bitv end a, b, bitv = math.floor(a/2), math.floor(b/2), bitv*2 end return r end}
COMBAT_FIREDAMAGE, COMBAT_PHYSICALDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_DROWNDAMAGE = 8, 1, 2, 4, 256
COMBAT_ICEDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_DEATHDAMAGE, COMBAT_WATERDAMAGE, COMBAT_ARCANEDAMAGE = 512, 1024, 2048, 4096, 8192
COMBAT_LIFEDRAIN, COMBAT_MANADRAIN, ORIGIN_NONE, ORIGIN_MELEE = 32, 64, 0, 3
local ev
CreatureEvent = function() ev = {register = function() end} return ev end
EventCallback = {register = function() end}
dofile(arg[1])
local function player(a, b) return {isPlayer = function() return true end, getStorageValue = function(_, k) if k == 977545 then return a elseif k == 977563 then return b end return -1 end} end
local function hit(a, b) local p = ev.onHealthChange(player(a, b), nil, -1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE) return p end
print(hit(0, 0), hit(40, 20), hit(60, 40), hit(100, 100), hit(80, 0))
'''
        out = subprocess.run(['luajit', '-e', 'arg={[1]="%s"}' % f.replace('\\', '/'), '-'], input=lua, capture_output=True, text=True)
        ok(out.stdout.split() == ['-1000', '-400', '-250', '-250', '-250'], 'event result ' + out.stdout + out.stderr)
    finally:
        shutil.rmtree(d)
print('patch_absorb_ceiling_test: %s' % ('all checks passed' if not fails else '%d FAILED' % fails))
sys.exit(1 if fails else 0)
