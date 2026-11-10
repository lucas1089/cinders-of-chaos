-- Run from the server/ folder: luajit tests/item_mods_v2_test.lua (and lua5.3; CI runs both)
-- O461 (2026-11-10), equipment modifiers version 2, stage 1: the roll rules (every tier the item level allows, equal weights, a
-- modifier's own gate, the pool of each kind), the modifiers that left the pool, the new ones and what each does on the
-- character (maximum life and mana, mana regeneration, attributes, spell damage, weapon damage, life and mana leech, Execute that
-- does not stack), and quality acting on the base bonus. The upgrade of old items is tests/modifier_upgrade_test.lua.

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
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_ATTACK_SPEED = 1, 2, 3
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_ARMOR, ITEM_ATTRIBUTE_DEFENSE = 11, 12, 13
CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_ARMOR, CONST_SLOT_RIGHT, CONST_SLOT_LEFT = 1, 2, 3, 4, 5, 6
CONST_SLOT_LEGS, CONST_SLOT_FEET, CONST_SLOT_RING, CONST_SLOT_AMMO = 7, 8, 9, 10
SLOTP_HEAD, SLOTP_NECKLACE, SLOTP_BACKPACK, SLOTP_ARMOR, SLOTP_RIGHT, SLOTP_LEFT = 1, 2, 4, 8, 16, 32
SLOTP_LEGS, SLOTP_FEET, SLOTP_RING, SLOTP_AMMO = 64, 128, 256, 512
WEAPON_NONE, WEAPON_SWORD, WEAPON_SHIELD, WEAPON_DISTANCE, WEAPON_WAND, WEAPON_AMMO = 0, 1, 4, 5, 6, 7
COMBAT_PHYSICALDAMAGE, COMBAT_FIREDAMAGE, COMBAT_HEALING, COMBAT_NONE = 1, 8, 128, 0
ORIGIN_NONE, ORIGIN_CONDITION, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED, ORIGIN_WAND = 0, 1, 2, 3, 4, 5
CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, CONDITION_PARAM_SUBID = 1, 0, 2
CONDITION_PARAM_STAT_MAXHITPOINTS, CONDITION_PARAM_STAT_MAXMANAPOINTS = 10, 11
CONST_ME_BLOCKHIT, CONST_ME_NONE = 9, 0
RETURNVALUE_NOERROR = 0
SKILL_LEVEL = 8
CONTAINER_POSITION = 0xFFFF
Chaos = {}

local TYPES = {
	[2400] = {name = "magic sword", weaponType = WEAPON_SWORD, attack = 48, slot = 48},
	[2200] = {name = "wand of vortex", weaponType = WEAPON_WAND, attack = 0, slot = 48},
	[2456] = {name = "bow", weaponType = WEAPON_DISTANCE, attack = 0, slot = 48},
	[2466] = {name = "golden armor", armor = 14, slot = SLOTP_ARMOR},
	[2195] = {name = "boots of haste", armor = 1, slot = SLOTP_FEET},
	[2171] = {name = "platinum amulet", armor = 2, slot = SLOTP_NECKLACE},
	[2471] = {name = "golden helmet", armor = 12, slot = SLOTP_HEAD},
	[2495] = {name = "plate legs", armor = 8, slot = SLOTP_LEGS},
	[2514] = {name = "mastermind shield", weaponType = WEAPON_SHIELD, defense = 37, slot = 48},
	[2210] = {name = "gloves of the north", armor = 1, slot = 1024}
}
function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getId = function() return id end,
		getName = function() return t.name or "" end,
		isContainer = function() return false end,
		isStackable = function() return false end,
		getWeaponType = function() return t.weaponType or 0 end,
		getSlotPosition = function() return t.slot or 0 end,
		getArmor = function() return t.armor or 0 end,
		getAttack = function() return t.attack or 0 end,
		getDefense = function() return t.defense or 0 end,
		getHitChance = function() return 0 end,
		getElementDamage = function() return 0 end,
		getAttackSpeed = function() return 0 end,
		getAbilities = function() return {} end
	}
end

local Item = {}
Item.__index = Item
local function newItem(id)
	return setmetatable({id = id, count = 1, attrs = {}, custom = {}}, Item)
end
function Item:getId() return self.id end
function Item:getType() return ItemType(self.id) end
function Item:getCount() return self.count end
function Item:getName() return ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:getAttribute(k) return self.attrs[k] or (k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil) end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:removeAttribute(k) self.attrs[k] = nil end
function Item:getActionId() return 0 end
function Item:sendUpdate() end

local events, callbacks, timers = {}, {}, {}
local function registry(kind)
	return function(name)
		local obj = {name = name, kind = kind}
		obj.register = function(self) events[name] = self return true end
		obj.type = function() end
		return obj
	end
end
CreatureEvent = registry("creature")
GlobalEvent = registry("global")
EventCallback = setmetatable({}, {
	__newindex = function(self, k, v) rawset(self, "_pending", {k, v}) end,
	__index = function(self, k)
		if k == "register" then
			return function(this)
				local p = rawget(this, "_pending")
				callbacks[p[1]] = callbacks[p[1]] or {}
				table.insert(callbacks[p[1]], p[2])
				rawset(this, "_pending", nil)
			end
		end
	end
})
function addEvent(fn, ms, ...) timers[#timers + 1] = {fn = fn, ms = ms, args = {...}} end
local function runCheckCycle()
	timers = {}
	events.ChaosItemModsStartup.onStartup()
	local steps = 0
	while steps < 12 do
		local t
		for i, timer in ipairs(timers) do
			if timer.ms == 250 then t = table.remove(timers, i) break end
		end
		if not t then break end
		steps = steps + 1
		t.fn((table.unpack or unpack)(t.args))
	end
end
function doTargetCombatHealth() end

-- creatures: a player with a health, a mana and a vocation, and a bag of conditions
local Creature = {}
Creature.__index = Creature
local nextId = 1
local function newCreature(kind, t)
	t = t or {}
	nextId = nextId + 1
	return setmetatable({cid = 0x10000000 + nextId, kind = kind, slots = {}, speed = 0, baseSpeed = 400, health = t.health or 1000,
		maxHealth = t.maxHealth or 100000, mana = t.mana or 0, maxMana = t.maxMana or 100000, registered = {}, conds = {}, condCalls = 0,
		tier = "normal"}, Creature)
end
function Creature:getId() return self.cid end
function Creature:isPlayer() return self.kind == "player" end
function Creature:isMonster() return self.kind == "monster" end
function Creature:getMaster() return nil end
function Creature:getSlotItem(slot) return self.slots[slot] end
function Creature:getBaseSpeed() return self.baseSpeed end
function Creature:changeSpeed(d) self.speed = self.speed + d end
function Creature:getHealth() return self.health end
function Creature:getMaxHealth() return self.maxHealth end
function Creature:getMana() return self.mana end
function Creature:getMaxMana() return self.maxMana end
function Creature:addHealth(a, b) if type(a) == "string" then self.health = math.min(self.maxHealth, self.health + b) end end
function Creature:addMana(v) self.mana = math.min(self.maxMana, self.mana + v) end
function Creature:registerEvent(name) self.registered[name] = true end
function Creature:getPosition() return {x = 100, y = 100, z = 7, sendMagicEffect = function() end} end
function Creature:getType() return {isBoss = function() return false end, getElementList = function() return {} end} end
function Creature:getName() return "orc" end
function Creature:getVocation()
	return {getManaGainAmount = function() return 5 end, getManaGainTicks = function() return 3000 end}
end
function Creature:removeCondition(kind, id, sub) self.conds[sub] = nil end
function Creature:addCondition(c) self.condCalls = self.condCalls + 1; self.conds[c.params[CONDITION_PARAM_SUBID]] = c end
function Condition(kind)
	local c = {kind = kind, params = {}}
	function c:setTicks() end
	function c:setParameter(k, v) self.params[k] = v end
	return c
end
function ChaosTierOf(c) return c.tier end
local online = {}
Game = {getPlayers = function() return online end, createItem = function(id) return newItem(id) end}

dofile("data/scripts/chaos/item_mods.lua")
local M, C = ChaosItemMods, ChaosCrafting
local realRandom = math.random

-- ---------------------------------------------------------------- the pool of each kind
local function candidateKeys(item, rarity, level)
	local set, n, w = {}, 0, 0
	for _, row in ipairs(C.candidates(item, rarity or 5, nil, {level = level or 150})) do
		set[row.entry.chaosKey or row.entry.key] = true
		n, w = n + 1, w + row.weight
	end
	return set, n, w
end
local sword, wand, bow = newItem(2400), newItem(2200), newItem(2456)
local armor, helmet, boots, legs = newItem(2466), newItem(2471), newItem(2195), newItem(2495)
local amulet, shield, other = newItem(2171), newItem(2514), newItem(2210)

local ks = candidateKeys(sword)
for _, key in ipairs({"goldfind", "itemfind", "manacost", "rarity_miningSkill", "rarity_woodcuttingSkill", "rarity_herbalistSkill",
		"rarity_armorsmithSkill", "rarity_weaponsmithSkill", "rarity_jewelsmithSkill", "rarity_lifeLeechChance", "rarity_manaLeechChance"}) do
	for name, item in pairs({sword = sword, helmet = helmet, amulet = amulet, armor = armor, other = other, boots = boots}) do
		eq(candidateKeys(item)[key], nil, key .. " never rolls on " .. name)
	end
end
ok(candidateKeys(amulet)["rarity_fishingSkill"] and candidateKeys(amulet)["rarity_craftingSkill"], "fishing and crafting stay in the pool")
ok(M.byKey.goldfind and M.byKey.itemfind and M.byKey.manacost, "the keys stay valid for uniques, sets, veiled modifiers, charms")
eq(M.totals({}, {goldfind = 20}).goldfind, 20, "and still count when a source adds them")
-- the new modifiers by kind
ok(ks.weapondamage and not ks.spelldamage, "a sword rolls Weapon Damage, not Spell Damage")
local ws = candidateKeys(wand)
ok(ws.spelldamage and not ws.weapondamage, "a wand rolls Spell Damage, not Weapon Damage")
local bs = candidateKeys(bow)
ok(not bs.spelldamage and not bs.weapondamage, "a bow (an attack of 0, no spell) rolls neither")
ok(ks.lifeleechw and ks.manaleechw and not ks.lifeleech and not ks.manaleech, "the weapon's leech is the weapon's own")
ok(ks.rarity_criticalHitChance and ks.rarity_criticalHitAmount, "critical chance and damage on a weapon")
ok(not candidateKeys(armor).rarity_criticalHitChance, "not on armor")
local as = candidateKeys(armor)
ok(as.maxlife and as.maxmana and as.regen and as.strength and as.dexterity and as.intelligence, "armor: life, mana, regen, attributes")
ok(not as.attackspeed and not as.lifeleech and not as.manaregen, "armor: no attack speed, leech or mana regeneration")
local hs = candidateKeys(helmet)
ok(hs.lifeleech and hs.manaleech and hs.maxmana and hs.manaregen and hs.rarityfind and hs.lifeonkill, "helmet")
ok(not hs.regen and not hs.experience, "a helmet no longer rolls Health Regeneration or Experience")
local js = candidateKeys(amulet)
ok(js.experience and js.rarity_criticalHitChance and js.maxlife and js.lifeleech, "jewels: experience, critical, maximum life, leech")
ok(not js.gearspeed and not js.lifeonhit, "jewels: no worn attack speed, no health on hit")
local bts = candidateKeys(boots)
ok(bts.movespeed and bts.rarityfind and bts.maxlife and not bts.gearspeed, "boots")
local os_ = candidateKeys(other)
ok(os_.gearspeed and os_.rarity_criticalHitChance and os_.lifeleech and os_.cdr, "the badge and the like")
ok(candidateKeys(shield).regen and candidateKeys(legs).regen, "regen stays on shields and legs")
-- the weapon's mana leech does not roll below T4 (item level 50)
eq(candidateKeys(sword, 5, 49).manaleechw, nil, "item level 49: no weapon mana leech")
eq(candidateKeys(sword, 5, 50).manaleechw, true, "item level 50: it may")
eq(candidateKeys(sword, 5, 50).lifeleechw, true)

-- the pool per kind: modifiers, total weight, the share of the best-weighted one (printed for the report)
if os.getenv("POOL_PRINT") then
	for _, k in ipairs({{"weapon", sword}, {"weapon (wand)", wand}, {"shield", shield}, {"helmet", helmet}, {"armor", armor},
			{"legs", legs}, {"boots", boots}, {"jewel", amulet}, {"other", other}}) do
		local set, n, w = candidateKeys(k[2], 4, 150)
		local top, topKey = 0, ""
		for _, row in ipairs(C.candidates(k[2], 4, nil, {level = 150})) do
			if row.weight > top then top, topKey = row.weight, row.entry.chaosKey or row.entry.key end
		end
		print(string.format("%s\t%d\t%d\t%s\t%d\t%.1f%%", k[1], n, w, topKey, top, 100 * top / w))
	end
end

-- ---------------------------------------------------------------- tiers: every tier the item level allows, equally likely
local function lcg(seed)
	local s = seed
	return function(a, b)
		s = (s * 1103515245 + 12345) % 2147483648
		return a + s % (b - a + 1)
	end
end
local seen, gateOk = {}, true
for seed = 1, 120 do
	local it = newItem(2400)
	local added = C.forge(it, 10, 150, lcg(seed * 31))
	for _, m in ipairs(added) do
		seen[m.tier] = (seen[m.tier] or 0) + 1
		if m.affix.minTier and m.tier < m.affix.minTier then
			gateOk = false
		end
	end
end
for t = 1, 8 do
	ok((seen[t] or 0) > 0, "T" .. t .. " rolls on an item of level 150")
end
ok(gateOk, "the gate of a modifier holds")
local low = newItem(2400)
for _, m in ipairs(C.forge(low, 5, 20, lcg(5))) do
	ok(m.tier <= 2, "item level 20: T1 and T2 only")
end
-- the top tier from a boss of monster level 1000 (item level 133): T8 can roll at 130
local bossLevel = M.sourceLevel({monsterLevel = 1000, tier = "boss"})
eq(bossLevel, 133, "a boss of level 1000")
eq(M.maxTierFor(bossLevel), 8, "rolls T8")
eq(M.maxTierFor(M.sourceLevel({monsterLevel = 1000})), 7, "a normal monster of level 1000 (item level 123): T7")

-- ---------------------------------------------------------------- the value is stored as rolled: quality never multiplies it
local q = newItem(2400)
q:setCustomAttribute(M.QUALITY, 20)
local m = C.writeAffix(q, C.affixOf("chaos_mod_attackspeed"), 3, 12)
eq(m.value, 12, "returned as rolled"); eq(q:getCustomAttribute("chaos_mod_attackspeed"), 12, "stored as rolled")
eq(q:getCustomAttribute("cv_chaos_mod_attackspeed"), nil, "no raw copy")
eq(q:getCustomAttribute("chaos_modv"), 2, "the version mark")
local ct = C.writeAffix(q, C.affixOf("rarity_criticalHitAmount"), 5, 27)
eq(q:getCustomAttribute("rarity_criticalHitAmount"), 27, "critical damage alone: the engine amount attribute")
eq(q:getCustomAttribute("rarity_criticalHitChance"), nil, "and no chance with it")
local cc = C.writeAffix(q, C.affixOf("rarity_criticalHitChance"), 5, 6)
eq(q:getCustomAttribute("rarity_criticalHitChance"), 6, "critical chance alone: the engine chance attribute")
eq(C.modText(cc), "Critical Strike Chance +6%"); eq(C.modText(ct), "Critical Strike Damage +27%")
eq(M.text("lifeleech", 4), "Life Leech +0.4%", "tenths of a percent")
eq(M.text("lifeleechw", 45), "Life Leech with Weapon +4.5%"); eq(M.text("manaleechw", 26), "Mana Leech with Weapon +2.6%")

-- ---------------------------------------------------------------- the base bonus carries the quality
local divine = newItem(2400)
C.forge(divine, 10, 100, function(a, b) return a end)
local atk = divine:getAttribute(ITEM_ATTRIBUTE_ATTACK)
eq(atk, 48 + C.baseBonusOf(10, 100), "a Divine sword at item level 100: 48 + 13")
C.setQuality(divine, 30)
eq(divine:getAttribute(ITEM_ATTRIBUTE_ATTACK), 48 + 17, "quality 30 multiplies the 13: 17")
C.setQuality(divine, 10)
eq(divine:getAttribute(ITEM_ATTRIBUTE_ATTACK), 48 + 14, "quality 10: 13 x 1.1 = 14.3: 14")
C.setQuality(divine, 0)
eq(divine:getAttribute(ITEM_ATTRIBUTE_ATTACK), atk, "and back")
local armed = newItem(2466)
armed:setCustomAttribute(M.QUALITY, 30)
C.forge(armed, 10, 100, function(a, b) return a end)
eq(armed:getAttribute(ITEM_ATTRIBUTE_ARMOR), 14 + 17, "a new copy rolls with the quality: the armour carries it")

-- ---------------------------------------------------------------- Weapon Damage: the weapon's own attack
local wd = newItem(2400)
C.forge(wd, 4, 50, function(a, b) return a end)
local plain = wd:getAttribute(ITEM_ATTRIBUTE_ATTACK)
for _, mod in ipairs(C.readMods(wd)) do C.removeMod(wd, mod, true) end
eq(wd:getAttribute(ITEM_ATTRIBUTE_ATTACK), plain)
M.set(wd, "weapondamage", 25, 4)
eq(wd:getAttribute(ITEM_ATTRIBUTE_ATTACK), math.floor(plain * 125 / 100), "25% more attack: " .. plain .. " -> " .. wd:getAttribute(ITEM_ATTRIBUTE_ATTACK))
eq(wd:getCustomAttribute(M.WEAPON_BASE), plain, "the attack before is kept")
M.set(wd, "weapondamage", 40, 5)
eq(wd:getAttribute(ITEM_ATTRIBUTE_ATTACK), math.floor(plain * 140 / 100), "a new value works from the same base")
C.setQuality(wd, 20)
ok(wd:getAttribute(ITEM_ATTRIBUTE_ATTACK) >= math.floor(plain * 140 / 100), "quality keeps the modifier on top of the new base")
C.setQuality(wd, 0)
eq(wd:getAttribute(ITEM_ATTRIBUTE_ATTACK), math.floor(plain * 140 / 100), "and takes only its own share back")
C.applyBaseBonus(wd, 5, 80) -- a Crown Orb: the base bonus is written again over the attack
local base2 = wd:getCustomAttribute(M.WEAPON_BASE)
eq(base2, 48 + C.baseBonusOf(5, 80), "the new attack is the base of the modifier")
eq(wd:getAttribute(ITEM_ATTRIBUTE_ATTACK), math.floor(base2 * 140 / 100))
M.remove(wd, "weapondamage")
eq(wd:getAttribute(ITEM_ATTRIBUTE_ATTACK), base2, "removed: the attack without it")
eq(wd:getCustomAttribute(M.WEAPON_BASE), nil)
-- a small attack still gains a point
local tiny = newItem(2400)
tiny:setAttribute(ITEM_ATTRIBUTE_ATTACK, 3)
M.set(tiny, "weapondamage", 13, 1)
eq(tiny:getAttribute(ITEM_ATTRIBUTE_ATTACK), 4, "at least one more than without")

-- ---------------------------------------------------------------- Execute does not stack, the caps are gone
local ex1, ex2 = newItem(2400), newItem(2400)
M.set(ex1, "execute", 10, 8); M.set(ex2, "execute", 10, 8)
eq(M.totals({ex1, ex2}).execute, 10, "two pieces: the highest counts, not 20")
eq(M.totals({ex1}, {execute = 6}).execute, 10, "a set bonus under it adds nothing")
eq(M.totals({}, {execute = 6, bleedchance = 0}).execute, 6, "a source alone")
M.set(ex1, "attackspeed", 27, 8); M.set(ex2, "attackspeed", 27, 8)
eq(M.totals({ex1, ex2}).attackspeed, 54, "no cap of the module: 27 + 27")
M.set(ex1, "bleedchance", 55, 8); M.set(ex2, "bleedchance", 55, 8)
eq(M.totals({ex1, ex2}).bleedchance, 110, "the chance is not capped here (the roll clamps at 100)")
eq(M.totals({}, {dodge = 99}).dodge, 10, "stage 2 rows keep their caps")

-- ---------------------------------------------------------------- the leech maths
local st = {}
eq(M.leechGain(st, 1000, 20), 20, "2% of 1000")
eq(M.leechGain(st, 100, 4), 0, "0.4% of 100: nothing yet") eq(st.frac, 0.4 + 0, "the part is carried")
local acc = 0
local st2 = {}
for _ = 1, 10 do acc = acc + M.leechGain(st2, 100, 4) end
eq(acc, 4, "ten hits of 100 at 0.4%: 4 points in all, none lost to rounding")
local lim = {}
eq(M.leechLimit(lim, 0, 1000, 150), 150, "under 20% of 1000 per second")
eq(M.leechLimit(lim, 400, 1000, 100), 50, "the same second: only the 50 that are left of 200")
eq(M.leechLimit(lim, 600, 1000, 100), 0, "nothing more in that second")
eq(M.leechLimit(lim, 1000, 1000, 100), 100, "a new second")
eq(M.config.leech.maxPct, 20)

-- ---------------------------------------------------------------- mana regeneration maths
local a1, f1 = M.manaRegenAmount(5, 3000, 40, 3000, 0)
eq(a1, 2, "5 mana every 3 s: 40% more is 2 per 3 s tick")
local a2, f2 = M.manaRegenAmount(5, 4000, 10, 3000, 0)
eq(a2, 0, "5 per 4 s, 10% more over 3 s: 0.375"); ok(math.abs(f2 - 0.375) < 1e-9, "the part is carried: " .. f2)
local total, fr = 0, 0
for _ = 1, 8 do local a; a, fr = M.manaRegenAmount(5, 4000, 10, 3000, fr); total = total + a end
eq(total, 3, "8 ticks: 3 whole points")

-- ---------------------------------------------------------------- on the character
local player = newCreature("player", {health = 500, maxHealth = 100000})
online[1] = player
events.ChaosItemModsLogin.onLogin(player)
local move = callbacks.onItemMoved[1]
local function equip(item, slot)
	player.slots[slot] = item
	move(player, item, 1, {x = 0xFFFF, y = 64, z = 0}, {x = 0xFFFF, y = slot, z = 0})
end
local function unequip(slot)
	local item = player.slots[slot]
	player.slots[slot] = nil
	move(player, item, 1, {x = 0xFFFF, y = slot, z = 0}, {x = 0xFFFF, y = 64, z = 0})
end

-- maximum life and mana: one flat condition each (sub ids 7222 / 7223), replaced when the number changes
local hat = newItem(2471)
M.set(hat, "maxlife", 100, 5); M.set(hat, "maxmana", 80, 4)
local calls0 = player.condCalls
equip(hat, CONST_SLOT_HEAD)
ok(player.conds[7222], "a maximum life condition")
eq(player.conds[7222].params[CONDITION_PARAM_STAT_MAXHITPOINTS], 100, "+100 maximum health")
eq(player.conds[7223].params[CONDITION_PARAM_STAT_MAXMANAPOINTS], 80, "+80 maximum mana")
local chest = newItem(2466)
M.set(chest, "maxlife", 50, 3)
equip(chest, CONST_SLOT_ARMOR)
eq(player.conds[7222].params[CONDITION_PARAM_STAT_MAXHITPOINTS], 150, "two pieces add")
local calls1 = player.condCalls
M.refresh(player, true)
eq(player.condCalls, calls1, "the same totals: no new condition")
unequip(CONST_SLOT_HEAD)
eq(player.conds[7222].params[CONDITION_PARAM_STAT_MAXHITPOINTS], 50)
eq(player.conds[7223], nil, "the mana condition goes with the helmet")
unequip(CONST_SLOT_ARMOR)
eq(player.conds[7222], nil, "and the life one when nothing is worn")
equip(hat, CONST_SLOT_HEAD)
events.ChaosItemModsLogout.onLogout(player)
events.ChaosItemModsLogin.onLogin(player) -- a fresh login: the refresh puts it on again
ok(player.conds[7222], "relog: refreshed from the items")
unequip(CONST_SLOT_HEAD)

-- attributes and spell damage: written to the tree's table, which the damage events read
ChaosPassiveCache = {[player:getId()] = {strength = 3}}
local legsItem = newItem(2495)
M.set(legsItem, "strength", 12, 5); M.set(legsItem, "dexterity", 4, 2); M.set(legsItem, "intelligence", 9, 4)
equip(legsItem, CONST_SLOT_LEGS)
local tb = ChaosPassiveCache[player:getId()]
eq(tb.gearStrength, 12, "Strength handed to the tree's table"); eq(tb.gearDexterity, 4); eq(tb.gearIntelligence, 9)
eq(tb.strength, 3, "the tree's own points are not touched")
local rod = newItem(2200)
M.set(rod, "spelldamage", 30, 5)
equip(rod, CONST_SLOT_LEFT)
eq(tb.gearSpell, 30, "Spell Damage handed on")
unequip(CONST_SLOT_LEFT)
eq(tb.gearSpell, 0, "and taken back")
unequip(CONST_SLOT_LEGS)
eq(tb.gearStrength, 0)
ChaosPassiveCache = nil

-- mana regeneration: in the 3 s check, a percent more of the vocation's own (5 per 3 s here)
local circlet = newItem(2471)
M.set(circlet, "manaregen", 60, 6)
equip(circlet, CONST_SLOT_HEAD)
player.mana = 0
runCheckCycle()
eq(player.mana, 3, "60% of 5 = 3 mana in one 3 s check")
runCheckCycle()
eq(player.mana, 6, "again")
player.mana = player.maxMana
runCheckCycle()
eq(player.mana, player.maxMana, "full: nothing")
unequip(CONST_SLOT_HEAD)

-- life and mana leech: in the hit event of the target, a share of the damage dealt, no chance
local monster = newCreature("monster", {health = 1000000})
local target = callbacks.onTargetCombat[1]
local dealt = events.ChaosItemModsDealt
local blade = newItem(2400)
M.set(blade, "lifeleechw", 20, 5); M.set(blade, "manaleechw", 30, 5)
equip(blade, CONST_SLOT_LEFT)
eq(target(player, monster), RETURNVALUE_NOERROR)
eq(monster.registered.ChaosItemModsDealt, true, "a leech modifier registers the hit event")
math.random = function() return 100 end -- no chance involved: the roll would miss every time
player.health, player.mana = 500, 0
dealt.onHealthChange(monster, player, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(player.health, 520, "2% of 1000 healed, no roll")
eq(player.mana, 30, "3% of 1000 as mana")
player.health, player.mana = 500, 0
dealt.onHealthChange(monster, player, 1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(player.health, 500, "the weapon's leech does not count a spell"); eq(player.mana, 0)
dealt.onHealthChange(monster, player, 1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_WAND)
eq(player.health, 520, "a wand hit is a weapon hit")
dealt.onHealthChange(monster, player, 1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_CONDITION)
eq(player.health, 520, "damage over time does not leech")
dealt.onHealthChange(monster, player, 500, COMBAT_PHYSICALDAMAGE, 500, COMBAT_FIREDAMAGE, ORIGIN_MELEE)
eq(player.health, 540, "both parts of a hit count: 2% of 1000")
math.random = realRandom
unequip(CONST_SLOT_LEFT)
-- the global one counts spells too; both add on a weapon hit
local ring = newItem(2171)
M.set(ring, "lifeleech", 10, 5)
equip(ring, CONST_SLOT_NECKLACE)
equip(blade, CONST_SLOT_LEFT)
player.health = 500
dealt.onHealthChange(monster, player, 1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(player.health, 510, "the necklace's 1% on a spell")
player.health = 500
dealt.onHealthChange(monster, player, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(player.health, 530, "weapon 2% + necklace 1% on a weapon hit")
-- the recovery limit: 20% of the maximum per second in all, per player (a fake clock keeps the second still)
local fakeNow = 5000
os.mtime = function() return fakeNow end
player.maxHealth, player.health = 1000, 100
dealt.onHealthChange(monster, player, 100000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE) -- 3% of 100000 = 3000 wanted
eq(player.health, 100 + 200, "at most 20% of the maximum (200 of 1000) in one second")
dealt.onHealthChange(monster, player, 100000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(player.health, 300, "nothing more in the same second")
fakeNow = fakeNow + 1000
dealt.onHealthChange(monster, player, 100000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(player.health, 500, "a new second: 200 more")
player.mana, player.maxMana = 0, 1000
M.refresh(player, true)
-- mana leech has its own budget of 20% of the maximum mana
equip(newItem(2471), CONST_SLOT_HEAD)
player.slots[CONST_SLOT_HEAD] = nil
local mage = newItem(2400)
M.set(mage, "manaleechw", 30, 5)
unequip(CONST_SLOT_LEFT)
equip(mage, CONST_SLOT_LEFT)
fakeNow = fakeNow + 1000
dealt.onHealthChange(monster, player, 100000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(player.mana, 200, "mana leech: 20% of the maximum mana (3000 wanted)")
os.mtime = nil
unequip(CONST_SLOT_LEFT); unequip(CONST_SLOT_NECKLACE)
player.maxHealth = 100000

events.ChaosItemModsLogout.onLogout(player)
print(string.format("item_mods_v2_test: %d checks OK", checks))
