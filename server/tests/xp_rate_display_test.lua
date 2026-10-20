-- Run from the server/ folder: luajit tests/xp_rate_display_test.lua (CI runs it with LuaJIT and Lua 5.3)
dofile("data/scripts/chaos/xp_rate_display_core.lua")
local R = ChaosXpRateDisplay
local fails = 0
local function eq(a, b, what)
	if a ~= b then fails = fails + 1 print("FAIL " .. what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
end
eq(R.percent(100, 100), 100, "no bonus is 100%")
eq(R.percent(250, 100), 250, "bonuses add up")
eq(R.percent(5, 100), 5, "a small rate")
eq(R.percent(10, 0), nil, "no base: unknown")
eq(R.percent(0, 100), nil, "no experience: unknown")
eq(R.percent(1e12, 1), R.MAX, "capped at uint16")
eq(R.baseGain(150, 100), 150, "no stamina bonus: as is")
eq(R.baseGain(150, 150), 100, "stamina x1.5 taken out of the base")
eq(R.baseGain(nil, 100), nil, "nil in, nil out")
eq(R.baseGain(0, 100), R.MIN, "never zero")
print(string.format("xp_rate_display_test: %d failures", fails))
if fails > 0 then os.exit(1) end
