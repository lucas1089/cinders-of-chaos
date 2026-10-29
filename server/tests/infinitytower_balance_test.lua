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
eq(B.level(C, 120), 2200, "the last point of the curve")
eq(B.level(C, 500), 2200 + 380 * C.beyond.levelPerFloor, "past the curve: it keeps climbing (O172)")
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

-- ---- O172: the tower never stops getting stronger
local be = C.beyond
eq(C.maxFloor, 120, "the curves end at floor 120")
ok(#C.health > 0 and C.health[#C.health][1] == C.maxFloor, "the health curve ends at maxFloor, the growth takes over")
ok(C.damage[#C.damage][1] == C.maxFloor, "so does the damage curve")
local lastBoss = 0
for k in pairs(C.bossHealth) do lastBoss = math.max(lastBoss, k) end
eq(lastBoss, C.maxFloor, "the boss table ends at maxFloor")
for f = 2 * C.bossEvery, C.maxFloor, C.bossEvery do
	ok(C.bossHealth[f] > C.bossHealth[f - C.bossEvery], "boss health rises from boss floor to boss floor (no dip at " .. f .. ")")
end
eq(B.growth(C, be.healthRate, be.healthAccel, 120), 1, "no growth at maxFloor")
eq(B.growth(C, be.healthRate, be.healthAccel, 1), 1, "none below it")
ok(B.growth(C, be.healthRate, be.healthAccel, 121) > 1, "growth from floor 121")
local function trend(f)
	return B.curve(C.health, f) * B.growth(C, be.healthRate, be.healthAccel, f)
end
local stepFirst = B.growth(C, be.healthRate, be.healthAccel, 121) - 1
local stepLate = B.growth(C, be.healthRate, be.healthAccel, 801) / B.growth(C, be.healthRate, be.healthAccel, 800) - 1
ok(stepLate > stepFirst * 1.15, "the step from one floor to the next climbs: a soft wall, not a flat rate")
ok(stepFirst < 0.01, "the first step above maxFloor is below 1% (no cliff)")
local capHealth, capBoss, capDamage = nil, nil, nil
local lvl = B.level(C, 1)
for f = 2, 1200 do
	ok(trend(f) > trend(f - 1), "the health trend rises with floor " .. f)
	ok(B.level(C, f) > B.level(C, f - 1), "the level rises with floor " .. f)
	ok(B.health(C, f) <= be.healthMax, "health under its cap at " .. f)
	if f % C.milestoneEvery == 0 or f > C.milestoneEvery then
		if f > C.milestoneEvery and B.health(C, f) < be.healthMax then
			ok(B.health(C, f) > B.health(C, f - C.milestoneEvery), "floor " .. f .. " has more health than the floor a climb before")
		end
	end
	if f > C.milestoneEvery and f % C.milestoneEvery ~= 1 and B.health(C, f) < be.healthMax then
		ok(B.health(C, f) > B.health(C, f - 1), "inside a climb floor " .. f .. " is above the one before")
	end
	if f > 52 and B.damage(C, f) < be.damageMax then
		ok(B.damage(C, f) > B.damage(C, f - 1), "damage factor rises from floor 52 (" .. f .. ")")
	end
	if f % C.bossEvery == 0 and f > C.bossEvery then
		if B.bossHealth(C, f) < be.bossHealthMax then
			ok(B.bossHealth(C, f) > B.bossHealth(C, f - C.bossEvery), "boss floor " .. f .. " has more health than the boss before")
		end
		if f > C.maxFloor and B.bossDamage(C, f) < be.damageMax then
			ok(B.bossDamage(C, f) > B.bossDamage(C, f - C.bossEvery), "boss damage rises above maxFloor (" .. f .. ")")
		end
	end
end
eq(B.bossDamage(C, 10), 1, "a boss up to maxFloor hits with its own damage")
eq(B.bossDamage(C, 120), 1, "a boss on maxFloor too")
ok(B.bossDamage(C, 130) > 1, "a boss above maxFloor hits harder")
ok(B.damage(C, 121) > B.damage(C, 120), "monsters above maxFloor hit harder than on 120")
ok(B.health(C, 125) > B.health(C, 120), "floor 125 over floor 120")
ok(B.bossHealth(C, 130) > B.bossHealth(C, 120), "the boss of floor 130 is stronger than the last tabled one")
ok(B.bossHealth(C, 130) > C.bossHealth[100], "bosses past the table do not repeat old health")
eq(B.bossAt(C, 130).name, "the ashen count", "the names still repeat")
-- the caps: start floors and extreme floors
local hc = B.growthFloor(C, be.healthRate, be.healthAccel, be.healthMax / (B.curve(C.health, 120) * C.sawtooth[#C.sawtooth]))
local bc = B.growthFloor(C, be.bossHealthRate, be.bossHealthAccel, be.bossHealthMax / C.bossHealth[120])
local dc = B.growthFloor(C, be.damageRate, be.damageAccel, be.damageMax / (B.curve(C.damage, 120) * B.climb(C, 120)))
ok(hc > 1000 and bc > 1000 and dc > 1000, "no cap starts before floor 1000 (" .. hc .. ", " .. bc .. ", " .. dc .. ")")
eq(B.bossHealth(C, bc - 1) < be.bossHealthMax and B.bossHealth(C, bc + 10) == be.bossHealthMax, true, "the boss health cap starts at floor " .. bc)
eq(B.damage(C, dc + 1), be.damageMax, "the damage cap starts at floor " .. dc)
local INT32 = 2147483647
for _, f in ipairs({1500, 2000, 5000, 100000, 10 ^ 7, 10 ^ 9, 10 ^ 12, 1e300, math.huge}) do
	local h, bh, d, bd, lv = B.health(C, f), B.bossHealth(C, f), B.damage(C, f), B.bossDamage(C, f), B.level(C, f)
	for name, v in pairs({health = h, bossHealth = bh, damage = d, bossDamage = bd, level = lv}) do
		ok(v == v and v ~= math.huge and v >= 0, name .. " is finite at floor " .. tostring(f))
	end
	ok(h <= be.healthMax and bh <= be.bossHealthMax and d <= be.damageMax and bd <= be.damageMax and lv <= be.levelMax, "everything under its cap at floor " .. tostring(f))
	ok(B.tierMaxHealth(C, h, "legendary") <= INT32 and B.preTierHealth(C, h, "legendary", 6.0) * 6 <= INT32, "the legendary monster fits int32 at floor " .. tostring(f))
	ok(bh <= INT32 and lv <= INT32, "boss health and level fit int32 at floor " .. tostring(f))
end
eq(B.health(C, 100000), be.healthMax, "floor 100000: the normal health cap (the sawtooth is under it)")
eq(B.bossHealth(C, 100000), be.bossHealthMax, "floor 100000: the boss health cap")
eq(B.damage(C, 100000), be.damageMax, "floor 100000: the damage cap")
eq(B.level(C, 100000), 2200 + (100000 - 120) * be.levelPerFloor, "floor 100000: the level")
eq(B.level(C, 1e12), math.min(be.levelMax, 2200 + (1e12 - 120) * be.levelPerFloor), "an absurd floor: the level cap")
eq(B.level(C, 0 / 0), B.level(C, 1), "a nan floor counts as floor 1")
eq(B.health(C, "x"), B.health(C, 1), "a text floor counts as floor 1")
ok(be.healthMax * C.tierHealth.legendary <= be.engineMaxHealth and be.engineMaxHealth <= INT32, "health cap x the legendary tier fits the engine limit")
ok(be.bossHealthMax <= be.engineMaxHealth and be.levelMax <= INT32, "boss health and level caps fit int32")
eq(B.tierMaxHealth(C, 1e12, "legendary"), be.engineMaxHealth, "the last guard before setMaxHealth")
local plan = B.plan(C, 501, 1, function() return 1 end)
ok(plan.spawns[1].damage == B.damage(C, 501) and plan.spawns[1].damage > 1 and plan.spawns[1].health == B.health(C, 501), "floor 501 plan: monsters carry the growth")
eq(plan.spawns[1].level, B.level(C, 501), "and the level")
local bp2 = B.plan(C, 500, 1, function() return 1 end)
ok(bp2.boss and bp2.spawns[1].damage == B.bossDamage(C, 500) and bp2.spawns[1].damage > 1, "the boss of floor 500 carries its damage factor")
eq(bp2.spawns[1].health, B.bossHealth(C, 500), "and its health")
eq(bp2.spawns[1].level, B.level(C, 500), "and its level")
-- rewards do not follow the growth
eq(B.itemsText(B.rewardItems(C.rewards.firstClear, 460, C.maxFloor)), B.itemsText(B.rewardItems(C.rewards.firstClear, 120, C.maxFloor)), "first-clear rewards above maxFloor are those of maxFloor (floor 460, no rule of 25)")
eq(B.itemsText(B.rewardItems(C.rewards.repeatable, 910, C.maxFloor)), B.itemsText(B.rewardItems(C.rewards.repeatable, 120, C.maxFloor)), "repeatable rewards too")
local it500 = B.firstClear(C, -1, 7, 460)
eq(B.itemsText(it500), B.itemsText(B.rewardItems(C.rewards.firstClear, 120, C.maxFloor)), "firstClear of floor 460 pays the capped reward")
eq(B.firstClear(C, -1, 7, 1000), nil, "the storage value holds floors below 1000 only")
local dropMax = 0
for _ = 1, 50 do
	for _, x in ipairs(B.dropRolls(C, 100000, "legendary", function(a, b) return b or 1 end)) do dropMax = math.max(dropMax, x.count) end
end
eq(dropMax, 2 + math.floor(0.05 * C.maxFloor), "drop counts stop growing at maxFloor")

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

-- ---- O328: loot follows the floor
eq(B.lootLevel(C, 1), 100, "floor 1: loot level 100")
eq(B.lootLevel(C, 60), B.level(C, 60), "inside the curve the loot level is the shown level")
eq(B.lootLevel(C, 120), 2200, "floor 120: 2200")
eq(B.lootLevel(C, 5000), 2200, "above maxFloor the loot level stays at maxFloor's (no inflation)")
ok(B.level(C, 5000) > B.lootLevel(C, 5000), "while the shown level keeps climbing")
for f = 2, 120 do
	ok(B.lootLevel(C, f) >= B.lootLevel(C, f - 1), "the loot level never falls with the floor " .. f)
end
for f = 1, 150 do
	local s = B.lootShare(C, f)
	ok(s > 0 and s <= 1, "the loot share of floor " .. f .. " is a share")
	ok(B.killGold(C, f) > 0, "floor " .. f .. " pays gold")
end
eq(B.lootShare(C, 1e9), B.lootShare(C, 120), "the share is that of maxFloor above it")
eq(B.killGold(C, 1e9), B.killGold(C, 120), "so is the gold: the economy does not inflate")
ok(B.killGold(C, 100) > B.killGold(C, 1) * 3, "gold per kill grows with the floor: " .. B.killGold(C, 1) .. " to " .. B.killGold(C, 100))
-- the pace factors of the loot level, x lootShare on the loot and notable shares
local asked
local function pace(level, scaled)
	asked = {level, scaled}
	return {loot = 0.4, notable = 0.5, coins = 0.7, junkKeep = 1.1, cheap = 20}
end
local f1 = B.lootFactors(C, 1, pace)
eq(asked[1], 100, "pace factors are asked at the loot level")
eq(asked[2], false, "a level up to lootScaledFrom uses the base set")
eq(f1.loot, 0.4 * B.lootShare(C, 1), "loot x lootShare")
eq(f1.notable, 0.5 * B.lootShare(C, 1), "notable x lootShare")
eq(f1.coins, 0.7, "coins, junkKeep and cheap stay the pace set's")
eq(f1.junkKeep, 1.1, "junkKeep")
B.lootFactors(C, 60, pace)
eq(asked[1], B.level(C, 60), "floor 60 asks at its level")
eq(asked[2], true, "a level above lootScaledFrom uses the scaled set")
B.lootFactors(C, 900, pace)
eq(asked[1], 2200, "floor 900 asks at maxFloor's level")
eq(B.lootFactors(C, 1, nil), nil, "no pace layer, no factors")
eq(B.lootFactors(C, 1, function() return nil end), nil, "a pace layer without a set, no factors")
-- gold: whole, the expected value is killGold
local sum, n = 0, 20000
local seed = 12345
local function lcg() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
for _ = 1, n do
	local g = B.goldRoll(C, 20, lcg)
	ok(g == math.floor(g), "gold is a whole number")
	sum = sum + g
end
ok(math.abs(sum / n - B.killGold(C, 20)) < 0.5 + B.killGold(C, 20) * 0.01, "the expected gold is the curve's: " .. sum / n .. " vs " .. B.killGold(C, 20))
eq(B.goldRoll(C, 20, function() return 0.999999 end), math.floor(B.killGold(C, 20)) + (B.killGold(C, 20) % 1 > 0.999999 and 1 or 0), "a high roll rounds down")
local noLoot = {maxFloor = 120, level = C.level, beyond = C.beyond}
eq(B.lootFactors(noLoot, 1, pace), nil, "a config without lootShare has no tower loot")
eq(B.killGold(noLoot, 5), 0, "and no gold")
eq(B.lootShare(noLoot, 5), 1, "and a share of 1")

-- ---- O328: the damage curve follows the shown level (floor 1 species are level 11 and hit 7x as hard at level 100)
ok(B.damage(C, 1) > 5, "floor 1 hits much harder than its level 11 species: " .. B.damage(C, 1))
ok(B.damage(C, 120) > B.damage(C, 60), "the factor keeps rising in the last band")
-- the climb (owner 2026-10-29): +climb a floor from the first, held at maxFloor
eq(B.climb(C, 1), 1, "floor 1: no climb")
ok(math.abs(B.climb(C, 58) - (1 + C.climb * 57)) < 1e-9 and B.climb(C, 500) == B.climb(C, C.maxFloor), "the climb grows to maxFloor, then holds")
ok(math.abs(B.damage(C, 58) - B.curve(C.damage, 58) * B.climb(C, 58)) < 1e-9, "the damage factor is the hunt match x the climb")
for f = 2, C.maxFloor do
	if math.floor(f / C.bandFloors) == math.floor((f - 1) / C.bandFloors) then
		ok(B.damage(C, f) >= B.damage(C, f - 1) * 0.995, "inside a band no floor hits softer than the one before (" .. f .. ")")
	end
end
ok(B.bossDamage(C, 100) == 1, "a boss up to maxFloor still hits with its own damage")

print(string.format("infinitytower_balance_test: %d checks, %d failed", checks, failed))
if failed > 0 then
	os.exit(1)
end
