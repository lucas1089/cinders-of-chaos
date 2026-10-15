-- Run from the server/ folder: luajit tests/smartloot_test.lua (CI runs it with luajit and lua5.3)
-- Smart loot (smartloot_core.lua, smartloot_config.lua, smartloot.lua; server/README.md "Smart loot"): who may wear
-- what, the candidates of a loot table (only gear someone near can wear, weights added up), the pick (same kind first,
-- the fallback, never the same id), the plan (chance, cap per corpse, nothing without candidates, wearable drops kept)
-- and the engine side on a mocked corpse: party members near count, far ones do not, the item is transformed in place.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label or "check") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/smartloot_core.lua")
local K = ChaosSmartLootCore
local cfg = dofile("data/scripts/chaos/smartloot_config.lua")

-- ---------------------------------------------------------------- config
eq(type(cfg), "table", "config")
check(cfg.swapChance >= 0 and cfg.swapChance <= 100, "swap chance is a percent")
check(cfg.maxSwapsPerCorpse >= 1, "at least one swap per corpse")
check(cfg.partyRange > 0, "party range")

-- ---------------------------------------------------------------- items
-- 100 wand (mystic), 101 rod (mystic), 200 sword (warrior), 201 axe (warrior, level 80), 300 bow (ranger),
-- 400 plate armour (warrior), 500 ring (anyone, no rule), 600 gold (not gear)
local RULES = {
	[100] = {level = 7, vocs = {mystic = true, elementalist = true}},
	[101] = {level = 7, vocs = {mystic = true}},
	[200] = {level = 0, vocs = {warrior = true, juggernaut = true}},
	[201] = {level = 80, vocs = {warrior = true}},
	[300] = {level = 0, vocs = {ranger = true}},
	[400] = {level = 0, vocs = {warrior = true}}
}
local KIND = {[100] = "weapon", [101] = "weapon", [200] = "weapon", [201] = "weapon", [300] = "weapon", [400] = "armor",
	[500] = "ring"}
local function isGear(id) return KIND[id] ~= nil end
local function ruleOf(id) return RULES[id] end
local function kindOf(id) return KIND[id] or "other" end

local warrior = {voc = "warrior", level = 20}
local mystic = {voc = "mystic", level = 20}
check(K.usableBy(nil, warrior), "no rule: anyone")
check(K.usableBy(RULES[200], warrior), "a warrior wears a sword")
check(not K.usableBy(RULES[100], warrior), "a warrior does not wear a wand")
check(K.usableBy(RULES[201], warrior, false), "level ignored")
check(not K.usableBy(RULES[201], warrior, true), "level counted")
check(K.usableByAny(RULES[100], {warrior, mystic}), "a party with a mystic wears a wand")
check(not K.usableByAny(RULES[300], {warrior, mystic}), "nobody wears a bow")
check(not K.usableByAny(RULES[300], {}), "nobody at all")

-- ---------------------------------------------------------------- candidates
local LOOT = {
	{itemId = 600, chance = 100000}, {itemId = 100, chance = 5000}, {itemId = 200, chance = 3000},
	{itemId = 201, chance = 1000}, {itemId = 400, chance = 2000}, {itemId = 200, chance = 1000}, {itemId = 500, chance = 0}
}
local c = K.candidates(LOOT, {isGear = isGear, ruleOf = ruleOf, kindOf = kindOf, wearers = {warrior}})
eq(#c, 3, "sword, axe, plate: not the wand, not gold, not a zero chance")
eq(c[1].id, 200, "first the sword"); eq(c[1].weight, 4000, "the sword's two entries add up")
eq(c[1].kind, "weapon", "kind kept")
c = K.candidates(LOOT, {isGear = isGear, ruleOf = ruleOf, kindOf = kindOf, wearers = {warrior}, checkLevel = true})
eq(#c, 2, "the level 80 axe left out when the level counts")

-- ---------------------------------------------------------------- pick
local function fixed(v) return function(a, b) return math.max(a, math.min(b, v)) end end
local cands = {{id = 200, weight = 10, kind = "weapon"}, {id = 400, weight = 30, kind = "armor"}}
eq(K.pick(cands, "weapon", fixed(1), true).id, 200, "same kind")
eq(K.pick(cands, "armor", fixed(30), true).id, 400, "same kind armour")
eq(K.pick(cands, "ring", fixed(31), true).id, 400, "fallback by weight")
eq(K.pick(cands, "ring", fixed(1), false), nil, "no fallback")
eq(K.pick(cands, "weapon", fixed(1), true, 200).id, 400, "never the same id")

-- ---------------------------------------------------------------- plan
local function ctx(wearers, rolls, over)
	local i = 0
	local c2 = {}
	for k, v in pairs(cfg) do c2[k] = v end
	for k, v in pairs(over or {}) do c2[k] = v end
	return {cfg = c2, lootTable = LOOT, wearers = wearers, isGear = isGear, ruleOf = ruleOf, kindOf = kindOf,
		rnd = function(a, b) i = i + 1; local v = rolls[i] or a; return math.max(a, math.min(b, v)) end}
end
-- corpse: gold, a wand, a ring, a bow
local corpse = {600, 100, 500, 300}
local plan = K.plan(corpse, ctx({warrior}, {1, 1, 1, 1}))
eq(#plan, 2, "the wand and the bow swapped, gold and the ring kept")
eq(plan[1].index, 2, "the wand's slot"); eq(plan[1].from, 100); eq(KIND[plan[1].to], "weapon", "a weapon for a weapon")
check(K.usableBy(RULES[plan[1].to], warrior), "the warrior can wear it")
eq(plan[2].index, 4, "the bow's slot")
plan = K.plan(corpse, ctx({warrior}, {100, 100}, {swapChance = 50}))
eq(#plan, 0, "rolls over the chance: kept")
plan = K.plan(corpse, ctx({warrior, mystic}, {1, 1, 1, 1}))
eq(#plan, 1, "a mystic near: the wand stays, the bow is swapped"); eq(plan[1].from, 300)
plan = K.plan(corpse, ctx({warrior}, {1, 1, 1, 1}, {maxSwapsPerCorpse = 1}))
eq(#plan, 1, "cap per corpse")
plan = K.plan(corpse, ctx({warrior}, {1, 1}, {enabled = false}))
eq(#plan, 0, "off")
plan = K.plan(corpse, ctx({}, {1, 1}))
eq(#plan, 0, "nobody")
plan = K.plan(corpse, ctx({{voc = "thief", level = 1}}, {1, 1}))
eq(#plan, 0, "no candidate for a thief: kept")

-- ---------------------------------------------------------------- class weighting
local W = cfg.weights
check(W.classSpecific > W.usable and W.usable > W.unusable, "class items weigh most")
-- 700 templar mace (templar only), 701 thief dagger (thief only), 702 cloak (no rule), 600 gold
RULES[700] = {level = 0, vocs = {templar = true}}
RULES[701] = {level = 0, vocs = {thief = true}}
KIND[700], KIND[701], KIND[702] = "weapon", "weapon", "armor"
local templar = {voc = "templar", level = 100}
eq(K.classWeight(RULES[700], {templar}, W), W.classSpecific, "made for the class")
eq(K.classWeight(nil, {templar}, W), W.usable, "anyone's item")
eq(K.classWeight(RULES[701], {templar}, W), W.unusable, "another class's item")
eq(K.classWeight(RULES[700], {templar}, {}), 1, "no weights: 1")
local T2 = {{itemId = 600, chance = 50000}, {itemId = 700, chance = 1000}, {itemId = 701, chance = 1000},
	{itemId = 702, chance = 1000}}
local rw = K.reweight(T2, {cfg = cfg, wearers = {templar}, isGear = isGear, ruleOf = ruleOf})
eq(rw[1], T2[1], "gold untouched")
eq(rw[2].chance, 1500, "the Templar mace x3, scaled (3000 x 3 / 6)"); eq(rw[3].chance, 500, "the Thief dagger x1, scaled")
eq(rw[4].chance, 1000, "the cloak x2, scaled"); eq(T2[2].chance, 1000, "the monster's table is not changed")
eq(rw[2].chance + rw[3].chance + rw[4].chance, 3000, "as many gear drops as before")
check(rw[2].chance > rw[3].chance, "a Templar gets more Templar items than Thief items")
local thief = {voc = "thief", level = 100}
rw = K.reweight(T2, {cfg = cfg, wearers = {thief}, isGear = isGear, ruleOf = ruleOf})
check(rw[3].chance > rw[2].chance, "and a Thief more Thief items")
rw = K.reweight({{itemId = 700, chance = 90000}, {itemId = 701, chance = 90000}}, {cfg = cfg, wearers = {templar},
	isGear = isGear, ruleOf = ruleOf})
eq(rw[1].chance, 100000, "never over the stock maximum")
c = K.candidates({{itemId = 700, chance = 100}, {itemId = 702, chance = 100}}, {isGear = isGear, ruleOf = ruleOf,
	kindOf = kindOf, wearers = {templar}, weights = W})
eq(c[1].weight, 300, "swap candidate made for the class x3"); eq(c[2].weight, 200, "generic x2")

-- ---------------------------------------------------------------- engine side
WEAPON_NONE, WEAPON_SHIELD, WEAPON_SWORD = 0, 4, 1
SLOTP_HEAD, SLOTP_NECKLACE, SLOTP_ARMOR, SLOTP_LEGS, SLOTP_FEET, SLOTP_RING = 1, 4, 8, 32, 64, 128
local TYPES = {[100] = {w = 1}, [200] = {w = 1}, [300] = {w = 1}, [400] = {s = 8}, [500] = {s = 128}, [600] = {}}
function ItemType(id)
	local t = TYPES[id] or {}
	return {getWeaponType = function() return t.w or 0 end, getSlotPosition = function() return t.s or 0 end}
end
ChaosGamble = {rules = function() return RULES end}
ChaosLoot = {isGearId = isGear, isRolled = function() return false end}
dofile("data/scripts/chaos/smartloot.lua")
local SL = ChaosSmartLoot
eq(SL.kindOf(200), "weapon", "engine kind weapon"); eq(SL.kindOf(400), "armor", "engine kind armour")
eq(SL.kindOf(500), "ring", "engine kind ring"); eq(SL.kindOf(600), "other", "engine kind other")

local function mkItem(id)
	local it = {id = id}
	function it:getId() return self.id end
	function it:isContainer() return false end
	function it:transform(to) self.id = to; return true end
	return it
end
local function mkCorpse(ids, pos)
	local items = {}
	for i, id in ipairs(ids) do items[i] = mkItem(id) end
	return {items = items, getSize = function(self) return #self.items end,
		getItem = function(self, slot) return self.items[slot + 1] end,
		getPosition = function() return pos end}
end
local function mkPlayer(id, voc, level, pos, party)
	local p = {id = id}
	function p:getId() return self.id end
	function p:getVocation() return {getName = function() return voc end} end
	function p:getLevel() return level end
	function p:getPosition() return pos end
	function p:getParty() return party end
	return p
end
local here = {x = 100, y = 100, z = 7}
local w = mkPlayer(1, "Warrior", 50, here, nil)
local cp = mkCorpse({600, 100, 300}, here)
eq(SL.apply(cp, w, LOOT, function(a) return a end), 2, "two swaps")
eq(cp.items[1].id, 600, "gold kept")
check(RULES[cp.items[2].id] and RULES[cp.items[2].id].vocs.warrior, "the wand became warrior gear")
check(RULES[cp.items[3].id] and RULES[cp.items[3].id].vocs.warrior, "the bow became warrior gear")

local party = {}
local m = mkPlayer(2, "Mystic", 50, {x = 110, y = 100, z = 7}, party)
local far = mkPlayer(3, "Ranger", 50, {x = 500, y = 100, z = 7}, party)
local leader = mkPlayer(1, "Warrior", 50, here, party)
function party:getMembers() return {m, far} end
function party:getLeader() return leader end
local list = SL.wearers(leader, here)
eq(#list, 2, "the leader and the mystic near; the far ranger left out")
cp = mkCorpse({100, 300}, here)
eq(SL.apply(cp, leader, LOOT, function(a) return a end), 1, "the wand stays for the mystic")
eq(cp.items[1].id, 100, "wand kept")
ChaosSmartLootConfig.enabled = false
cp = mkCorpse({100}, here)
eq(SL.apply(cp, w, LOOT, function(a) return a end), 0, "off on the engine side")
ChaosSmartLootConfig.enabled = true
local rwe = SL.reweight(T2, mkPlayer(9, "Templar", 100, here, nil))
eq(rwe[2].chance, 1500, "engine reweight for the owner's class")
ChaosSmartLootConfig.enabled = false
eq(SL.reweight(T2, w), T2, "off: the table itself")
ChaosSmartLootConfig.enabled = true
ChaosGamble = nil
eq(SL.apply(mkCorpse({100}, here), w, LOOT, function(a) return a end), 0, "no rules: nothing")
eq(SL.reweight(T2, w), T2, "no rules: the table itself")

print(string.format("smartloot_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
