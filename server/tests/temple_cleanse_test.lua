-- Run from the server/ folder: luajit tests/temple_cleanse_test.lua (CI runs it with LuaJIT and Lua 5.3)
dofile("data/scripts/chaos/temple_cleanse_core.lua")
local K = ChaosTempleCleanseCore
local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
eq(K.shouldClear({inProtectionZone = true, hasDebuff = true}), true, "debuff in the temple")
eq(K.shouldClear({inProtectionZone = true, hasDebuff = false}), false, "nothing to clear")
eq(K.shouldClear({inProtectionZone = false, hasDebuff = true}), false, "outside a protection zone")
eq(K.shouldClear({inProtectionZone = true, hasDebuff = true, pzLocked = true}), false, "PvP lock stays")
eq(K.shouldClear({inProtectionZone = true, hasDebuff = true, skulled = true}), false, "a skull stays")
eq(K.shouldClear(nil), false)
local has = {}
for _, c in ipairs(K.conditions) do has[c] = true end
eq(has.CONDITION_FIRE and has.CONDITION_INFIGHT and has.CONDITION_POISON, true, "fire, poison and the battle lock")
print("temple_cleanse_test: " .. n .. " checks OK")
