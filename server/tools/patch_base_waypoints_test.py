#!/usr/bin/env python3
"""Test of patch_base_waypoints.py (O386) on a synthetic copy of the base waypoint script's shape (no base names): the
three storage tests replaced, the block added once before the MoveEvent, nothing else changed, CRLF kept, idempotent,
an unexpected script left alone, a data folder without it, --dry-run, bad args; the patched script run under luajit and
lua5.3 with a mocked engine (unlockAll on: every other waypoint in the menu at the first step, no unlock written; off:
the base rule); and the install_all.py step is wired.
Run: python3 -I server/tools/patch_base_waypoints_test.py"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
TOOL = os.path.join(HERE, 'patch_base_waypoints.py')
sys.path.insert(0, HERE)
import patch_base_waypoints as P  # noqa: E402

# the base script's shape: the list, the step-in with its three storage tests, the menu
BASE = '''
print(">> Waypoint System Loaded")

local waypointList = {
    [1] = {
        name = "Town A",
        actionId = 7000,
        position = Position(100, 100, 7),
        requireQuest = {check = false, storage = 0, value = 0},
        cost = {check = false, itemId = 0, amount = 0}
    },
    [2] = {
        name = "Town B",
        actionId = 7001,
        position = Position(200, 200, 7),
        requireQuest = {check = false, storage = 0, value = 0},
        cost = {check = false, itemId = 0, amount = 0}
    },
    [3] = {
        name = "Town C",
        actionId = 7002,
        position = Position(300, 300, 7),
        requireQuest = {check = false, storage = 0, value = 0},
        cost = {check = false, itemId = 0, amount = 0}
    },
}

local cooldowns = {}

local waypoints = MoveEvent()
function waypoints.onStepIn(player,item,position,fromPosition)
    if not player:isPlayer() then
        return false
    end
        local unlockedWaypoints = 0

        for i = 1, #waypointList do
            if player:getStorageValue(waypointList[i].actionId) == 1 then
                unlockedWaypoints = unlockedWaypoints + 1
            end
        end

        if unlockedWaypoints == 1 then
            player:sendTextMessage(MESSAGE_INFO_DESCR, "You need to unlock another waypoint in order to use waypoints.")
        end
    local waypoint = false

    for i=1,#waypointList do
        if waypointList[i].actionId == item.actionid then
            waypoint = waypointList[i]
        end
    end

    if waypoint then
        if player:getStorageValue(waypoint.actionId) ~= 1 then
            player:setStorageValue(waypoint.actionId,1)
            player:sendTextMessage(MESSAGE_INFO_DESCR, "You have unlocked waypoint to ".. waypoint.name ..".")
            return true
        end

        local window = ModalWindow(5000, "Waypoints", "Waypoint: " .. waypoint.name .. "\\n")

        local unlockedWps = 0

        for i=1,#waypointList do
            if player:getStorageValue(waypointList[i].actionId) == 1 then
                if waypointList[i].actionId ~= item.actionid then
                    unlockedWps = unlockedWps+1
                    window:addChoice(i, waypointList[i].name)
                end
            end
        end

        if unlockedWps ~= 0 then
            window:sendToPlayer(player)
        end

        return true
    end
end

for j=1,#waypointList do
    waypoints:aid(waypointList[j].actionId)
end

waypoints:type("stepin")
waypoints:register()
'''

# a mocked engine: run the script, step a fresh character onto waypoint 7001 twice; print what it saw
HARNESS = r'''
local unlockAll = (arg and arg[2]) == "on"
ChaosWaypointsCore = nil
dofile("data/scripts/chaos/waypoints_core.lua")
ChaosWaypointsCore.loaded = {unlockAll = unlockAll}
MESSAGE_INFO_DESCR = 1
Position = function(x, y, z) return {x = x, y = y, z = z} end
local ev
MoveEvent = function()
  ev = {aid = function() end, type = function() end, register = function() end}
  return ev
end
local menus = {}
ModalWindow = function(id, title, text)
  local w = {choices = {}}
  function w:addChoice(i, name) self.choices[#self.choices + 1] = name end
  function w:sendToPlayer() menus[#menus + 1] = table.concat(self.choices, ",") end
  return w
end
local store, msgs, reads = {}, {}, 0
local player = {
  isPlayer = function() return true end,
  getStorageValue = function(_, k) reads = reads + 1; return store[k] or -1 end,
  setStorageValue = function(_, k, v) store[k] = v end,
  sendTextMessage = function(_, _, t) msgs[#msgs + 1] = t end,
}
local real_print = print
print = function() end
dofile(arg[1])
print = real_print
local r1 = ev.onStepIn(player, {actionid = 7001}, {}, {})
local r2 = ev.onStepIn(player, {actionid = 7001}, {}, {})
local written = 0
for _ in pairs(store) do written = written + 1 end
print(table.concat(menus, "|") .. ";" .. #msgs .. ";" .. written .. ";" .. reads .. ";" .. tostring(r1) .. tostring(r2))
'''

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def run(folder, *extra):
    p = subprocess.run([sys.executable, '-I', TOOL, folder] + list(extra), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout.decode()


new, n, added, note = P.patch(BASE)
check(note is None and n == 3 and added, 'three storage tests, the block added: %s %s %s' % (n, added, note))
check('getStorageValue(' not in new.replace('getStorageValue = ', ''), 'no storage read left in the script')
check(new.count('chaosWaypointOpen(player, waypointList[i].actionId)') == 2, 'the count and the menu ask the core')
check('if not chaosWaypointOpen(player, waypoint.actionId) then' in new, 'the first-step unlock asks the core')
check(new.index(P.MARK) < new.index('local waypoints = MoveEvent()'), 'the block comes before the MoveEvent')
check(new.count(P.MARK + ':') == 1 and new.count(P.MARK + ' end') == 1, 'the block once')
back = new.replace('\n'.join(P.BLOCK) + '\n\n', '')
back = back.replace('not chaosWaypointOpen(player, waypoint.actionId)', 'player:getStorageValue(waypoint.actionId) ~= 1')
back = back.replace('chaosWaypointOpen(player, waypointList[i].actionId)', 'player:getStorageValue(waypointList[i].actionId) == 1')
check(back == BASE, 'nothing else changed')
check(P.patch(new) == (new, 0, False, None), 'idempotent')
crlf = BASE.replace('\n', '\r\n')
out = P.patch(crlf)[0]
check(out.count('\n') == out.count('\r\n'), 'CRLF kept')
odd = BASE.replace('player:getStorageValue', 'player:getOther')
check(P.patch(odd)[3] is not None and P.patch(odd)[0] == odd, 'a script without the storage tests is left alone')
check(P.patch(BASE.replace('MoveEvent()', 'Other()'))[3] is not None, 'a script without a MoveEvent is left alone')
check(P.patch('x = player:getStorageValue(a.actionId) == 10\n')[1] == 0, 'only the test against 1')

luas = [b for b in ('luajit', 'lua5.3') if shutil.which(b)]
with tempfile.TemporaryDirectory() as d:
    rc, out = run(d)
    check(rc == 0 and 'not there' in out, 'a data folder without the script: %s' % out)
    path = os.path.join(d, P.SCRIPT)
    os.makedirs(os.path.dirname(path))
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(BASE)
    rc, out = run(d, '--dry-run')
    check(rc == 0 and 'dry run' in out and open(path, encoding='utf-8').read() == BASE, 'dry run writes nothing')
    rc, out = run(d)
    check(rc == 0 and '3 storage test' in out, 'patched: %s' % out)
    check(open(path, encoding='utf-8').read() == new, 'the file is the patched text')
    rc, out = run(d)
    check(rc == 0 and 'already' in out, 'second run: %s' % out)
    check(not os.path.exists(path + '.tmp'), 'no temporary file left')
    harness = os.path.join(d, 'harness.lua')
    with open(harness, 'w', encoding='utf-8') as f:
        f.write(HARNESS)
    for lua in luas:
        def sim(mode, script=path):
            p = subprocess.run([lua, harness, script, mode], cwd=SERVER, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            return p.stdout.decode().strip()
        on = sim('on')
        check(on == 'Town A,Town C|Town A,Town C;0;0;0;truetrue', '%s, unlockAll on: the menu at once, no storage: %s' % (lua, on))
        off = sim('off')
        check(off == ';2;1;11;truetrue', '%s, off: the base rule (unlock message, no menu with one open): %s' % (lua, off))
        base = os.path.join(d, 'base.lua')
        with open(base, 'w', encoding='utf-8') as f:
            f.write(BASE)
        check(sim('on', base) == off, '%s: off behaves as the unpatched base script' % lua)
    check(luas, 'luajit or lua5.3 on PATH for the mocked run')

for bad in ([], ['a', 'b'], ['--x']):
    p = subprocess.run([sys.executable, '-I', TOOL] + bad, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    check(p.returncode == 1, 'bad args %s' % bad)

text = open(os.path.join(HERE, 'install_all.py'), encoding='utf-8').read()
check("def step_waypoints(" in text and "'patch_base_waypoints.py'" in text, 'install_all.py has the step')
check("'waypoints')" in text and 'waypoints    tools/patch_base_waypoints.py' in text, 'the step is in STEPS and the docstring')

print('patch_base_waypoints_test: %s' % ('OK' if not fails else '%d FAILED' % fails))
sys.exit(1 if fails else 0)
