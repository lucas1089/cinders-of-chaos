#!/usr/bin/env python3
"""python3 -I server/tools/patch_waystone_bosses_test.py: patch_waystone_bosses.py on synthetic copies of the three base
files (the lines it changes are as in the base server; the real files are also checked when the WAYSTONE_BASE_DATA
environment variable names a base data folder): the changes are made once, a second run changes nothing, a dry run
writes nothing, CRLF text is kept, a text that is not the known one is refused without writing anything, and the patched
health events run in luajit and lua5.3 against a mocked engine (a share away from the pillar, the full hit next to it,
the base rule without the Chaos scripts)."""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_waystone_bosses as P

ROOM = '''local config = {\r
    actionId = 42646, \r
    bossName = "Frostreaver the Glacialblade",\r
    bossArea = {\r
        fromPos = Position(32960, 33224, 7), \r
        toPos = Position(32974, 33239, 7), \r
        entrancePos = Position(32965, 33236, 7), \r
        exitPosition = Position(32369, 32241, 7) \r
    },\r
}\r
'''

MORGRATH = '''local ARCHMAGE_NAME = "Morgrath the Umbral Archmage"
local function archmageNearPillar(archmage)
    return NEAR
end
local evt = CreatureEvent("archmage_damage")
function evt.onHealthChange(target, source, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
    if not target or not target:isMonster() then
        return primaryDamage, primaryType, secondaryDamage, secondaryType
    end
    if target:getName() ~= ARCHMAGE_NAME then
        return primaryDamage, primaryType, secondaryDamage, secondaryType
    end
    if not archmageNearPillar(target) then
        return 0, primaryType, 0, secondaryType
    end
    return primaryDamage, primaryType, secondaryDamage, secondaryType
end
evt:register()
'''

NYXDRATH = '''local BOSS_NAME = "Nyxdrath the Midnight Terror"
local function pillarTypeAdjacentToBoss(boss)
  return PILLAR
end
local evt = CreatureEvent("nyxdrath_damage")
function evt.onHealthChange(target, source, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
  if not target or not target:isMonster() then
    return primaryDamage, primaryType, secondaryDamage, secondaryType
  end
  if target:getName() ~= BOSS_NAME then
    return primaryDamage, primaryType, secondaryDamage, secondaryType
  end

  local allowedType = pillarTypeAdjacentToBoss(target)
  if not allowedType then
    return 0, primaryType, 0, secondaryType
  end

  local pd = (primaryType == allowedType) and primaryDamage or 0
  local sd = (secondaryType == allowedType) and secondaryDamage or 0
  return pd, primaryType, sd, secondaryType
end
evt:register()
'''

fails = 0


def check(cond, label):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + label)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)


def read(path):
    with open(path, encoding='utf-8', newline='') as f:
        return f.read()


def run(data, *extra):
    p = subprocess.run([sys.executable, '-I', os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                           'patch_waystone_bosses.py'), data] + list(extra),
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


HARNESS = r'''
local handler
CreatureEvent = function(name) local ev = {} function ev:register() handler = self end return ev end
local src = io.open(arg[1]):read("*a")
local function load_with(near)
  local text = src:gsub("NEAR", tostring(near)):gsub("PILLAR", near and "COMBAT_FIRE" or "nil")
  assert((loadstring or load)(text))()
end
COMBAT_FIRE, COMBAT_ICE = 1, 2
local boss = {isMonster = function() return true end, getName = function() return arg[2] end}
local out = {}
local function hit(p, pt, s, st) local a, _, b = handler.onHealthChange(boss, nil, p, pt, s, st) out[#out + 1] = a .. "," .. b end
load_with(false)
hit(1000, COMBAT_FIRE, 400, COMBAT_ICE)      -- away from a pillar, no Chaos: the base rule
ChaosWaystoneTiers = {shielded = function(t, s, p, q) return math.floor(p * 0.25), math.floor(q * 0.25) end}
hit(1000, COMBAT_FIRE, 400, COMBAT_ICE)      -- away from a pillar: a quarter
load_with(true)
hit(1000, COMBAT_FIRE, 400, COMBAT_ICE)      -- next to the pillar (Nyxdrath: a fire pillar)
print(table.concat(out, ";"))
'''


def lua_run(script, boss):
    res = {}
    with tempfile.TemporaryDirectory() as d:
        h = os.path.join(d, 'h.lua')
        s = os.path.join(d, 's.lua')
        write(h, HARNESS)
        write(s, script)
        for lua in ('luajit', 'lua5.3'):
            if shutil.which(lua):
                p = subprocess.run([lua, h, s, boss], capture_output=True, text=True)
                res[lua] = (p.stdout.strip(), p.stderr.strip())
    return res


with tempfile.TemporaryDirectory() as tmp:
    data = os.path.join(tmp, 'data')
    room, morg, nyx = (os.path.join(data, r) for r in (P.ROOM, P.MORGRATH, P.NYXDRATH))
    write(room, ROOM)
    write(morg, MORGRATH)
    write(nyx, NYXDRATH)
    code, out = run(data, '--dry-run')
    check(code == 0 and out.count('dry run') == 3, 'dry run lists the three files: ' + out)
    check(read(room) == ROOM and read(morg) == MORGRATH, 'dry run writes nothing')
    code, out = run(data)
    check(code == 0 and out.count(': patched') == 3, 'patched: ' + out)
    r = read(room)
    check('entrancePos = Position(32964, 33236, 7), ' + P.MARK in r, 'the entrance moved off the tar')
    check(r.count('\r\n') == ROOM.count('\r\n') and '\n' not in r.replace('\r\n', ''), 'CRLF kept')
    m, n = read(morg), read(nyx)
    check('return 0, primaryType' not in m and 'return 0, primaryType' not in n, 'no "nothing" left')
    check(n.count(P.MARK) == 7, 'Nyxdrath: the block and the two element lines')
    code, out2 = run(data)
    check(code == 0 and out2.count('already patched') == 3, 'second run: nothing new: ' + out2)
    check(read(morg) == m and read(nyx) == n and read(room) == r, 'idempotent')
    for lua, (got, err) in lua_run(m, 'Morgrath the Umbral Archmage').items():
        check(got == '0,0;250,100;1000,400', 'Morgrath in %s: base rule, a quarter, the full hit: %s %s' % (lua, got, err))
    for lua, (got, err) in lua_run(n, 'Nyxdrath the Midnight Terror').items():
        # next to a fire pillar: the fire part in full, the ice part a quarter
        check(got == '0,0;250,100;1000,100', 'Nyxdrath in %s: %s %s' % (lua, got, err))

    # a text this patch does not know: refused, nothing written
    data2 = os.path.join(tmp, 'data2')
    write(os.path.join(data2, P.ROOM), ROOM)
    write(os.path.join(data2, P.MORGRATH), MORGRATH.replace('return 0, primaryType, 0, secondaryType', 'return 0'))
    write(os.path.join(data2, P.NYXDRATH), NYXDRATH)
    code, out = run(data2)
    check(code == 1 and 'refused' in out, 'unknown text refused: ' + out)
    check(read(os.path.join(data2, P.ROOM)) == ROOM, 'nothing written on a refusal')
    os.remove(os.path.join(data2, P.MORGRATH))
    code, out = run(data2)
    check(code == 1 and 'missing' in out, 'a missing file refused: ' + out)

base = os.environ.get('WAYSTONE_BASE_DATA')
if base and os.path.isdir(base):
    with tempfile.TemporaryDirectory() as tmp:
        data = os.path.join(tmp, 'data')
        for rel in (P.ROOM, P.MORGRATH, P.NYXDRATH):
            os.makedirs(os.path.dirname(os.path.join(data, rel)), exist_ok=True)
            shutil.copy(os.path.join(base, rel), os.path.join(data, rel))
        code, out = run(data)
        check(code == 0 and out.count(': patched') == 3, 'the real base files: ' + out)
        code, out = run(data)
        check(code == 0 and out.count('already patched') == 3, 'the real base files, second run: ' + out)

print('patch_waystone_bosses_test: %s' % ('ok' if fails == 0 else '%d failure(s)' % fails))
sys.exit(1 if fails else 0)
