-- Chaos.inCombat (chaos_constants.lua): PZ-locked, or the battle condition outside a protection zone.
-- Run from server/: luajit tests/incombat_test.lua (also lua5.3)
local fails = 0
local function check(c, what)
	if not c then
		fails = fails + 1
		print("FAIL: " .. what)
	end
end

CONDITION_INFIGHT = 1
TILESTATE_PROTECTIONZONE = 2
local pz = {}
function Tile(pos)
	return {hasFlag = function(_, f) return f == TILESTATE_PROTECTIONZONE and pz[pos.x] == true end}
end
local _print = print
print = function() end
dofile("data/scripts/chaos/chaos_constants.lua")
print = _print

local function player(x, locked, infight)
	return {
		isPzLocked = function() return locked end,
		hasCondition = function(_, c) return c == CONDITION_INFIGHT and infight end,
		getPosition = function() return {x = x, y = 0, z = 7} end
	}
end
pz[1] = true

check(Chaos.inCombat(player(1, true, true)) == true, "PZ-locked counts, even on a PZ tile")
check(Chaos.inCombat(player(2, false, true)) == true, "the battle condition outside a PZ counts")
check(Chaos.inCombat(player(1, false, true)) == false, "the battle condition in a PZ does not count (owner 2026-10-30)")
check(Chaos.inCombat(player(2, false, false)) == false, "no fight")
check(Chaos.inCombat({}) == false, "a broken player object is not in combat")

print(fails == 0 and "incombat_test: ok" or ("incombat_test: " .. fails .. " failure(s)"))
os.exit(fails == 0 and 0 or 1)
