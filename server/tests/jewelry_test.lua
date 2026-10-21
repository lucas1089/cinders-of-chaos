-- Run from the server/ folder: luajit tests/jewelry_test.lua (and lua5.3; CI runs both)
-- Rings and necklaces as gear (server/README.md "Rings and necklaces as gear"): data/lib/chaos_jewelry.lua (the
-- consumables, the loot bases and rows, old copies) and the jewelry gates of data/scripts/chaos/loot.lua.
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local J = dofile("data/lib/chaos_jewelry.lua")

-- consumables: both ids of a pair, and no loot base is one
for _, id in ipairs({2164, 2165, 2202, 2167, 2204, 2169, 2206, 2213, 2215, 2173, 2197, 10218, 10219, 10220, 10221}) do
	ok(J.isConsumable(id), "consumable " .. id)
end
ok(not J.isConsumable(2207) and not J.isConsumable("2198") and not J.isConsumable(nil), "gear is no consumable")
for kind, list in pairs(J.bases) do
	local last = 0
	for _, b in ipairs(list) do
		ok(not J.isConsumable(b.id), kind .. " base " .. b.id .. " is no consumable")
		ok(b.level >= last, kind .. " bases sorted by level at " .. b.id)
		last = b.level
	end
end

-- eligible: the window, then the fallback
local function ids(list)
	local out = {}
	for _, b in ipairs(list) do out[#out + 1] = b.id end
	return table.concat(out, ",")
end
eq(ids(J.eligible("ring", 1)), "2168,2166,2207,2208,2209,2214", "level 1: the rings up to level 1 + 50")
eq(ids(J.eligible("ring", 50)), "2168,2166,2207,2208,2209,2214,6300", "level 50: up to the death ring")
eq(ids(J.eligible("ring", 300)), "18408,28691,26808", "level 300: the window drops the low rings")
eq(ids(J.eligible("ring", 2000)), "18408,28691,26808", "level 2000: the three highest (fallback)")
eq(ids(J.eligible("necklace", 1000)), "26807,27251,27215", "level 1000: the three highest necklaces")
eq(#J.eligible("ring", -100), 0, "a level below every base: none")
eq(#J.eligible("nothing", 100), 0, "unknown kind: none")

-- lootRows: one slot's share per kind, split over the bases, a floor per row
local pool = {
	hunt = {{name = "rat", level = 1}, {name = "dragon", level = 50}},
	bosses = {{name = "the boss", level = 300}}
}
local rows = J.lootRows(pool)
local by = {}
for _, r in ipairs(rows) do
	by[r[1]] = by[r[1]] or {}
	by[r[1]][r[2]] = r[3]
end
eq(by.rat[2168], 12, "rat: 75 / 6 rings")
eq(by.rat[2214], 12, "rat: ring of healing")
eq(by.rat[6300], nil, "rat: no death ring")
eq(by.rat[2172], 10, "rat: 75 / 7 necklaces")
eq(by.rat[2199], 10, "rat: garlic necklace")
eq(by.dragon[2168], 10, "dragon: 75 / 7 rings")
eq(by.dragon[6300], 10, "dragon: death ring")
eq(by["the boss"][26808], 633, "boss: 1900 / 3")
local hi = J.lootRows({hunt = {{name = "x", level = 150}}}, function(e) return e.level * 2 end)
eq(hi[1][2], 18408, "a levelOf is used: level 300 drops from the prismatic ring")
local tight = {monsterChance = {ring = 20, necklace = 0}, bossChance = {ring = 0, necklace = 0}, minChance = 5,
	window = J.config.window, fallback = 3}
local trow = J.lootRows({hunt = {{name = "dragon", level = 50}}}, nil, tight)
eq(#trow, 7, "no necklace rows with a chance of 0")
eq(trow[1][3], 5, "the floor: 20 / 7 -> 5")
eq(#J.lootRows(nil), 0, "no pool: no rows")

-- chancePerKill: never more than one slot's share (the floor aside)
for _, level in ipairs({1, 50, 100, 300, 500, 800, 1000, 1500}) do
	local c = J.chancePerKill(level)
	ok(c.ring <= 75 and c.ring >= 70, "ring per kill at " .. level .. ": " .. c.ring)
	ok(c.necklace <= 75 and c.necklace >= 70, "necklace per kill at " .. level .. ": " .. c.necklace)
	local b = J.chancePerKill(level, true)
	ok(b.ring <= 1900 and b.ring >= 1890, "boss ring per kill at " .. level .. ": " .. b.ring)
end

-- normalize: old copies lose their charges and time; consumables and others keep them
local ATTR = {charges = 1, duration = 2}
local function itemOf(id, attrs)
	local it = {id = id, a = attrs}
	function it:getId() return self.id end
	function it:getAttribute(k) return self.a[k] or 0 end
	function it:removeAttribute(k) self.a[k] = nil return true end
	return it
end
local function typeOf(slot, charges, duration, stackable)
	return {
		getSlotPosition = function() return slot end,
		getCharges = function() return charges or 0 end,
		getDuration = function() return duration or 0 end,
		isStackable = function() return stackable == true end
	}
end
ok(J.isJewelType(typeOf(2 + 48)) and J.isJewelType(typeOf(256 + 48)), "necklace and ring slots")
ok(not J.isJewelType(typeOf(1 + 48)) and not J.isJewelType(typeOf(4096)) and not J.isJewelType(nil), "head, badge, nil")
local elven = itemOf(2198, {[1] = 37})
eq(J.normalize(elven, typeOf(2 + 48), ATTR), 1, "elven amulet: charges go")
eq(elven.a[1], nil, "elven amulet: no charges attribute")
eq(J.normalize(elven, typeOf(2 + 48), ATTR), 0, "second pass: nothing")
local sword = itemOf(2210, {[2] = 900000})
eq(J.normalize(sword, typeOf(256 + 48), ATTR), 1, "worn sword ring: the time left goes")
local both = itemOf(18408, {[1] = 3, [2] = 5})
eq(J.normalize(both, typeOf(256), ATTR), 2, "both attributes")
local stone = itemOf(2197, {[1] = 4})
eq(J.normalize(stone, typeOf(2 + 48), ATTR), 0, "a consumable keeps its charges")
eq(stone.a[1], 4, "stone skin amulet: charges kept")
local keeps = itemOf(9999, {[1] = 4})
eq(J.normalize(keeps, typeOf(2, 5), ATTR), 0, "a type with charges keeps them")
eq(J.normalize(itemOf(2400, {[1] = 4}), typeOf(48), ATTR), 0, "a weapon is left alone")
eq(J.normalize(itemOf(1, {[1] = 4}), typeOf(256, 0, 0, true), ATTR), 0, "a stackable is left alone")
eq(J.normalize(nil, typeOf(256), ATTR), 0, "no item")

-- the loot layer's gates
MAX_LOOTCHANCE = 100000
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
local TYPES = {
	[2168] = {slot = 256 + 48, abilities = {healthGain = 1, manaGain = 4}}, -- life ring: regeneration only
	[2165] = {slot = 256 + 48, abilities = {healthGain = 0}, }, -- stealth ring: consumable
	[2197] = {slot = 2 + 48, armor = 0, abilities = {absorbPercent = {80}}}, -- stone skin amulet: consumable
	[2200] = {slot = 2 + 48, armor = 1, abilities = {}}, -- protection amulet: armour
	[1001] = {slot = 1 + 48, abilities = {healthGain = 2}}, -- a helmet with regeneration only: not by that rule
	[10310] = {slot = 256 + 48, abilities = {}} -- a ring without stats
}
function ItemType(id)
	local t = TYPES[id] or {slot = 48, abilities = {}}
	return {
		getId = function() return id end,
		getName = function() return "item " .. id end,
		isContainer = function() return false end,
		isStackable = function() return false end,
		getAmmoType = function() return 0 end,
		getAttack = function() return 0 end,
		getDefense = function() return 0 end,
		getArmor = function() return t.armor or 0 end,
		getHitChance = function() return 0 end,
		getSlotPosition = function() return t.slot end,
		getAbilities = function() return t.abilities end,
		getWeaponType = function() return 0 end
	}
end
dofile("data/scripts/chaos/loot.lua")
local L = ChaosLoot
ok(L.isGearId(2168), "life ring is gear (regeneration on a ring)")
ok(L.isGearId(2200), "protection amulet is gear")
ok(not L.isGearId(2165), "stealth ring is no gear")
ok(not L.isGearId(2197), "stone skin amulet is no gear, absorbs and all")
ok(not L.isGearId(1001), "regeneration alone makes no other slot gear")
ok(not L.isGearId(10310), "a ring without stats is no gear")

local function rolled(id, rarity)
	local it = {id = id, a = {rarity = rarity}}
	function it:getId() return self.id end
	function it:getCustomAttribute(k) return self.a[k] end
	function it:removeCustomAttribute(k) self.a[k] = nil return true end
	return it
end
local stealth, life = rolled(2165, 2), rolled(2168, 2)
eq(L.stripStackableRarity({stealth, life}), 1, "one consumable cleared")
eq(stealth:getCustomAttribute("rarity"), nil, "stealth ring: no rarity")
eq(life:getCustomAttribute("rarity"), 2, "life ring keeps its rarity")

-- the game file loads with a mocked engine
local registered = {}
local function event(kind)
	return function(name)
		local e = {name = name}
		function e:register() registered[#registered + 1] = kind .. ":" .. tostring(name) return true end
		return e
	end
end
GlobalEvent, CreatureEvent = event("global"), event("creature")
EventCallback = {register = function() registered[#registered + 1] = "callback" end}
ITEM_ATTRIBUTE_CHARGES, ITEM_ATTRIBUTE_DURATION = 1, 2
local added = {}
function MonsterType(name)
	if name == "ghost" then return nil end
	return {addLoot = function(_, loot) added[#added + 1] = {name, loot.id, loot.chance} return true end}
end
function Loot()
	local l = {}
	function l:setId(v) self.id = v end
	function l:setChance(v) self.chance = v end
	function l:setMaxCount(v) self.max = v end
	return l
end
local print0 = print
print = function() end
dofile("data/scripts/chaos/jewelry.lua")
local a, s = ChaosJewelryLoot.addAll({{"rat", 2168, 75}, {"ghost", 2168, 75}})
print = print0
eq(a, 1, "one row added")
eq(s, 1, "a missing monster skipped")
eq(added[1][2], 2168, "the life ring")
eq(added[1][3], 75, "its chance")
eq(ChaosJewelryLoot.addAll({{"rat", 2168, 75}}), 0, "once per server run")
eq(#registered, 3, "a startup event, the move callback, the login event")
local old = itemOf(2198, {[1] = 9})
TYPES[2198] = {slot = 2 + 48, abilities = {}}
eq(ChaosJewelryLoot.normalize(old), 1, "the game normalize reads the item type")
eq(ChaosJewelryLoot.normalize(nil), 0, "nil item")

-- uniques on consumable bases: their own bases, old copies turn
eq(#J.uniqueBases, 3, "three unique bases")
for i, b in ipairs(J.uniqueBases) do
	eq(b.id, 41639 + i, "unique base id " .. i)
	ok(not J.isConsumable(b.id), "unique base " .. b.id .. " is no consumable")
	for _, f in ipairs(b.from) do
		ok(J.isConsumable(f), "old base " .. f .. " is a consumable")
	end
end
eq(J.uniqueTarget(2206, true), 41640, "worn time ring with the marker")
eq(J.uniqueTarget(2169, false, "Ring of the Last Ember"), 41640, "time ring by its name (before the marker)")
eq(J.uniqueTarget("10218", true), 41641, "Heart of Cinders")
eq(J.uniqueTarget(10221, false, "Heartbleed Pendant"), 41642, "Heartbleed Pendant by name")
eq(J.uniqueTarget(2169, false, nil), nil, "a plain time ring stays")
eq(J.uniqueTarget(10218, false, "Heartbleed Pendant"), nil, "another unique's name: no")
eq(J.uniqueTarget(41641, true), nil, "already moved")
eq(J.uniqueTarget(2207, true), nil, "another unique base")
-- the specs and the drop list name the new ids
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_DEFENSE, ITEM_ATTRIBUTE_EXTRADEFENSE = 11, 12, 13
ITEM_ATTRIBUTE_ARMOR, ITEM_ATTRIBUTE_HITCHANCE, ITEM_ATTRIBUTE_SHOOTRANGE = 14, 15, 16
dofile("data/lib/chaos_unique_specs.lua")
for _, b in ipairs(J.uniqueBases) do
	ok(ChaosUniqueSpecs[b.id] and ChaosUniqueSpecs[b.id].name == b.unique, "spec of " .. b.unique .. " at " .. b.id)
	for _, f in ipairs(b.from) do
		eq(ChaosUniqueSpecs[f], nil, "no spec left on " .. f)
	end
end

ITEM_ATTRIBUTE_NAME = 99
MESSAGE_EVENT_ADVANCE = 19
CONST_SLOT_BACKPACK, CONST_SLOT_NECKLACE, CONST_SLOT_RING, CONST_SLOT_FIRST, CONST_SLOT_LAST = 3, 2, 9, 1, 10
Chaos = Chaos or {}
Chaos.t = function(_, text) return text end
TYPES[41640] = {slot = 256 + 48, abilities = {speed = 20}}
TYPES[41641] = {slot = 2 + 48, abilities = {}}
local function uitem(id, attrs, custom)
	local it = itemOf(id, attrs or {})
	it.c = custom or {}
	function it:getCustomAttribute(k) return self.c[k] end
	local getA = it.getAttribute
	function it:getAttribute(k)
		if k == ITEM_ATTRIBUTE_NAME then return self.name end
		return getA(self, k)
	end
	function it:transform(id2) self.id = id2 return true end
	function it:moveTo(bag)
		if bag.full then return false end
		if self.id == 2206 then self.id = 2169 end -- the worn time ring's DeEquip
		bag.list[#bag.list + 1] = self
		self.slot = nil
		return true
	end
	return it
end
local heart = uitem(10218, {[1] = 3}, {chaos_unique = 1})
ok(ChaosJewelryLoot.migrateUnique(heart), "a Heart of Cinders turns")
eq(heart.id, 41641, "into 41641")
eq(heart.a[1], nil, "its charges go (the new type has none)")
ok(not ChaosJewelryLoot.migrateUnique(heart), "only once")
ok(not ChaosJewelryLoot.migrateUnique(uitem(10218, {[1] = 5})), "a plain bonfire amulet stays")
-- the move callback: not into a slot
local pend = uitem(10221, {}, {chaos_unique = 1})
EventCallback.onItemMoved(nil, pend, 1, {}, {x = 65535, y = CONST_SLOT_NECKLACE, z = 0})
eq(pend.id, 10221, "moved into the necklace slot: left for the next login")
EventCallback.onItemMoved(nil, pend, 1, {}, {x = 65535, y = 64, z = 0})
eq(pend.id, 41642, "moved into a container: turns")
-- login: the worn ring goes to the backpack, then turns; the backpack's copies turn
local bag = {list = {}}
local legacyRing = uitem(2206, {[2] = 300000})
legacyRing.name = "Ring of the Last Ember"
local inBag = uitem(10221, {}, {chaos_unique = 1})
bag.list[1] = inBag
local backpack = {isContainer = function() return true end, getItems = function() return bag.list end,
	moveTarget = bag}
local slots = {[CONST_SLOT_RING] = legacyRing, [CONST_SLOT_BACKPACK] = backpack}
local said = {}
local player = {getSlotItem = function(_, s) return slots[s] end,
	sendTextMessage = function(_, _, text) said[#said + 1] = text end}
local mv = legacyRing.moveTo
function legacyRing:moveTo(target) local r = mv(self, bag) if r then slots[CONST_SLOT_RING] = nil end return r end
eq(ChaosJewelryLoot.migratePlayer(player), 2, "login: two copies turn")
eq(legacyRing.id, 41640, "the worn ring is an ember ring now")
eq(legacyRing.a[2], nil, "its time left goes")
eq(slots[CONST_SLOT_RING], nil, "taken off")
eq(inBag.id, 41642, "the copy in the backpack turns")
eq(#said, 1, "one message for the worn copy")
eq(ChaosJewelryLoot.migratePlayer(player), 0, "a second login: nothing")
bag.full = true
local worn = uitem(10218, {[1] = 2}, {chaos_unique = 1})
slots[CONST_SLOT_NECKLACE] = worn
eq(ChaosJewelryLoot.migratePlayer(player), 0, "a full backpack: the worn copy stays")
eq(worn.id, 10218, "still the old id, for the next login")

if fails > 0 then
	print(string.format("jewelry_test: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("jewelry_test: OK (%d checks)", checks))
