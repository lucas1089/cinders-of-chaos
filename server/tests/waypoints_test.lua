-- Run from the server/ folder: luajit tests/waypoints_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the base waypoints for everyone (O386, data/scripts/chaos/waypoints_core.lua, waypoints_config.lua): the
-- switch is on in the shipped config, every waypoint is open with it on (new character, old character, any storage
-- value) and no storage is read, with it off the base rule (storage 1 = open), a missing or broken config counts as
-- off, and the action id range is the base script's (7000-7017, 18 towns). The patch of the base script itself:
-- tools/patch_base_waypoints_test.py (mocked engine run).
dofile("data/scripts/chaos/waypoints_core.lua")
local W = ChaosWaypointsCore
local cfg = dofile("data/scripts/chaos/waypoints_config.lua")

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- the shipped config: owner 2026-11-03, every waypoint for every character
eq(cfg.unlockAll, true, "unlockAll on")
eq(cfg.firstAid, 7000, "first action id")
eq(cfg.lastAid, 7017, "last action id")
eq(cfg.lastAid - cfg.firstAid + 1, 18, "18 waypoints, one per base town")

-- the rule
for _, v in ipairs({-1, 0, 1, 2}) do
	eq(W.unlocked({unlockAll = true}, v), true, "on: open with storage " .. v)
end
eq(W.unlocked({unlockAll = true}, nil), true, "on: open without a storage value")
eq(W.unlocked({unlockAll = false}, 1), true, "off: stepped on (1) is open")
eq(W.unlocked({unlockAll = false}, -1), false, "off: a new character has it closed")
eq(W.unlocked({unlockAll = false}, 0), false, "off: 0 is closed")
eq(W.unlocked({}, 1), true, "no switch: the base rule, open")
eq(W.unlocked({}, -1), false, "no switch: the base rule, closed")
eq(W.unlocked(nil, -1), false, "no config: the base rule")
eq(W.unlocked({unlockAll = "yes"}, -1), false, "only true switches it on")

-- the base script's call: no storage read while on, the storage while off
local reads = 0
local player = {getStorageValue = function(_, k)
	reads = reads + 1
	return k == 7003 and 1 or -1
end}
W.loaded = nil
eq(W.cfg().unlockAll, true, "the config file is read")
for aid = cfg.firstAid, cfg.lastAid do
	eq(W.isUnlocked(player, aid), true, "on: waypoint " .. aid .. " open")
end
eq(reads, 0, "on: no storage read")
W.loaded = {unlockAll = false}
eq(W.isUnlocked(player, 7003), true, "off: the stepped one open")
eq(W.isUnlocked(player, 7004), false, "off: another one closed")
eq(reads, 2, "off: the storage read")
W.loaded = false
eq(W.cfg().unlockAll, nil, "a broken config counts as off")
eq(W.isUnlocked(player, 7004), false, "a broken config: the base rule")
W.loaded = nil

print(string.format("waypoints_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
