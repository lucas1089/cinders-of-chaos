-- Run from the server/ folder: luajit tests/weapon_power_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers weapon_power_core.lua and weapon_power_config.lua (server/README.md "Auto attack power"): the config shape, the
-- level factor (never below 1, never dropping with the level, interpolated), the skill factor (1 at the typical skill, more
-- above, less below, clamped, monotonic) and that a hit scales with BOTH the skill and the level.
dofile("data/scripts/chaos/weapon_skill_core.lua")
dofile("data/scripts/chaos/weapon_power_core.lua")
local P = ChaosWeaponPower
local S = ChaosWeaponSkill

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function near(a, b, tol, what)
	ok(math.abs(a - b) <= tol, what .. ": " .. tostring(a) .. " ~ " .. tostring(b))
end

-- ------------------------------------------------------------------ the config
local c = P.config
ok(#c.levels >= 2, "levels")
for i = 2, #c.levels do
	ok(c.levels[i] > c.levels[i - 1], "levels ascend")
end
for _, kind in ipairs({"melee", "distance", "wand", "fist"}) do
	ok(#c[kind] == #c.levels, kind .. ": a factor per level")
	for i, v in ipairs(c[kind]) do
		ok(v >= 1 and v <= 3, kind .. ": factor " .. v .. " within 1 .. 3 (never a cut, never over x3)")
		if i > 1 then
			ok(v >= c[kind][i - 1], kind .. ": never drops with the level")
		end
	end
end
ok(c.skill.exponent > 0 and c.skill.min > 0 and c.skill.min < 1 and c.skill.max > 1, "skill clamp around 1")

-- ------------------------------------------------------------------ the level factor
near(P.levelFactor("melee", 300), 1, 1e-9, "melee is on its share already: 1")
near(P.levelFactor("distance", 100), 1, 1e-9, "a launcher is above its share at level 100: 1")
ok(P.levelFactor("distance", 1000) > 1.1, "a launcher is lifted at level 1000 (" .. P.levelFactor("distance", 1000) .. ")")
ok(P.levelFactor("distance", 2000) > P.levelFactor("distance", 1000), "and more at 2000")
ok(P.levelFactor("wand", 300) > 1.5, "a wand is lifted at level 300")
near(P.levelFactor("distance", 2000), c.distance[#c.distance], 1e-9, "flat at the last level")
near(P.levelFactor("distance", 99999), c.distance[#c.distance], 1e-9, "flat far above")
near(P.levelFactor("wand", 0), c.wand[1], 1e-9, "flat below the first level")
near(P.levelFactor("sword", 500), 1, 1e-9, "unknown kind: 1")
near(P.levelFactor("skill", 500), 1, 1e-9, "the skill table is not a kind")
-- between two levels the factor is linear
do
	local a, b = c.levels[#c.levels - 2], c.levels[#c.levels - 1]
	local fa, fb = P.levelFactor("distance", a), P.levelFactor("distance", b)
	near(P.levelFactor("distance", (a + b) / 2), (fa + fb) / 2, 1e-9, "linear between two levels")
end
-- monotonic over the whole range
for _, kind in ipairs({"melee", "distance", "wand", "fist"}) do
	local last = 0
	for lv = 1, 2500, 7 do
		local f = P.levelFactor(kind, lv)
		ok(f >= last - 1e-12 and f >= 1, kind .. " level " .. lv .. ": monotonic and >= 1")
		last = f
	end
end

-- ------------------------------------------------------------------ the skill factor
for _, lv in ipairs({10, 50, 100, 300, 600, 1000, 2000}) do
	local typ = S.typical("skill", lv)
	near(P.skillFactor(lv, typ), 1, 1e-9, "level " .. lv .. ": the typical skill is x1")
	ok(P.skillFactor(lv, typ * 1.2) > 1, "level " .. lv .. ": more skill, more damage")
	ok(P.skillFactor(lv, typ * 0.8) < 1, "level " .. lv .. ": less skill, less damage")
	ok(P.skillFactor(lv, typ * 1.2) > P.skillFactor(lv, typ * 1.1), "level " .. lv .. ": monotonic")
	ok(P.skillFactor(lv, typ * 100) == c.skill.max, "level " .. lv .. ": clamped above")
	ok(P.skillFactor(lv, typ * 0.01) == c.skill.min, "level " .. lv .. ": clamped below")
end
-- +10 skill at level 1000 (skill 140): the engine gives +5%, the exponent adds about as much again
do
	local engine = S.maxHit(1000, 150, 65) / S.maxHit(1000, 140, 65)
	local total = engine * P.skillFactor(1000, 150) / P.skillFactor(1000, 140)
	ok(engine > 1.04 and engine < 1.07, "engine: +10 skill is about +5% (" .. engine .. ")")
	ok(total > 1.09, "with the factor: +10 skill is over +9% (" .. total .. ")")
end
ok(P.skillFactor(300, nil) == 1 and P.skillFactor(300, 0) == 1 and P.skillFactor(300, "x") == 1, "no skill: 1")

-- ------------------------------------------------------------------ a hit scales with BOTH the skill and the level
-- the mean hit: the engine's maximum (weapon_skill_core.lua) / 2 x the power factor
local function hit(kind, level, skill, attack)
	return S.maxHit(level, skill, attack) / 2 * P.hitFactor(kind, level, skill)
end
local attack = 65 -- gear attack flat above level 1000
ok(hit("distance", 2000, 140, attack) > hit("distance", 1000, 140, attack) * 1.3,
	"same skill and gear: level 2000 hits over 1.3x level 1000 (the engine alone: " ..
	S.maxHit(2000, 140, attack) / S.maxHit(1000, 140, attack) .. "x)")
ok(hit("melee", 1000, 160, attack) > hit("melee", 1000, 140, attack) * 1.15, "same level: +20 skill is over +15%")
ok(hit("melee", 1000, 120, attack) < hit("melee", 1000, 140, attack) * 0.9, "same level: -20 skill is under -10%")
-- the typical character: a launcher at 200 is the engine's hit as before (no balance jump below the lift); at 300 it is
-- lifted 8% since O176 (the Ranger line's rotation is 20% stronger, weapon_power_config.lua)
near(P.hitFactor("distance", 200, S.typical("skill", 200)), 1, 1e-9, "level 200 typical launcher: unchanged")
near(P.hitFactor("distance", 300, S.typical("skill", 300)), 1.08, 1e-9, "level 300 typical launcher: lifted 8% (O176)")
-- a wand: no skill factor (the magic level's own factor in weapon_skill_core), only the level
near(P.hitFactor("wand", 300, 999), P.levelFactor("wand", 300), 1e-9, "a wand ignores the skill argument")
near(P.hitFactor("wand", 300), P.levelFactor("wand", 300), 1e-9, "a wand without a skill")
near(P.hitFactor("melee", 400), 1, 1e-9, "melee without a skill: the level factor, 1 (level 400; 500 and up is 1.01 since the quest spells)")
-- a Monk's fists: the fist kind scales with the fist skill like melee, 1 at the typical skill, and never cuts the level factor
for _, lv in ipairs({50, 300, 1000, 2000}) do
	near(P.hitFactor("fist", lv, S.typical("skill", lv)), P.levelFactor("fist", lv), 1e-9, "level " .. lv .. ": typical fist skill is the level factor")
	ok(P.hitFactor("fist", lv, S.typical("skill", lv) * 1.2) > P.hitFactor("fist", lv, S.typical("skill", lv)), "level " .. lv .. ": more fist skill, more damage")
end
near(P.hitFactor("fist", 500), P.levelFactor("fist", 500), 1e-9, "fist without a skill: the level factor")
ok(P.levelFactor("fist", 1) >= 1 and P.levelFactor("fist", 2400) >= 1, "fist factor never cuts")

-- ------------------------------------------------------------------ the tooltip's estimated DPS includes it
dofile("data/scripts/chaos/weapon_balance_core.lua")
dofile("data/scripts/chaos/weapon_dps_core.lua")
local D = ChaosWeaponDps
do
	local typ = S.typical("skill", 1500)
	local base = (300 + D.maxHit(1500, typ, 70)) / 2 * ChaosWeaponBalance.hitFactor(1500, true, "crossbow") / 3
	near(D.estimate({level = 1500, skill = typ, attack = 70, interval = 3000, launcher = "crossbow", twoHanded = true}),
		base * P.levelFactor("distance", 1500), 1e-6, "tooltip: a crossbow at level 1500 carries the level factor")
	ok(D.estimate({level = 1500, skill = typ * 1.2, attack = 70, interval = 3000, launcher = "crossbow", twoHanded = true})
		> D.estimate({level = 1500, skill = typ, attack = 70, interval = 3000, launcher = "crossbow", twoHanded = true}) * 1.2,
		"tooltip: 20% more skill is over 20% more estimate")
	near(D.estimate({level = 1500, skill = typ, attack = 70, interval = 3000, launcher = "crossbow", styleFactor = 1}),
		(300 + D.maxHit(1500, typ, 70)) / 2 / 3, 1e-6, "tooltip: an explicit style factor stands for the whole multiplier")
end

print(string.format("weapon_power_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
