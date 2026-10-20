-- Run from the server/ folder: luajit tests/absorb_ceiling_test.lua (and lua5.3; CI runs both)
-- Global absorb ceiling of 75 percent per combat type (engine patch 0049, server/README.md "Absorb ceiling").
-- ChaosItemMods.effectiveAbsorb mirrors Player::blockHit after the patch (equipment, each applied to what was left, plus
-- the storage absorbs the Lua event takes off afterwards), and the checks read the patch for the constant it carries.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

Chaos = {}
dofile("data/lib/chaos_item_mods.lua")
local M = ChaosItemMods or Chaos.ItemMods
assert(M, "ChaosItemMods missing")

eq(M.config.absorbCeiling, 75, "ceiling config")

-- the patch carries the same number, and the one place to change it
local f = assert(io.open("src-patches/0049-absorb-ceiling.patch", "r"))
local patch = f:read("*a")
f:close()
eq(tonumber(patch:match("CHAOS_ABSORB_CEILING_PERCENT = (%d+);")), M.config.absorbCeiling, "patch constant")
eq(select(2, patch:gsub("CHAOS_ABSORB_CEILING_PERCENT = %d+;", "")), 1, "constant defined once")

local A = M.effectiveAbsorb
-- under the ceiling: unchanged (equipment multiplies, storages add: 50% then 20% storage = 1 - 0.5 * 0.8)
eq(A({50}, 0), 50, "one item under")
eq(A({10, 10}, 0), 19, "two items multiply (stock rule)")
eq(A({}, 60), 60, "storage only")
eq(A({50}, 20), 60, "item and storage under")
-- over the ceiling: held at 75
eq(A({50, 50, 50}, 0), 75, "gear alone over")
eq(A({50}, 50), 75, "exactly the ceiling")
eq(A({60}, 60), 75, "item and storage over")
eq(A({90, 90}, 70), 75, "far over")
eq(A({30}, 75), 75, "storage at the ceiling: equipment adds nothing")
eq(A({30}, 100), 100, "storage past the ceiling is the Lua event's (README: keep the tree at or under 75)")
eq(A({}, 0), 0, "nothing")
eq(A({-20}, 0), -20, "a negative absorb (weakness) is not capped")

print(string.format("absorb_ceiling_test: %d checks ok", checks))
