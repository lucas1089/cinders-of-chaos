-- Run from the server/ folder: luajit tests/loot_guarantee_test.lua (and lua5.3; CI runs both)
-- O575 (owner 2026-11-14: "make legendary monsters always drop good loot"): a kill of a Legendary tier monster
-- (monster_tiers.lua) always leaves at least one gear piece of Rare or better in the corpse (loot_config.lua
-- gear.guarantee). The kill's own gear counts first; a corpse short of gear gets one piece of the monster's loot table, else
-- a base of the killer's class near the level. Other tiers are untouched, and `enabled = false` is the old rule.

local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

Chaos = {}
MAX_LOOTCHANCE = 100000
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
-- ids 100-199 are gear, 200 is a stackable potion, 300 is an arrow (ammo), 400 a boat (excluded)
local function isGear(id) return (id >= 100 and id < 200) or id >= 1000 end
function ItemType(id)
	return {
		getId = function() return id end,
		isStackable = function() return id == 200 or id == 300 end,
		isContainer = function() return false end,
		getAmmoType = function() return id == 300 and 1 or 0 end,
		getArmor = function() return isGear(id) and 5 or 0 end,
		getAttack = function() return 0 end, getDefense = function() return 0 end,
		getExtraDefense = function() return 0 end, getHitChance = function() return 0 end,
		getName = function() return "item " .. id end,
		getAbilities = function() return nil end
	}
end
dofile("data/scripts/chaos/loot.lua")
local L, C = ChaosLoot, ChaosLootConfig
local R = ChaosRarity
ok(R ~= nil, "the rarity ladder is loaded")

-- ---------------------------------------------------------------- config
local g = C.gear.guarantee
ok(type(g) == "table" and g.enabled == true, "the guarantee is on")
local rule = L.guaranteeRule("legendary")
ok(rule and rule.pieces == 1 and rule.minRarity == 4, "legendary: 1 piece of Rare (stored id 4)")
ok(R.rank(rule.minRarity) == R.rank(C.gear.minRarity.legendary), "the guarantee floor is the tier's floor")
for _, t in ipairs({"normal", "magic", "rare", "boss", "nonsense"}) do
	ok(L.guaranteeRule(t) == nil, t .. ": no guarantee")
end
g.enabled = false
ok(L.guaranteeRule("legendary") == nil, "enabled = false: no rule")
g.enabled = true

-- ---------------------------------------------------------------- how many pieces are missing
ok(L.guaranteeMissing(rule, 0) == 1, "an empty corpse misses 1")
ok(L.guaranteeMissing(rule, 1) == 0, "one gear piece: nothing missing")
ok(L.guaranteeMissing(rule, 5) == 0, "five pieces: nothing missing")
ok(L.guaranteeMissing(nil, 0) == 0, "no rule: nothing")
ok(L.guaranteeMissing({pieces = 3, minRarity = 4}, 1) == 2, "3 pieces wanted, 1 held: 2 missing")

-- ---------------------------------------------------------------- candidates
local table1 = {{itemId = 200, chance = 50000}, {itemId = 120, chance = 1000}, {itemId = 300, chance = 100},
	{itemId = 121, chance = 10}, {itemId = 120, chance = 5}, {itemId = 400, chance = 1}}
local ids = L.guaranteeCandidates(table1, function(id) return id == 300 end)
table.sort(ids)
ok(#ids == 2 and ids[1] == 120 and ids[2] == 121, "candidates: gear only, once each, no potion / ammo / boat")
ok(#L.guaranteeCandidates({{itemId = 200, chance = 1}}) == 0, "a table without gear: none")
ok(#L.guaranteeCandidates(nil) == 0, "no table: none")

-- ---------------------------------------------------------------- the pick
L.setRandom(function(a, b) return b end)
ok(L.guaranteePick(table1, nil, 100, nil) == 121, "pick: the monster's own gear")
L.setRandom(function(a, b) return a end)
ok(L.guaranteePick(table1, nil, 100, nil) == 120, "pick: the first of the monster's own gear")
-- no gear in the table and no class: nothing (and no error)
ok(L.guaranteePick({{itemId = 200, chance = 1}}, {getVocation = function() return nil end}, 100, nil) == nil,
	"no table gear, no vocation: nil")
-- no gear in the table: a base of the killer's class near the level
ChaosClassLoot = dofile("data/lib/chaos_class_loot.lua")
local CL = ChaosClassLoot
local cls
for name, kinds in pairs(CL.classKinds) do
	if #kinds > 0 then
		cls = name
		break
	end
end
ok(cls ~= nil, "a class with weapon kinds exists")
local owner = {getVocation = function() return {getName = function() return cls end} end}
local pick = L.guaranteePick({{itemId = 200, chance = 1}}, owner, 150, nil)
local known = false
for _, kind in ipairs(CL.classKinds[cls]) do
	for _, b in ipairs(CL.eligible(kind, 150)) do
		known = known or b[1] == pick
	end
end
ok(pick ~= nil and known, "no table gear: a base of the class family near the level (" .. tostring(pick) .. ")")
L.setRandom(nil)

-- ---------------------------------------------------------------- the corpse
local function newCorpse(ids)
	local corpse = {items = {}}
	local function mk(id)
		return {id = id, attrs = {}, getId = function(self) return self.id end, isItem = function() return true end,
			setCustomAttribute = function(self, k, v) self.attrs[k] = v end,
			getCustomAttribute = function(self, k) return self.attrs[k] end}
	end
	for _, id in ipairs(ids) do
		corpse.items[#corpse.items + 1] = mk(id)
	end
	function corpse:getSize() return #self.items end
	function corpse:getItem(slot) return self.items[slot + 1] end
	function corpse:addItem(id, n)
		local it = mk(id)
		self.items[#self.items + 1] = it
		return it
	end
	return corpse
end
-- the gear test of this mock: every non-stackable with an armour value
local gearTable = {{itemId = 150, chance = 100}, {itemId = 200, chance = 1}}

local corpse = newCorpse({200, 200})
local names = L.guaranteeGear(corpse, nil, owner, "legendary", 150, gearTable, nil)
ok(#names == 1 and corpse:getSize() == 3, "a legendary corpse without gear gets 1 piece")
ok(corpse:getItem(2):getId() == 150, "it is the monster's own gear")

corpse = newCorpse({200, 151})
names = L.guaranteeGear(corpse, nil, owner, "legendary", 150, gearTable, nil)
ok(#names == 0 and corpse:getSize() == 2, "a corpse with gear gets none extra")

corpse = newCorpse({})
names = L.guaranteeGear(corpse, nil, owner, "magic", 150, gearTable, nil)
ok(#names == 0 and corpse:getSize() == 0, "a magic corpse is left as it is")

corpse = newCorpse({})
names = L.guaranteeGear(corpse, nil, owner, "boss", 150, gearTable, nil)
ok(#names == 0 and corpse:getSize() == 0, "a boss corpse is left as it is")

g.enabled = false
corpse = newCorpse({})
names = L.guaranteeGear(corpse, nil, owner, "legendary", 150, gearTable, nil)
ok(#names == 0 and corpse:getSize() == 0, "disabled: the old rule")
g.enabled = true

-- the guarantee holds over every roll of the pick
for seed = 1, 200 do
	math.randomseed(seed)
	L.setRandom(function(a, b) return math.random(a, b) end)
	local c2 = newCorpse({200})
	L.guaranteeGear(c2, nil, owner, "legendary", 150, {{itemId = 150, chance = 1}, {itemId = 151, chance = 1},
		{itemId = 152, chance = 1}}, nil)
	local n = 0
	for slot = 0, c2:getSize() - 1 do
		n = n + (L.isGearId(c2:getItem(slot):getId()) and 1 or 0)
	end
	ok(n == 1, "seed " .. seed .. ": exactly one gear piece")
end
L.setRandom(nil)

-- ---------------------------------------------------------------- the floor over the corpse's gear
local floorId = rule.minRarity
local function raised(gear) return L.guaranteeRaise(rule, gear) end
ok(#raised({}) == 0, "no gear: nothing to raise")
ok(#raised({{rarity = 4, raisable = true}}) == 0, "a Rare piece satisfies it")
ok(#raised({{rarity = 5, raisable = true}}) == 0, "a Legendary piece satisfies it")
ok(#raised({{rarity = 10, raisable = true}}) == 0, "a Divine piece satisfies it")
local r1 = raised({{rarity = 0, raisable = true}})
ok(#r1 == 1 and r1[1].index == 1 and r1[1].target == floorId, "a plain piece is raised to Rare")
local r2 = raised({{rarity = 1, raisable = true}, {rarity = 3, raisable = true}, {rarity = 2, raisable = true}})
ok(#r2 == 1 and r2[1].index == 2 and r2[1].target == floorId, "the best of the low pieces is raised (Magic, not Common)")
local r3 = raised({{rarity = 3, raisable = true}, {rarity = 5, raisable = true}})
ok(#r3 == 0, "one good piece among low ones: no raise")
local r4 = raised({{rarity = 0, raisable = false}})
ok(#r4 == 0, "a rolled piece is never touched")
local r5 = raised({{rarity = 0, raisable = false}, {rarity = 2, raisable = true}})
ok(#r5 == 1 and r5[1].index == 2, "only a raisable piece is raised")
ok(#L.guaranteeRaise(nil, {{rarity = 0, raisable = true}}) == 0, "no rule: nothing")
local two = {pieces = 2, minRarity = 4}
local r6 = L.guaranteeRaise(two, {{rarity = 1, raisable = true}, {rarity = 5, raisable = true}, {rarity = 3, raisable = true}})
ok(#r6 == 1 and r6[1].index == 3, "2 pieces wanted, 1 good: the best low one is raised")

-- an old stored id (7 = old Legendary of the 15 rarities) counts by its rank
ok(#raised({{rarity = 7, raisable = true}}) == 0, "an old id of Rare or better counts by rank")

-- ---------------------------------------------------------------- the floor equals the tier's floor, the better chance stays
ok(C.gear.bonusChance.legendary > 0 and C.gear.divineChance.legendary > 0, "a chance of better stays on the tier")
ok(C.gear.ensureChance.legendary == 100, "the tier floor is applied to every gear drop")

print(string.format("loot_guarantee_test: %d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)
