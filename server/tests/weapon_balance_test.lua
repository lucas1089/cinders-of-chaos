-- Run from the server/ folder: luajit tests/weapon_balance_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers owner debug item 47 (server/data/spells/README.md "Weapon damage per second"): the generated factor table
-- (weapon_balance_config.lua, server/tools/weapon_sim.py), its interpolation, and the damage per second the factors give
-- at levels 8 .. 300: every weapon style of one tier within 10% of the others (the Lua side of weapon_sim.py --check).
dofile("data/scripts/chaos/weapon_balance_core.lua")
local W = ChaosWeaponBalance

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
local function near(a, b, tol, what)
	ok(math.abs(a - b) <= tol, what .. ": " .. tostring(a) .. " ~ " .. tostring(b))
end

-- ------------------------------------------------------------------ the table
local c = W.config
eq(#c.levels, #c.twoHanded, "twoHanded has a value per level")
eq(#c.levels, #c.bow, "bow has a value per level")
eq(#c.levels, #c.crossbow, "crossbow has a value per level")
for i = 2, #c.levels do
	ok(c.levels[i] > c.levels[i - 1], "levels ascend")
end
for _, style in ipairs({"twoHanded", "bow", "crossbow"}) do
	for i, v in ipairs(c[style]) do
		ok(v > 0.5 and v < 2, style .. " factor " .. i .. " is a sane multiplier: " .. v)
	end
end
eq(c.typeFactor.sword, 1, "sword typeFactor")

-- ------------------------------------------------------------------ interpolation
near(W.factor("twoHanded", 8), c.twoHanded[2], 1e-9, "an anchor")
near(W.factor("twoHanded", 1), c.twoHanded[1], 1e-9, "the first anchor")
near(W.factor("twoHanded", 0), c.twoHanded[1], 1e-9, "below the first: flat")
near(W.factor("twoHanded", 5000), c.twoHanded[#c.twoHanded], 1e-9, "above the last: flat")
near(W.factor("bow", 40), (W.factor("bow", 30) + W.factor("bow", 50)) / 2, 0.2, "between two anchors")
near(W.interp({10, 20}, {1, 3}, 15), 2, 1e-9, "linear")
eq(W.factor("sword", 100), 1, "an unknown style is 1")
eq(W.hitFactor(100, false, nil, "sword"), 1, "one-handed: 1")
near(W.hitFactor(100, true, nil, "axe"), W.factor("twoHanded", 100), 1e-9, "two-handed melee")
near(W.hitFactor(100, true, "crossbow", nil), W.factor("crossbow", 100), 1e-9, "a launcher is two-handed, but its own factor")

-- ------------------------------------------------------------------ the damage per second at levels 8 .. 300
-- the model of weapon_sim.py: tier attack by level (install_gear_sets.py CURVES), skill 10 + 0.4 x (level - 8)
local anchors = {8, 50, 100, 200, 400, 700, 1000, 1500, 2000}
local curves = {
	attack = {16, 40, 46, 49, 53, 57, 61, 65, 69},
	bow = {31, 38, 68, 71, 73, 76, 79, 82, 85},
	hit = {90, 93, 95, 95, 96, 96, 97, 97, 98}
}
local function curve(name, level)
	return W.interp(anchors, curves[name], level)
end
local function maxHit(level, skill, attack)
	return math.floor(level / 5) + ((skill / 4 + 1) * (attack / 3) * 1.03)
end
local function dps(style, level)
	local skill = 10 + 0.4 * (level - 8)
	local hit, interval, chance, low = 0, 2000, 1, 0
	if style == "melee1" then
		hit = maxHit(level, skill, curve("attack", level))
	elseif style == "melee2" then
		hit, interval = maxHit(level, skill, curve("attack", level) + 3), 3000
	else
		local extra = style == "crossbow" and 3 or 0
		hit, interval, chance = maxHit(level, skill, curve("bow", level) + extra), 3000, curve("hit", level) / 100
		low = math.ceil(level * 0.2)
	end
	local factor = ({melee1 = 1, melee2 = W.factor("twoHanded", level), bow = W.factor("bow", level),
		crossbow = W.factor("crossbow", level)})[style]
	return (low + hit) / 2 * chance * factor / interval * 1000
end
-- the launchers keep the flat x1.6 while they are not aligned (weapon_sim.py RANGED_ALIGN); aligned, they are gated too
local aligned = false
for _, v in ipairs(c.bow) do aligned = aligned or v ~= 1.6 end
for _, v in ipairs(c.crossbow) do aligned = aligned or v ~= 1.6 end
local gated = aligned and {"melee1", "melee2", "bow", "crossbow"} or {"melee1", "melee2"}
print("weapon_balance_test: launchers " .. (aligned and "aligned" or "kept at the flat 1.6") .. ", gated styles: " .. table.concat(gated, ", "))
local worst = 0
for level = 8, 300 do
	local lo, hi = math.huge, 0
	for _, style in ipairs(gated) do
		local v = dps(style, level)
		lo, hi = math.min(lo, v), math.max(hi, v)
	end
	worst = math.max(worst, hi / lo - 1)
	ok(hi / lo <= 1.10, "level " .. level .. ": the gated styles are within 10% (" .. string.format("%.1f%%", (hi / lo - 1) * 100) .. ")")
end
print(string.format("weapon_balance_test: widest gap between two gated styles at levels 8-300: %.1f%%", worst * 100))

if fails > 0 then
	print(fails .. " of " .. checks .. " checks failed")
	os.exit(1)
end
print("weapon_balance_test: OK (" .. checks .. " checks)")
