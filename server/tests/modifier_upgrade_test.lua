-- Run from the server/ folder: luajit tests/modifier_upgrade_test.lua (and lua5.3; CI runs both)
-- O461 (2026-11-10): the upgrade of an item rolled with the numbers before the equipment modifier rework. The beta server is
-- live and is not wiped, so an item that carries modifiers and no version mark ("chaos_modv") is upgraded the first time it is
-- read (ChaosCrafting.upgradeItem, ChaosItemMods.read, C.readMods) or moved: each modifier keeps its tier and its place in the
-- tier's range, quality moves to the base bonus, a critical pair becomes two modifiers, a leech pair one Lua modifier. Uniques,
-- set pieces, vendor gear and store items are never touched. Worked examples are printed at the end (the report quotes them).

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(c, m)
	eq(not not c, true, m)
end

-- ---------------------------------------------------------------- engine mock
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME = 1, 2
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_ARMOR, ITEM_ATTRIBUTE_DEFENSE = 11, 12, 13

local TYPES = {
	[2400] = {name = "magic sword", weaponType = 1, attack = 48, slot = 48},
	[2466] = {name = "golden armor", armor = 14, slot = 8},
	[2171] = {name = "platinum amulet", armor = 2, slot = 2},
	[2471] = {name = "golden helmet", armor = 12, slot = 1}
}
function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getName = function() return t.name or "" end,
		isContainer = function() return false end,
		isStackable = function() return false end,
		getWeaponType = function() return t.weaponType or 0 end,
		getSlotPosition = function() return t.slot or 0 end,
		getArmor = function() return t.armor or 0 end,
		getAttack = function() return t.attack or 0 end,
		getDefense = function() return 0 end,
		getHitChance = function() return 0 end,
		getElementDamage = function() return 0 end,
		getAbilities = function() return {} end
	}
end

local Item = {}
Item.__index = Item
local function newItem(id)
	return setmetatable({id = id, attrs = {}, custom = {}}, Item)
end
function Item:getId() return self.id end
function Item:getCount() return 1 end
function Item:getName() return self.attrs[ITEM_ATTRIBUTE_NAME] or ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:getAttribute(k) return self.attrs[k] or (k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil) end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:removeAttribute(k) self.attrs[k] = nil end
function Item:getActionId() return 0 end
Game = {createItem = function(id) return newItem(id) end}

dofile("data/lib/chaos_crafting.lua")
local C, M = ChaosCrafting, ChaosItemMods

-- an item the way the live server holds it: rolled before O461 (no version mark), stored tiers
local function oldItem(id, rarity, level, quality)
	local it = newItem(id)
	it:setCustomAttribute("rarity", rarity)
	it:setCustomAttribute("chaos_ilvl", level)
	it:setCustomAttribute("combatPowerLevel", level)
	if quality and quality > 0 then
		it:setCustomAttribute(M.QUALITY, quality)
	end
	return it
end
local function oldMod(it, key, value, tier, raw)
	it:setCustomAttribute(M.attr(key), value)
	it:setCustomAttribute(M.tierAttr(M.attr(key)), tier)
	if raw then
		it:setCustomAttribute(M.rawAttr(M.attr(key)), raw)
	end
end
local function modValue(it, key)
	return it:getCustomAttribute(M.attr(key))
end

-- ---------------------------------------------------------------- remapping a value to the same place of the new range
eq(C.remapValue(5, {5, 7}, {14, 16}), 14, "the bottom of the range stays the bottom")
eq(C.remapValue(7, {5, 7}, {14, 16}), 16, "the top stays the top")
eq(C.remapValue(6, {5, 7}, {14, 16}), 15, "the middle stays the middle")
eq(C.remapValue(80, {60, 100}, {90, 140}), 115, "40 of 40: half way")
eq(C.remapValue(3, {3, 3}, {3, 3}), 3, "the same range keeps the value")
eq(C.remapValue(9, {5, 7}, {5, 7}), 7, "a value above an unchanged range is held at its top")
eq(C.remapValue(2, {2, 2}, {26, 32}), 29, "a single value of the old range lands in the middle of the new one")
eq(C.remapValue(100, {5, 7}, {14, 16}), 16, "above the old range: the top of the new")
eq(C.remapValue(1, {5, 7}, {14, 16}), 14, "below the old range: the bottom of the new")

-- ---------------------------------------------------------------- 1. a rolled item with quality
local sword = oldItem(2400, 10, 100, 30) -- Divine, item level 100, quality 30
sword:setAttribute(ITEM_ATTRIBUTE_ATTACK, 48 + C.baseBonusOf(10, 100)) -- the base bonus as the forge wrote it: 13, no quality
eq(sword:getAttribute(ITEM_ATTRIBUTE_ATTACK), 61)
oldMod(sword, "attackspeed", 7, 4, 5) -- v1 T4 {5,7}: rolled 5, x1.3 = 6.5 = 7 with quality 30
oldMod(sword, "lifeonkill", 104, 5, 80) -- v1 T5 {60,100}: rolled 80, x1.3 = 104
oldMod(sword, "bleedchance", 8, 2, 6) -- v1 T2 {5,7}: rolled 6, x1.3 = 8
oldMod(sword, "execute", 7, 6, 5) -- v1 T6 {5,6}: rolled 5 -> 7?? the stored value follows the multiplier; the raw one is used
oldMod(sword, "goldfind", 26, 3, 20) -- left the roll pool: stays as stored, quality share and all
sword:setCustomAttribute("rarity_swordSkill", 5); sword:setCustomAttribute("ct_rarity_swordskill", 5)
sword:setCustomAttribute("cv_rarity_swordskill", 4) -- E.skill T5 {4,6}: the engine rows keep their ranges: only the quality goes
sword:setCustomAttribute("rarity_criticalHitChance", 6); sword:setCustomAttribute("rarity_criticalHitAmount", 8)
sword:setCustomAttribute("ct_rarity_criticalhitchance", 6); sword:setCustomAttribute("cv_rarity_criticalhitchance", 6)
sword:setCustomAttribute("rarity_lifeLeechChance", 4); sword:setCustomAttribute("rarity_lifeLeechAmount", 6)
sword:setCustomAttribute("ct_rarity_lifeleechchance", 5); sword:setCustomAttribute("cv_rarity_lifeleechchance", 5)
sword:setCustomAttribute(M.bindAttr("rarity_criticalHitChance"), 1) -- the pair was bound
eq(M.versionOf(sword), 0, "no version mark")
eq(C.needsUpgrade(sword), true)
eq(C.upgradeItem(sword), true, "upgraded")
eq(M.versionOf(sword), 2, "marked")
eq(C.needsUpgrade(sword), false); eq(C.upgradeItem(sword), false, "once")
-- attack speed: T4 {5,7} -> {14,16}, the rolled 5 is the bottom
eq(modValue(sword, "attackspeed"), 14, "Attack Speed: rolled 5 of T4 5-7 (the 7 stored was the quality's) -> 14 of 14-16")
eq(sword:getCustomAttribute("ct_chaos_mod_attackspeed"), 4, "the tier stays")
eq(modValue(sword, "lifeonkill"), 115, "Life on Kill: rolled 80 of T5 60-100 -> half way of 90-140")
eq(modValue(sword, "bleedchance"), 24, "Chance to Bleed: rolled 6 of T2 5-7 -> 24 of 22-25")
eq(modValue(sword, "execute"), 10, "Execute: 10 at every tier")
eq(modValue(sword, "goldfind"), 26, "left the roll pool: stays as it was")
eq(sword:getCustomAttribute("ct_chaos_mod_goldfind"), 3, "and its tier")
eq(sword:getCustomAttribute("rarity_swordSkill"), 4, "an engine row keeps its range: the rolled 4 of T5 4-6, the quality taken off")
-- the critical pair: two modifiers at the pair's tier
eq(sword:getCustomAttribute("rarity_criticalHitChance"), 6, "Critical Strike Chance: T6 is 6 points")
eq(sword:getCustomAttribute("rarity_criticalHitAmount"), 30, "Critical Strike Damage: rolled 6 of v1 T6 5-8 (a third) -> 30 of 29-31")
eq(sword:getCustomAttribute("ct_rarity_criticalhitchance"), 6); eq(sword:getCustomAttribute("ct_rarity_criticalhitamount"), 6)
eq(sword:getCustomAttribute(M.bindAttr("rarity_criticalHitChance")), 1, "the bind stays on the chance")
eq(sword:getCustomAttribute(M.bindAttr("rarity_criticalHitAmount")), 1, "and goes to the damage: the pair was one bound modifier")
-- the leech pair: one Lua modifier of the weapon, the engine pair removed
eq(sword:getCustomAttribute("rarity_lifeLeechChance"), nil, "the leech pair is gone")
eq(sword:getCustomAttribute("rarity_lifeLeechAmount"), nil)
eq(sword:getCustomAttribute("ct_rarity_lifeleechchance"), nil)
eq(modValue(sword, "lifeleechw"), 32, "Life Leech with Weapon: rolled 5 of T5 4-6 (half) -> T5 of 31-32")
eq(sword:getCustomAttribute("ct_chaos_mod_lifeleechw"), 5)
-- no cv_ stays, quality is off the modifiers and on the base bonus
for _, key in ipairs({"chaos_mod_attackspeed", "chaos_mod_lifeonkill", "rarity_swordSkill", "rarity_criticalHitChance"}) do
	eq(sword:getCustomAttribute("cv_" .. key:lower()), nil, "no raw value any more: " .. key)
end
eq(M.qualityOf(sword), 30, "the quality stays")
eq(sword:getAttribute(ITEM_ATTRIBUTE_ATTACK), 48 + C.qualityBonus(13, 30), "the base bonus carries the quality: 13 x 1.3 = 17")
eq(sword:getAttribute(ITEM_ATTRIBUTE_ATTACK), 65)
local desc = sword:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION)
ok(desc:find("Quality: +30%", 1, true), "the description is written again: " .. desc)
ok(desc:find("Critical Strike Chance +6% (T6, bound)", 1, true) and desc:find("Critical Strike Damage +30% (T6, bound)", 1, true), desc)
ok(desc:find("Life Leech with Weapon +3.2% (T5)", 1, true), desc)
ok(desc:find("Attack Speed +14% (T4)", 1, true), desc)
eq(#C.readMods(sword), 9, "the pair became one more: eight modifiers and the lone leech make nine of a Divine item's six")
local before = desc
C.readMods(sword)
eq(sword:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), before, "reading again changes nothing")

-- ---------------------------------------------------------------- 2. the leech of other kinds, the quality without a raw value
local armor = oldItem(2466, 4, 60, 20)
armor:setAttribute(ITEM_ATTRIBUTE_ARMOR, 14 + C.baseBonusOf(4, 60))
armor:setCustomAttribute("rarity_manaLeechChance", 3); armor:setCustomAttribute("rarity_manaLeechAmount", 5)
armor:setCustomAttribute("ct_rarity_manaleechchance", 4)
oldMod(armor, "regen", 17, 4) -- quality 20, no cv_: 17 / 1.2 = 14.17 -> 14 inside v1 T4 {11,18}
C.readMods(armor)
eq(modValue(armor, "manaleech"), 5, "a leech pair on armor becomes the global Lua modifier: 5 of T4 3-5, a mana leech of the T4 range 5-5")
eq(armor:getCustomAttribute("ct_chaos_mod_manaleech"), 4)
eq(modValue(armor, "manaleechw"), nil, "not the weapon's")
-- v1 T4 {11,18}: raw 14 is 3/7 of the way; the new T4 {89,105}: 89 + 0.43 x 16 = 95.9 -> 96
eq(modValue(armor, "regen"), 96, "Health Regeneration: the quality taken off by division, then the new range")
eq(armor:getAttribute(ITEM_ATTRIBUTE_ARMOR), 14 + C.qualityBonus(C.baseBonusOf(4, 60), 20), "armour carries the quality")

-- ---------------------------------------------------------------- 3. what is never upgraded
local function fixed(setup)
	local it = oldItem(2400, 5, 120)
	oldMod(it, "attackspeed", 6, 4)
	oldMod(it, "lifeonkill", 70, 5)
	it:setCustomAttribute("rarity_criticalHitChance", 5); it:setCustomAttribute("rarity_criticalHitAmount", 20)
	setup(it)
	return it
end
local function untouched(it, label)
	eq(C.needsUpgrade(it), false, label .. ": nothing to upgrade")
	eq(C.upgradeItem(it), false, label)
	C.readMods(it)
	M.read(it)
	eq(modValue(it, "attackspeed"), 6, label .. ": the value stays")
	eq(modValue(it, "lifeonkill"), 70, label)
	eq(it:getCustomAttribute("rarity_criticalHitAmount"), 20, label .. ": the pair stays as the unique's")
	eq(M.versionOf(it), 0, label .. ": not even a mark")
end
untouched(fixed(function(it) it:setCustomAttribute("chaos_unique", 1) end), "a unique")
untouched(fixed(function(it) it:setCustomAttribute("chaos_unique", 1); it:setCustomAttribute("chaos_set", "embers") end), "a set piece")
untouched(fixed(function(it) it:setCustomAttribute("chaos_raid", "v_blade") end), "raid vendor gear")
untouched(fixed(function(it) it:setCustomAttribute("chaos_faction", "vigil") end), "faction quartermaster gear")
untouched(fixed(function(it) it:setCustomAttribute("chaos_storebound", 1) end), "a store-bound item")
untouched(fixed(function(it) it.isStoreItem = function() return true end end), "an engine store item")
ChaosUniqueSpecs = {[2400] = {name = "Ironclad Blade"}}
untouched(fixed(function(it) it:setAttribute(ITEM_ATTRIBUTE_NAME, "Ironclad Blade") end), "an old unique known by its spec name")
ChaosUniqueSpecs = nil
-- an item without a rarity has nothing rolled
local plain = newItem(2400)
plain:setCustomAttribute(M.attr("attackspeed"), 6)
eq(C.needsUpgrade(plain), false, "no rarity: not upgraded")
-- a unique's modifiers still read: the fixed T8 value stays (a number far below the new top)
local unique = newItem(2400)
unique:setCustomAttribute("chaos_unique", 1)
M.set(unique, "attackspeed", 12, 8)
eq(M.read(unique)[1].value, 12, "a unique keeps its fixed 12")
eq(M.read(unique)[1].tier, 8)
eq(M.versionOf(unique), 0)

-- ---------------------------------------------------------------- 4. an item from before the tier marks keeps working
local ancient = oldItem(2400, 5, 55)
ancient:setCustomAttribute(M.attr("attackspeed"), 9) -- no tier mark: the tier follows from the value in the legacy tables
ancient:setCustomAttribute("rarity_swordSkill", 2)
ancient:setCustomAttribute("rarity_criticalHitChance", 3); ancient:setCustomAttribute("rarity_criticalHitAmount", 4)
local am = C.readMods(ancient)
eq(M.versionOf(ancient), 2, "reading marked it")
eq(modValue(ancient, "attackspeed"), 9, "a modifier without a tier mark keeps its number")
eq(ancient:getCustomAttribute("ct_chaos_mod_attackspeed"), nil, "and has no mark written: the legacy tables still read its tier")
eq(M.tierOf(ancient, "attackspeed"), 6, "T6 of the legacy table (7-10), as before")
eq(ancient:getCustomAttribute("rarity_swordSkill"), 2)
-- the pair of an item without tier marks still becomes two modifiers; its tier from the amount in the legacy table
-- legacy critical {{1,1},{1,2},{1,3},{2,3},{2,4},...}: an amount of 4 is T5 (2-4) in T2..T6
eq(ancient:getCustomAttribute("ct_rarity_criticalhitchance"), 5, "the pair's tier from its amount (T5)")
eq(ancient:getCustomAttribute("ct_rarity_criticalhitamount"), 5)
eq(ancient:getCustomAttribute("rarity_criticalHitChance"), 6, "T5 of Critical Strike Chance is 5-6 points: the old amount was the top (4 of 2-4), so 6")
eq(ancient:getCustomAttribute("rarity_criticalHitAmount"), 28, "Critical Strike Damage T5 25-28: the top, as the old value was the top of its range")

-- ---------------------------------------------------------------- 5. it also happens through the paths that read an item
local viaRead = oldItem(2400, 4, 60)
oldMod(viaRead, "attackspeed", 6, 4)
M.read(viaRead)
eq(M.versionOf(viaRead), 2, "ChaosItemMods.read upgrades")
eq(modValue(viaRead, "attackspeed"), 15, "5-7 -> 14-16: 6 is the middle")
local viaMods = oldItem(2400, 4, 60)
oldMod(viaMods, "attackspeed", 7, 4)
C.readMods(viaMods)
eq(modValue(viaMods, "attackspeed"), 16, "ChaosCrafting.readMods upgrades: 7 is the top")
-- a new item is rolled in today's numbers and marked
local forged = newItem(2400)
C.forge(forged, 4, 100, function(a, b) return b end)
eq(M.versionOf(forged), 2, "a forged item carries the mark")
eq(C.needsUpgrade(forged), false)
local before2 = forged:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION)
C.readMods(forged)
eq(forged:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), before2, "and is never upgraded")

-- ---------------------------------------------------------------- 6. the orbs read first: an old item is upgraded before the orb works
local oldRare = oldItem(2400, 4, 60)
oldMod(oldRare, "attackspeed", 6, 4)
oldRare:setCustomAttribute("rarity_criticalHitChance", 3); oldRare:setCustomAttribute("rarity_criticalHitAmount", 5)
oldRare:setCustomAttribute("ct_rarity_criticalhitchance", 4)
local okC, why = C.check("exalted", oldRare)
eq(M.versionOf(oldRare), 2, "an orb's check reads the item")
eq(okC, true, "a Rare item with the pair (two prefixes) and attack speed (a suffix): a suffix is still open")
-- the item may end with one modifier more than its rarity allows: a Common item with a pair is two prefixes after the upgrade
local common = oldItem(2400, 1, 60)
common:setCustomAttribute("rarity_criticalHitChance", 3); common:setCustomAttribute("rarity_criticalHitAmount", 5)
common:setCustomAttribute("ct_rarity_criticalhitchance", 4)
eq(#C.readMods(common), 2, "one pair, two modifiers: one more than a Common item has")
eq(M.modCount(common:getCustomAttribute("rarity")), 1)
okC, why = C.check("exalted", common)
eq(okC, false); eq(why, "full", "and no room for more")
eq(C.check("annulment", common), true, "an Orb of Unmaking still works: it takes one of the two")

-- ---------------------------------------------------------------- the worked examples (the report quotes them)
if os.getenv("UPGRADE_PRINT") then
	print("example 1: Attack Speed T4 rolled 5 (shown 7 at quality 30) -> " .. modValue(sword, "attackspeed") .. ", Life on Kill rolled 80 -> " ..
		modValue(sword, "lifeonkill") .. ", the critical pair -> " .. sword:getCustomAttribute("rarity_criticalHitChance") .. " points and " ..
		sword:getCustomAttribute("rarity_criticalHitAmount") .. "%")
end

print(string.format("modifier_upgrade_test: %d checks OK", checks))
