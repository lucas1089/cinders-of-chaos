-- Run from the server/ folder: luajit tests/item_tooltip_test.lua (and lua5.3; CI runs both)
-- Rich item tooltips (data/scripts/chaos/item_tooltip_core.lua) against a mocked engine: the keys of the item custom
-- attributes agree in the engine patch, the server constants and the client; client positions (inventory, container,
-- map, malformed); map access; the request budget; the slots an item is compared with; and the tooltip of a rolled
-- rare weapon (modifiers with tiers and roll ranges, Chaos modifier, sockets with gems, compare numbers), of a unique
-- (set, requirement, flavour text), of a plain item, of a locked item, of a Rift Key, and the cache key.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- engine mock
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_ARTICLE = 1, 2, 3
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_DEFENSE, ITEM_ATTRIBUTE_EXTRADEFENSE = 4, 5, 6
ITEM_ATTRIBUTE_ARMOR, ITEM_ATTRIBUTE_HITCHANCE, ITEM_ATTRIBUTE_SHOOTRANGE, ITEM_ATTRIBUTE_ATTACK_SPEED = 7, 8, 9, 10
ITEM_ATTRIBUTE_CHARGES = 11
INDEX_WHEREEVER, FLAG_NOLIMIT, RETURNVALUE_NOERROR = -1, 1, 0
SLOTP_TWO_HAND, WEAPON_SHIELD, WEAPON_AMMO = 2048, 4, 7

local TYPES = {
	[2400] = {name = "magic sword", weaponType = 1, attack = 48, defense = 35, slot = 48, level = 80, voc = "knights"},
	[2431] = {name = "stonecutter axe", weaponType = 3, attack = 50, slot = 48 + 2048, attackSpeed = 2200},
	[2181] = {name = "test rod", weaponType = 6, slot = 48, level = 26},
	[2450] = {name = "test club", weaponType = 2, attack = 44, slot = 48},
	[2466] = {name = "golden armor", armor = 14, slot = 8 + 48, description = "It shines.",
		abilities = {skills = {0, 0, 0, 0, 0, 0}, stats = {0, 0, 0, 0}, absorbPercent = {[4] = 5}, speed = 0}},
	[2514] = {name = "mastermind shield", weaponType = WEAPON_SHIELD, defense = 37, slot = 48},
	[2496] = {name = "horned helmet", armor = 11, slot = 1}, -- Hornsworn Helm (a unique of the Embers set)
	[3975] = {name = "dragon shield", weaponType = WEAPON_SHIELD, defense = 31, slot = 48}, -- Emberwarden
	[2206] = {name = "strange ring", slot = 256},
	[36656] = {name = "pair of ember knuckles", weaponType = WEAPON_SHIELD, attack = 46, defense = 12, slot = 48}, -- a fist weapon
	[2183] = {name = "test wand", weaponType = 6, slot = 48, level = 26, voc = "mystics and necromancers"}, -- O490
	[2184] = {name = "test bow", weaponType = 5, slot = 48 + 2048, level = 80, voc = "rangers"}, -- O490
	[2185] = {name = "test blade", weaponType = 1, slot = 48, level = 220, voc = "warriors"}, -- O490
	[2160] = {name = "crystal coin", stackable = true, description = ""},
	[27749] = {name = "lasting exercise wand", charges = 14400},
	[27849] = {name = "Moon Amplifier Catalyst [1]", slot = 48, description = "An amplifier of the old badge rite.",
		abilities = {skills = {0, 0}, absorbPercent = {0}, specialSkills = {0}}} -- the engine's tables: zeros
}

function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getId = function() return id end,
		getClientId = function() return id + 1000 end,
		getName = function() return t.name or "" end,
		getDescription = function() return t.description or "" end,
		isContainer = function() return false end,
		isStackable = function() return t.stackable == true end,
		getWeaponType = function() return t.weaponType or 0 end,
		getSlotPosition = function() return t.slot or 0 end,
		getArmor = function() return t.armor or 0 end,
		getAttack = function() return t.attack or 0 end,
		getDefense = function() return t.defense or 0 end,
		getExtraDefense = function() return 0 end,
		getHitChance = function() return 0 end,
		getShootRange = function() return 0 end,
		getAttackSpeed = function() return t.attackSpeed or 0 end,
		getElementDamage = function() return 0 end,
		getElementType = function() return 0 end,
		getAbilities = function() return t.abilities or {} end,
		getMinReqLevel = function() return t.level or 0 end,
		getMinReqMagicLevel = function() return 0 end,
		getVocationString = function() return t.voc or "" end,
		getCharges = function() return t.charges or 0 end
	}
end

local Item = {}
Item.__index = Item
local function newItem(id, count)
	return setmetatable({id = id, count = count or 1, attrs = {}, custom = {}}, Item)
end
function Item:getId() return self.id end
function Item:getCount() return self.count end
function Item:getWeight() return 4500 end
function Item:getName() return self.attrs[ITEM_ATTRIBUTE_NAME] or ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:hasAttribute(k) return self.attrs[k] ~= nil end
function Item:getAttribute(k) return self.attrs[k] or (k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil) end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:removeAttribute(k) self.attrs[k] = nil end
function Item:getParent() return nil end
function Item:getActionId() return 0 end

Game = {createItem = function(id, count) return newItem(id, count) end}

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/lib/chaos_crafting.lua") -- loads chaos_item_mods.lua and chaos_gems.lua
dofile("data/lib/chaos_unique_items.lua")
dofile("data/scripts/chaos/item_tooltip_core.lua")
local T, C, M, G = ChaosItemTooltip, ChaosCrafting, ChaosItemMods, ChaosGems

-- ---------------------------------------------------------------- the keys agree everywhere
local function readFile(path)
	local f = assert(io.open(path, "r"), "cannot open " .. path)
	local s = f:read("*a")
	f:close()
	return s
end
local engine = {}
-- 0003 brings keys 1-7, 0019 (transmog) key 8
for _, patch in ipairs({"0003-item-custom-attributes.patch", "0019-transmog-appearance.patch"}) do
	for name, value in readFile("src-patches/" .. patch):gmatch("CHAOS_ITEM_KEY_(%u+) = (%d+)") do
		engine[name] = tonumber(value)
	end
end
local client = {}
local block = readFile("../client/overlay/modules/game_itemrarity/itemrarity.lua"):match("ChaosItemAttr = (%b{})")
assert(block, "ChaosItemAttr table in the client")
for name, value in block:gmatch("(%u+) = (%d+)") do
	client[name] = tonumber(value)
end
local n = 0
for key, value in pairs(Chaos.itemAttr) do
	n = n + 1
	eq(engine[key:upper()], value, "engine key " .. key)
	eq(client[key:upper()], value, "client key " .. key)
end
eq(n, 8, "eight keys")
for name in pairs(engine) do
	eq(Chaos.itemAttr[name:lower()] ~= nil, true, "engine key " .. name .. " in Chaos.itemAttr")
end
eq(ChaosOpcodes.itemTooltip, 242, "opcode")
local used = {}
for name, op in pairs(ChaosOpcodes) do
	eq(used[op], nil, "opcode " .. op .. " used twice (" .. name .. ")")
	used[op] = name
end

-- ---------------------------------------------------------------- positions
local p = T.decodePos({x = 65535, y = 6, z = 0})
eq(p.kind, "slot") eq(p.slot, 6)
p = T.decodePos({x = 65535, y = 0x40 + 3, z = 7})
eq(p.kind, "container") eq(p.cid, 3) eq(p.index, 7)
p = T.decodePos({x = 1000, y = 1000, z = 7, s = 2})
eq(p.kind, "map") eq(p.stackpos, 2)
eq(T.decodePos({x = 65535, y = 11, z = 0}), nil, "slot past the 10.98 inventory")
eq(T.decodePos({x = 65535, y = 3, z = 1}), nil, "inventory slot with z")
eq(T.decodePos({x = 65535, y = 0x50, z = 0}), nil, "container id past 15")

-- ---------------------------------------------------------------- the item the client means (T.matchIndex)
-- live test winpkg-35: a Rope showed "Cheese 62", a Training Wand "Gold coin 100". Two open containers with other items
-- at the same index; the backpack got a stack of cheese at the front after the client looked (its items moved one up).
do
	local ROPE, CHEESE, WAND, GOLD = 3003, 3607, 3075, 3031
	local backpack = {{CHEESE, 62}, {ROPE, 1}, {WAND, 1}} -- the server's view (index 0 first)
	local lootbag = {{GOLD, 100}, {ROPE, 1}}
	local function at(list)
		return function(i)
			local e = list[i + 1]
			if e then
				return e[1], e[2]
			end
		end
	end
	eq(T.matchIndex(0, 3, at(backpack), ROPE), 1, "the rope asked at its old index: found one slot further")
	eq(T.matchIndex(1, 3, at(backpack), WAND), 2, "the wand too")
	eq(T.matchIndex(1, 3, at(backpack), ROPE), 1, "the rope where it is")
	eq(T.matchIndex(0, 2, at(lootbag), WAND), nil, "no wand in the loot bag: nothing (not the gold at that index)")
	eq(T.matchIndex(0, 2, at(lootbag), ROPE), 1, "same index, other container: its own rope")
	eq(T.matchIndex(0, 3, at(backpack), CHEESE, 62), 0, "a stack by id and count")
	eq(T.matchIndex(0, 3, at(backpack), CHEESE, 10), nil, "another count is another stack")
	eq(T.matchIndex(0, 3, at(backpack), nil), 0, "an older client (no client id): the slot as before")
	eq(T.matchIndex(5, 3, at(backpack), ROPE), 1, "an index past the end still finds it")
end
eq(T.decodePos({x = 65535, y = 0x40, z = 300}), nil, "container slot past 255")
eq(T.decodePos({x = 10.5, y = 1, z = 7}), nil, "fraction")
eq(T.decodePos({x = "a", y = 1, z = 7}), nil, "string")
eq(T.decodePos({x = 100, y = 100, z = 16}), nil, "floor 16")
eq(T.decodePos({x = 100, y = 100, z = 7, s = 12}), nil, "stack position 12")
eq(T.decodePos(nil), nil, "nil")

local me = {x = 100, y = 100, z = 7}
eq(T.mapAllowed(me, {x = 104, y = 103, z = 7}, true), true, "near and visible")
eq(T.mapAllowed(me, {x = 104, y = 103, z = 7}, false), false, "not visible")
eq(T.mapAllowed(me, {x = 109, y = 100, z = 7}, true), false, "too far")
eq(T.mapAllowed(me, {x = 100, y = 100, z = 6}, true), false, "other floor")

-- ---------------------------------------------------------------- budget
local b = {}
for i = 1, 12 do
	eq(T.allow(b, 1000, 1), true, "burst " .. i)
end
eq(T.allow(b, 1000, 1), false, "13th at once")
eq(T.allow(b, 1500, 3), true, "half a second later: 3 tokens back")
eq(T.allow(b, 1500, 1), false, "and spent")
eq(T.allow(b, 4000, 12), true, "full again after 2.5 s (capped at 12)")
eq(T.allow(b, 4000, 1), false, "never above the bucket size")

-- ---------------------------------------------------------------- slots
local slots, name = T.slotsOf(48, "weapon")
eq(#slots, 2) eq(slots[1], 6) eq(slots[2], 5) eq(name, "Weapon")
slots, name = T.slotsOf(48 + 2048, "weapon")
eq(name, "Two-handed weapon")
-- owner 2026-11-02: every weapon names its kind ("Two-handed sword", "Dagger", "Fist weapon" ...)
slots, name = T.slotsOf(48 + 2048, "weapon", {weaponType = 1, name = "soulshredder"})
eq(name, "Two-handed sword", "a two-handed sword")
eq(T.weaponLabel({weaponType = 1, name = "combat knife"}), "Dagger", "a one-handed sword named knife is a dagger")
eq(T.weaponLabel({weaponType = 1, name = "assassin dagger"}), "Dagger")
eq(T.weaponLabel({weaponType = 1, name = "saint's blade"}), "One-handed sword", "no dagger word in the middle of another")
eq(T.weaponLabel({weaponType = 1, twoHanded = true, name = "giant dagger"}), "Two-handed sword", "a two-handed one is no dagger")
eq(T.weaponLabel({weaponType = 2, twoHanded = true, name = "maul"}), "Two-handed club")
eq(T.weaponLabel({weaponType = 3, name = "hatchet"}), "One-handed axe")
eq(T.weaponLabel({weaponType = 1, fist = true, name = "claw"}), "Fist weapon", "a Monk fist weapon")
eq(T.weaponLabel({weaponType = 5, launcher = "bow"}), "Bow")
eq(T.weaponLabel({weaponType = 5, launcher = "crossbow"}), "Crossbow")
eq(T.weaponLabel({weaponType = 5, name = "spear"}), "Throwing weapon")
eq(T.weaponLabel({weaponType = 6, name = "wand of vortex"}), "Wand")
eq(T.weaponLabel({weaponType = 6, name = "hailstorm rod"}), "Rod")
eq(T.weaponLabel({weaponType = 0}), "Weapon", "an unknown type stays a weapon")
slots, name = T.slotsOf(48, "shield")
eq(name, "Shield") eq(#slots, 2)
slots, name = T.slotsOf(1, "helmet")
eq(slots[1], 1) eq(name, "Helmet")
slots, name = T.slotsOf(256, "jewel")
eq(slots[1], 9) eq(name, "Ring")
eq(#slots, 1, "a ring is compared with the ring slot only (engine patch 0058 took the second ring slot away)")
slots, name = T.slotsOf(8192 + 48, "other")
eq(slots[1], 13, "a badge is compared with the badge slot") eq(#slots, 1) eq(name, "Badge")
slots, name = T.slotsOf(4096 + 8192 + 48, "other")
eq(#slots, 0, "a deck (deck and badge bits) is worn nowhere") eq(name, nil)
slots, name = T.slotsOf(8 + 48, "armor")
eq(#slots, 1, "an armour that may also be held is compared as an armour") eq(slots[1], 4) eq(name, "Armour")
slots, name = T.slotsOf(48, nil)
eq(#slots, 0, "a plain item held in the hands") eq(name, nil)
slots, name = T.slotsOf(0, nil)
eq(#slots, 0) eq(name, nil)

-- ---------------------------------------------------------------- a rolled rare weapon with sockets and gems
local sword = newItem(2400)
sword:setCustomAttribute("rarity", 4) -- Epic: tier 2
sword:setCustomAttribute("combatPowerLevel", 37)
sword:setCustomAttribute("rarity_physicalAbsorb", 2)
sword:setCustomAttribute("rarity_swordSkill", 1)
sword:setCustomAttribute("chaos_modv", 3) -- numbers of O461: read as they are, not upgraded (the upgrade has its own tests)
sword:setCustomAttribute("rarity_criticalHitChance", 2)
sword:setCustomAttribute("rarity_criticalHitAmount", 1)
sword:setCustomAttribute("rarity_elementfire", 7)
sword:setCustomAttribute("chaos_mod_lifeonkill", 15)
sword:setAttribute(ITEM_ATTRIBUTE_ATTACK, 50) -- the rarity roll raised the attack
G.setCount(sword, 2)
G.insert(sword, G.gemId(1, 4)) -- Flawless Ruby: Fire Damage +9% in a weapon
local tip = T.build(sword, {attrs = {[1] = 4, [2] = 37, [5] = 2, [6] = 1873000000123, [7] = 3054}})
eq(tip.key, "1873000000123:3054", "cache key from the client attributes")
eq(tip.name, "magic sword") eq(tip.id, 3400, "client id") eq(tip.kind, "weapon") eq(tip.slot, "One-handed sword", "the weapon names its kind")
eq(tip.rarity, 4) eq(tip.rarityName, "Rare") eq(tip.level, 37) eq(tip.maxTier, 3, "item level 37: up to T3")
-- a catalyst a boss dropped before 2026-10-22 carries the kill's item level: no gear, so the tooltip shows none
do
	local cat = newItem(27849)
	cat:setCustomAttribute(M.ILVL, 135)
	local ct = T.build(cat)
	eq(ct.level, nil, "no item level on a catalyst") eq(ct.maxTier, nil, "no tier line")
	eq(ct.desc, "An amplifier of the old badge rite.", "its description")
end
eq(tip.tier, nil, "no rarity tier any more")
eq(tip.sides.p, 4, "skill, critical chance, critical damage, element") eq(tip.sides.s, 2) eq(tip.sides.max, 2, "Rare: two of each (an old item may carry more)")
eq(tip.cmp[1], 6) eq(tip.cmp[2], 5)
eq(tip.base[1].k, "attack") eq(tip.base[1].v, 50, "attack from the item, not the type")
eq(tip.base[2].k, "defense") eq(tip.base[2].v, 35)
eq(#tip.mods, 6, "absorb, skill, critical chance, critical damage (two modifiers since O461), Chaos modifier, element")
local byKey = {}
for _, m in ipairs(tip.mods) do
	byKey[m.k] = m
end
eq(byKey.rarity_physicalAbsorb.t, "Physical +2%") eq(byKey.rarity_physicalAbsorb.lo, 1) eq(byKey.rarity_physicalAbsorb.hi, 2)
eq(byKey.rarity_physicalAbsorb.tr, 2, "tier from the value (an old item)") eq(byKey.rarity_physicalAbsorb.sd, "s")
eq(byKey.rarity_elementfire.lo, 5, "the range of its tier") eq(byKey.rarity_elementfire.hi, 9)
eq(byKey.rarity_elementfire.tr, 3) eq(byKey.rarity_elementfire.sd, "p")
eq(tip.mods[1].sd, "p", "prefixes first") eq(tip.mods[#tip.mods].sd, "s", "suffixes last")
eq(byKey.rarity_criticalHitChance.t, "Critical Strike Chance +2%") eq(byKey.rarity_criticalHitChance.g, "single")
eq(byKey.rarity_criticalHitAmount.t, "Critical Strike Damage +1%") eq(byKey.rarity_criticalHitAmount.sd, "p")
-- O471: the critical modifiers carry the character caps (45 / 150), "over" only when the viewer's total is above them
eq(byKey.rarity_criticalHitChance.cap, 45, "the chance cap on the line") eq(byKey.rarity_criticalHitAmount.cap, 150, "the damage cap")
eq(byKey.rarity_criticalHitChance.over, nil, "not over: no flag") eq(byKey.chaos_mod_lifeonkill.cap, nil, "other modifiers have no cap")
do
	local t2 = T.build(sword, {over = {chance = true}})
	local by2 = {}
	for _, m in ipairs(t2.mods) do by2[m.k] = m end
	eq(by2.rarity_criticalHitChance.over, true, "the viewer is over the chance cap") eq(by2.rarity_criticalHitAmount.over, nil, "but not the damage cap")
	local pen = newItem(3400)
	pen:setCustomAttribute("rarity", 4) pen:setCustomAttribute("chaos_modv", 3) pen:setCustomAttribute("combatPowerLevel", 100)
	M.set(pen, "physpen", 9, 6)
	local t3 = T.build(pen, {})
	eq(t3.mods[1].cap, 20, "penetration: 20 points in total")
end
local lok = byKey.chaos_mod_lifeonkill
local r = M.legacy.lifeonkill[3] -- no stored tier: the range it was rolled in (before the ranges were raised)
eq(lok.t, "Life on Kill +15") eq(lok.g, "chaos") eq(lok.lo, r[1]) eq(lok.hi, r[2]) eq(lok.tr, 3) eq(lok.sd, "s")
eq(tip.sockets.count, 2) eq(tip.sockets.max, 2)
eq(tip.sockets.list[1].name, "Flawless Ruby") eq(tip.sockets.list[1].text, "Fire Damage +9%")
eq(tip.sockets.list[2].name, nil, "empty socket")
local stats = {}
for _, s in ipairs(tip.stats) do
	stats[s.k] = s
end
eq(stats.attack.v, 50) eq(stats.rarity_criticalHitAmount.v, 1, "its own number") eq(stats.rarity_criticalHitChance.v, 2)
eq(stats.rarity_elementfire.l, "Fire Damage") eq(stats.gem_dmg_fire.v, 9, "gem effect in the compare numbers")
eq(stats.chaos_mod_lifeonkill.fmt, nil, "flat Chaos modifier") eq(stats.rarity_swordSkill.v, 1)
eq(tip.req.level, 80) eq(tip.req.voc, "knights") eq(tip.weight, 45)
-- a worn item with no engine class list is for every class (a stock Warrior Helmet printed no line)
eq(T.build(newItem(2466)).req.voc, "all classes", "armour with no class list")
eq(T.build(newItem(2206)).req.voc, "all classes", "ring with no class list")
-- O307: the class text names who may use the item (the Beastmaster is no crossbow class)
do
	local D5, A_ARROW, A_BOLT = 5, 2, 1
	eq(T.vocationText("rangers", {weaponType = D5, slot = 2048, ammoType = A_BOLT}), "Ranger, Deadeye", "crossbow")
	eq(T.vocationText("rangers", {weaponType = D5, slot = 2048, ammoType = A_ARROW}), "Ranger, Deadeye, Beastmaster", "bow")
	eq(T.vocationText("rangers", {weaponType = D5, slot = 512, ammoType = A_ARROW}), "Ranger, Deadeye, Beastmaster", "arrow")
	eq(T.vocationText("rangers", {weaponType = D5, slot = 512, ammoType = A_BOLT}), "Ranger, Deadeye", "bolt")
	eq(T.vocationText("rangers", {weaponType = 0, slot = 8, ammoType = 0}), "Ranger, Deadeye, Beastmaster", "armour: the whole line")
	eq(T.vocationText("warriors", {weaponType = 1, slot = 16, ammoType = 0}), "Warrior, Juggernaut", "one-handed sword")
	eq(T.vocationText("warriors", {weaponType = 1, slot = 2048, ammoType = 0}), "Warrior, Juggernaut, Berserker", "two-handed sword")
	eq(T.vocationText("warriors", {weaponType = 4, slot = 32, ammoType = 0}), "Warrior, Juggernaut", "shield")
	eq(T.vocationText("warriors", {weaponType = 0, slot = 8, ammoType = 0}), "Warrior, Juggernaut, Berserker", "armour")
	eq(T.vocationText("deadeyes", {weaponType = D5, slot = 2048, ammoType = A_BOLT}), "Deadeye", "an ascension alone stays alone")
	eq(T.vocationText("rangers, thieves and monks", {slot = 8}), "Ranger, Thief, Monk, Deadeye, Beastmaster", "a list")
	eq(T.vocationText("knights", {}), "knights", "unknown names stay")
end
eq(tip.desc, nil, "a rolled item's description is its modifiers, not repeated")
eq(tip.unique, nil) eq(tip.locked, nil)

-- orbs v2 on the tooltip: quality, a bound modifier, a legendary power, the extra slot, a ruined item
sword:setCustomAttribute("rarity", 5)
C.addQuality(sword, 7)
local lokDef = C.affixOf("chaos_mod_lifeonkill")
sword:setCustomAttribute(M.bindAttr("chaos_mod_lifeonkill"), 1)
C.writeAffix(sword, C.affixOf(M.attr("deathblast")), 4, 5)
sword:setCustomAttribute(M.EXTRA, 1)
sword:setCustomAttribute(M.RUINED, 1)
tip = T.build(sword)
eq(tip.quality.q, 7, "item quality") eq(tip.quality.cap, 20)
eq(tip.ruined, true, "ruined")
eq(tip.sides.mp, 4, "Legendary: three prefixes, one more from the extra slot") eq(tip.sides.ms, 3)
local rows = {}
for _, m in ipairs(tip.mods) do rows[m.k] = m end
eq(rows.chaos_mod_lifeonkill.bd, true, "a bound modifier") eq(rows.rarity_swordSkill.bd, nil)
eq(rows.chaos_mod_deathblast.pw, true, "a legendary power") eq(rows.chaos_mod_deathblast.t, "Death Blast: 5% chance on kill to explode")
eq(rows.chaos_mod_deathblast.sd, "p")
for _, k in ipairs({"chaos_mod_deathblast", "rarity_swordSkill"}) do
	eq(rows[k].v, rows[k].v)
end
sword:removeCustomAttribute(M.RUINED); sword:removeCustomAttribute(M.EXTRA); sword:removeCustomAttribute(M.QUALITY)
tip = T.build(sword)
eq(tip.quality, nil, "no quality") eq(tip.ruined, nil)
eq(tip.corrupted, nil, "not corrupted")

-- a Void Orb's corruption: the flag and the corrupted implicit (side "i", listed first, no slot taken)
local pBefore = tip.sides.p
sword:setCustomAttribute(M.CORRUPTED, 1)
sword:setCustomAttribute(M.IMPLICIT, "chaos_mod_bossdamage")
C.writeAffix(sword, C.affixOf("chaos_mod_bossdamage"), 8, 20)
tip = T.build(sword)
eq(tip.corrupted, true, "corrupted")
eq(tip.mods[1].k, "chaos_mod_bossdamage", "the implicit comes first")
eq(tip.mods[1].sd, "i", "side implicit")
eq(tip.mods[1].tr, 8)
eq(tip.sides.p, pBefore, "the implicit takes no prefix slot")
sword:removeCustomAttribute(M.CORRUPTED); sword:removeCustomAttribute(M.IMPLICIT)
C.removeMod(sword, C.modByKey(sword, "chaos_mod_bossdamage"))
tip = T.build(sword)
eq(tip.corrupted, nil)

-- the attack interval of a two-handed weapon (lower is better)
local axe = newItem(2431)
tip = T.build(axe)
eq(tip.slot, "Two-handed axe", "the weapon names its kind")
for _, s in ipairs(tip.base) do
	if s.k == "attackspeed" then
		eq(s.v, 2.2) eq(s.fmt, "sec") eq(s.low, true)
	end
end
eq(tip.key, nil, "no client attributes: no cache key")
eq(tip.rarity, 0) eq(tip.rarityName, nil) eq(tip.tier, nil)

-- ---------------------------------------------------------------- a unique of a set
local helm = newItem(2496)
eq(ChaosMakeUnique(helm), true, "Hornsworn Helm has a spec")
tip = T.build(helm, {equippedIds = {[3975] = true, [8892] = true}})
eq(tip.unique ~= nil, true, "unique")
eq(tip.name, ChaosUniqueSpecs[2496].name)
eq(tip.unique.set.name, "Embers of Aranoth") eq(tip.unique.set.have, 2) eq(tip.unique.set.total, 6)
eq(tip.req.level, ChaosUniqueById[2496].level, "the unique's level")
eq(tip.desc, ChaosUniqueSpecs[2496].description, "flavour text")
eq(tip.sockets.count, 1, "a unique's fixed socket") eq(tip.sockets.list[1].name, nil)
eq(tip.mods[1].lo, nil, "uniques have no roll ranges")
eq(tip.cmp[1], 1)

-- O489: a stock copy of a base id that is also a unique with its own equip rule names the STOCK rule (the engine reads
-- the looser entry of movements.xml: here level 0, everyone); a unique copy keeps its own
ChaosUniqueEquip = ChaosUniqueEquip or {}
local stockBefore = ChaosUniqueEquip.stock
ChaosUniqueEquip.stock = {[2496] = {level = 100, vocations = {"Ranger", "Deadeye", "Beastmaster", "Thief"}}, [2466] = {}}
tip = T.build(newItem(2496))
eq(tip.req.level, 100, "a stock copy: the stock level")
eq(tip.req.voc, "Ranger, Deadeye, Beastmaster, Thief only", "a stock copy: the stock classes (O490: a base class alone reads as its whole line, so the Thief without a Ninja or Samurai is \"Thief only\")")
tip = T.build(helm)
eq(tip.req.level, ChaosUniqueById[2496].level, "a unique copy: its own level")
eq(tip.req.voc ~= "Ranger, Deadeye, Beastmaster, Thief only", true, "a unique copy: not the stock classes")
tip = T.build(newItem(2466))
eq(tip.req.level, nil, "a stock rule of {}: no level")
eq(tip.req.voc, "all classes", "a stock rule of {}: everyone")
ChaosUniqueEquip.stock = stockBefore

-- O490: the rule each item is held to (data/lib/chaos_equip_rules.lua, tools/install_equip_rules.py), not the engine's item type
local Rd = T.readClasses
local function set(...)
	local t = {}
	for _, n in ipairs({...}) do t[n] = true end
	return t
end
local function same(a, b)
	for k in pairs(a) do if not b[k] then return false end end
	for k in pairs(b) do if not a[k] then return false end end
	return true
end
eq(same(Rd("Mystic"), set("Mystic", "Elementalist", "Illusionist")), true, "a base class alone is its whole line")
eq(same(Rd("Mystic, Illusionist, Necromancer"), set("Mystic", "Illusionist", "Necromancer", "Lich", "Bone Lord")), true,
	"a line named class by class, a line named by its base")
eq(same(Rd("Mystic only"), set("Mystic")), true, "Name only is that class alone")
eq(same(Rd("Deadeye, Ninja"), set("Deadeye", "Ninja")), true, "ascended classes without their base")
eq(Rd("all classes").Sentinel == true and Rd("").Lich == true, true, "all classes and no text: everyone")
eq(T.stockClassText({"Mystic", "Thief", "Ninja", "Samurai"}), "Mystic only, Thief", "a base class without its ascended classes")
local everyone = {}
for _, fam in ipairs(T.CLASS_LINES) do
	everyone[#everyone + 1] = fam.base
	everyone[#everyone + 1] = fam.ascended[1]
	everyone[#everyone + 1] = fam.ascended[2]
end
eq(T.stockClassText(everyone), "", "all 21 classes: the row says all classes")
eq(T.ruleVocString("rangers", {"Ranger", "Deadeye"}, {weaponType = 5, slot = 48 + 2048, ammoType = 0}), "rangers", "a text that already reads as the list stays the engine's")
eq(T.ruleVocString("mystics and necromancers", {"Mystic", "Illusionist", "Necromancer", "Lich", "Bone Lord"}, {}),
	"Mystic, Illusionist, Necromancer", "the engine's text misses the Illusionist's line: the list is named")
eq(T.equipRuleOf(2183), nil, "no rules file: the engine's item type stands")
tip = T.build(newItem(2183))
eq(tip.req.level, 26, "no rules: the engine's level") eq(tip.req.voc, "Mystic, Necromancer", "no rules: the engine's classes")
T.setEquipRules({sets = {{"Mystic", "Illusionist", "Necromancer", "Lich", "Bone Lord"}, {"Ranger", "Deadeye", "Beastmaster"}, {"Warrior", "Juggernaut"}},
	rules = {[2183] = {30, 1, 5}, [2184] = {80, 2}, [2185] = {270, 3}}})
tip = T.build(newItem(2183))
eq(tip.req.level, 30, "a rule: its level") eq(tip.req.magic, 5, "a rule: its magic level")
eq(tip.req.voc, "Mystic, Illusionist, Necromancer", "a wand for the Mystic and the Illusionist names both")
tip = T.build(newItem(2184))
eq(tip.req.voc, "Ranger, Deadeye, Beastmaster", "a bow takes the Beastmaster: the whole Ranger line, class by class")
tip = T.build(newItem(2185))
eq(tip.req.level, 270, "a rule: the level of the stricter entry") eq(tip.req.voc, "Warrior, Juggernaut", "a rule: partly named line")
-- a plain copy with a rule: the rule wins over the O489 stock table
ChaosUniqueEquip.stock = {[2183] = {level = 1, vocations = {"Thief"}}}
tip = T.build(newItem(2183))
eq(tip.req.level, 30, "the rules table wins over the stock table") eq(tip.req.voc, "Mystic, Illusionist, Necromancer", "ditto")
ChaosUniqueEquip.stock = stockBefore
T.setEquipRules(nil)
-- the class row is cut between two names
local long = {}
for i = 1, 14 do long[i] = "Longclassname" .. i end
local row = T.classLine(table.concat(long, ", "), {slot = 1}, "Helmet")
eq(row:sub(-14), "Longclassname7", "cut between two names")
eq(#row <= 120, true, "within 120")

-- ---------------------------------------------------------------- plain items
local armor = newItem(2466)
tip = T.build(armor)
eq(tip.desc, "It shines.") eq(tip.sockets, nil) eq(#tip.mods, 0)
local fire
for _, s in ipairs(tip.base) do
	if s.k == "protect4" then fire = s end
end
eq(fire.l, "Fire Protection", "the type's own protection") eq(fire.v, 5)
local coin = newItem(2160, 37)
tip = T.build(coin)
eq(tip.count, 37) eq(tip.kind, nil) eq(tip.cmp, nil, "nothing to compare") eq(tip.desc, nil)

-- locked
local ring = newItem(2206)
ring:setCustomAttribute("chaos_locked", 1)
eq(T.build(ring).locked, true)

-- a Rift Key: its map modifiers, rewards and level; not worn, so nothing to compare
dofile("data/scripts/chaos/rift_core.lua")
ChaosRiftConfig = dofile("data/scripts/chaos/rift_config.lua")
local key = newItem(10155)
key:setCustomAttribute("rift_tier", 5)
key:setCustomAttribute("rift_mods", "vitality:40,coffer:100")
key:setAttribute(ITEM_ATTRIBUTE_NAME, "Rift Key (Tier 5)")
tip = T.build(key)
eq(tip.kind, nil, "a key is no gear") eq(tip.cmp, nil, "a key has nothing to compare") eq(tip.slot, nil)
eq(#tip.mods, 2, "both key modifiers") eq(tip.mods[1].k, "vitality")
eq(tip.mods[1].t:find("+40%% health") ~= nil, true, "the modifier's text: " .. tip.mods[1].t)
eq(tip.mods[2].g, "chaos", "a boon in the Chaos colour")
eq(tip.req.level, ChaosRiftCore.tierInfo(ChaosRiftConfig, 5).minLevel, "the level the tier needs")
eq(tip.desc:find("Opens a rift of tier 5") ~= nil, true, "how it is used")
eq(tip.desc:find("item quantity") ~= nil, true, "the reward bonus")
local plainOrb = newItem(10155)
eq(T.build(plainOrb).mods == nil or #T.build(plainOrb).mods == 0, true, "a shadow orb without a tier is not a key")
ChaosRiftCore, ChaosRiftConfig = nil, nil

-- a broken attribute does not break the tooltip
local odd = newItem(2400)
odd:setCustomAttribute("rarity", "x")
eq(T.build(odd).rarity, 0)

-- ---------------------------------------------------------------- the viewer's attack interval (attack speed cap)
local function yours(t)
	for _, s in ipairs(t.base) do
		if s.k == "yourinterval" then
			return s
		end
	end
end
eq(yours(T.build(axe)), nil, "no viewer: no line")
local fast = newItem(2400)
fast:setAttribute(ITEM_ATTRIBUTE_ATTACK_SPEED, 1600) -- attack speed +20% (no own interval: from 2000)
local y = yours(T.build(fast, {wielder = {voc = 2000, dex = 0}}))
eq(y.v, 1.6) eq(y.l, "Your Attack Interval") eq(y.low, true)
y = yours(T.build(fast, {wielder = {voc = 1300, dex = 20}}))
eq(y.v, 0.83, "Shadowfist with dexterity: 832 ms, no floor in the way (3 per second since O426)") eq(y.l, "Your Attack Interval")
y = yours(T.build(fast, {wielder = {voc = 1300, dex = 20, bonus = 80}}))
eq(y.v, 0.33, "Shadowfist, 100 points stacked: held at the 3 per second floor") eq(y.l, "Your Attack Interval (capped)")
y = yours(T.build(fast, {wielder = {voc = 2000, dex = 20}}))
eq(y.v, 1.28, "weapon + dexterity: -36%") eq(y.l, "Your Attack Interval")
eq(yours(T.build(armor, {wielder = {voc = 2000, dex = 0}})), nil, "only weapons")

-- the estimated DPS of a weapon (weapon_dps_core.lua): from the wielder's level and best skill
dofile("data/scripts/chaos/weapon_balance_core.lua")
dofile("data/scripts/chaos/weapon_dps_core.lua")
local function dpsOf(t)
	for _, s in ipairs(t.base) do
		if s.k == "dps" then
			return s
		end
	end
end
local sword = newItem(2400) -- one-handed, attack 48, default 2 s interval
local row = dpsOf(T.build(sword, {wielder = {voc = 2000, dex = 0, level = 100, melee = 70, distance = 10}}))
eq(row ~= nil, true, "a sword has the line") eq(row.l, "Estimated DPS") eq(row.fmt, "est")
eq(row.v, ChaosWeaponDps.round(ChaosWeaponDps.maxHit(100, 70, 48) / 2 / 2), "level 100, melee 70, attack 48, 2 s")
local row2 = dpsOf(T.build(sword, {wielder = {voc = 2000, dex = 0, level = 100, melee = 90, distance = 10}}))
eq(row2.v > row.v, true, "more skill, more DPS")
eq(dpsOf(T.build(sword, {wielder = {voc = 2000, dex = 0}})), nil, "no level: no estimate")
eq(dpsOf(T.build(sword, {})), nil, "no viewer: no estimate")
eq(dpsOf(T.build(armor, {wielder = {voc = 2000, dex = 0, level = 100, melee = 70}})), nil, "armour has none")
-- a Monk fist weapon (owner 2026-11-01 "sem dps"): the fist skill, the fist attack and the vocation's meleeDamage
dofile("data/scripts/chaos/monk_chi_core.lua")
local knuckles = newItem(36656)
local fw = {voc = 2000, dex = 0, level = 150, melee = 10, distance = 10, fist = 80, vocId = 17}
local frow = dpsOf(T.build(knuckles, {wielder = fw}))
eq(frow ~= nil, true, "a fist weapon has the line")
local MK = ChaosMonk
local fmax = MK.maxWeaponDamage(150, 80, MK.fistAttack(150, 46), 1) * 1.2
local fpow = ChaosWeaponPower and ChaosWeaponPower.hitFactor and ChaosWeaponPower.hitFactor("fist", 150, 80) or 1
eq(frow.v, ChaosWeaponDps.round(fmax / 2 * fpow / 2), "level 150, fist 80, attack 46, Monk x1.2, 2 s")
fw.fist = 100
eq(dpsOf(T.build(knuckles, {wielder = fw})).v > frow.v, true, "more fist skill, more DPS (the melee skill does not count)")
fw.fist, fw.vocId = 80, 2
eq(dpsOf(T.build(knuckles, {wielder = fw})).v, frow.v, "another viewer: the base Monk's factor")
fw.vocId = 19
eq(dpsOf(T.build(knuckles, {wielder = fw})).v < frow.v, true, "Iron Sage x1.1")
eq(dpsOf(T.build(newItem(2514), {wielder = fw})), nil, "a plain shield has none")
local twoH = dpsOf(T.build(newItem(2431), {wielder = {voc = 2000, dex = 0, level = 100, melee = 70}}))
eq(twoH ~= nil, true, "a two-handed axe has one")
-- the family line of a sword, axe or club (weapon_families_core.lua, O454) and the family's price in the estimate
dofile("data/scripts/chaos/weapon_families_core.lua")
local FM = ChaosWeaponFamilies
eq(T.build(newItem(2400)).note, FM.note("sword"), "a sword carries its tempo line")
eq(T.build(newItem(2431)).note, FM.note("axe"), "an axe its cleave line")
eq(T.build(newItem(2450)).note, FM.note("club"), "a club its impact line")
eq(T.build(newItem(2400), {wielder = {voc = 2000, dex = 0, level = 100, melee = 70, vocId = 4}}).note, FM.note("sword"), "a Warrior sees it")
eq(T.build(newItem(2400), {wielder = {voc = 2000, dex = 0, level = 100, melee = 70, vocId = 17}}).note, nil, "a Monk does not (the Monk line is untouched)")
eq(T.build(newItem(2400), {wielder = {voc = 2000, dex = 0, level = 100, melee = 70, vocId = 3}}).note, nil, "nor a Ranger")
eq(T.build(newItem(2514)).note, nil, "a shield has none")
eq(T.build(newItem(2181)).note, nil, "a rod has none")
eq(T.build(newItem(36656)).note, nil, "a fist weapon has none")
local axeW = {voc = 2000, dex = 0, level = 100, melee = 70}
local axePlain = dpsOf(T.build(newItem(2431), {wielder = axeW})).v
axeW.vocId = 17
eq(dpsOf(T.build(newItem(2431), {wielder = axeW})).v, axePlain, "a Monk's estimate is the plain one")
axeW.vocId = 4
local axeFam = dpsOf(T.build(newItem(2431), {wielder = axeW})).v
eq(axeFam < axePlain and axeFam >= math.floor(axePlain * FM.single("axe")) - 1, true, "a Warrior's axe estimate pays the family price: " .. axeFam .. " of " .. axePlain)
local swordW = {voc = 2000, dex = 0, level = 100, melee = 70, vocId = 4}
eq(dpsOf(T.build(newItem(2400), {wielder = swordW})).v, row.v, "a sword's estimate is the plain one (the tempo is not in it)")
ChaosDisplayScale = {factor = function() return 10 end}
eq(dpsOf(T.build(sword, {wielder = {voc = 2000, dex = 0, level = 100, melee = 70}})).v, row.v * 10, "x the display scale of the level")
ChaosDisplayScale = nil
-- a wand or rod (O353): its hit for the viewer as "Attack lo-hi" first, and its estimated DPS
ChaosWeaponDps.wands = {[2181] = {min = 42, max = 48}}
ChaosWeaponSkill = {wandFactor = function(level, ml) return ml >= 50 and 2 or 1 end}
ChaosWeaponPower = {levelFactor = function() return 1.5 end}
local rod = newItem(2181)
local rt = T.build(rod, {wielder = {voc = 2000, dex = 0, level = 100, magic = 60}})
eq(rt.base[1].k, "attack", "the rod's attack comes first") eq(rt.base[1].fmt, "range")
eq(rt.base[1].lo, 126, "42 x 2 x 1.5") eq(rt.base[1].hi, 144, "48 x 2 x 1.5") eq(rt.base[1].v, 135, "attack value: the mean")
eq(dpsOf(rt).v, ChaosWeaponDps.round(45 * 3 / 2), "rod dps: mean hit x factor / 2 s")
eq(T.build(rod, {wielder = {voc = 2000, dex = 0, level = 100, magic = 10}}).base[1].hi, 72, "less magic level, smaller hit")
eq(dpsOf(T.build(rod, {})), nil, "no viewer: no rod estimate")
ChaosWeaponDps.wands = {}
eq(dpsOf(T.build(rod, {wielder = {voc = 2000, dex = 0, level = 100, magic = 60}})), nil, "an unknown wand: no rows")
ChaosWeaponDps.wands, ChaosWeaponSkill, ChaosWeaponPower = nil, nil, nil

-- a transmog look travels in the tip (also in item link snapshots, itemlink.lua builds them with T.build): the client
-- draws the tooltip icon with it (game_itemtooltip setAppearanceId) and names it
local dressed = newItem(3975)
dressed:setCustomAttribute("chaos_tmog", 2206)
local lookTip = T.build(dressed)
eq(type(lookTip.look), "table", "the look is in the tip")
eq(lookTip.look.cid, 3206, "look client id") eq(lookTip.look.name, "strange ring", "look name")
eq(lookTip.id, 4975, "the item stays its own")
eq(T.build(newItem(3975)).look, nil, "no look without a transmog")

-- ---------------------------------------------------------------- the display scale (display_scale_core.lua DS.itemTip)
-- a built tooltip as sent: the factor of the item's level requirement, the flat health / mana / damage / heal rows only
dofile("data/scripts/chaos/display_scale_core.lua")
local DS = ChaosDisplayScale
DS.configure({curve = {{100, 1}, {1000, 1000}, {1500, 10000}}}) -- the scale is off (x1); its code is tested on the old curve
local flatItem = newItem(2400) -- magic sword, level 80
ChaosItemMods.set(flatItem, "lifeonhit", 20, 4)
ChaosItemMods.set(flatItem, "attackspeed", 5, 4)
local raw = T.build(flatItem)
local function rowOf(list, key) for _, r in ipairs(list or {}) do if r.k == key then return r end end end
local rawHit = rowOf(raw.mods, "chaos_mod_lifeonhit")
eq(rawHit ~= nil and rawHit.v, 20, "the built tooltip has the flat modifier")
eq(DS.itemTip(raw).ds, 1, "a level-80 item: x1")
eq(rowOf(DS.itemTip(raw).mods, "chaos_mod_lifeonhit").v, 20, "x1: as built")
TYPES[2400].level = 1000
local high = T.build(flatItem)
eq(high.req.level, 1000, "now a level-1000 item")
local shown = DS.itemTip(high)
eq(shown.ds, 1000, "its factor")
eq(rowOf(shown.mods, "chaos_mod_lifeonhit").v, 20000, "flat health on hit x1000")
eq(rowOf(shown.mods, "chaos_mod_lifeonhit").t, ChaosItemMods.text("lifeonhit", 20000), "its text")
eq(rowOf(shown.mods, "chaos_mod_attackspeed").v, 5, "a percent modifier stays")
eq(rowOf(shown.stats, "chaos_mod_lifeonhit").v, 20000, "compare stats x1000")
eq(rowOf(shown.stats, "chaos_mod_lifeonhit").sc, 1, "marked for the compare view")
eq(rowOf(shown.base, "attack").v, rowOf(high.base, "attack").v, "attack stays")
eq(rowOf(high.mods, "chaos_mod_lifeonhit").v, 20, "the built tooltip itself stays raw")
TYPES[2400].level = 80

-- ---------------------------------------------------------------- charges (live test winpkg-35: a Lasting Exercise Wand
-- showed only its name and weight)
do
	eq(T.chargeInfo(14400, 14400).n, 14400, "full charges")
	eq(T.chargeInfo(14400, 14400).max, nil, "no max when full")
	eq(T.chargeInfo(1200, 14400).max, 14400, "used: n of max")
	eq(T.chargeInfo(nil, 14400).unlimited, true, "a type with charges, the item without: unlimited")
	eq(T.chargeInfo(nil, 0), nil, "no charges at all")
	eq(T.chargeInfo(0, 0), nil, "a zero attribute on a type without charges")
	eq(T.chargeInfo(3, 0).n, 3, "charges of a type without a default")
	local wand = newItem(27749)
	wand.attrs[ITEM_ATTRIBUTE_CHARGES] = 13000
	local tip = T.build(wand, {})
	eq(tip.charges and tip.charges.n, 13000, "the built tooltip carries the charges")
	eq(tip.charges and tip.charges.max, 14400, "and the full charges")
	eq(T.build(newItem(27749), {}).charges.unlimited, true, "no charges attribute: unlimited")
	eq(T.build(newItem(2160, 5), {}).charges, nil, "a stackable has no charges line")
	eq(T.build(newItem(2496), {}).charges, nil, "a plain helmet has none")
end

-- ---------------------------------------------------------------- a unique's passive as a block of its own
do
	local en = "Hungry Blade: Each kill restores 7.1% of your maximum health. For: Warrior, Thief."
	local pt = "Hungry Blade: Cada morte restaura 7.1% da sua vida máxima. Só para: Guerreiro, Gatuno."
	local p = T.splitPassive("Every soul it cuts feeds the blade. " .. en .. " (Requires level 120.)", {pt, en}, "Hungry Blade")
	eq(p.name, "Hungry Blade", "the passive's name")
	eq(p.text, "Each kill restores 7.1% of your maximum health. For: Warrior, Thief.", "the rule without the name")
	eq(p.flavor, "Every soul it cuts feeds the blade. (Requires level 120.)", "the rest of the description")
	local q = T.splitPassive("Uma alma. " .. pt .. " (Requer nível 120.)", {pt, en}, "Hungry Blade")
	eq(q.text, "Cada morte restaura 7.1% da sua vida máxima. Só para: Guerreiro, Gatuno.", "the pt-BR text")
	eq(q.flavor, "Uma alma. (Requer nível 120.)", "the pt-BR rest")
	eq(T.splitPassive(en, {en}, "Hungry Blade").flavor, "", "a description of only the passive")
	eq(T.splitPassive("Plain text.", {en}, "Hungry Blade"), nil, "no passive text in it")
	eq(T.splitPassive(nil, {en}, "Hungry Blade"), nil, "no description")
	eq(T.splitPassive(en, {en}, ""), nil, "no name")
end

-- O475: an owned copy keeps the passive line of the day it was made; the tooltip renders the current one by the passive's name
do
	local cur = "Hungry Blade: Each kill restores 9% of your maximum health. For: Warrior, Thief."
	local oldDesc = "Every soul it cuts feeds the blade. Hungry Blade: Each kill restores 7.1% of your maximum health. For: Warrior, Thief. (Requires level 120.)"
	local fresh, found = T.refreshPassive(oldDesc, cur, "Hungry Blade")
	eq(fresh, "Every soul it cuts feeds the blade. " .. cur .. " (Requires level 120.)", "an old stored line becomes the current one")
	eq(found, true, "and it says so")
	local p = T.splitPassive(fresh, {cur}, "Hungry Blade")
	eq(p.text, "Each kill restores 9% of your maximum health. For: Warrior, Thief.", "the block of the explanation reads the current rule")
	eq(p.flavor, "Every soul it cuts feeds the blade. (Requires level 120.)", "the flavour is kept")
	local same, f2 = T.refreshPassive("Flavour. " .. cur .. " (Requires level 120.)", cur, "Hungry Blade")
	eq(f2, false, "the current line in it: nothing to do")
	eq(same, "Flavour. " .. cur .. " (Requires level 120.)", "and the text is unchanged")
	eq(T.refreshPassive("Flavour only.", cur, "Hungry Blade"), "Flavour only.", "no line of this name: unchanged")
	local twice = "Hungry Blade: a. Hungry Blade: b."
	eq(T.refreshPassive(twice, cur, "Hungry Blade"), twice, "a name twice: left alone")
	eq(T.refreshPassive("Hungry Blade: Each kill restores 7.1% of your maximum health.", cur, "Hungry Blade"), cur, "no requirement part: the line runs to the end")
	eq(T.refreshPassive("Uma alma. Hungry Blade: Cada morte restaura 7.1%. (Requer n\195\173vel 120.)", cur, "Hungry Blade"), "Uma alma. " .. cur .. " (Requer n\195\173vel 120.)", "the pt-BR requirement marker ends the line too")
	eq(T.refreshPassive(nil, cur, "Hungry Blade"), nil, "no description")
end

-- the Codex page of a unique or set piece (O467): the unique page when the Codex has one, else the set page
do
	eq(T.codexId(8209, {[8209] = {}}, nil), "unique:8209", "a unique with a page")
	eq(T.codexId(8209, {[8209] = {}}, {key = "ember"}), "unique:8209", "a set piece with a unique page: the unique page")
	eq(T.codexId(7384, {[8209] = {}}, {key = "ember"}), "set:ember", "a set piece without one: its set page")
	eq(T.codexId(7384, {[8209] = {}}, nil), nil, "no page at all")
	eq(T.codexId(7384, nil, {key = ""}), nil, "an empty set key is no page")
end

-- O479: a gem item sends its effects as data, one row per place, built from the gem tables (never from the description)
do
	local chipped = newItem(G.gemId(6, 1)) -- Chipped Diamond
	local gt = T.build(chipped)
	eq(gt.gem ~= nil, true, "a gem item has the gem field")
	eq(#gt.gem.rows, 3, "a gem: one row per place")
	eq(gt.gem.rows[1].place, "weapon") eq(gt.gem.rows[1].label, "Holy Damage") eq(gt.gem.rows[1].value, "+2%")
	eq(gt.gem.rows[1].text, "Holy Damage +2%", "the English line of the row")
	eq(gt.gem.rows[2].place, "armour") eq(gt.gem.rows[2].label, "Elemental Resistances") eq(gt.gem.rows[2].value, "+1%")
	eq(gt.gem.rows[3].place, "jewel") eq(gt.gem.rows[3].label, "Holy Resistance") eq(gt.gem.rows[3].value, "+2%")
	eq(gt.gem.combine, true, "below Perfect: it combines")
	eq(gt.gem.rows[1].label2, nil, "a single effect has no second part")
	local perfect = T.build(newItem(G.gemId(4, 5))) -- Perfect Amethyst
	eq(perfect.gem.combine, false, "a Perfect gem does not combine")
	eq(perfect.gem.rows[1].label, "Critical Chance") eq(perfect.gem.rows[1].value, "+3%")
	eq(perfect.gem.rows[1].label2, "Critical Hit") eq(perfect.gem.rows[1].value2, "+25%", "a pair effect: both numbers")
	eq(perfect.gem.rows[1].text, "Critical Chance +3%, Critical Hit +25%")
	local ruby = T.build(newItem(G.gemId(1, 4))) -- Flawless Ruby
	eq(ruby.gem.rows[2].label, "Max Health") eq(ruby.gem.rows[2].value, "+130", "a flat effect has no percent sign")
	-- every gem of every type and quality has its three rows, each part a plain string
	for ti = 1, G.TYPES do
		for tier = 1, G.TIERS do
			local g = T.build(newItem(G.gemId(ti, tier))).gem
			eq(#g.rows, 3, "gem " .. ti .. "/" .. tier .. ": three rows")
			for _, row in ipairs(g.rows) do
				eq(type(row.label), "string") eq(type(row.value), "string")
				eq(row.value:match("^%+%d+%%?$") ~= nil, true, "the number part: " .. row.value)
			end
			eq(g.combine, tier < G.TIERS)
		end
	end
	-- the size: the whole tip of a gem stays small (an extended opcode holds 8192 bytes and a tooltip answer has up to 3 tips)
	-- anything that is no gem has no gem field; a socketed gem's row has the name and the number apart
	eq(T.build(newItem(2160)).gem, nil, "a coin is no gem")
	eq(T.build(sword).gem, nil, "gear is no gem")
	local socketed = newItem(2400)
	socketed:setCustomAttribute("rarity", 4)
	G.setCount(socketed, 1)
	G.insert(socketed, G.gemId(1, 4))
	local sl = T.build(socketed).sockets.list[1]
	eq(sl.l, "Fire Damage", "a socketed gem: the effect name apart") eq(sl.v, "+9%")
	eq(sl.text, "Fire Damage +9%", "and the text as before (an old client)")
end

print(string.format("item_tooltip_test: %d checks OK", checks))
