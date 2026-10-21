-- Run from the server/ folder: luajit tests/crafting_test.lua (and lua5.3; CI runs both)
-- The crafting orbs (data/lib/chaos_crafting.lua) against a mocked item: eligibility, what every orb does, the
-- modifier slot limits, the description text, and that uniques are never touched. Also the Chaos item modifiers through
-- the orbs (Grafting adds, Unmaking removes, Upheaval / Erasure), the bench preview, and the orbs on Rift Keys.

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- engine mock
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME = 1, 2
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_ARMOR = 11, 12
INDEX_WHEREEVER, FLAG_NOLIMIT, RETURNVALUE_NOERROR = -1, 1, 0

local TYPES = {
	[2400] = {name = "magic sword", weaponType = 1, attack = 48, slot = 48}, -- a weapon
	[2466] = {name = "golden armor", armor = 14, slot = 8},                -- body armor: no element modifiers
	[2160] = {name = "crystal coin", stackable = true},                   -- not gear
	[1988] = {name = "backpack", container = true, slot = 4},
	[8925] = {name = "solar axe", weaponType = 3, attack = 52, slot = 48, element = 12}, -- own element
	[27797] = {name = "boat", armor = 1, slot = 8}                         -- excluded id
}

function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getName = function() return t.name or "" end,
		isContainer = function() return t.container == true end,
		isStackable = function() return t.stackable == true end,
		getWeaponType = function() return t.weaponType or 0 end,
		getSlotPosition = function() return t.slot or 0 end,
		getArmor = function() return t.armor or 0 end,
		getAttack = function() return t.attack or 0 end,
		getDefense = function() return 0 end,
		getHitChance = function() return 0 end,
		getElementDamage = function() return t.element or 0 end,
		getAbilities = function() return {} end
	}
end

local Item = {}
Item.__index = Item
local function newItem(id, count)
	return setmetatable({id = id, count = count or 1, attrs = {}, custom = {}, removed = false}, Item)
end
function Item:getId() return self.id end
function Item:getCount() return self.count end
function Item:getName() return self.attrs[ITEM_ATTRIBUTE_NAME] or ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:getAttribute(k) return self.attrs[k] or (k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil) end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:getParent() return self.parent end
function Item:getActionId() return self.aid or 0 end
function Item:setActionId(a) self.aid = a end
function Item:remove() self.removed = true
	if self.parent then
		for i, it in ipairs(self.parent.items) do
			if it == self then table.remove(self.parent.items, i) break end
		end
	end
	return true
end

local bag = {items = {}}
function bag:addItemEx(item, index, flags)
	self.items[#self.items + 1] = item
	item.parent = self
	return RETURNVALUE_NOERROR
end
local function put(item)
	bag:addItemEx(item)
	return item
end

-- the engine's rarity roll, simplified: an item level, the stat bonus and two modifiers
local engineRolls = 0
Game = {
	createItem = function(id, count) return newItem(id, count) end,
	createItemWithRarity = function(id, count, rarity)
		engineRolls = engineRolls + 1
		local it = newItem(id, count)
		if (TYPES[id] or {}).slot then
			it:setCustomAttribute("rarity", rarity)
			it:setCustomAttribute("combatPowerLevel", rarity * 10 - 3)
			it:setCustomAttribute("rarity_swordSkill", 1)
			it:setCustomAttribute("rarity_earthAbsorb", 1)
			it:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "Level: " .. (rarity * 10 - 3) .. ", Earth +1%, Sword +1")
		end
		return it
	end
}

dofile("data/lib/chaos_crafting.lua")
local C = ChaosCrafting
local M = ChaosItemMods
-- drops roll with M.random (forgeDrop's default); tests pass their own dice
M.random = function(a, b) return a end
-- deterministic dice: queue values, else the lowest
local dice = {}
C.random = function(a, b)
	local v = table.remove(dice, 1)
	if v == nil then
		return a
	end
	assert(v >= a and v <= b, "dice value " .. v .. " outside " .. a .. ".." .. b)
	return v
end

-- an item as the engine makes it with rarity r and the given modifiers
local function rareItem(id, r, mods)
	local it = put(newItem(id))
	it:setCustomAttribute("rarity", r)
	it:setCustomAttribute("combatPowerLevel", 42)
	for k, v in pairs(mods or {}) do
		it:setCustomAttribute(k, v)
	end
	C.rewriteDescription(it)
	return it
end

-- ---------------------------------------------------------------- reading (an old item: no stored tiers)
local sword = rareItem(2400, 4, {rarity_physicalAbsorb = 2, rarity_swordSkill = 1, rarity_criticalHitChance = 2,
	rarity_criticalHitAmount = 2, rarity_elementfire = 7})
local mods = C.readMods(sword)
eq(#mods, 4, "critical chance + amount is ONE modifier")
eq(mods[1].group, "absorb")
eq(mods[3].group, "special")
eq(mods[1].side, "suffix", "absorbs are suffixes (resistances)")
eq(mods[2].side, "prefix", "combat skills are prefixes (damage)")
eq(mods[3].side, "prefix", "critical is a prefix")
eq(mods[4].side, "prefix", "element damage is a prefix")
eq(mods[1].tier, 2, "Physical +2%: T2 (1-2) from the value")
eq(mods[3].tier, 2, "the pair's tier from its amount (2: T2)")
eq(mods[4].tier, 3, "Fire +7% dmg: T3 (5-9)")
eq(mods[4].lo, 5); eq(mods[4].hi, 9)
eq(sword:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION),
	"Item Level: 42. Prefixes: Melee +1 (T1); Critical Chance +2%, Critical Hit +2% (T2); Fire +7% dmg (T3). " ..
	"Suffixes: Physical +2% (T2)", "item level, prefixes and suffixes with their tiers")
eq(C.rarityOf(sword), 4)
eq(C.rarityName(4), "Rare")
eq(C.rarityName(6), "Legendary", "an old Exotic reads as Legendary")
eq(C.rarityName(15), "Divine", "an old Transcendent reads as Divine")
eq(C.rarityOf(rareItem(2466, 9, {})), 5, "an old Eternal: stored id 5")
eq(C.rarityOf(rareItem(2466, 12, {})), 10, "an old Celestial: stored id 10")
eq(C.levelOf(sword), 42, "an old item's level: combatPowerLevel")
-- keys are case-insensitive like the engine's (the stock equip script reads rarity_FireAbsorb)
local fireArmor = rareItem(2466, 2, {rarity_FireAbsorb = 1})
eq(C.readMods(fireArmor)[1].label, "Fire", "rarity_FireAbsorb is the fire absorb")
-- old values above every range: the top tier
local big = rareItem(2400, 15, {rarity_elementholy = 40})
eq(C.readMods(big)[1].tier, 8, "an old +40% element: T8")
-- a shielded drop (rarity as text while the engine's pass runs) reads the same
local shielded = rareItem(2466, 3, {})
shielded:setCustomAttribute("rarity", "3")
eq(C.rarityOf(shielded), 3)
eq(C.unshield(shielded), true); eq(shielded:getCustomAttribute("rarity"), 3); eq(C.unshield(shielded), false)

-- ---------------------------------------------------------------- the affix list
local aff = C.affixes()
eq(#aff, 10 + 15 + 3 + #M.config.mods + 8, "every type once")
local seen = {}
for _, a in ipairs(aff) do
	assert(not seen[a.key:lower()], "unique key " .. a.key)
	seen[a.key:lower()] = true
	eq(#a.tiers, 8, a.key .. ": eight tiers")
	assert(a.side == "prefix" or a.side == "suffix", a.key)
	assert(a.weight > 0, a.key)
end
eq(C.affixOf("rarity_fishingSkill").side, "suffix", "profession skills are utility")
eq(C.affixOf("rarity_lifeLeechChance").side, "suffix", "leech is sustain")
eq(C.affixOf("chaos_mod_movespeed").side, "suffix")
eq(C.affixOf("CHAOS_MOD_BLOCK").side, "prefix", "case-insensitive")

-- ---------------------------------------------------------------- eligibility
local coin = put(newItem(2160, 5))
eq(C.check("exalted", coin), false, "coins are not gear")
local bp = put(newItem(1988))
eq(select(2, C.check("transmutation", bp)), "notGear", "containers are not gear")
eq(select(2, C.check("transmutation", put(newItem(27797)))), "notGear", "boats are excluded")
eq(select(2, C.check("nothing", sword)), "unknownOrb")
local normal = put(newItem(2400))
eq(C.isNormal(normal), true)
normal:setCustomAttribute("chaos_ilvl", 80)
eq(C.isNormal(normal), true, "a plain drop's item level keeps it normal")
eq(C.check("transmutation", normal), true, "transmutation on a normal item")
eq(C.check("alchemy", normal), true, "alchemy on a normal item")
eq(select(2, C.check("exalted", normal)), "needRarity", "exalted needs a rarity")
eq(select(2, C.check("annulment", normal)), "needRarity")
eq(select(2, C.check("scouring", normal)), "needRarity")
eq(select(2, C.check("chaos", normal)), "needRarity", "chaos keeps the rarity, so it needs one")
eq(C.check("divine", normal), true, "the stock divine roll works on any gear")
eq(select(2, C.check("transmutation", sword)), "needNormal", "transmutation refuses a rarity item")
-- an item level without a rarity (upgrade scripts) is not normal either
local upgraded = put(newItem(2466))
upgraded:setCustomAttribute("combatPowerLevel", 5)
eq(select(2, C.check("alchemy", upgraded)), "needNormal", "upgraded item is not normal")

-- ---------------------------------------------------------------- uniques
local unique = put(newItem(2400))
unique:setCustomAttribute("chaos_unique", 1)
unique:setCustomAttribute("rarity_swordSkill", 4)
for _, orb in ipairs(C.config.orbs) do
	eq(select(2, C.check(orb.key, unique)), "unique", "unique refused by " .. orb.key)
	local ok, msg = C.apply(orb.key, unique)
	eq(ok, false, "apply refused: " .. orb.key)
	eq(msg, C.reasons.unique)
end
eq(unique:getCustomAttribute("rarity_swordSkill"), 4, "unique untouched")
eq(unique.removed, false, "unique not replaced")
eq(#C.forgeDrop(unique, 100), 0, "drops: uniques never")
-- an old unique without the marker: recognised by its spec name
ChaosUniqueSpecs = {[2466] = {name = "Ironclad Bulwark"}}
local oldUnique = put(newItem(2466))
oldUnique:setAttribute(ITEM_ATTRIBUTE_NAME, "Ironclad Bulwark")
eq(C.isUnique(oldUnique), true, "unique by spec name")
eq(C.isUnique(put(newItem(2466))), false, "a plain copy of the base item is not unique")
ChaosUniqueSpecs = nil

-- ---------------------------------------------------------------- limits: prefixes and suffixes
eq(C.maxMods(1), 2); eq(C.maxMods(4), 4); eq(C.maxMods(5), 6); eq(C.maxMods(10), 6); eq(C.maxMods(15), 6, "an old id counts as the rarity it became")
local full = rareItem(2466, 1, {rarity_physicalAbsorb = 1, rarity_clubSkill = 1})
eq(select(2, C.check("exalted", full)), "full", "a Common item: one prefix and one suffix, full")
eq(C.apply("exalted", full), false)
eq(#C.readMods(full), 2, "nothing added to a full item")
eq(C.check("annulment", full), true, "a full item can still be annulled")
-- two suffixes on a Rare item (2 + 2): only prefixes can come
local twoSuf = rareItem(2466, 4, {rarity_physicalAbsorb = 1, rarity_iceAbsorb = 1})
for _, row in ipairs(C.candidates(twoSuf)) do
	eq(row.entry.side, "prefix", "suffixes full: " .. row.entry.key)
end
-- an old item with more suffixes than today's limit and room in total: the prefixes still open
local legacy = rareItem(2466, 4, {rarity_physicalAbsorb = 1, rarity_iceAbsorb = 1, rarity_fireAbsorb = 1})
eq(C.check("exalted", legacy), true, "3 of 4, the prefix side open")
local legacyFull = rareItem(2466, 4, {rarity_physicalAbsorb = 1, rarity_iceAbsorb = 1, rarity_fireAbsorb = 1,
	rarity_deathAbsorb = 1})
eq(select(2, C.check("exalted", legacyFull)), "full")

-- ---------------------------------------------------------------- Orb of Grafting
-- armor, item level 42 (T1-T3 can roll, best first). Lowest dice: the first candidate (Physical, a suffix), the first
-- tier row (T3), the lowest value of T3 (1)
local armor = rareItem(2466, 4, {rarity_holyAbsorb = 2})
dice = {}
local ok, res = C.apply("exalted", armor)
eq(ok, true, "exalted on armor")
eq(res.added.key, "rarity_physicalAbsorb")
eq(res.added.tier, 3, "T3: the best tier item level 42 allows (lowest dice)")
eq(armor:getCustomAttribute("ct_rarity_physicalabsorb"), 3, "tier stored")
eq(armor:getCustomAttribute("rarity_physicalAbsorb"), 3, "the lowest value of T3 (3-5 since the ranges were raised)")
eq(res.text, "golden armor gained Physical +3% (T3) (suffix).")
eq(armor:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Item Level: 42. Suffixes: Physical +3% (T3); Holy +2% (T2)")
-- the tier roll: highest dice = the last row (T1)
dice = {1, 270, 1}
ok, res = C.apply("exalted", armor)
eq(res.added.tier, 1, "highest tier dice: T1")
eq(res.added.key, "rarity_fistSkill", "two suffixes on a Rare item: the first prefix")
-- a critical / leech pair: the chance is two thirds of the roll, the amount the roll
local pair = rareItem(2466, 4, {})
local pm = C.writeAffix(pair, C.affixOf("rarity_manaLeechChance"), 4, 3)
eq(pair:getCustomAttribute("rarity_manaLeechChance"), 2, "the chance is two thirds of the roll (uniform chance rolls)")
eq(pair:getCustomAttribute("rarity_manaLeechAmount"), 3, "the amount the full roll")
eq(pair:getCustomAttribute("ct_rarity_manaleechchance"), 4)
eq(pm.lo, 2); eq(pm.hi, 3, "T4 (3-5): chance 2..3"); eq(pm.lo2, 3); eq(pm.hi2, 5)
eq(C.readMods(pair)[1].tier, 4, "the stored tier wins")
for v, want in ipairs({1, 1, 2, 3, 3, 4}) do
	eq(C.specialChance(v), want, "special chance of a roll of " .. v .. " (as engine patch 0004)")
end
-- an element only on weapons without an own element, and at most one
local function count(rows, group)
	local n = 0
	for _, r in ipairs(rows) do
		if r.entry.group == group then n = n + 1 end
	end
	return n
end
local w = rareItem(2400, 3, {})
eq(count(C.candidates(w), "element"), 8, "weapon can get an element")
eq(count(C.candidates(armor), "element"), 0, "armor cannot")
eq(count(C.candidates(rareItem(8925, 3, {})), "element"), 0, "weapon with its own element cannot")
eq(count(C.candidates(rareItem(2400, 9, {rarity_elementfire = 5})), "element"), 0, "only one element modifier")
eq(count(C.candidates(armor), "chaos") > 0, true, "Chaos types on armor")
local kinds = {}
for _, row in ipairs(C.candidates(armor)) do kinds[row.entry.key] = true end
eq(kinds.chaos_mod_attackspeed, nil, "no attack speed on armor")
eq(kinds.chaos_mod_thorns, true)
eq(kinds.rarity_holyabsorb or kinds.rarity_holyAbsorb, nil, "never a modifier the item has")

-- ---------------------------------------------------------------- Orb of Unmaking
local ann = rareItem(2400, 5, {rarity_swordSkill = 2, rarity_lifeLeechChance = 3, rarity_lifeLeechAmount = 3})
ann:setCustomAttribute("ct_rarity_lifeleechchance", 5)
dice = {2}
ok, res = C.apply("annulment", ann)
eq(ok, true)
eq(res.removed.key, "rarity_lifeLeechChance", "second modifier removed")
eq(ann:getCustomAttribute("rarity_lifeLeechAmount"), nil, "both keys of the pair go")
eq(ann:getCustomAttribute("ct_rarity_lifeleechchance"), nil, "and its tier")
eq(ann:getCustomAttribute("rarity_swordSkill"), 2, "the other stays")
eq(C.rarityOf(ann), 5, "rarity stays")
eq(ann:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Item Level: 42. Prefixes: Melee +2 (T2)")
dice = {1}
C.apply("annulment", ann)
eq(#C.readMods(ann), 0)
eq(ann:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Item Level: 42", "no modifiers left")
eq(select(2, C.check("annulment", ann)), "noMods", "nothing left to annul")
eq(C.check("exalted", ann), true, "but it can be exalted again")

-- description: text in front of the rarity part and upgrade slots behind it are kept (old "Level:" too)
local deco = rareItem(2466, 2, {rarity_iceAbsorb = 1})
deco:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "Forged by Ana, Level: 42, Ice +1% [Armor+2]")
dice = {1}
C.apply("exalted", deco)
eq(deco:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION),
	"Forged by Ana. Item Level: 42. Prefixes: Fist +2 (T3). Suffixes: Ice +1% (T1) [Armor+2]")
C.rewriteDescription(deco)
eq(deco:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION),
	"Forged by Ana. Item Level: 42. Prefixes: Fist +2 (T3). Suffixes: Ice +1% (T1) [Armor+2]", "stable on a rewrite")

-- ---------------------------------------------------------------- Orb of Erasure (a new plain copy)
local sc = rareItem(2466, 7, {rarity_deathAbsorb = 3})
ok, res = C.apply("scouring", sc)
eq(ok, true)
eq(sc.removed, true, "old copy removed")
eq(res.item.removed, false)
eq(res.item.parent, bag, "new copy in the same container")
eq(C.isNormal(res.item), true, "normal now")
eq(C.levelOf(res.item), 42, "the item level stays")
eq(res.text, "golden armor is now a normal item (item level 42).")

-- ---------------------------------------------------------------- Awakening / Gilding / Upheaval / Fate
local tr = put(newItem(2466))
tr:setCustomAttribute("chaos_ilvl", 100)
dice = {80} -- transmutation weights 65 / 35 -> rarity 2
ok, res = C.apply("transmutation", tr)
eq(ok, true)
eq(engineRolls, 0, "the engine's roll is not used")
eq(C.rarityOf(res.item), 2, "Uncommon")
eq(C.levelOf(res.item), 100, "the item level of the plain item")
eq(res.item:getCustomAttribute("combatPowerLevel"), 100, "mirrored for the client")
eq(tr.removed, true)
local tm = C.readMods(res.item)
eq(#tm, 2, "Uncommon: two modifiers")
local p, s = C.sideCounts(tm)
eq(p, 1); eq(s, 1, "one prefix, one suffix")
eq(tm[1].tier, 6, "lowest dice at item level 100: T6, the best it allows")
eq(res.item:getAttribute(ITEM_ATTRIBUTE_ARMOR), 14 + C.baseBonusOf(2, 100), "the rarity's armor bonus")
assert(res.text:find("is now Uncommon %(item level 100%)"), res.text)
-- a plain item without a level of its own: from its type (no required level -> item level 1, T1 only)
dice = {100} -- alchemy 55 / 30 / 15 -> rarity 5
ok, res = C.apply("alchemy", put(newItem(2400)))
eq(C.rarityOf(res.item), 5, "Legendary")
eq(C.levelOf(res.item), 1)
for _, m in ipairs(C.readMods(res.item)) do
	eq(m.tier, 1, "item level 1: T1 only")
end
local ch = rareItem(2400, 9, {rarity_axeSkill = 3})
ok, res = C.apply("chaos", ch)
eq(C.rarityOf(res.item), 5, "chaos keeps the rarity (an old Eternal is stored as Legendary, 5)")
eq(C.levelOf(res.item), 42, "and the item level")
eq(#C.readMods(res.item), M.modCount(9), "a new set of five")
dice = {16} -- above the 15% chance: no rarity
ok, res = C.apply("divine", rareItem(2400, 12, {}))
eq(res.rarity, 0, "the stock divine roll mostly removes the rarity")
eq(C.levelOf(res.item), 42, "the level stays on the plain copy")
dice = {15, 100, 18} -- inside 15%, rarity 1 fails (100 > 25), rarity 2 hits (18 <= 20)
eq(C.rollDivineRarity(), 2)

-- ---------------------------------------------------------------- the forge (drops, every orb copy)
C.random = math.random
math.randomseed(7)
for _, case in ipairs({{2400, 1, 10}, {2400, 9, 75}, {2466, 15, 150}, {2400, 15, 150}, {2466, 4, 30}, {2400, 7, 1}}) do
	for _ = 1, 40 do
		local it = put(newItem(case[1]))
		C.forge(it, case[2], case[3])
		local fm = C.readMods(it)
		eq(#fm, M.modCount(case[2]), "count by rarity " .. case[2])
		local fp, fs = C.sideCounts(fm)
		assert(fp <= M.sideLimit(case[2]) and fs <= M.sideLimit(case[2]), "sides within the limit")
		local top = M.maxTierFor(case[3])
		local elements = 0
		for _, m in ipairs(fm) do
			assert(m.tier <= top and m.tier > top - M.config.tierWindow, "tier allowed at item level " .. case[3])
			local r = m.affix.tiers[m.tier]
			local v = m.group == "special" and m.value2 or m.value
			assert(v >= r[1] and v <= r[2], m.key .. " value in its tier")
			assert(it:getCustomAttribute("ct_" .. m.key:lower()) == m.tier, "tier stored")
			elements = elements + (m.group == "element" and 1 or 0)
		end
		assert(elements <= 1, "one element at most")
		eq(C.levelOf(it), case[3])
		eq(C.rarityOf(it), ChaosRarity.canon(case[2]), "stored as the id of its rarity")
	end
end
-- the base bonus (item.cpp's formula at the item level)
eq(C.baseBonusOf(10, 150), 6 + math.floor(150 * 7 / 100), "Divine {6, 12}")
eq(C.baseBonusOf(15, 150), C.baseBonusOf(10, 150), "an old Transcendent has Divine's")
eq(C.baseBonusOf(1, 1), 1)
local fw = put(newItem(2400))
C.forge(fw, 15, 150)
eq(fw:getAttribute(ITEM_ATTRIBUTE_ATTACK), 48 + 16, "magic sword 48 + 16")
-- forging again replaces every modifier (no leftovers, no stale tiers)
local before = C.readMods(fw)
C.forge(fw, 1, 1)
eq(#C.readMods(fw), 1, "Common now: one modifier")
for _, m in ipairs(before) do
	local still = C.customNumber(fw, m.key) ~= 0
	if still then
		assert(C.customNumber(fw, "ct_" .. m.key) == 1, "a modifier rolled again has its new tier")
	end
end
C.random = function(a, b)
	local v = table.remove(dice, 1)
	if v == nil then
		return a
	end
	return v
end
-- drops: a plain gear drop keeps the item level only; one with a rarity is forged and shielded
local plain = put(newItem(2466))
eq(#C.forgeDrop(plain, 33, function(a) return a end), 0)
eq(plain:getCustomAttribute("chaos_ilvl"), 33, "plain drop: the item level")
eq(C.isNormal(plain), true, "still a normal item")
local drop = put(newItem(2400))
drop:setCustomAttribute("rarity", 4)
eq(#C.forgeDrop(drop, 70, function(a) return a end), 4, "Rare: four modifiers")
eq(drop:getCustomAttribute("rarity"), "4", "shielded from the engine's pass")
eq(C.levelOf(drop), 70)
assert(drop:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("^Item Level: 70%. Prefixes: "), "description written")
-- createItem (rift chests, world boss, store, tutorial)
local made = C.createItem(2466, 3, 60, function(a) return a end)
eq(C.rarityOf(made), 3); eq(C.levelOf(made), 60); eq(#C.readMods(made), 3)
local madePlain = C.createItem(2466, 0, 60)
eq(C.rarityOf(madePlain), 0); eq(madePlain:getCustomAttribute("chaos_ilvl"), 60)
eq(C.rarityOf(C.createItem(2160, 5, 60)), 0, "no rarity on coins")

-- rerolls for orbs v2: values inside the tier, tiers by the item level
local rr = put(newItem(2400))
C.forge(rr, 9, 150, function(a, b) return a end) -- lowest dice: T8 everywhere, lowest values
local tiersBefore = {}
for _, m in ipairs(C.readMods(rr)) do tiersBefore[m.key] = m.tier end
C.rerollValues(rr, function(a, b) return b end)
for _, m in ipairs(C.readMods(rr)) do
	eq(m.tier, tiersBefore[m.key], "values only: same tier")
	eq(m.group == "special" and m.value2 or m.value, m.hi2 or m.hi, "highest value of the tier")
end
C.rerollTiers(rr, function(a, b) return b end)
for _, m in ipairs(C.readMods(rr)) do
	eq(m.tier, 4, "highest tier dice at 150: T4")
end

-- ---------------------------------------------------------------- orbs v2: an orb with rules of its own
local tempered = C.addOrb({key = "testorb", id = 30001, name = "Orb of Testing", text = "Rerolls the values.",
	check = function(item)
		if C.rarityOf(item) == 0 then return false, "needRarity" end
		return true
	end,
	apply = function(item)
		C.rerollValues(item)
		return true, {item = item, text = "tempered"}
	end,
	preview = function(item) return "same modifiers, new values" end})
eq(C.orbByKey.testorb, tempered); eq(C.orbById[30001], tempered)
eq(C.addOrb({key = "testorb", id = 30001, name = "x"}), tempered, "added once")
eq(select(2, C.check("testorb", put(newItem(2400)))), "needRarity", "its own check")
eq(select(2, C.check("testorb", unique)), "unique", "the common rules first")
local tok, tres = C.apply("testorb", rr)
eq(tok, true); eq(tres.text, "tempered")
eq(C.preview("testorb", rr), "same modifiers, new values")
eq(C.describe(rr).preview.testorb, "same modifiers, new values", "on the bench")
table.remove(C.config.orbs)
C.orbByKey.testorb, C.orbById[30001] = nil, nil

-- ---------------------------------------------------------------- describe / signature / preview
local d = C.describe(sword)
eq(d.rarityName, "Rare")
eq(d.maxMods, 4)
eq(#d.mods, 4)
eq(d.mods[1].side, "prefix", "prefixes first")
eq(d.mods[#d.mods].side, "suffix")
eq(d.mods[1].tier, 1)
eq(d.prefixes[1], 3); eq(d.prefixes[2], 2, "an old item may carry more than today's limit")
eq(d.suffixes[1], 1)
eq(d.level, 42); eq(d.maxTier, 3)
eq(d.orbs.exalted, C.reasons.full, "four of four")
eq(d.orbs.transmutation, C.reasons.needNormal)
local sig = C.signature(sword)
dice = {1}
C.apply("annulment", sword)
assert(C.signature(sword) ~= sig, "signature changes with the modifiers")
local pv = C.describe(rareItem(2466, 4, {rarity_iceAbsorb = 2}))
eq(pv.preview.exalted, "1 -> 2 of 4 (prefixes 0/2, suffixes 1/2), T1-T3")
eq(pv.preview.annulment, "one of 1 modifiers goes")
eq(pv.preview.chaos, "stays Rare, item level 42: 4 new modifiers, T1-T3")
eq(pv.preview.transmutation, "", "no preview for an orb that does not fit")
local pn = put(newItem(2400))
pn:setCustomAttribute("chaos_ilvl", 150)
eq(C.describe(pn).preview.alchemy, "Magic 60%, Rare 30%, Legendary 10%; item level 150: T4-T8")

-- attack speed is the weapon's own interval (ITEM_ATTRIBUTE_ATTACK_SPEED); removing it gives the base back
ITEM_ATTRIBUTE_ATTACK_SPEED = 99
function Item:removeAttribute(k) self.attrs[k] = nil end
local aw = rareItem(2400, 5, {})
M.set(aw, "attackspeed", 8, 5)
eq(aw:getAttribute(ITEM_ATTRIBUTE_ATTACK_SPEED), 1840, "2000 ms base (no own interval) -8%")
C.rewriteDescription(aw)
eq(aw:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Item Level: 42. Suffixes: Attack Speed +8% (T5)")
dice = {1}
C.apply("annulment", aw)
eq(aw:getAttribute(ITEM_ATTRIBUTE_ATTACK_SPEED), nil, "interval back to the item type's")
ITEM_ATTRIBUTE_ATTACK_SPEED = nil

-- ---------------------------------------------------------------- Rift Keys
local R, rcfg = C.rift()
local function newKey(tier, mods)
	local k = put(newItem(rcfg.key.itemId))
	k:setActionId(rcfg.key.actionId)
	C.writeKey(k, {tier = tier, mods = R.decodeMods(rcfg, mods or "")})
	return k
end
local key = newKey(4, "")
eq(C.isRiftKey(key), true, "a key")
eq(C.isRiftKey(put(newItem(rcfg.key.itemId))), false, "the base item without the action id is no key")
eq(C.check("exalted", key), true, "exalted on an empty key")
eq(select(2, C.check("annulment", key)), "keyNoMods")
eq(select(2, C.check("scouring", key)), "keyNoMods")
eq(select(2, C.check("chaos", key)), "keyNoMods")
eq(select(2, C.check("divine", key)), "keyNoMods")
-- Awakening: one modifier. pool of 8, pick 3 = haste, value step 0 -> 40
dice = {300, 0} -- weighted pick: the old eight weigh 100 each, so 300 is the third (haste)
ok, res = C.apply("transmutation", key)
eq(ok, true, "transmutation on a key")
eq(key:getCustomAttribute("rift_mods"), "haste:40")
eq(key:getAttribute(ITEM_ATTRIBUTE_NAME), "Rift Key (Tier 4)")
eq(key:getCustomAttribute("rift_tier"), 4, "tier unchanged")
assert(key:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Monsters move %+40 faster"), "description rewritten")
eq(res.text, "Rift Key (Tier 4): Monsters move +40 faster. Rewards: +6% quantity, +0% rarity, +0% experience.")
eq(select(2, C.check("transmutation", key)), "keyNeedNone", "transmutation needs an empty key")
eq(select(2, C.check("alchemy", key)), "keyNeedNone")
-- Grafting up to the maximum (3)
dice = {100, 2}
C.apply("exalted", key) -- pool without haste: vitality first, value 20 + 2 x 5
eq(key:getCustomAttribute("rift_mods"), "vitality:30,haste:40", "config order")
dice = {600, 0}
C.apply("exalted", key) -- pool of 6 left (vitality and haste taken): the 6th is swarm, value 1
eq(#C.readKey(key).mods, 3)
eq(select(2, C.check("exalted", key)), "keyFull", "three is the maximum")
eq(C.describe(key).maxMods, 3)
eq(C.describe(key).kind, "riftkey")
-- Divine: same modifiers, new values inside the ranges
dice = {8, 0, 2}
C.apply("divine", key)
local dk = C.readKey(key).mods
eq(dk[1].key, "vitality"); eq(dk[1].value, 60, "vitality 20 + 8 x 5")
eq(dk[2].key, "haste"); eq(dk[2].value, 40)
eq(#dk, 3)
-- Unmaking: one goes
dice = {1}
ok, res = C.apply("annulment", key)
eq(#C.readKey(key).mods, 2)
eq(C.readKey(key).mods[1].key, "haste", "the first one went")
assert(res.text:find("lost \"Monsters have %+60%% health\""), res.text)
-- Chaos: new modifiers (1-3 by the drop weights)
dice = {100} -- count roll 100 of 100 -> 3 modifiers; then the lowest dice: the first of the pool each time
C.apply("chaos", key)
local ck = C.readKey(key).mods
eq(#ck, 3, "chaos rolled three")
eq(ck[1].key, "vitality"); eq(ck[2].key, "brutality"); eq(ck[3].key, "haste")
-- Erasure: all go
C.apply("scouring", key)
eq(key:getCustomAttribute("rift_mods"), "", "scoured key")
assert(key:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Modifiers: none"), "description says none")
-- Gilding: 2 or 3 on an empty key ({2, 60}, {3, 40}: roll 61 -> 3)
dice = {61}
C.apply("alchemy", key)
eq(#C.readKey(key).mods, 3, "alchemy gave three")
-- uniques and rarity rules do not apply; a stack of keys does not exist (not stackable). The signature follows mods
local ksig = C.signature(key)
dice = {1}
C.apply("annulment", key)
assert(C.signature(key) ~= ksig, "key signature changes")
-- maxMods from the config caps the decoded list too
eq(#R.decodeMods(rcfg, "vitality:20,brutality:20,haste:40,elites:50"), 3, "at most key.maxMods")

print("crafting_test: OK")
