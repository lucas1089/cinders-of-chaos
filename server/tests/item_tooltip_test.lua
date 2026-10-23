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
	[2466] = {name = "golden armor", armor = 14, slot = 8 + 48, description = "It shines.",
		abilities = {skills = {0, 0, 0, 0, 0, 0}, stats = {0, 0, 0, 0}, absorbPercent = {[4] = 5}, speed = 0}},
	[2514] = {name = "mastermind shield", weaponType = WEAPON_SHIELD, defense = 37, slot = 48},
	[2496] = {name = "horned helmet", armor = 11, slot = 1}, -- Hornsworn Helm (a unique of the Embers set)
	[3975] = {name = "dragon shield", weaponType = WEAPON_SHIELD, defense = 31, slot = 48}, -- Emberwarden
	[2206] = {name = "strange ring", slot = 256},
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
sword:setCustomAttribute("rarity_criticalHitChance", 2)
sword:setCustomAttribute("rarity_criticalHitAmount", 1)
sword:setCustomAttribute("rarity_elementfire", 7)
sword:setCustomAttribute("chaos_mod_lifeonkill", 15)
sword:setAttribute(ITEM_ATTRIBUTE_ATTACK, 50) -- the rarity roll raised the attack
G.setCount(sword, 2)
G.insert(sword, G.gemId(1, 4)) -- Flawless Ruby: Fire Damage +9% in a weapon
local tip = T.build(sword, {attrs = {[1] = 4, [2] = 37, [5] = 2, [6] = 1873000000123, [7] = 3054}})
eq(tip.key, "1873000000123:3054", "cache key from the client attributes")
eq(tip.name, "magic sword") eq(tip.id, 3400, "client id") eq(tip.kind, "weapon") eq(tip.slot, "Weapon")
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
eq(tip.sides.p, 3) eq(tip.sides.s, 2) eq(tip.sides.max, 2, "Rare: two of each (an old item may carry more)")
eq(tip.cmp[1], 6) eq(tip.cmp[2], 5)
eq(tip.base[1].k, "attack") eq(tip.base[1].v, 50, "attack from the item, not the type")
eq(tip.base[2].k, "defense") eq(tip.base[2].v, 35)
eq(#tip.mods, 5, "absorb, skill, critical pair, Chaos modifier, element")
local byKey = {}
for _, m in ipairs(tip.mods) do
	byKey[m.k] = m
end
eq(byKey.rarity_physicalAbsorb.t, "Physical +2%") eq(byKey.rarity_physicalAbsorb.lo, 1) eq(byKey.rarity_physicalAbsorb.hi, 2)
eq(byKey.rarity_physicalAbsorb.tr, 2, "tier from the value (an old item)") eq(byKey.rarity_physicalAbsorb.sd, "s")
eq(byKey.rarity_elementfire.lo, 5, "the range of its tier") eq(byKey.rarity_elementfire.hi, 9)
eq(byKey.rarity_elementfire.tr, 3) eq(byKey.rarity_elementfire.sd, "p")
eq(tip.mods[1].sd, "p", "prefixes first") eq(tip.mods[#tip.mods].sd, "s", "suffixes last")
eq(byKey.rarity_criticalHitChance.t, "Critical Chance +2%, Critical Hit +1%")
eq(byKey.rarity_criticalHitChance.v2, 1)
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
eq(stats.attack.v, 50) eq(stats.rarity_criticalHitAmount.v, 1, "pair split into two numbers")
eq(stats.rarity_elementfire.l, "Fire Damage") eq(stats.gem_dmg_fire.v, 9, "gem effect in the compare numbers")
eq(stats.chaos_mod_lifeonkill.fmt, nil, "flat Chaos modifier") eq(stats.rarity_swordSkill.v, 1)
eq(tip.req.level, 80) eq(tip.req.voc, "knights") eq(tip.weight, 45)
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
eq(tip.slot, "Two-handed weapon")
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
eq(y.v, 1.0, "Shadowfist with dexterity: the floor") eq(y.l, "Your Attack Interval (capped)")
y = yours(T.build(fast, {wielder = {voc = 2000, dex = 20}}))
eq(y.v, 1.5, "weapon + dexterity: at most -25%") eq(y.l, "Your Attack Interval (capped)")
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
local twoH = dpsOf(T.build(newItem(2431), {wielder = {voc = 2000, dex = 0, level = 100, melee = 70}}))
eq(twoH ~= nil, true, "a two-handed axe has one")
ChaosDisplayScale = {factor = function() return 10 end}
eq(dpsOf(T.build(sword, {wielder = {voc = 2000, dex = 0, level = 100, melee = 70}})).v, row.v * 10, "x the display scale of the level")
ChaosDisplayScale = nil

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

print(string.format("item_tooltip_test: %d checks OK", checks))
