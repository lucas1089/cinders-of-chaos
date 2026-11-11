-- damage_pool_table.lua: what the one additive damage pool (O473) does to a stack of damage bonuses, before and after.
-- usage (from server/): luajit tools/damage_pool_table.lua [--check]     (also lua5.3)
--
-- COMPUTED FROM ASSUMED PROFILES, NOT MEASURED. The three profiles below are inputs, not data of a live server: how much damage
-- bonus of each source a fresh, a typical and a heavily invested character holds at a level. They follow the sizes of the design of
-- the damage round (a tree supply of 64 raw for the poorest class and 514 for the richest at level 1000, one unique power for a
-- typical build and four to five for an invested one, gems at their caps, Paragon at 0.5 a point to 40 points). Replace them with
-- measured builds when the final re-fit of the round has them (README "Increased damage pool (O473)", "not verified").
--
-- Before: the sources multiply each other: the tree (with the worn Spell Damage, soft cap 150 / H 60), Paragon, the product of the
-- unique passives (clamped to 1.8), the gem of the type (cap 40, physical 12), the card set, Damage to a family (charm, cap 15)
-- with the sword edge, and a brand mastery's free brand. After: the same bonuses are raw percent of ONE pool with the caps of
-- damage_pool_config.lua and the soft cap once. The table prints the damage factor of both and their ratio. --check fails when a
-- profile gets MORE from the pool than from the product (the pool must never raise damage) or when a fresh character moves.
local cfg = dofile("data/scripts/chaos/damage_pool_config.lua")
local S = cfg.sources
local CAP, H = cfg.softCap.cap, cfg.softCap.H
local function soft(raw)
	if raw <= CAP then return raw end
	return CAP + H * math.log(1 + (raw - CAP) / H)
end
local function lin(points, x)
	if x <= points[1][1] then return points[1][2] end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if x <= b[1] then return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]) end
	end
	return points[#points][2]
end

-- O475 (2026-11-10): 200, 850 and 1500 added so the typical row has the levels of the weapon growth table (class_dps_model.py reads it)
local LEVELS = {100, 200, 300, 500, 700, 850, 1000, 1500, 2000}
-- the tree's raw damage percent of the hit's type, with the worn Spell Damage (the soft cap sits on this sum)
local TREE = {
	fresh = {{100, 10}, {300, 20}, {500, 30}, {700, 40}, {1000, 50}, {2000, 60}},
	typical = {{100, 25}, {300, 60}, {500, 95}, {700, 120}, {1000, 150}, {2000, 170}},
	invested = {{100, 50}, {300, 130}, {500, 240}, {700, 350}, {1000, 480}, {2000, 520}},
}
-- the unique powers that give a damage bonus while their condition holds (percent each) and the multiplicative price kept as it was
local UNIQUES = {fresh = {}, typical = {30}, invested = {40, 30, 35, 25}}
-- an elemental damage gem of the type (before the caps; physical gems are lower and not shown)
local GEMS = {fresh = 0, typical = 12, invested = 36}
local CARDSET = {fresh = 0, typical = 0, invested = 4}
local CHARMS = {fresh = 0, typical = 3, invested = 15} -- Damage to the monster family
local EDGE = {fresh = 0, typical = 0, invested = 2} -- the sword's tempo edge at full stacks
local MASTERY_BRAND = {fresh = 0, typical = 0, invested = 15} -- a brand mastery: its free brand (15% of the spell) before, +3 raw after

local function paragon(profile, level)
	local points = math.min(40, math.floor(math.max(0, level - 100) / 10))
	if profile == "fresh" then return 0 end
	if profile == "typical" then return 0.5 * points * 0.5 end
	return 0.5 * points + (level >= 500 and 6 * math.log(1 + 10 / 50) or 0)
end

local function before(profile, level)
	local tree = lin(TREE[profile], level)
	local f = (1 + soft(tree) / 100) * (1 + paragon(profile, level) / 100)
	local u = 1
	for _, b in ipairs(UNIQUES[profile]) do u = u * (1 + b / 100) end
	f = f * math.min(u, 1.8)
	f = f * (1 + math.min(GEMS[profile], 40) / 100)
	f = f * (1 + CARDSET[profile] / 100)
	f = f * (1 + CHARMS[profile] / 100) * (1 + EDGE[profile] / 100)
	f = f * (1 + MASTERY_BRAND[profile] * 0.3 / 100) -- the free brand adds to one spell of the rotation, a share of the damage
	return f
end

local function after(profile, level)
	local raw = lin(TREE[profile], level) + paragon(profile, level)
	local u = 0
	for _, b in ipairs(UNIQUES[profile]) do u = u + math.min(b, S.uniques.each) end
	raw = raw + math.min(u, S.uniques.cap)
	raw = raw + math.min(GEMS[profile], S.gems.cap)
	raw = raw + math.min(CARDSET[profile], S.cardSets.cap)
	raw = raw + math.min(CHARMS[profile] + EDGE[profile], cfg.groups.extras.cap)
	raw = raw + (MASTERY_BRAND[profile] > 0 and S.masteries.each or 0)
	return 1 + soft(raw) / 100
end

-- O475 (2026-11-10): the typical row, as a csv class_dps_model.py reads (server/data/spells/pool_typical.csv): the tree's raw damage
-- percent of the typical profile, the damage factor of the old product and of the one pool. The final re-fit of the round uses the
-- ratio after / before as the pool step of the typical character (the profiles are assumed, see the header). --csv prints it,
-- --check fails when the committed file is not what this script prints.
local function typical_csv()
	local out = {"level,tree_raw,before,after,fresh_before,fresh_after,invested_before,invested_after"}
	for _, level in ipairs(LEVELS) do
		out[#out + 1] = string.format("%d,%.1f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f", level, lin(TREE.typical, level),
			before("typical", level), after("typical", level), before("fresh", level), after("fresh", level),
			before("invested", level), after("invested", level))
	end
	return table.concat(out, "\n") .. "\n"
end
if arg and arg[1] == "--csv" then
	io.write(typical_csv())
	return
end

local rows, bad = {}, {}
local lines = {"| Level | Profile | Before (product) | After (one pool) | After / before |", "|---:|---|---:|---:|---:|"}
for _, level in ipairs(LEVELS) do
	for _, profile in ipairs({"fresh", "typical", "invested"}) do
		local b, a = before(profile, level), after(profile, level)
		lines[#lines + 1] = string.format("| %d | %s | %.2f | %.2f | %.2f |", level, profile, b, a, a / b)
		if a > b + 1e-9 then
			bad[#bad + 1] = string.format("%s at %d: the pool (%.3f) is above the product (%.3f)", profile, level, a, b)
		end
		if profile == "fresh" and math.abs(a / b - 1) > 0.03 then
			bad[#bad + 1] = string.format("fresh at %d moved by %.1f%%", level, (a / b - 1) * 100)
		end
	end
end
print(table.concat(lines, "\n"))
if arg and arg[1] == "--check" then
	local f = io.open("data/spells/pool_typical.csv", "r")
	local committed = f and f:read("*a") or ""
	if f then f:close() end
	if committed ~= typical_csv() then
		bad[#bad + 1] = "data/spells/pool_typical.csv is out of date (luajit tools/damage_pool_table.lua --csv > data/spells/pool_typical.csv)"
	end
	for _, m in ipairs(bad) do print("FAIL " .. m) end
	if #bad > 0 then os.exit(1) end
	print("damage pool table: ok (the pool never raises a profile over the old product; a fresh character moves under 3%)")
end
