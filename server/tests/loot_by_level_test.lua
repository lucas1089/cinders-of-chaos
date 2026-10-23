-- Run from the server/ folder: luajit tests/loot_by_level_test.lua (and lua5.3; CI runs it)
-- Loot by monster level (owner 2026-10-21, "Ajuste o loot de acordo com o lvl só monstro"; server/README.md "Loot by
-- monster level"): pace_core.lua P.smooth / P.factors (coins, junkKeep, notable) / P.isNotable / P.levelPlan /
-- P.coinStacks, the shipped curves, the economy model of every band (tools/loot_model.lua: gold and items per hour
-- before and after at the pack model's kills per hour), the two widows of the beta report per kill, and a Monte Carlo
-- of the core plan against the model. The thinning ignores the killer: tests/lootline_corpse_test.lua runs the loot
-- layer for owners of different levels and parties.
local checks, failures = 0, 0
local function check(v, m)
	checks = checks + 1
	if not v then
		failures = failures + 1
		print("FAIL " .. tostring(m))
	end
end
local function eq(a, b, m) check(a == b, tostring(m) .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b, eps, m) check(math.abs(a - b) <= eps, tostring(m) .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/scripts/chaos/pace_core.lua")
local P = ChaosPaceCore
local cfg = dofile("data/scripts/chaos/pace_config.lua")
local ll = cfg.lootLevel

-- ---------------------------------------------------------------- P.smooth
do
	local pts = {{100, 1.0}, {300, 0.6}, {500, 0.3}, {800, 0.25}, {1000, 0.4}}
	for _, p in ipairs(pts) do
		near(P.smooth(pts, p[1]), p[2], 1e-12, "smooth: through the point " .. p[1])
	end
	eq(P.smooth(pts, 10), 1.0, "smooth: flat below the first point")
	eq(P.smooth(pts, 5000), 0.4, "smooth: flat above the last point")
	eq(P.smooth({}, 5, 7), 7, "smooth: default for an empty list")
	eq(P.smooth({{100, 0.5}}, 900), 0.5, "smooth: one point")
	near(P.smooth({{0, 0}, {10, 1}}, 4), 0.4, 1e-12, "smooth: two points are a line")
	-- monotone between monotone points (no overshoot), continuous (no jump at a point)
	local prev = P.smooth(pts, 100)
	for x = 101, 500 do
		local v = P.smooth(pts, x)
		check(v <= prev + 1e-12 and v >= 0.3 - 1e-12, "smooth: falling 100-500 without overshoot at " .. x)
		prev = v
	end
	for x = 500, 800 do
		local v = P.smooth(pts, x)
		check(v >= 0.25 - 1e-12 and v <= 0.3 + 1e-12, "smooth: within 0.25-0.30 between 500 and 800 at " .. x)
	end
	for _, p in ipairs(pts) do
		check(math.abs(P.smooth(pts, p[1] - 1e-6) - P.smooth(pts, p[1] + 1e-6)) < 1e-5, "smooth: continuous at " .. p[1])
	end
end

-- ---------------------------------------------------------------- the shipped curves
check(ll and ll.enabled ~= false, "lootLevel is on")
eq(ll.notableRarity, 4, "notable from Rare (stored id 4)")
eq(ll.notableChance, 1000, "rare drops: 1% or less")
for _, set in ipairs({"base", "scaled"}) do
	local s = cfg[set]
	check(s.gold == nil, set .. ": the linear gold curve is replaced by coins")
	for _, k in ipairs({"coins", "junkKeep", "notable"}) do
		check(type(s[k]) == "table" and #s[k] >= 2, set .. ": " .. k .. " points")
		for i = 2, #(s[k] or {}) do
			check(s[k][i][1] > s[k][i - 1][1], set .. ": " .. k .. " points sorted")
		end
	end
end
for L = 20, 2000, 10 do
	for _, scaled in ipairs({false, true}) do
		local f = P.factors(cfg, L, scaled)
		local tag = (scaled and "scaled " or "base ") .. L
		check(f.coins > 0 and f.coins <= 1, tag .. ": coins in (0, 1] (" .. f.coins .. ")")
		check(f.notable >= f.loot - 1e-12 and f.notable <= 1, tag .. ": notable between loot and 1")
		check(f.junkKeep and f.junkKeep > 0, tag .. ": junkKeep set")
		eq(f.gold, f.coins, tag .. ": gold is the coins share (old readers)")
		if L <= 650 then
			near(f.notable, f.loot, 1e-9, tag .. ": below 650 the notable drops keep the loot factor")
		elseif L >= 700 then
			eq(f.notable, 1, tag .. ": from 700 every notable drop stays")
		end
	end
	-- the generated set has no curves of its own: the 2026-10-20 thinning
	local g = P.factors(cfg, L, true, true)
	eq(g.coins, 1, "generated " .. L .. ": coins 1")
	check(g.junkKeep == nil, "generated " .. L .. ": no junkKeep (stacks thinned by count as before)")
	near(g.notable, g.loot, 1e-12, "generated " .. L .. ": notable = loot")
end
-- below 400 the coins follow the old linear gold (x0.963, the floor); 400-600 they are the O141 smooth gold curve
-- (0.73-0.90, lootLevel.goldPerHour: the 0.30 plateau left the gold per hour at 400-600 under the level 300 band's);
-- from 650 they stay under the old 0.30
near(P.factors(cfg, 100, false).coins, 0.963, 1e-9, "base 100: coins 0.963")
for L = 400, 600, 25 do
	local c = P.factors(cfg, L, false).coins
	check(c >= 0.70 and c <= 0.95, "base " .. L .. ": coins on the O141 gold curve (" .. c .. ")")
end
for L = 650, 1500, 25 do -- (625 is the ramp down)
	check(P.factors(cfg, L, false).coins <= 0.30, "base " .. L .. ": coins at most the old 0.30")
end
-- a config without the new keys keeps the 2026-10-20 reading
do
	local old = {enabled = true, base = {loot = {{20, 0.5}}, gold = {{250, 1.0}, {450, 0.30}}}}
	local f = P.factors(old, 450, false)
	near(f.coins, 0.30, 1e-12, "old config: coins = gold")
	check(f.junkKeep == nil, "old config: no junkKeep")
	near(f.notable, 0.5, 1e-12, "old config: notable = loot")
end

-- ---------------------------------------------------------------- P.isNotable
check(P.isNotable(ll, {class = "gear", rarity = 4}), "Rare gear is notable")
check(P.isNotable(ll, {class = "gear", rarity = 7}), "an old Legendary id is notable")
check(P.isNotable(ll, {class = "gear", rarity = 10}), "Divine gear is notable")
check(not P.isNotable(ll, {class = "gear", rarity = 3}), "Magic gear is not")
check(not P.isNotable(ll, {class = "gear"}), "plain gear is not")
check(P.isNotable(ll, {class = "junk", chance = 1000}), "a 1% drop is notable")
check(not P.isNotable(ll, {class = "junk", chance = 1001}), "a 1.001% drop is not")
check(P.isNotable(ll, {class = "other", chance = 50}), "a rare orb drop is notable")
check(not P.isNotable(ll, {class = "coin", chance = 10, rarity = 10}), "coins never are")

-- ---------------------------------------------------------------- P.coinStacks
do
	local s = P.coinStacks(123456)
	eq(#s, 3, "coin stacks: three kinds")
	eq(s[1][1], 2160)
	eq(s[1][2], 12)
	eq(s[2][1], 2152)
	eq(s[2][2], 34)
	eq(s[3][1], 2148)
	eq(s[3][2], 56)
	eq(#P.coinStacks(0), 0, "no gold, no coins")
	eq(#P.coinStacks(99), 1, "99 gold: gold coins only")
end

-- ---------------------------------------------------------------- P.levelPlan
local function seq(values)
	local i = 0
	return function()
		i = i + 1
		return values[(i - 1) % #values + 1]
	end
end
do
	local f = {loot = 0.25, coins = 0.4, junkKeep = 0.2, notable = 1}
	-- coins: value x 0.1 back as coins, the coin items removed
	local keep, pay = P.levelPlan(ll, f, {{class = "coin", value = 10000, count = 3, stackable = true}}, seq({0.5}))
	eq(keep[1], 0, "coins: the stock coins go")
	eq(pay, 3000, "coins: 30000 x 0.25 x 0.4 come back")
	-- notable: kept whole whatever the roll
	keep = P.levelPlan(ll, f, {{class = "gear", rarity = 5, count = 1}, {class = "junk", value = 9000, chance = 500,
		count = 2, stackable = true}}, seq({0.999}))
	eq(keep[1], 1, "notable: a Legendary drop stays")
	eq(keep[2], 2, "notable: a 0.5% drop stays")
	-- junk: sv = 0.1, sk = 0.05. In kind on a roll below 0.05; else paid (0.1 - 0.05) / 0.95 of its value
	keep, pay = P.levelPlan(ll, f, {{class = "junk", value = 1000, count = 1, chance = 50000}}, seq({0.01}))
	eq(keep[1], 1, "junk: kept in kind on a low roll")
	eq(pay, 0, "junk: nothing paid when it stays")
	keep, pay = P.levelPlan(ll, f, {{class = "junk", value = 1900, count = 1, chance = 50000},
		{class = "coin", value = 1, count = 0}}, seq({0.9}))
	eq(keep[1], 0, "junk: taken out on a high roll")
	eq(pay, 100, "junk: 1900 x 0.05 / 0.95 = 100 paid")
	-- a stack in kind with junkKeep above coins: count x sv / sk
	local f2 = {loot = 0.25, coins = 0.4, junkKeep = 2, notable = 1}
	keep = P.levelPlan(ll, f2, {{class = "junk", value = 10, count = 50, stackable = true, chance = 50000}}, seq({0.1}))
	eq(keep[1], 10, "junk stack: kept with chance 0.5, 50 x 0.1 / 0.5 = 10")
	-- gear and orbs: the loot factor as before
	keep = P.levelPlan(ll, f, {{class = "gear", count = 1}, {class = "other", count = 8, stackable = true}}, seq({0.5}))
	eq(keep[1], 0, "plain gear at 0.5 >= 0.25: removed")
	eq(keep[2], 2, "8 orbs x 0.25 = 2")
	-- the floor: only junk, all of it taken out without a pay (sk = sv) -> its value x sv as coins
	local f3 = {loot = 0.25, coins = 0.4, junkKeep = 0.4, notable = 1}
	keep, pay = P.levelPlan(ll, f3, {{class = "junk", value = 5000, count = 2, stackable = true, chance = 50000}},
		seq({0.99}))
	eq(keep[1], 0, "floor: the junk is gone")
	eq(pay, 1000, "floor: an emptied corpse gets 2 x 5000 x 0.1 = 1000 in coins")
	-- no floor when something else shows
	keep, pay = P.levelPlan(ll, f3, {{class = "junk", value = 5000, count = 2, stackable = true, chance = 50000},
		{class = "gear", rarity = 4, count = 1}}, seq({0.99}))
	eq(pay, 0, "floor: not when a notable drop shows")
	-- shares of 1: nothing changes but the coins' form
	keep, pay = P.levelPlan(ll, {loot = 1, coins = 1, notable = 1}, {{class = "junk", value = 5, count = 3,
		stackable = true}, {class = "coin", value = 100, count = 7}, {class = "gear", count = 1}}, seq({0.99}))
	eq(keep[1], 3, "shares 1: junk stays")
	eq(keep[3], 1, "shares 1: gear stays")
	eq(pay, 700, "shares 1: the coins' value back")
	-- the plan reads no player: its only inputs are the config, the monster's factors, the items and the roll
	local info = debug and debug.getinfo and debug.getinfo(P.levelPlan, "u")
	if info and info.nparams then
		eq(info.nparams, 4, "levelPlan(ll, f, items, rnd): no killer argument")
	end
end

-- expected values: Monte Carlo of the plan against the shares
do
	math.randomseed(12345)
	local f = {loot = 0.24, coins = 0.27, junkKeep = 3.4, notable = 1}
	local items = {{class = "coin", value = 10000, count = 4, stackable = true},
		{class = "junk", value = 650, count = 2, stackable = true, chance = 19000},
		{class = "junk", value = 33000, count = 1, stackable = false, chance = 10000},
		{class = "other", value = 0, count = 3, stackable = true, chance = 20000}}
	local n, gold, other = 40000, 0, 0
	for _ = 1, n do
		local keep, pay = P.levelPlan(ll, f, items, math.random)
		gold = gold + pay + keep[2] * 650 + keep[3] * 33000
		other = other + keep[4]
	end
	local sv = 0.24 * 0.27
	local expect = (40000 + 1300 + 33000) * sv
	-- the floor adds a little (only when nothing shows; here the orbs and coins usually do): within 3%
	near(gold / n / expect, 1, 0.03, "Monte Carlo: gold per kill = value x loot x coins")
	near(other / n, 3 * 0.24, 0.02, "Monte Carlo: orbs x loot")
end

-- ---------------------------------------------------------------- the economy model, band by band
ChaosLootModelLib = true
local M = dofile("tools/loot_model.lua")
local ctx = M.load()
local text, rows = M.report(ctx)
if os.getenv("LOOT_MODEL_SHOW") then print(text) end
eq(#rows, 6, "six bands: 100, 300, 500, 800, 1000, 1500")
for _, r in ipairs(rows) do
	check(r.monsters >= 5, r.band .. ": a sample of monsters (" .. r.monsters .. ")")
	check(r.kills > 1000 and r.kills < 1700, r.band .. ": the pack model's kills per hour (" .. r.kills .. ")")
	local goldRef = (ctx.ll.goldPerHour or {})[r.band] or r.oldGold -- O141: the smooth target where the config has one
	near(r.newGold / goldRef, 1, M.TOL.gold, r.band .. ": gold per hour kept (" .. M.fmt(r.oldGold) .. " -> " ..
		M.fmt(r.newGold) .. ")")
	near(r.newItems / r.oldItems, 1, M.TOL.items, r.band .. ": items per hour kept (" .. M.fmt(r.oldItems) .. " -> " ..
		M.fmt(r.newItems) .. ")")
	check(r.newEmpty <= r.oldEmpty, r.band .. ": no more empty corpses than before")
	if r.band >= 300 then
		check(r.newEmpty < r.oldEmpty / 2, r.band .. ": empty corpses at most half as often (" .. r.oldEmpty .. " -> " ..
			r.newEmpty .. ")")
	end
end
-- O141: gold per hour grows with the level from 300 to 1000 (no dip at 400-600) by at most M.MAX_STEP between bands
do
	local prev
	for _, b in ipairs({300, 350, 400, 450, 500, 550, 600, 650, 700, 800, 900, 1000}) do
		M.RANGES[b] = M.RANGES[b] or {math.floor(b * 0.85), math.ceil(b * 1.15)}
		local g = M.band(ctx, b).newGold
		if prev then
			check(g >= prev[2] and g / prev[2] <= M.MAX_STEP, "gold per hour " .. prev[1] .. " -> " .. b .. " smooth (" ..
				M.fmt(prev[2]) .. " -> " .. M.fmt(g) .. ")")
		end
		prev = {b, g}
	end
end
-- the model's own rule matches the core: the shipped factors of a level
do
	local mon = {level = 1018, scaled = false}
	local _, n = M.rules(ctx, mon)
	local f = P.factors(cfg, 1018, false)
	eq(n.f.coins, f.coins, "model: the core's coins")
	eq(n.f.junkKeep, f.junkKeep, "model: the core's junkKeep")
	eq(n.f.notable, 1, "model: notable 1 at 1018")
	near(ctx.rare, 0.0772, 0.0005, "model: Rare+ is 7.72% of the stock gear drops")
end

-- ---------------------------------------------------------------- the widows (beta report 2026-10-21)
for _, name in ipairs(M.WIDOWS) do
	local w = M.monster(ctx, name)
	check(w ~= nil, name .. ": in the band data")
	if w then
		near(w.new.gold / w.old.gold, 1, 0.05, name .. ": gold per kill kept (" .. M.fmt(w.old.gold) .. " -> " ..
			M.fmt(w.new.gold) .. ")")
		near(w.new.items / w.old.items, 1, 0.07, name .. ": items per kill kept")
		check(w.old.empty > 0.45, name .. ": before, about half the corpses looked empty (" .. w.old.empty .. ")")
		check(w.new.empty < 0.10, name .. ": now under 10% (" .. w.new.empty .. ")")
		check(w.new.coins > 0.7, name .. ": coins in most corpses (" .. w.new.coins .. ")")
	end
end

-- Monte Carlo of the core plan on the Nightfang Widow's stock table against the model
do
	local mon
	for _, m in ipairs(ctx.data) do
		if m.name == "Nightfang Widow" then mon = m end
	end
	local f = P.factors(cfg, mon.level, mon.scaled)
	math.randomseed(777)
	local n, gold, items, empty = 30000, 0, 0, 0
	for _ = 1, n do
		local corpse = {}
		for _, e in ipairs(mon.loot) do
			if math.random() * 100000 < e[2] then
				local stack = e[3] > 1 or e[4] == "coin"
				corpse[#corpse + 1] = {class = e[4], value = e[5], count = stack and math.random(1, e[3]) or 1,
					stackable = stack, chance = e[2]}
			end
		end
		local keep, pay = P.levelPlan(ll, f, corpse, math.random)
		local shows = pay > 0
		gold = gold + pay
		for i, it in ipairs(corpse) do
			if keep[i] > 0 then
				shows = true
				if it.class ~= "coin" then
					items = items + 1
					gold = gold + keep[i] * (it.value or 0)
				end
			end
		end
		empty = empty + (shows and 0 or 1)
	end
	local w = M.monster(ctx, "Nightfang Widow")
	near(gold / n / w.new.gold, 1, 0.04, "Nightfang Widow: core gold per kill = model (" .. gold / n .. " vs " ..
		w.new.gold .. ")")
	near(items / n, w.new.items, 0.03, "Nightfang Widow: core items per kill = model")
	near(empty / n, w.new.empty, 0.02, "Nightfang Widow: core empty corpses = model")
end

-- ---------------------------------------------------------------- crystal coins only (beta report 2026-10-22)
do
	for _, name in ipairs(M.WIDOWS) do
		local listed = false
		for _, n in ipairs(ll.crystalOnly or {}) do
			if n == name then listed = true end
		end
		check(listed, name .. ": on lootLevel.crystalOnly")
	end
	eq(#P.crystalStacks(0, function() return 0 end), 0, "crystal: no gold, no coins")
	eq(P.crystalStacks(25000, function() return 0.99 end)[1][2], 2, "crystal: 25000 rounds down on a high roll")
	eq(P.crystalStacks(25000, function() return 0.1 end)[1][2], 3, "crystal: 25000 rounds up on a low roll")
	eq(P.payStacks(ll, "nightfang widow", 12345, function() return 0.99 end)[1][1], 2160, "pay: a listed name, any case")
	eq(#P.payStacks(ll, "Some Other Monster", 12345), 3, "pay: other monsters keep the three coin kinds")
	-- Monte Carlo: the widow's pay as crystal coins keeps the gold per kill, and the bag gets one coin kind only
	local mon
	for _, m in ipairs(ctx.data) do
		if m.name == "Nightfang Widow" then mon = m end
	end
	local f = P.factors(cfg, mon.level, mon.scaled)
	math.randomseed(4242)
	local n, plain, crystal, other, maxCount = 30000, 0, 0, 0, 0
	for _ = 1, n do
		local corpse = {}
		for _, e in ipairs(mon.loot) do
			if math.random() * 100000 < e[2] then
				local stack = e[3] > 1 or e[4] == "coin"
				corpse[#corpse + 1] = {class = e[4], value = e[5], count = stack and math.random(1, e[3]) or 1,
					stackable = stack, chance = e[2]}
			end
		end
		local _, pay = P.levelPlan(ll, f, corpse, math.random)
		plain = plain + pay
		for _, c in ipairs(P.payStacks(ll, "Nightfang Widow", pay, math.random)) do
			if c[1] == 2160 then
				crystal = crystal + c[2] * 10000
				maxCount = math.max(maxCount, c[2])
			else
				other = other + 1
			end
		end
	end
	eq(other, 0, "Nightfang Widow: crystal coins only")
	near(crystal / plain, 1, 0.04, "Nightfang Widow: crystal pay keeps the coin gold per kill (" .. crystal / n ..
		" vs " .. plain / n .. ")")
	check(maxCount <= 10, "Nightfang Widow: a small number of crystal coins (max " .. maxCount .. ")")
end

print(string.format("loot_by_level_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
