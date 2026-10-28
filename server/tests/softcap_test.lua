-- Run from the server/ folder: luajit tests/softcap_test.lua (and lua5.3; CI runs both)
-- O146: soft caps of the passive tree (passivetree_effects.lua ChaosSoftCap, ChaosPassiveCharStat, ChaosPassiveDamagePercent),
-- the totals of the tree window (passivetree_totals_core.lua, passivetree_totals.lua) and the critical reach model
-- (tools/crit_reach.lua). No engine needed: the engine API is a mock.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function near(a, b, m, tol)
	checks = checks + 1
	if math.abs(a - b) > (tol or 1e-6) then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function ok(c, m)
	checks = checks + 1
	if not c then error(m or "assertion failed", 2) end
end

dofile("data/scripts/chaos/chaos_constants.lua")
function Chaos.load() end
ChaosOpcodes = ChaosOpcodes or {passivetree = 65}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) end})
rawset(EventCallback, "register", function() end)
function CreatureEvent() local o = {}; function o:register() end; return o end
function Condition() return {setTicks = function() end, setParameter = function() end} end
function addEvent() end
dofile("data/scripts/chaos/passivetree_effects.lua")
dofile("data/scripts/chaos/passivetree_totals_core.lua")
local E = ChaosPassiveEffectsConfig

-- ------------------------------------------------------------------------------------------------ ChaosSoftCap
eq(ChaosSoftCap(0, 150, 60), 0, "zero"); eq(ChaosSoftCap(100, 150, 60), 100, "below the cap: unchanged")
eq(ChaosSoftCap(150, 150, 60), 150, "at the cap: unchanged"); eq(ChaosSoftCap(nil, 150, 60), 0, "nil is zero")
near(ChaosSoftCap(150 + 1e-9, 150, 60), 150, "continuous at the cap", 1e-8)
near(ChaosSoftCap(300, 150, 60), 150 + 60 * math.log(3.5), "the formula"); near(ChaosSoftCap(300, 150, 60), 225.2, "300 raw -> 225", 0.05)
near(ChaosSoftCap(400, 150, 60), 248.5, "400 raw -> 248", 0.05)
near(ChaosSoftCap(1000, 150, 60), 313.15, "1000 raw -> 313", 0.05)
-- never decreasing, every extra point adds something, each adds less than the one before, no ceiling
do
	local prev, prevGain = 0, math.huge
	for raw = 1, 3000 do
		local v = ChaosSoftCap(raw, 150, 60)
		local gain = v - prev
		ok(gain > 0, "every point adds (" .. raw .. ")")
		ok(gain <= prevGain + 1e-9, "each point adds no more than the one before (" .. raw .. ")")
		ok(raw <= 150 or gain < 1, "past the cap a point adds less than one")
		prev, prevGain = v, gain
	end
	ok(ChaosSoftCap(1e6, 150, 60) > ChaosSoftCap(1e4, 150, 60), "no upper limit")
	ok(ChaosSoftCap(1e6, 150, 60) < 1e6, "but far below the raw value")
end

-- ------------------------------------------------------------------------------------------------ attributes
-- the beta report: strength about 280 against a cap of 120
local at = {}
for _, stat in ipairs({"strength", "intelligence", "dexterity", "vitality", "spirit"}) do
	local cap = E.charStatCap[stat]
	eq(E.softCap.charStatH[stat], cap, stat .. ": H = the cap")
	local atCap = ChaosPassiveCharStat(cap, stat)
	eq(atCap, E.charStatMax[stat], stat .. ": the value at the cap is the old maximum")
	local prev = atCap
	for p = cap + 1, cap * 8, math.max(1, math.floor(cap / 10)) do
		local v = ChaosPassiveCharStat(p, stat)
		ok(v > prev, stat .. ": past the cap " .. p .. " adds value")
		prev = v
	end
	at[stat] = ChaosPassiveCharStat(cap * 3, stat)
	-- bounded for PvP: three times the cap in points gives under +45% of the capped value (dexterity under +35%)
	ok(at[stat] < atCap * (stat == "dexterity" and 1.35 or 1.45), stat .. ": 3x the cap in points stays a modest extra: " .. at[stat] .. " vs " .. atCap)
	-- the slope at the cap is the one the curve had just below it
	local slope = E.charStatMax[stat] * (1 - E.charStatKneeShare) / (cap - E.charStatKnee[stat])
	near(ChaosPassiveCharStat(cap + 1, stat) - atCap, slope * (ChaosSoftCap(cap + 1, cap, E.softCap.charStatH[stat]) - cap), stat .. ": slope past the cap", 1e-5)
end
-- strength 280: 120 + 120 ln(1 + 160 / 120) = 221.7 effective points -> value 60 + 0.2 x 101.7 = 80.3 -> x1.349 against x1.261 at the cap
near(ChaosPassiveCharStat(280, "strength"), 60 + 0.2 * 120 * math.log(1 + 160 / 120), "strength 280 value", 1e-5)
near(ChaosPassiveStatMultiplier({strength = 280}, COMBAT_PHYSICALDAMAGE, nil) / ChaosPassiveStatMultiplier({strength = 120}, COMBAT_PHYSICALDAMAGE, nil),
	1.0698, "strength 280 against the cap: +7%", 0.0005)
ok(ChaosPassiveStatMultiplier({strength = 400}, COMBAT_PHYSICALDAMAGE, nil) < 1.4, "strength 400 under x1.4")
-- vitality 300: max health percent
near(ChaosPassiveMaxPercent({vitality = 300}, "vitality"), 50 + 0.2 * 100 * math.log(3), "vitality 300 -> +72%", 1e-5)
-- dexterity: a divisor, held under the ceiling whatever the points
ok(ChaosPassiveCharStat(1e9, "dexterity") <= E.softCap.dexterityValueCeiling, "dexterity ceiling")
ok(ChaosPassiveStatMultiplier({dexterity = 1e9}, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE) < 3, "dexterity multiplier stays finite")
-- wisdom: no effect, no soft cap value
ok(ChaosPassiveCharStat(500, "wisdom") >= ChaosPassiveCharStat(E.charStatCap.wisdom, "wisdom"), "wisdom: never below its value at the cap")

-- ------------------------------------------------------------------------------------------------ damage increments
local b = {incrementPhysical = 150}
eq(ChaosPassiveDamagePercent(b, COMBAT_PHYSICALDAMAGE), 150, "at the old cap: 150")
eq(ChaosPassiveDamagePercent({incrementPhysical = 80}, COMBAT_PHYSICALDAMAGE), 80, "below: unchanged")
near(ChaosPassiveDamagePercent({incrementPhysical = 350}, COMBAT_PHYSICALDAMAGE), 150 + 60 * math.log(1 + 200 / 60), "physical 350 raw")
ok(ChaosPassiveDamagePercent({incrementPhysical = 350}, COMBAT_PHYSICALDAMAGE) > 150, "more than the old cap")
-- the beta numbers: 300-400 raw -> 225-248 effective, x3.25-x3.5 damage against x2.5 at the old cap
ok((1 + ChaosPassiveDamagePercent({incrementPhysical = 400}, COMBAT_PHYSICALDAMAGE) / 100) / 2.5 < 1.4, "400 raw is under +40% damage over the old cap")
-- elements: the increment and all-elements add before the soft cap; healing and drains keep their own stat
near(ChaosPassiveDamagePercent({incrementFire = 200, multiIncrement = 100}, COMBAT_FIREDAMAGE), 150 + 60 * math.log(1 + 150 / 60), "fire + all elements")
eq(ChaosPassiveDamagePercent({incrementFire = 200}, COMBAT_ICEDAMAGE), 0, "another element is not raised")
eq(ChaosPassiveDamageRaw({incrementFire = 200, multiIncrement = 100}, COMBAT_FIREDAMAGE), 300, "raw sum")
eq(ChaosPassiveDamageRaw({incrementFire = 200, multiIncrement = 100}, COMBAT_PHYSICALDAMAGE), 0, "all elements is not physical")
eq(ChaosPassiveDamagePercent({incrementPhysical = -20}, COMBAT_PHYSICALDAMAGE), 0, "never negative")
-- damage dealt end to end, not only the helper
do
	local prev = 0
	for pct = 0, 1000, 25 do
		local v = ChaosPassiveDamagePercent({incrementPhysical = pct}, COMBAT_PHYSICALDAMAGE)
		ok(v >= prev, "damage percent never decreases")
		prev = v
	end
end

-- ------------------------------------------------------------------------------------------------ the totals rows
local api = {charStat = ChaosPassiveCharStat, softCap = ChaosSoftCap, cfg = E, damageRaw = ChaosPassiveDamageRaw,
	damagePercent = ChaosPassiveDamagePercent, types = {{"incrementPhysical", COMBAT_PHYSICALDAMAGE}, {"incrementFire", COMBAT_FIREDAMAGE},
		{"incrementIce", COMBAT_ICEDAMAGE}}}
local bon = {strength = 280, vitality = 40, intelligence = 0, incrementPhysical = 300, incrementFire = 20, multiIncrement = 10,
	criticalHitChance = 12, criticalHitAmount = 20, paragonCritDamage = 5}
local rows = PassiveTotalsCore.attributes(bon, api)
eq(#rows, 2, "only the attributes with points"); eq(rows[1].k, "strength", "order"); eq(rows[1].raw, 280, "raw strength")
near(rows[1].eff, 120 + 120 * math.log(1 + 160 / 120), "effective strength points", 0.06); eq(rows[1].cap, 120, "cap shown")
near(rows[1].effect, ChaosPassiveCharStat(280, "strength"), "the value", 0.006)
eq(rows[2].k, "vitality", "vitality"); eq(rows[2].eff, 40, "below the cap raw = effective")
local dmg = PassiveTotalsCore.damage(bon, api)
eq(#dmg, 3, "physical, fire, ice (all elements)"); eq(dmg[1].k, "incrementPhysical", "physical first")
eq(dmg[1].raw, 300, "raw"); near(dmg[1].eff, 150 + 60 * math.log(3.5), "effective", 0.06); eq(dmg[1].cap, 150, "cap")
eq(dmg[2].raw, 30, "fire = 20 + all elements 10"); eq(dmg[2].eff, 30, "no soft cap below 150"); eq(dmg[3].raw, 10, "ice gets the all-elements share")
-- crit: the engine's total against the tree and Paragon shares
local c = PassiveTotalsCore.crit(bon, 28, 40)
eq(c.chance.total, 28, "total chance is the engine's"); eq(c.chance.tree, 12, "tree share"); eq(c.chance.other, 16, "gear and the rest")
eq(c.amount.total, 40, "total damage"); eq(c.amount.tree, 20, "tree damage"); eq(c.amount.paragon, 5, "Paragon damage"); eq(c.amount.other, 15, "gear damage")
c = PassiveTotalsCore.crit(bon, nil, nil)
eq(c.chance.total, 12, "no engine value: the tree only"); eq(c.chance.other, 0, "nothing else known"); eq(c.amount.total, 25, "tree + Paragon")
local sp = PassiveTotalsCore.attackSpeed({attackSpeed = 9}, 5, 12, 20)
eq(sp.total, 14, "attack speed: tree + gear"); eq(sp.tree, 9, "tree share"); eq(sp.gear, 5, "gear share")
sp = PassiveTotalsCore.attackSpeed({attackSpeed = 30}, 15, 12, 20)
eq(sp.total, 20, "held at the player cap"); eq(sp.tree, 12, "tree share held at its cap")
eq(PassiveTotalsCore.attackSpeed({}, 0, 12, 20), nil, "no attack speed, no row")
c = PassiveTotalsCore.crit({}, 0, 0); eq(c.chance.total, 0, "no crit"); eq(c.amount.total, 0, "no damage")
c = PassiveTotalsCore.crit(bon, 5, 5); eq(c.chance.total, 12, "never below what the tree itself gives"); eq(c.amount.other, 0, "never negative")

-- the engine glue: a mocked player, the message, the rate limit
Chaos.send = function(player, opcode, action, data) player.sent[#player.sent + 1] = {action = action, data = data} end
Chaos.t = function(player, text) return text end
dofile("data/scripts/chaos/passivetree_stats_config.lua")
ChaosPassiveTree = ChaosPassiveTree or {}
dofile("data/scripts/chaos/passivetree_totals.lua")
local player = {sent = {}, skills = {[SPECIALSKILL_CRITICALHITCHANCE] = 28, [SPECIALSKILL_CRITICALHITAMOUNT] = 40}}
function player:getId() return 5 end
function player:getSpecialSkill(i) return self.skills[i] end
ChaosPassiveCache = {[5] = bon}
local h = ChaosPassiveTree.extraActions.statTotals
eq(h(player), true, "handled"); eq(#player.sent, 1, "one answer"); eq(player.sent[1].action, "statTotals", "action")
local d = player.sent[1].data
eq(d.crit.chance.total, 28, "chance from the engine"); eq(d.crit.chance.other, 16, "gear share"); eq(d.attributes[1].n, "Strength", "named")
eq(d.damage[1].n, "Physical damage", "damage named")
eq(h(player), true, "second request"); eq(#player.sent, 1, "inside the rate limit: no second answer")
ChaosPassiveTotals.last = {}
player.getSpecialSkill = nil
h(player); eq(#player.sent, 2, "answered again"); eq(player.sent[2].data.crit.chance.total, 12, "no engine binding: the tree share only")

-- ------------------------------------------------------------------------------------------------ the crit reach model
local R = dofile("tools/crit_reach.lua")
local o = R.compute()
eq(o.t8.chanceLo, 5, "T8 chance low"); eq(o.t8.chanceHi, 7, "T8 chance high"); eq(o.t8.amountHi, 10, "T8 amount high")
eq(o.slots, 8, "eight slots"); eq(o.gear.max, 56, "8 x 7"); eq(o.gear.min, 40, "8 x 5"); eq(o.gear.avg, 48, "8 x 6")
eq(o.t8.chanceHiQuality, 9, "7 at +30% quality"); eq(o.gear.maxQuality, 72, "8 x 9")
eq(o.t7.chanceHi, 6, "T7 high"); eq(o.gearT7.max, 48, "T7 everywhere")
ok(o.treeBest >= o.treeMedian and o.treeMedian >= o.treeWorst and o.treeWorst > 0, "tree crit sums ordered")
ok(o.casual < o.dedicated and o.dedicated < o.ceiling, "casual < dedicated < ceiling")
ok(o.suggestedThreshold % 5 == 0 and o.suggestedThreshold > o.casual and o.suggestedThreshold < o.dedicated, "threshold between the builds")
ok(o.suggestedThreshold <= 50, "a gated passive asks for at most 50%")
ok(R.report(o):find("suggested threshold", 1, true), "report")

print("softcap: " .. checks .. " checks OK")
