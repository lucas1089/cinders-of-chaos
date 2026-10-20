-- Run from the server/ folder: luajit tests/weapon_dps_test.lua (and lua5.3; CI runs both)
-- weapon_dps_core.lua: the estimated damage per second of a weapon, the same model as tools/weapon_sim.py.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function near(a, b, tol, what)
	ok(a ~= nil and math.abs(a - b) <= tol, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/weapon_balance_core.lua")
local D = dofile("data/scripts/chaos/weapon_dps_core.lua")

-- the engine formula: level 100, skill 70, attack 40 -> 20 + (18.5 * 13.33 * 1.03) = 20 + 254.0 -> 274
ok(D.maxHit(100, 70, 40) == 274, "max hit " .. D.maxHit(100, 70, 40))
ok(D.maxHit(100, 70, 40, 2) == 147, "defensive stance halves the attack part " .. D.maxHit(100, 70, 40, 2))
ok(D.maxHit(8, 10, 0) == 1, "level part only")

-- one-handed: mean = top / 2, 2 s
near(D.estimate({level = 100, skill = 70, attack = 40, interval = 2000}), 274 / 2 / 2, 1e-9, "one-handed")
-- interval scales it
near(D.estimate({level = 100, skill = 70, attack = 40, interval = 1000}), 274 / 2, 1e-9, "1 s interval")
-- two-handed: the style factor of the level (weapon_balance_config) and 3 s
local f2 = ChaosWeaponBalance.hitFactor(100, true, nil, "sword")
ok(f2 > 1.3 and f2 < 1.7, "two-handed factor " .. f2)
near(D.estimate({level = 100, skill = 70, attack = 43, interval = 3000, twoHanded = true, weaponType = "sword"}),
	D.maxHit(100, 70, 43) / 2 * f2 / 3, 1e-9, "two-handed sword")
-- launcher: min a fifth of the level, hit chance, style factor
local fb = ChaosWeaponBalance.hitFactor(100, true, "bow")
near(D.estimate({level = 100, skill = 60, attack = 50, interval = 3000, launcher = "bow", twoHanded = true, hitChance = 90}),
	(20 + D.maxHit(100, 60, 50)) / 2 * fb * 0.9 / 3, 1e-9, "bow")
-- a launcher without a hit chance counts as 100%
near(D.estimate({level = 100, skill = 60, attack = 50, interval = 3000, launcher = "bow", styleFactor = 1}),
	(20 + D.maxHit(100, 60, 50)) / 2 / 3, 1e-9, "no hit chance")
-- more skill, more damage
ok(D.estimate({level = 100, skill = 90, attack = 40, interval = 2000}) > D.estimate({level = 100, skill = 70, attack = 40, interval = 2000}), "skill raises it")
-- nothing to estimate
ok(D.estimate({level = 100, skill = 70, attack = 0, interval = 2000}) == nil, "no attack")
ok(D.estimate({level = 100, skill = 70, attack = 40, interval = 0}) == nil, "no interval")
ok(D.estimate({level = 0, skill = 70, attack = 40, interval = 2000}) == nil, "no level")
ok(D.estimate(nil) == nil, "no input")
ok(D.round(137.5) == 138 and D.round(0) == nil and D.round(nil) == nil, "round")

-- agrees with tools/weapon_sim.py's model: one-handed sword at level 100 with its tier attack, the skill the model assumes
local skill = 10 + 0.4 * (100 - 8)
ok(D.estimate({level = 100, skill = skill, attack = 30, interval = 2000}) > 0, "model skill gives a number")

print(string.format("weapon_dps_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
