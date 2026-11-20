-- Run from the server/ folder: luajit tests/health_factor_test.lua && lua5.3 tests/health_factor_test.lua (CI runs both)
-- O686 phase 3: the door every monster health goes through (Chaos.healthFactor / Chaos.scaleHealth in chaos_constants.lua, reading
-- data/lib/chaos_spell_ranks.lua and spell_ranks_config.lua `health`): 1 while the ranks are off, the curve when on, never an error,
-- and the planned levels the systems read it at (uber, raid, guild boss, Omen guardian, Greater Rift) are in their configs.
-- Which files call the door: tools/ci/check_health_paths.py.

local checks, fails = 0, 0
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
local function near(a, b, tol, what)
	ok(type(a) == "number" and math.abs(a - b) <= tol, what .. ": " .. tostring(a) .. " vs " .. tostring(b))
end

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
ok(type(Chaos.healthFactor) == "function" and type(Chaos.scaleHealth) == "function", "the door exists")
dofile("data/lib/chaos_spell_ranks.lua")
local cfg = ChaosSpellRanksConfig
eq(cfg.enabled, false, "ships switched off")

-- ---------------------------------------------------------------- off: nothing moves
for _, lv in ipairs({1, 99, 100, 500, 1000, 2500, 9999}) do
	eq(Chaos.healthFactor(lv), 1, "off: x1 at level " .. lv)
	eq(Chaos.scaleHealth(12345, lv), 12345, "off: health unchanged at level " .. lv)
end
eq(Chaos.scaleHealth(0.5, 1000), 0.5, "off: a decimal is not rounded")
eq(Chaos.healthFactor(nil), 1, "no level: x1")
eq(Chaos.healthFactor("abc"), 1, "a non number: x1")
eq(Chaos.scaleHealth(nil, 1000), nil, "no health: nothing")

-- ---------------------------------------------------------------- on: the curve
cfg.enabled = true
eq(Chaos.healthFactor(1), 1, "on: below 100 x1")
eq(Chaos.healthFactor(99), 1, "on: level 99 x1")
near(Chaos.healthFactor(100), 1.02, 1e-9, "on: level 100")
near(Chaos.healthFactor(1000), 1.21, 1e-9, "on: level 1000")
near(Chaos.healthFactor(2000), 1.31, 1e-9, "on: level 2000 (the Greater Rift)")
near(Chaos.healthFactor(2500), 1.39, 1e-9, "on: level 2500")
near(Chaos.healthFactor(5000), 1.39, 1e-9, "on: flat above the last point")
near(Chaos.healthFactor("1000"), 1.21, 1e-9, "on: a numeric string")
eq(Chaos.healthFactor(nil), 1, "on: no level x1")
eq(Chaos.scaleHealth(1000, 1000), 1210, "on: 1000 health at level 1000")
eq(Chaos.scaleHealth(1000, 50), 1000, "on: below 100 unchanged")
eq(Chaos.scaleHealth(1, 2500), 1, "on: at least 1")
eq(Chaos.scaleHealth(580000000, 2500), 806200000, "on: the tower's health cap x H")
eq(Chaos.scaleHealth(2100000000, 2500), 2147000000, "on: never past the engine's 32 bit health")
eq(Chaos.scaleHealth(2147483000, 2500), 2147483000, "on: a value already above the guard stays")
local last = 1
for lv = 1, 2600, 10 do
	local f = Chaos.healthFactor(lv)
	ok(f >= last - 1e-12, "on: the curve never falls at level " .. lv)
	last = f
end
cfg.enabled = false
eq(Chaos.healthFactor(1000), 1, "off again: x1")

-- ---------------------------------------------------------------- the planned levels of the fixed contents
local function load(name)
	return dofile("data/scripts/chaos/" .. name)
end
eq(load("uber_config.lua").model.refLevel, 1000, "uber: planned for level 1000")
eq(load("raid_config.lua").model.refLevel, 1000, "raid: planned for level 1000")
eq(load("guildboss_config.lua").model.refLevel, 600, "guild boss: planned for level 600")
local rift = load("rift_config.lua")
eq(rift.omen.refLevel, 1000, "Omen guardian: planned for level 1000")
eq(rift.greater.healthLevel, 2000, "Greater Rift: H read at level 2000 (a tier serves 1500 to 2500)")

print(string.format("health_factor_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
