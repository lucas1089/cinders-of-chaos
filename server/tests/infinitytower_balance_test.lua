-- Run from the server/ folder: luajit tests/infinitytower_balance_test.lua && lua5.3 tests/infinitytower_balance_test.lua
-- Infinity Tower balance (O144): infinitytower_balance_core.lua against infinitytower_balance_config.lua. The model that
-- bounds the numbers (time to clear a floor) is tools/tower_model.py (CI runs --check and its test).
dofile("data/scripts/chaos/infinitytower_balance_core.lua")
local C = dofile("data/scripts/chaos/infinitytower_balance_config.lua")
local B = ChaosTowerBalanceCore

local checks, failed = 0, 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		failed = failed + 1
		print("FAIL " .. m .. ": " .. tostring(a) .. " ~= " .. tostring(b))
	end
end
local function ok(v, m)
	eq(not not v, true, m)
end

-- ---- curves
eq(B.curve({{1, 10}, {5, 50}}, 0), 10, "flat before the first point")
eq(B.curve({{1, 10}, {5, 50}}, 3), 30, "linear between the points")
eq(B.curve({{1, 10}, {5, 50}}, 99), 50, "flat after the last point")
for _, name in ipairs({"count", "magic", "rare", "legendary", "level", "clear", "health", "damage", "bossSeconds"}) do
	if C[name] then
		for i = 2, #C[name] do
			ok(C[name][i][1] > C[name][i - 1][1], name .. ": floors rise")
		end
	end
end

-- ---- O168: the level shown after the name follows the floor's level curve
eq(B.level(C, 1), 100, "floor 1: level 100")
eq(B.level(C, 15), 420, "floor 15: between 300 and 540")
eq(B.level(C, 500), 2200, "past the curve: its last level")
for f = 2, 120 do
	ok(B.level(C, f) >= B.level(C, f - 1), "the level never falls with the floor " .. f)
end
for _, f in ipairs({1, 10, 25, 50}) do
	for _, s in ipairs(B.plan(C, f, 2, function() return 1 end).spawns) do
		eq(s.level, B.level(C, f), "every spawn of floor " .. f .. " carries the floor's level")
	end
end

-- ---- floors
eq(B.count(C, 1, 1), 4, "floor 1 has 4 monsters")
eq(B.count(C, 1, 3), 8, "two more players add perPlayer each")
ok(B.count(C, 120, 1) <= 10, "the count stays a pack, not a crowd")
ok(B.count(C, 40, 1) <= 8, "floor 40 holds at most 8 (the old planner: 13)")
eq(#C.sawtooth, C.milestoneEvery, "the sawtooth is one climb of milestoneEvery floors")
for i = 2, #C.sawtooth do
	ok(C.sawtooth[i] > C.sawtooth[i - 1], "the sawtooth climbs")
end
ok(C.sawtooth[1] < 1 and C.sawtooth[#C.sawtooth] > 1, "it starts below and ends above 1")
eq(B.sawtooth(C, 1), C.sawtooth[1], "floor 1 is the first of the climb")
eq(B.sawtooth(C, 5), C.sawtooth[5], "floor 5 is the milestone floor")
eq(B.sawtooth(C, 6), C.sawtooth[1], "floor 6 is the breather")
ok(B.health(C, 6) < B.health(C, 5), "the breather: the floor after a milestone floor is softer than it")
for f = 2, 120 do
	if f % C.milestoneEvery ~= 1 then
		ok(B.health(C, f) <= B.health(C, f - 1) * 1.35, "floor " .. f .. " is at most 35% over the floor before")
	end
end
local trend = {}
for f = 1, 120 do
	trend[f] = B.curve(C.health, f)
	if f > 1 then
		ok(trend[f] >= trend[f - 1], "the health curve never falls (floor " .. f .. ")")
	end
end

-- ---- bosses
eq(B.isBoss(C, 10), true, "floor 10 is a boss floor")
eq(B.isBoss(C, 15), false, "floor 15 is not")
eq(B.bossAt(C, 10).name, "the ashen count", "the first boss")
eq(B.bossAt(C, 120).name, "ashvoran", "the 12th boss")
eq(B.bossAt(C, 130).name, "the ashen count", "the list repeats")
for k = 1, C.maxFloor / C.bossEvery do
	ok(C.bossHealth[k * C.bossEvery], "a boss health for floor " .. k * C.bossEvery)
end
for f = 20, 100, 10 do
	if C.bosses[f / 10].heal <= 300 and C.bosses[f / 10 - 1].heal <= 300 then
		ok(B.bossHealth(C, f) > B.bossHealth(C, f - 10), "bosses of the same kind get more health with the floor (" .. f .. ")")
	end
end
eq(B.bossHealth(C, 10), C.bossHealth[10], "a boss floor reads its health")
eq(B.bossHealth(C, 15), C.bossHealth[10], "between boss floors, the one below")
ok(B.bossHealth(C, 130) > B.bossHealth(C, 120), "above the table the boss grows")
for _, b in ipairs(C.bosses) do
	ok(b.name == b.name:lower(), "boss names are the lowercase type names: " .. b.name)
end
-- the two 1,750-a-second healers stand where a median class out-damages them (tools/tower_model.py bossHeal)
eq(C.bosses[11].name, "zeburoth", "Zeburoth is on floor 110")
eq(C.bosses[12].name, "ashvoran", "Ashvoran is on floor 120")

-- ---- pools and tiers
eq(B.poolAt(C, 1)[1], "troll", "band 1")
eq(B.poolAt(C, 8)[1], "minotaur", "band 2 from floor 8")
eq(B.poolAt(C, 999)[1], "demon", "the last band repeats")
eq(#C.pools, 7, "seven bands")
eq(B.tierRoll(C, 1, 100), nil, "a roll of 100 is a normal monster")
eq(B.tierRoll(C, 1, 1), "magic", "a roll of 1 on floor 1: magic")
eq(B.tierRoll(C, 120, 1), "legendary", "a roll of 1 on floor 120: legendary")
eq(B.tierRoll(C, 120, 5), "rare", "then rare")
local m, r, l = B.tierChances(C, 120)
ok(m + r + l <= 60, "most monsters of the top floors are not tiered together with rare and legendary")
ok(C.tierHealth.magic < 2.0 and C.tierHealth.rare < 3.5 and C.tierHealth.legendary < 6.0, "the tower tiers are softer than the stock ones")
eq(B.preTierHealth(C, 1000, "legendary", 6.0), math.floor(1000 * C.tierHealth.legendary / 6.0), "the health to set before the stock tier multiplies")
eq(B.tierMaxHealth(C, 1000, "rare"), math.floor(1000 * C.tierHealth.rare), "the health a tier ends at")
eq(B.tierMaxHealth(C, 1000, nil), 1000, "no tier: the floor's health")

-- ---- the plan
local det = function() return 1 end
local plan = B.plan(C, 1, 1, det)
eq(#plan.spawns, 4, "floor 1 plan")
eq(plan.spawns[1].health, B.health(C, 1), "the plan carries the floor's health")
eq(plan.spawns[1].damage, B.damage(C, 1), "and its damage factor")
local bp = B.plan(C, 10, 1, det)
eq(bp.boss, true, "boss floor")
eq(bp.spawns[1].boss, true, "the boss first")
eq(bp.spawns[1].health, C.bossHealth[10], "with its health")
eq(bp.spawns[1].damage, 1, "its own damage")
eq(#bp.spawns, 1 + math.floor(B.count(C, 10, 1) / C.bossHelperDivisor), "and a third of the count as helpers")
eq(#B.plan(C, 1, 4, det).spawns, 10, "four players: 4 + 3 x 2")
local seen = {}
for i = 1, 200 do
	for _, s in ipairs(B.plan(C, 20, 1).spawns) do
		seen[s.name] = true
	end
end
local nseen = 0
for _ in pairs(seen) do
	nseen = nseen + 1
end
ok(nseen >= 4, "a floor shows several species of its pool")

-- ---- rewards
local function items(rules, floor)
	return B.itemsText(B.rewardItems(rules, floor))
end
eq(items(C.rewards.firstClear, 4), "", "no reward off the milestone floors")
eq(items(C.rewards.firstClear, 5), "5 Crystal Coin", "floor 5: coins")
eq(items(C.rewards.firstClear, 10), "10 Crystal Coin, 2 Orb of Upheaval, 1 Orb of Fate", "floor 10 adds the boss floor orbs")
eq(items(C.rewards.firstClear, 25), "25 Crystal Coin, 3 Orb of Fate", "floor 25 pays the 25 rule")
eq(items(C.rewards.firstClear, 50), "50 Crystal Coin, 6 Orb of Upheaval, 6 Orb of Fate", "floor 50: rules of one item add up")
eq(items(C.rewards.repeatable, 5), "1 Crystal Coin", "repeatable: floor 5")
eq(items(C.rewards.repeatable, 30), "7 Crystal Coin, 1 Orb of Upheaval", "repeatable: floor 30")
for f = 5, 120, 5 do
	ok(#B.rewardItems(C.rewards.firstClear, f) > 0, "floor " .. f .. " has a first-clear reward")
	ok(#B.rewardItems(C.rewards.repeatable, f) > 0, "floor " .. f .. " has a repeatable reward")
end
local function upheaval(f)
	for _, it in ipairs(B.rewardItems(C.rewards.firstClear, f)) do
		if it.id == 29856 then return it.count end
	end
	return 0
end
for f = 20, 120, 10 do
	ok(upheaval(f) >= upheaval(f - 10), "the Orbs of Upheaval of a boss floor do not fall (" .. f .. ")")
end
eq(B.nextMilestone(C, 0), 5, "the first milestone")
eq(B.nextMilestone(C, 5), 10, "after 5")
eq(B.nextMilestone(C, 7), 10, "inside a climb")
eq(B.nextMilestone(C, 120), nil, "nothing above the last")

-- ---- the storage value: season x 1000 + the highest floor paid
eq(B.encode(7, 25), 7025, "encode")
eq(B.stored(7025, 7), 25, "stored: this season")
eq(B.stored(7025, 8), 0, "stored: another season pays again")
eq(B.stored(-1, 7), 0, "stored: the engine's default")
eq(B.stored(nil, 7), 0, "stored: nothing")
local it, v = B.firstClear(C, -1, 7, 5)
eq(B.itemsText(it), "5 Crystal Coin", "first clear of floor 5")
eq(v, 7005, "the new value")
eq(B.firstClear(C, 7005, 7, 5), nil, "floor 5 pays once per season")
eq(B.firstClear(C, 7010, 7, 5), nil, "a floor below the highest paid pays nothing")
ok(B.firstClear(C, 7005, 7, 10), "floor 10 pays after floor 5")
ok(B.firstClear(C, 7010, 8, 5), "a new season pays floor 5 again")
eq(B.firstClear(C, -1, 7, 6), nil, "off the milestone floors")

-- ---- drops
local always = function(a, b) if b then return a end return 1 end
local d = B.dropRolls(C, 1, nil, always)
local ids = {}
for _, x in ipairs(d) do ids[x.id] = x.count end
ok(ids[29856], "an Orb of Upheaval from floor 1")
ok(ids[2160], "crystal coins from floor 1")
eq(ids[29857], nil, "the Orb of Fate from floor 20 only")
ids = {}
for _, x in ipairs(B.dropRolls(C, 20, "legendary", always)) do ids[x.id] = x.count end
ok(ids[29857], "the Orb of Fate from floor 20")
local never = function(a, b) if b then return b end return 10000 end
eq(#B.dropRolls(C, 100, "legendary", never), 0, "a high roll drops nothing")
-- expected drops per kill stay small: orbs well under one a kill
local up, fate = 0, 0
for _, x in ipairs(C.drops.items) do
	if x.id == 29856 then up = x.chance / 10000 end
	if x.id == 29857 then fate = x.chance / 10000 end
end
ok(up * C.drops.tierMult.legendary < 0.05 and fate * C.drops.tierMult.legendary < 0.05, "orbs stay rare even from a legendary monster")

-- ---- the storage block is free of the Haunted Harvest (7102800-7102810) and the tester block (7102900-7102909)
ok(C.rewards.storage >= 7102811 and C.rewards.storage < 7102900, "the reward storage lies in 7102811-7102899")

print(string.format("infinitytower_balance_test: %d checks, %d failed", checks, failed))
if failed > 0 then
	os.exit(1)
end
