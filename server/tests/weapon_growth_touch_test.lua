-- Run from the server/ folder: luajit tests/weapon_growth_touch_test.lua && lua5.3 tests/weapon_growth_touch_test.lua (CI runs both)
-- O472 (2026-11-10): the attack of our weapons grew with the level (tools/weapon_growth.py, data/lib/chaos_weapon_growth.lua). The item
-- type follows the install; an item that carries its attack itself follows when it is touched (ChaosCrafting.growWeapon, called by
-- ChaosCrafting.upgradeItem, own mark "chaos_wgrow"): a rolled weapon (rarity, quality, +N upgrade), a weapon with Weapon Damage
-- (chaos_wdbase), a unique, a corrupted one. The roll, the tier, the value of every modifier and the quality stay; nothing is
-- rerolled or deleted; once only; waits while the item type still has the old attack (install not done).
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

-- type attack as the installed server has it NOW (the new numbers); the table says what it was before
local TYPES = {
	[36656] = {name = "ember knuckles", weaponType = 1, attack = 50, slot = 48},   -- {46, 50}
	[37030] = {name = "a set sword", weaponType = 1, attack = 51, slot = 48},      -- {35, 51}
	[2408] = {name = "crimson sword", weaponType = 1, attack = 40, slot = 48},     -- a unique's stock base: type attack is not the unique's
	[2466] = {name = "golden armor", armor = 14, slot = 8}
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

-- the growth table: the real generated one, also used below
local T = dofile("data/lib/chaos_weapon_growth.lua")
eq(T.version, 1, "table version")
eq(T.types[36656][1], 46, "ember knuckles: before 46"); eq(T.types[36656][2], 50, "after 50")
ok(next(T.types) and next(T.uniques), "types and uniques listed")
-- the tests use a small table of their own so the numbers are plain
C.setGrowthTable({version = 1, types = {[36656] = {46, 50}, [37030] = {35, 51}}, uniques = {[2408] = {78, 188}}})

-- a rolled weapon the way the forge made it: attack = the type's before + the base bonus (+ quality share)
local function rolled(id, beforeAttack, rarity, level)
	local it = newItem(id)
	it:setCustomAttribute("rarity", rarity or 3)
	it:setCustomAttribute("chaos_ilvl", level or 100)
	it:setCustomAttribute("combatPowerLevel", level or 100)
	it:setCustomAttribute(M.VERSION, M.config.modVersion)
	local bonus = C.baseBonusOf(rarity or 3, level or 100)
	it:setAttribute(ITEM_ATTRIBUTE_ATTACK, beforeAttack + bonus)
	return it, bonus
end

-- ---------------------------------------------------------------- 1. a rolled weapon: attack + (new base - old base)
local a, bonus = rolled(37030, 35, 4, 120)
eq(a:getAttribute(ITEM_ATTRIBUTE_ATTACK), 35 + bonus, "before the touch")
a:setCustomAttribute(M.attr("attackspeed"), 8); a:setCustomAttribute(M.tierAttr(M.attr("attackspeed")), 5)
a:setCustomAttribute("rarity_swordSkill", 3)
local modsBefore = {}
for k, v in pairs(a.custom) do modsBefore[k] = v end
ok(C.upgradeItem(a), "the touch changes the item")
eq(a:getAttribute(ITEM_ATTRIBUTE_ATTACK), 51 + bonus, "attack = the stored one + 16 (the type grew from 35 to 51): the bonus is kept")
eq(a:getCustomAttribute("chaos_wgrow"), 1, "marked")
for k, v in pairs(modsBefore) do
	eq(a.custom[k], v, "nothing else changed: " .. k)
end
-- once
ok(not C.upgradeItem(a), "a second touch changes nothing")
eq(a:getAttribute(ITEM_ATTRIBUTE_ATTACK), 51 + bonus, "still the same attack")
ok(not C.growWeapon(a), "growWeapon alone: nothing either")

-- ---------------------------------------------------------------- 2. quality, a +N upgrade, corruption: what is on the item stays
local q, qb = rolled(36656, 46, 5, 100)
q:setCustomAttribute(M.QUALITY, 20)
q:setAttribute(ITEM_ATTRIBUTE_ATTACK, q:getAttribute(ITEM_ATTRIBUTE_ATTACK) + 6 + 3) -- the quality share of the bonus and a +3 upgrade
q:setCustomAttribute("chaos_corrupted", 1)
local stored = q:getAttribute(ITEM_ATTRIBUTE_ATTACK)
C.upgradeItem(q)
eq(q:getAttribute(ITEM_ATTRIBUTE_ATTACK), stored + 4, "a quality, upgraded and corrupted weapon: + 4, the rest stays")
eq(q:getCustomAttribute("chaos_corrupted"), 1, "still corrupted")
eq(q:getCustomAttribute(M.QUALITY), 20, "quality kept")

-- ---------------------------------------------------------------- 3. Weapon Damage: its base moves, the percent stays, the attack follows
local w = newItem(37030)
w:setCustomAttribute("rarity", 4); w:setCustomAttribute("chaos_ilvl", 100); w:setCustomAttribute(M.VERSION, M.config.modVersion)
w:setAttribute(ITEM_ATTRIBUTE_ATTACK, 35 + 10) -- type 35 + bonus 10
M.set(w, "weapondamage", 20, 4) -- the attack is now 45 x 1.2 = 54; chaos_wdbase = 45
eq(w:getCustomAttribute(M.WEAPON_BASE), 45, "base kept")
eq(w:getAttribute(ITEM_ATTRIBUTE_ATTACK), 54, "attack with the modifier")
C.upgradeItem(w)
eq(w:getCustomAttribute(M.WEAPON_BASE), 61, "the base moved by +16")
eq(w:getAttribute(ITEM_ATTRIBUTE_ATTACK), math.floor(61 * 1.2 + 1e-9), "attack = new base x 1.2 (the value 20 and its tier stay)")
eq(w:getCustomAttribute(M.attr("weapondamage")), 20, "the rolled value stays")
eq(M.storedTier(w, M.attr("weapondamage")), 4, "the tier stays")

-- ---------------------------------------------------------------- 4. an item without a stored attack reads the type: nothing to move
local plain = newItem(37030)
plain:setCustomAttribute("rarity", 0)
ok(not C.upgradeItem(plain), "a plain item: nothing stored, nothing moved")
eq(plain:getAttribute(ITEM_ATTRIBUTE_ATTACK), nil, "no attack written")
eq(plain:getCustomAttribute("chaos_wgrow"), 1, "but marked: it reads the new type")

-- ---------------------------------------------------------------- 5. the install is not done yet: the type still has the old attack
TYPES[37030].attack = 35
local early = rolled(37030, 35, 3, 100)
local st = early:getAttribute(ITEM_ATTRIBUTE_ATTACK)
ok(not C.upgradeItem(early), "the type still has the old attack: wait")
eq(early:getAttribute(ITEM_ATTRIBUTE_ATTACK), st, "unchanged")
eq(early:getCustomAttribute("chaos_wgrow"), nil, "not marked: the next touch after the install moves it")
TYPES[37030].attack = 51
ok(C.upgradeItem(early), "after the install")
eq(early:getAttribute(ITEM_ATTRIBUTE_ATTACK), st + 16, "moved then")

-- ---------------------------------------------------------------- 6. a unique carries its spec's attack: moved when it is the old spec's
local function unique(attack)
	local u = newItem(2408)
	u:setCustomAttribute("chaos_unique", 1)
	u:setAttribute(ITEM_ATTRIBUTE_ATTACK, attack)
	return u
end
local u1 = unique(78)
ok(C.upgradeItem(u1), "a unique is touched too (the modifier upgrade never touches it)")
eq(u1:getAttribute(ITEM_ATTRIBUTE_ATTACK), 188, "the unique's attack: the spec's new number")
local u2 = unique(150) -- not the old spec's number (another script changed it): left alone, marked
C.upgradeItem(u2)
eq(u2:getAttribute(ITEM_ATTRIBUTE_ATTACK), 150, "a unique that holds another number is left as it is")
eq(u2:getCustomAttribute("chaos_wgrow"), 1, "marked")
-- a unique with Weapon Damage built in
local u3 = unique(78)
u3:setCustomAttribute(M.WEAPON_BASE, 78); u3:setCustomAttribute(M.attr("weapondamage"), 10)
u3:setAttribute(ITEM_ATTRIBUTE_ATTACK, math.floor(78 * 1.1 + 1e-9))
C.upgradeItem(u3)
eq(u3:getCustomAttribute(M.WEAPON_BASE), 188, "the unique's base moved")
eq(u3:getAttribute(ITEM_ATTRIBUTE_ATTACK), math.floor(188 * 1.1 + 1e-9), "its attack follows with the 10%")

-- ---------------------------------------------------------------- 7. what the growth never touches
local armor = newItem(2466)
armor:setCustomAttribute("rarity", 3)
armor:setAttribute(ITEM_ATTRIBUTE_ARMOR, 20)
C.upgradeItem(armor)
eq(armor:getAttribute(ITEM_ATTRIBUTE_ARMOR), 20, "armour is not a weapon")
eq(armor:getCustomAttribute("chaos_wgrow"), nil, "not marked")
C.setGrowthTable(nil)

-- ---------------------------------------------------------------- 8. the real table: every row follows the rule
for id, row in pairs(T.types) do
	ok(row[2] > row[1], "type " .. id .. " grew")
end
for id, row in pairs(T.uniques) do
	ok(row[2] > row[1], "unique " .. id .. " grew")
end

print("weapon_growth_touch_test: " .. checks .. " checks ok")
