-- Run from the server/ folder: luajit tests/item_mods_test.lua (and lua5.3; CI runs both)
-- The Chaos item modifiers: data/lib/chaos_item_mods.lua (catalogue, roll ranges per rarity tier and item level, caps,
-- description text, drop rolls) and data/scripts/chaos/item_mods.lua against a mocked engine (totals applied when an
-- item is put on and removed when it is taken off: speed, experience, dodge, reflect, thorns, damage from monsters,
-- elites and bosses, healing, life and mana on kill, gold find; item find for the loot layer).

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- engine mock
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_ATTACK_SPEED = 1, 2, 3
CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_ARMOR, CONST_SLOT_RIGHT, CONST_SLOT_LEFT = 1, 2, 3, 4, 5, 6
CONST_SLOT_LEGS, CONST_SLOT_FEET, CONST_SLOT_RING, CONST_SLOT_AMMO = 7, 8, 9, 10
SLOTP_HEAD, SLOTP_NECKLACE, SLOTP_BACKPACK, SLOTP_ARMOR, SLOTP_RIGHT, SLOTP_LEFT = 1, 2, 4, 8, 16, 32
SLOTP_LEGS, SLOTP_FEET, SLOTP_RING, SLOTP_AMMO = 64, 128, 256, 512
WEAPON_NONE, WEAPON_SWORD, WEAPON_SHIELD, WEAPON_AMMO = 0, 1, 4, 7
COMBAT_PHYSICALDAMAGE, COMBAT_FIREDAMAGE, COMBAT_HEALING, COMBAT_NONE = 1, 8, 128, 0
ORIGIN_NONE, ORIGIN_SPELL, ORIGIN_MELEE = 0, 2, 3
CONST_ME_BLOCKHIT, CONST_ME_NONE = 9, 0
RETURNVALUE_NOERROR = 0
SKILL_LEVEL = 8
CONTAINER_POSITION = 0xFFFF
Chaos = {} -- item_mods.lua skips chaos_constants.lua

local TYPES = {
	[2400] = {name = "magic sword", weaponType = WEAPON_SWORD, attack = 48, slot = 48},
	[7390] = {name = "the justice seeker", weaponType = WEAPON_SWORD, attack = 47, slot = 48, attackSpeed = 1500},
	[2466] = {name = "golden armor", armor = 14, slot = SLOTP_ARMOR},
	[2195] = {name = "boots of haste", armor = 0, slot = SLOTP_FEET},
	[2171] = {name = "platinum amulet", armor = 2, slot = SLOTP_NECKLACE},
	[2123] = {name = "ring of the sky", slot = SLOTP_RING},
	[2471] = {name = "golden helmet", armor = 12, slot = SLOTP_HEAD},
	[2514] = {name = "mastermind shield", weaponType = WEAPON_SHIELD, defense = 37, slot = 48},
	[2456] = {name = "bow", weaponType = 5, attack = 0, slot = 48},
	[36656] = {name = "pair of ember knuckles", weaponType = WEAPON_SHIELD, attack = 46, defense = 12, slot = 48},
	[2210] = {name = "gloves of the north", armor = 1, slot = 1024}, -- a worn piece that is none of the kinds (kind "other")
	[2160] = {name = "crystal coin", stackable = true}
}

function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getId = function() return id end,
		getName = function() return t.name or "" end,
		isContainer = function() return false end,
		isStackable = function() return t.stackable == true end,
		getWeaponType = function() return t.weaponType or 0 end,
		getSlotPosition = function() return t.slot or 0 end,
		getArmor = function() return t.armor or 0 end,
		getAttack = function() return t.attack or 0 end,
		getDefense = function() return t.defense or 0 end,
		getHitChance = function() return 0 end,
		getElementDamage = function() return 0 end,
		getAttackSpeed = function() return t.attackSpeed or 0 end,
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

-- revscript registries
local events = {} -- CreatureEvent name -> table
local callbacks = {} -- EventCallback name -> list of functions
local timers = {}
local function registry(kind)
	return function(name)
		local obj = {name = name, kind = kind}
		obj.register = function(self)
			events[name] = self
			return true
		end
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
function addEvent(fn, ms, ...)
	timers[#timers + 1] = {fn = fn, ms = ms, args = {...}}
end

-- the periodic equipment check: the startup timer and the 11 after it (one group of the players online each, every group
-- once in 3 s). Returns the number of groups run and the time they span.
local function runCheckCycle()
	timers = {}
	events.ChaosItemModsStartup.onStartup()
	local steps, elapsed = 0, 0
	while steps < 12 do
		local t
		for i, timer in ipairs(timers) do
			if timer.ms == 250 then
				t = table.remove(timers, i)
				break
			end
		end
		if not t then
			break
		end
		steps, elapsed = steps + 1, elapsed + t.ms
		t.fn((table.unpack or unpack)(t.args))
	end
	return steps, elapsed
end

local hits = {} -- doTargetCombatHealth calls
function doTargetCombatHealth(cid, target, ctype, min, max, effect)
	hits[#hits + 1] = {from = cid, to = target, type = ctype, min = min}
end

-- creatures
local Creature = {}
Creature.__index = Creature
local nextId = 1
local function newCreature(kind, t)
	t = t or {}
	nextId = nextId + 1
	return setmetatable({cid = 0x10000000 + nextId, kind = kind, slots = {}, speed = 0, baseSpeed = t.baseSpeed or 400,
		health = t.health or 1000, mana = 0, registered = {}, tier = t.tier or "normal", boss = t.boss}, Creature)
end
function Creature:getId() return self.cid end
function Creature:isPlayer() return self.kind == "player" end
function Creature:isMonster() return self.kind == "monster" end
function Creature:getMaster() return self.master end
function Creature:getSlotItem(slot) return self.slots[slot] end
function Creature:getBaseSpeed() return self.baseSpeed end
function Creature:changeSpeed(d) self.speed = self.speed + d end
function Creature:getHealth() return self.health end
function Creature:getMaxHealth() return 100000 end
function Creature:addHealth(a, b) -- this engine: (damage type, amount); a lone amount heals nothing
	if type(a) == "string" then
		self.health = self.health + b
	end
end
function Creature:addMana(v) self.mana = self.mana + v end
function Creature:registerEvent(name) self.registered[name] = true end
-- x, y, z: the item power procs send pack effects at an offset tile (ChaosPackFx, switch on since 2026-10-13)
function Creature:getPosition() return {x = 100, y = 100, z = 7, sendMagicEffect = function() end} end
function Creature:getType() return {isBoss = function() return self.boss == true end} end
function ChaosTierOf(c) return c.tier end

local online = {}
Game = {getPlayers = function() return online end}

dofile("data/scripts/chaos/item_mods.lua")
local M = ChaosItemMods
local C = ChaosCrafting

-- ---------------------------------------------------------------- catalogue
eq(#M.config.mods, 73, "seventy-three modifiers (fifteen old, fifteen new, one worn attack speed, twelve legendary powers, three energy shield, eight quiver, four Lua leech, eight of O461, seven of O464: armour, spell suppression, four resistances, all resistances)")
local sides = {prefix = 0, suffix = 0}
for _, def in ipairs(M.config.mods) do
	eq(#def.tiers, 8, def.key .. ": eight tiers")
	assert((def.cap == nil or def.cap > 0) and def.weight > 0, def.key) -- O461: most rows have no cap of their own
	assert(def.side == "prefix" or def.side == "suffix", def.key .. ": a side")
	sides[def.side] = sides[def.side] + 1
	local prevLo, prevHi = 0, 0
	for t, r in ipairs(def.tiers) do
		assert(r[1] >= 1 and r[1] <= r[2], def.key .. " tier " .. t .. " range")
		assert(r[1] >= prevLo and r[2] >= prevHi, def.key .. " ranges grow with the tier")
		prevLo, prevHi = r[1], r[2]
	end
	assert(def.cap == nil or def.tiers[8][2] <= def.cap, def.key .. ": one item never beats the cap")
	assert(next(def.kinds), def.key .. ": allowed somewhere")
end
eq(sides.prefix, 36, "fifteen prefixes, seven prefix powers, two energy shield, seven quiver prefixes, four of O461 (maximum life and mana, spell and weapon damage), one of O464 (armour)")
eq(sides.suffix, 37, "sixteen suffixes (one worn attack speed), five suffix powers, energy shield recharge, quiver attack speed, four leech, four of O461 (mana regeneration, three attributes), six of O464 (spell suppression, the four resistances, all resistances)")
-- the five tiers of before are T2 .. T6, so old items keep their meaning
local OLD = {attackspeed = {{2, 3}, {3, 5}, {4, 6}, {5, 8}, {7, 10}}, lifeonkill = {{5, 10}, {10, 20}, {20, 40}, {35, 60},
	{50, 90}}, goblinchance = {{10, 15}, {14, 20}, {18, 27}, {22, 33}, {28, 40}}, dodge = {{1, 1}, {1, 2}, {1, 2}, {2, 3},
	{2, 4}}, movespeed = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}}}
for key, old in pairs(OLD) do
	for t, r in ipairs(old) do
		-- the ranges were raised on 2026-10-18 (owner item 78); the old ones are M.legacy and still read the tier of an old item
		local n = M.legacy[key][M.config.oldTiers[t]]
		eq(n[1], r[1], key .. " old tier " .. t .. " low"); eq(n[2], r[2], key .. " old tier " .. t .. " high")
	end
end
-- item 78: every Chaos modifier and every engine type got bigger numbers (about x1.5 to x3 for the small ones, less at
-- the top where a cap or the engine sits close) and no tier got smaller
-- (O461: these pins are on the ranges of version 1, M.v1 where a row changed, today's row where it did not)
local grown, total = 0, 0
for _, def in ipairs(M.config.mods) do
	local legacy = M.legacy[def.key]
	if legacy then -- the legendary powers, the energy shield and the quiver modifiers have their own tables
		local v1 = M.v1.mods[def.key] or M.v2.mods[def.key] or def.tiers -- the ranges of the version the item had before O464
		for t = 1, 8 do
			assert(v1[t][1] >= legacy[t][1] and v1[t][2] >= legacy[t][2], def.key .. " T" .. t .. " never shrank")
		end
		local oldSum, newSum = 0, 0
		for t = 1, 8 do
			oldSum, newSum = oldSum + legacy[t][1] + legacy[t][2], newSum + v1[t][1] + v1[t][2]
		end
		total = total + 1
		if newSum >= oldSum * 1.3 then
			grown = grown + 1
		end
		assert(newSum >= oldSum * 1.15, def.key .. " grew by at least 15%: " .. oldSum .. " -> " .. newSum)
	end
end
eq(total, 30, "thirty modifiers with an old table")
assert(grown >= 26, "most grew by 30% or more: " .. grown)
local v1Engine = {absorb = M.config.engine.absorb.tiers, skill = M.config.engine.skill.tiers, profession = M.config.engine.profession.tiers,
	element = M.config.engine.element.tiers, critical = M.v1.engine.critical, leech = M.v1.engine.leech}
for name, tiers in pairs(v1Engine) do
	for t = 1, 8 do
		assert(tiers[t][2] >= M.legacyEngine[name][t][2], name .. " T" .. t .. " never shrank")
	end
	assert(tiers[8][2] >= M.legacyEngine[name][8][2] * 1.4, name .. " T8 grew by at least 40%")
end
-- O461: no module cap on the rows of stage 1; the numbers are the ladders of the owner list. The caps that stay: the stage 2 rows, the
-- rows left out of the roll pool (valid keys for uniques, sets, veiled modifiers, charms, factions and raid rewards) and the
-- unchanged ones
eq(M.byKey.attackspeed.tiers[8][2], 27, "attack speed T8 27") eq(M.byKey.movespeed.tiers[8][2], 35)
for t, v in ipairs({10, 13, 16, 20, 24, 28, 32, 35}) do
	eq(M.byKey.movespeed.tiers[t][1], v, "movement speed: one fixed number per tier") eq(M.byKey.movespeed.tiers[t][2], v)
end
eq(M.byKey.dodge.tiers[8][2], 11, "dodge T8 10-11 (O464: the layer holds the sum at 75, no module cap)")
assert(M.config.engine.leech.tiers[8][2] <= 10 and M.v1.engine.critical[8][2] <= 10, "the old critical / leech pairs topped at 10")
eq(M.config.engine.critchance.tiers[8][2], 8, "Critical Strike Chance T8 7-8 points") eq(M.config.engine.critdamage.tiers[8][2], 38)
eq(M.byKey.movespeed.cap, nil, "no cap of the module")
eq(M.byKey.dodge.cap, nil, "O464: no module cap, the player defence layer caps dodge at 75")
eq(M.byKey.experience.cap, nil)
eq(M.byKey.goldfind.cap, 40, "out of the roll pool, the key keeps its cap") eq(M.byKey.itemfind.cap, 25) eq(M.byKey.manacost.cap, 25)
for _, key in ipairs({"attackspeed", "gearspeed", "movespeed", "bleedchance", "ignitechance", "poisonchance", "chillchance",
		"shockchance", "execute", "dot", "bossdamage", "lifeonkill", "manaonkill", "lifeonhit", "manaonhit", "regen", "experience",
		"rarityfind", "cdr", "bowcrit", "bowspeed", "arrowfire", "arrowice", "arrowenergy", "arrowearth", "lifeleech", "lifeleechw",
		"manaleech", "manaleechw", "maxlife", "maxmana", "manaregen", "strength", "dexterity", "intelligence", "spelldamage",
		"weapondamage"}) do
	eq(M.byKey[key].cap, nil, key .. ": no cap of the module (O461)")
end
for _, key in ipairs({"healing", "goblinchance", "multishot", "bowdistance"}) do
	assert(M.byKey[key].cap, key .. ": unchanged, keeps its cap")
end
-- O464: the defence rows lost their module caps (the caps are the player defence layer's and the engine's)
for _, key in ipairs({"dodge", "block", "reflect", "thorns", "monsterreduction", "physpen", "elepen", "energyshield",
		"energyshieldpct", "esrecharge", "lastbreath", "frostward", "armour", "spellsuppress", "fireres", "coldres", "lightningres",
		"chaosres", "allres"}) do
	eq(M.byKey[key].cap, nil, key .. ": no cap of the module (O464)")
end
-- the roll rules: tier ranges never overlap and narrow toward the top (a row whose ladder was given as it is may touch)
local STAGE1 = {"attackspeed", "gearspeed", "bowspeed", "movespeed", "bowcrit", "bleedchance", "ignitechance", "poisonchance",
	"chillchance", "shockchance", "dot", "lifeonkill", "manaonkill", "lifeonhit", "manaonhit", "regen", "experience", "rarityfind",
	"cdr", "arrowfire", "arrowice", "arrowenergy", "arrowearth", "lifeleech", "lifeleechw", "maxlife", "maxmana", "manaregen",
	"strength", "dexterity", "intelligence", "spelldamage", "weapondamage"}
for _, key in ipairs(STAGE1) do
	local tiers = M.byKey[key].tiers
	for t = 2, 8 do
		assert(tiers[t][1] >= tiers[t - 1][1] and tiers[t][2] >= tiers[t - 1][2], key .. ": a higher tier never rolls lower")
		assert(tiers[t][1] >= tiers[t - 1][2] or key == "cdr" or key == "experience" or key == "gearspeed" or key == "bowspeed",
			key .. " T" .. t .. ": starts at or above the end of the tier before")
	end
end
for _, key in ipairs({"attackspeed", "bleedchance", "dot", "lifeonkill", "manaonkill", "lifeonhit", "manaonhit", "regen", "maxlife",
		"maxmana", "manaregen", "strength", "spelldamage", "weapondamage", "arrowfire", "lifeleechw", "armour", "spellsuppress",
		"fireres", "coldres", "lightningres", "chaosres", "allres", "thorns", "energyshield", "energyshieldpct",
		"esrecharge", "lastbreath", "reflect", "frostward", "monsterreduction"}) do
	local tiers = M.byKey[key].tiers
	for t = 2, 8 do
		assert(tiers[t][1] > tiers[t - 1][2], key .. " T" .. t .. ": above the whole tier before (no overlap)")
	end
end
-- the ladders of the owner's list
local function ladder(key)
	local out = {}
	for _, r in ipairs(M.byKey[key].tiers) do
		out[#out + 1] = r[1] .. "-" .. r[2]
	end
	return table.concat(out, " ")
end
eq(ladder("attackspeed"), "5-7 8-10 11-13 14-16 17-19 20-22 23-25 26-27")
eq(ladder("gearspeed"), "5-6 7-8 9-10 11-11 12-12 13-13 14-15 15-16")
eq(ladder("bowspeed"), ladder("gearspeed"), "bows: the ladder of the worn pieces")
eq(ladder("bleedchance"), "18-21 22-25 26-29 30-33 34-38 39-43 44-49 50-55")
eq(ladder("lifeonkill"), "4-9 12-20 25-40 50-80 90-140 150-220 230-320 330-430")
eq(ladder("manaonkill"), "2-5 6-10 12-20 25-40 45-65 70-100 105-145 150-195")
eq(ladder("lifeonhit"), "2-4 6-10 12-20 24-36 40-55 60-78 82-100 104-119")
eq(ladder("manaonhit"), "1-2 3-5 6-10 12-18 20-28 30-39 41-50 52-60", "half of the health on hit, rounded up")
eq(ladder("experience"), "1-1 1-1 1-2 1-2 2-2 2-3 2-3 3-3")
eq(ladder("cdr"), "6-8 8-10 10-12 12-14 14-15 15-16 16-18 18-20")
eq(ladder("maxlife"), "3-6 7-12 14-24 36-60 88-130 198-260 469-560 693-748")
eq(ladder("execute"), "10-10 10-10 10-10 10-10 10-10 10-10 10-10 10-10", "Execute: 10 at every tier")
-- O464: the ladders of the defence stage
for _, key in ipairs({"fireres", "coldres", "lightningres"}) do
	eq(ladder(key), "6-11 12-17 18-23 24-29 30-35 36-41 42-45 46-48", key .. ": one element, 6-11 to 46-48")
end
eq(ladder("chaosres"), "5-8 9-12 13-16 17-20 21-24 25-28 29-31 32-35", "chaos resistance")
eq(ladder("allres"), "3-4 5-6 7-8 9-10 11-12 13-14 15-15 16-16", "all elements: Fire, Cold and Lightning together")
eq(ladder("armour"), "3-5 6-9 10-14 15-20 21-27 28-35 36-44 45-52", "armour, flat")
eq(ladder("dodge"), "2-3 3-4 4-5 5-6 6-7 7-8 8-9 10-11", "dodge")
eq(ladder("spellsuppress"), "8-9 10-11 12-13 14-15 16-17 18-19 20-21 22-22", "spell suppression")
eq(ladder("block"), "8-9 10-11 12-13 14-15 15-16 16-17 17-18 18-20", "block")
eq(ladder("monsterreduction"), "1-1 2-2 3-3 4-4 5-5 6-6 7-7 8-8", "damage taken from monsters, made non-overlapping")
eq(ladder("physpen"), "3-3 4-4 5-5 6-6 7-8 9-9 10-11 11-12", "penetration, the ladder as given")
eq(ladder("elepen"), ladder("physpen"), "elemental penetration the same")
eq(ladder("esrecharge"), "24-25 26-27 28-29 30-31 32-33 34-35 36-36 37-38", "energy shield recharge")
eq(ladder("energyshield"), "12-25 26-50 51-85 86-135 136-195 196-270 271-360 361-480", "energy shield: today's ends, non-overlapping")
eq(ladder("energyshieldpct"), "2-4 5-7 8-10 11-13 14-17 18-21 22-25 26-28", "energy shield percent")
eq(M.config.engine.physabsorb.tiers[1][1] .. "-" .. M.config.engine.physabsorb.tiers[8][2], "2-8", "physical absorb 2 .. 8")
for t, r in ipairs({{2, 2}, {3, 3}, {4, 4}, {5, 5}, {5, 6}, {6, 6}, {7, 7}, {7, 8}}) do
	eq(M.config.engine.physabsorb.tiers[t][1], r[1], "physical absorb T" .. t) eq(M.config.engine.physabsorb.tiers[t][2], r[2])
end
eq(M.byKey.chaosres.weight, M.byKey.fireres.weight / 2, "chaos resistance: half the weight of one element")
eq(M.byKey.armour.kinds.jewel, nil, "armour: not on jewels") eq(M.byKey.armour.kinds.shield, true) eq(M.byKey.armour.side, "prefix")
eq(M.byKey.allres.kinds.jewel, true, "all resistances: jewel, other, shield") eq(M.byKey.allres.kinds.armor, nil)
eq(M.byKey.spellsuppress.kinds.helmet, true, "spell suppression: armor, helmet, boots, other") eq(M.byKey.spellsuppress.kinds.shield, nil)
eq(M.byKey.fireres.kinds.weapon, nil, "resistances: not on weapons") eq(M.byKey.fireres.kinds.shield, true)
eq(M.byKey.lifeleech.tiers[1][1] .. "-" .. M.byKey.lifeleech.tiers[1][2], "2-4"); eq(M.byKey.lifeleech.tiers[8][2], 12)
eq(M.byKey.lifeleechw.tiers[1][1], 20); eq(M.byKey.lifeleechw.tiers[8][2], 45)
eq(M.byKey.manaleech.tiers[8][2], 8)
eq(M.byKey.manaleechw.minTier, 4, "the weapon's mana leech does not roll below T4")
for t = 1, 8 do
	eq(M.byKey.manaleechw.tiers[t][1], 26) eq(M.byKey.manaleechw.tiers[t][2], 32)
end
-- Health Regeneration: T8 is 3.5% to 4.1% of the median health at level 1000 (17,004), T1 .. T7 the same share of the median
-- health of the level where a normal drop first reaches the tier
eq(M.byKey.regen.tiers[8][1], 595); eq(M.byKey.regen.tiers[8][2], 697)
eq(M.byKey.regen.tiers[1][1], 9); eq(M.byKey.regen.tiers[4][1], 89)
eq(M.byKey.maxmana.tiers[8][1], 704, "Maximum Mana T8: 4.9% to 5.2% of the median mana of level 1000 (14,369)") eq(M.byKey.maxmana.tiers[8][2], 747)
eq(M.byKey.bossdamage.cap, nil, "numbers kept, cap removed")
eq(M.byKey.attackspeed.side, "suffix", "speed is a suffix")
eq(M.byKey.gearspeed.kinds.jewel, nil, "worn Attack Speed: the badge and the like only (O461)") eq(M.byKey.gearspeed.kinds.other, true)
eq(M.byKey.lifeonhit.kinds.jewel, nil, "health on hit: weapons only (O461)") eq(M.byKey.manaonhit.kinds.weapon, true)
eq(M.byKey.experience.kinds.helmet, nil, "experience: jewels only (O461)") eq(M.byKey.experience.kinds.jewel, true)
eq(M.byKey.rarityfind.kinds.boots, true, "rarity find: helmet, jewel, boots") eq(M.byKey.regen.kinds.helmet, nil)
eq(M.byKey.regen.kinds.shield, true) eq(M.byKey.regen.kinds.armor, true) eq(M.byKey.regen.kinds.legs, true)
eq(M.byKey.execute.stack, "max", "Execute does not stack")
eq(M.byKey.bossdamage.side, "prefix", "damage is a prefix")
-- the engine's types have eight tiers too
for name, e in pairs(M.config.engine) do
	eq(#e.tiers, 8, name .. ": eight tiers")
end

-- ---------------------------------------------------------------- kinds
eq(M.kindOf(newItem(2400)), "weapon")
eq(M.kindOf(newItem(2514)), "shield")
eq(M.kindOf(newItem(2466)), "armor")
eq(M.kindOf(newItem(2195)), "boots")
eq(M.kindOf(newItem(2171)), "jewel")
eq(M.kindOf(newItem(2123)), "jewel")
eq(M.kindOf(newItem(2471)), "helmet")
eq(M.kindOf(newItem(2160)), nil, "coins are no equipment")
local function addableKeys(item)
	local set = {}
	for _, row in ipairs(M.addable(item)) do
		set[row.entry.key] = true
	end
	return set
end
eq(addableKeys(newItem(2195)).movespeed, true, "movement speed on boots")
eq(addableKeys(newItem(2466)).movespeed, nil, "not on armor")
eq(addableKeys(newItem(2400)).attackspeed, true, "attack speed on weapons")
eq(addableKeys(newItem(2514)).attackspeed, nil, "not on shields")
-- owner 2026-10-28, "few attack speed on items": a worn piece (ring, amulet, belt..) rolls Attack Speed too, as a player-level
-- bonus (engine patch 0078), the weapon's own modifier stays local to the weapon
eq(addableKeys(newItem(2210)).gearspeed, true, "worn attack speed on the badge and the like (kind other)")
eq(addableKeys(newItem(2123)).gearspeed, nil, "no longer on rings (O461)")
eq(addableKeys(newItem(2171)).gearspeed, nil, "no longer on amulets (O461)")
eq(addableKeys(newItem(2400)).gearspeed, nil, "not on weapons (they have attackspeed)")
eq(addableKeys(newItem(2466)).gearspeed, nil, "not on armor")
-- Echo Shot works on a ranged hit only: a bow rolls it, a sword or a Monk's fist weapon does not (owner 2026-11-01)
eq(M.addable(newItem(2456), 5)[1] ~= nil, true, "a bow has addable modifiers")
local function powerKeys(id)
	local out = {}
	for _, row in ipairs(M.addable(newItem(id), 5)) do
		out[row.entry.key] = true
	end
	return out
end
eq(powerKeys(2456).echoshot, true, "Echo Shot on a bow")
eq(powerKeys(2400).echoshot, nil, "no Echo Shot on a sword")
eq(powerKeys(36656).echoshot, nil, "no Echo Shot on a fist weapon")
eq(powerKeys(36656).critecho, true, "a fist weapon keeps the other weapon powers")
eq(addableKeys(newItem(2123)).attackspeed, nil, "the weapon's own modifier is not on rings")
eq(M.byKey.gearspeed.cap, nil, "worn attack speed: no cap of the module (the player cap 45 of ChaosItemMods config stays)")
eq(M.byKey.gearspeed.label, "Attack Speed")
eq(M.byKey.attackspeed.weight, 20, "weapon attack speed weight (was 8)")
eq(M.totals({}, {gearspeed = 30}).gearspeed, 30, "the pieces add up (the module has no cap; ChaosItemMods.playerSpeedTotal holds the player cap)")
eq(M.config.playerSpeedCap, 45, "the cap of the player's own attack speed is untouched")
-- the weapon's modifier does not count as a player bonus, and gear speed does not touch the weapon's interval
eq(M.totals({}, {attackspeed = 9}).gearspeed, 0)
eq(addableKeys(newItem(2514)).block, true, "block on shields")
eq(addableKeys(newItem(2400)).block, nil, "not on weapons")
eq(addableKeys(newItem(2400)).execute, true, "execute on weapons")
eq(addableKeys(newItem(2471)).cdr, true, "cooldown reduction on helmets")

-- ---------------------------------------------------------------- tiers
eq(table.concat(M.config.tierLevels, ","), "1,15,30,50,70,90,110,130", "O461: the item level of each tier")
eq(M.config.tierWindow, nil, "O461: the window of the best five tiers is gone")
eq(M.maxTierFor(1), 1); eq(M.maxTierFor(14), 1); eq(M.maxTierFor(15), 2); eq(M.maxTierFor(69), 4)
eq(M.maxTierFor(70), 5); eq(M.maxTierFor(89), 5); eq(M.maxTierFor(90), 6); eq(M.maxTierFor(109), 6); eq(M.maxTierFor(110), 7)
eq(M.maxTierFor(129), 7); eq(M.maxTierFor(130), 8); eq(M.maxTierFor(150), 8)
eq(M.maxTierFor(0), 1, "no level: T1")
local rows = M.tierRows(150)
eq(#rows, 8, "every tier the item level allows can roll"); eq(rows[1][1], 8, "best first"); eq(rows[8][1], 1, "T1 still rolls at 150")
eq(#M.tierRows(40), 3, "T1-T3 at item level 40")
eq(#M.tierRows(150, 4), 5, "a modifier gated at T4 rolls T4 .. T8 on an item of level 150")
eq(#M.tierRows(40, 4), 0, "and nothing on an item that allows T3 at most")
-- all tiers weigh the same (O461)
for t = 2, 8 do
	eq(M.config.tierWeights[t], M.config.tierWeights[t - 1], "weights are equal")
end
local ch = M.tierChances(150)
eq(ch[8], 12.5, "T8 at item level 150: one chance in eight"); eq(ch[4], 12.5); eq(ch[1], 12.5, "T1 can still roll at 150")
eq(M.tierChances(10)[1], 100, "item level 10: only T1")
eq(M.tierChances(133)[8], 12.5, "a boss of monster level 1000 (item level 133) rolls the top tier")
-- the roll: forced dice pick the tiers
eq(M.rollTier(150, function(a, b) return a end), 8, "lowest dice: the first row (best tier)")
eq(M.rollTier(150, function(a, b) return b end), 1, "highest dice: the last row")
eq(M.rollTier(150, function(a, b) return b end, 4), 4, "highest dice with a gate at T4")
eq(M.rollTier(1, function(a, b) return b end), 1)
-- average tier grows with the item level (exact weighted mean)
local function mean(level)
	local sum, w = 0, 0
	for _, r in ipairs(M.tierRows(level)) do
		sum, w = sum + r[1] * r[2], w + r[2]
	end
	return sum / w
end
assert(mean(20) < mean(60) and mean(60) < mean(100) and mean(100) < mean(150), "higher item levels roll higher tiers")
-- ranges and old values
local as = M.byKey.attackspeed
eq(M.range(as, 1)[1], 5); eq(M.range(as, 8)[2], 27); eq(M.range(as, 99)[2], 27, "clamped")
eq(M.tierOfValue(as.tiers, 10), 2, "+10% attack speed: the lowest tier that holds it, T2 (8-10)")
eq(M.tierOfValue(as.tiers, 6), 1, "+6%: T1 (5-7)")
eq(M.tierOfValue(M.legacy.attackspeed, 3), 2, "the old table: +3% was T2 (2-3)")
eq(M.tierOfValue(as.tiers, 40), 8, "above every range: the top tier")
eq(M.tierOfValue(as.tiers, 0), 1)
eq(M.tierOfValue(as.tiers, 2, 2, 6), 2, "searched in T2..T6 only")
for _, def in ipairs(M.config.mods) do
	for t = 1, 8 do
		for _, low in ipairs({true, false}) do
			local v = M.rollValue(def, t, function(a, b) return low and a or b end)
			local r = def.tiers[t]
			assert(v >= r[1] and v <= r[2], def.key .. " roll in its tier")
		end
	end
end
-- stored tier, else the one of the value
local sw = newItem(2400)
M.set(sw, "attackspeed", 9, 7)
eq(sw:getCustomAttribute("ct_chaos_mod_attackspeed"), 7, "tier stored next to the value")
eq(M.read(sw)[1].tier, 7)
eq(M.read(sw)[1].side, "suffix")
sw:removeCustomAttribute("ct_chaos_mod_attackspeed")
eq(M.read(sw)[1].tier, 6, "no stored tier (an old item): 9 in today's T2..T6 -> T6 (7-10)")
M.set(sw, "attackspeed", 2)
eq(M.read(sw)[1].tier, 2, "an old +2%: T2 (the old T1), not the new T1")
eq(sw:getCustomAttribute("ct_chaos_mod_attackspeed"), nil, "set without a tier drops a stale one")

-- ---------------------------------------------------------------- rarity: how many
-- the seven rarities (data/lib/chaos_rarity.lua): Common 1 modifier, Uncommon 2, Magic 3, Rare 4, Legendary 5, Divine 6
eq(M.modCount(1), 1); eq(M.sideLimit(1), 1); eq(M.maxMods(1), 2, "Common: one prefix, one suffix")
eq(M.modCount(2), 2); eq(M.sideLimit(2), 1); eq(M.maxMods(2), 2, "Uncommon: two modifiers, one on each side")
eq(M.modCount(3), 3); eq(M.sideLimit(3), 2); eq(M.maxMods(3), 4, "Magic")
eq(M.modCount(4), 4); eq(M.maxMods(4), 4, "Rare")
eq(M.modCount(5), 5); eq(M.sideLimit(5), 3); eq(M.maxMods(5), 6, "Legendary")
eq(M.modCount(10), 6); eq(M.sideLimit(10), 3); eq(M.maxMods(10), 6, "Divine: 3 + 3")
-- an item with one of the 15 old ids counts as the rarity it became
eq(M.modCount(7), M.modCount(5), "an old Mythic is Legendary") eq(M.modCount(15), 6, "an old Transcendent is Divine")
eq(M.maxMods(12), 6); eq(M.sideLimit(8), 3)
eq(M.modCount(0), 0); eq(M.maxMods(0), 0); eq(M.modCount(16), 0, "Unique is no rarity of a roll")
local last = 0
for _, r in ipairs({1, 2, 3, 4, 5, 10}) do
	assert(M.modCount(r) <= M.maxMods(r), "count within the limits at rarity " .. r)
	assert(M.modCount(r) >= last, "never fewer at a higher rarity")
	last = M.modCount(r)
end
eq(M.maxBinds(1), 1); eq(M.maxBinds(4), 1); eq(M.maxBinds(5), 2); eq(M.maxBinds(10), 2); eq(M.maxBinds(9), 2, "an old Eternal: Legendary's")
eq(M.qualityCap(5), 20); eq(M.qualityCap(10), 30); eq(M.qualityCap(9), 20, "an old Eternal: below Divine") eq(M.qualityCap(11), 30, "an old Phantasmal: Divine's")

-- ---------------------------------------------------------------- item level of a drop
eq(M.levelFromMonster(1), 1); eq(M.levelFromMonster(50), 22); eq(M.levelFromMonster(75), 29, "between 50 and 100")
eq(M.levelFromMonster(1100), 128); eq(M.levelFromMonster(99999), 145)
eq(M.sourceLevel({monsterLevel = 42}), 18, "a Dragon: 12 + 10 x 17 / 25")
eq(M.sourceLevel({monsterLevel = 42, tier = "legendary"}), 25, "+7 legendary")
eq(M.sourceLevel({monsterLevel = 1000, tier = "legendary", riftTier = 10}), 140, "a legendary in a tier 10 rift: T8")
eq(M.sourceLevel({monsterLevel = 1100, tier = "boss", riftTier = 15, omen = true}), 150, "capped")
eq(M.sourceLevel({monsterLevel = 5, riftTier = 99}), M.levelFromMonster(5) + 15, "rift bonus capped")
eq(M.sourceLevel({worldBoss = true}), 145)
eq(M.sourceLevel({fixed = 60}), 60)
eq(M.estimateMonsterLevel(700, 1000), 42, "Dragon, as gen_bounty_pool.py")
eq(M.estimateMonsterLevel(6000, 8200), 137, "Demon: its health counts (as bounty_pool.lua)")

-- ---------------------------------------------------------------- text and description
eq(M.text("attackspeed", 6), "Attack Speed +6%")
eq(M.text("lifeonkill", 25), "Life on Kill +25")
eq(M.text("monsterreduction", 3), "Damage Taken from Monsters -3%")
eq(M.text("rarityfind", 7), "Rarity Find +7%")
local amulet = newItem(2171)
amulet:setCustomAttribute("rarity", 6)
amulet:setCustomAttribute("combatPowerLevel", 55)
amulet:setCustomAttribute("rarity_holyAbsorb", 3)
amulet:setCustomAttribute("chaos_modv", 3) -- today's numbers: not upgraded when read (the upgrade has its own test)
M.set(amulet, "experience", 4)
M.set(amulet, "lifeonkill", 18)
eq(C.rewriteDescription(amulet), "Item Level: 55. Suffixes: Holy +3% (T3); Life on Kill +18 (T3); Experience +4% (T4)",
	"item level, the suffixes with their tiers (an old item: tiers from the values)")
eq(M.summary(amulet), "Life on Kill +18 (T3); Experience +4% (T4)")
eq(M.text("execute", 4), "Executes Monsters below 4% Health")
eq(M.text("regen", 12), "Health Regeneration +12 per Second")
eq(M.text("bleedchance", 6), "Chance to Bleed +6%")
eq(M.text("lifeonhit", 9), "Health on Hit +9")
-- attack speed: the weapon's own interval
local js = newItem(7390)
M.set(js, "attackspeed", 10)
eq(js:getAttribute(ITEM_ATTRIBUTE_ATTACK_SPEED), 1350, "1500 ms -10%")
M.remove(js, "attackspeed")
eq(js:getAttribute(ITEM_ATTRIBUTE_ATTACK_SPEED), nil, "back to the item type's 1500")
eq(M.attackInterval(0, 15), 1700, "no own interval: from 2000")
eq(M.attackInterval(150, 99), 100, "never below the engine's floor")

-- ---------------------------------------------------------------- totals and caps
local a1, a2 = newItem(2171), newItem(2123)
M.set(a1, "experience", 9)
M.set(a2, "experience", 9)
M.set(a2, "goldfind", 5)
local t = M.totals({a1, a2})
eq(t.experience, 18, "O461: no cap of the module on experience (9 + 9)")
eq(t.goldfind, 5)
eq(M.totals({}, {goldfind = 99}).goldfind, 40, "gold find is out of the roll pool but keeps its cap for uniques, sets and charms")
eq(t.dodge, 0, "every key present")
eq(M.speedBonus(437, 7), 30)
eq(M.scale(100, 10), 110); eq(M.scale(-100, 10), -110); eq(M.scale(100, -3), 97)
eq(M.reflected(250, 6), 15)
eq(M.experience(1000, 4), 1040)

-- ---------------------------------------------------------------- Treasure Goblin Chance (treasure_goblin.lua)
do
	local gc = M.byKey.goblinchance
	eq(gc.label, "Treasure Goblin Chance"); eq(gc.fmt, "pct"); eq(gc.cap, 100)
	eq(gc.tiers[1][1], 9, "+9% at the bottom (it was 6)"); eq(M.legacy.goblinchance[6][2], 40, "+40% at the top of the old tiers")
	eq(gc.tiers[8][2], 90, "+90% at T8 (it was 60)")
	eq(M.text("goblinchance", 25), "Treasure Goblin Chance +25%")
	eq(addableKeys(newItem(2471)).goblinchance, true, "on helmets")
	eq(addableKeys(newItem(2171)).goblinchance, true, "on amulets")
	eq(addableKeys(newItem(2123)).goblinchance, true, "on rings")
	eq(addableKeys(newItem(2466)).goblinchance, nil, "not on armor")
	eq(addableKeys(newItem(2400)).goblinchance, nil, "not on weapons")
	eq(addableKeys(newItem(2195)).goblinchance, nil, "not on boots")
	-- rolls: the tier's range
	local lo = M.rollValue(gc, 1, function(a, b) return a end)
	local hi = M.rollValue(gc, 8, function(a, b) return b end)
	eq(lo, 9); eq(hi, 90)
	-- helmets may get it
	local helm = newItem(2471)
	local found = false
	for _, row in ipairs(M.addable(helm)) do
		found = found or row.entry.key == "goblinchance"
	end
	eq(found, true, "on the helmet's list")
	-- cap: helmet 40 + amulet 40 + ring 40 = 120 -> 100
	local h, am, rg = newItem(2471), newItem(2171), newItem(2123)
	M.set(h, "goblinchance", 40); M.set(am, "goblinchance", 40); M.set(rg, "goblinchance", 40)
	eq(M.totals({h, am, rg}).goblinchance, 100, "capped at +100% per character")
	eq(M.totals({h, am}).goblinchance, 80)
	eq(M.summary(h), "Treasure Goblin Chance +40% (T6)")
end

-- ---------------------------------------------------------------- on the character
local player = newCreature("player", {baseSpeed = 400, health = 500})
online[1] = player
events.ChaosItemModsLogin.onLogin(player)
eq(player.registered.ChaosItemModsTaken, true, "hit event registered")
eq(player.registered.ChaosItemModsKill, true)
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

-- movement speed: % of the base speed, given on equip and taken back on unequip
local fast = newItem(2195)
M.set(fast, "movespeed", 6)
equip(fast, CONST_SLOT_FEET)
eq(player.speed, 24, "6% of 400")
eq(M.playerBonus(player, "movespeed"), 6)
-- boots in the wrong slot (a hand) count for nothing
unequip(CONST_SLOT_FEET)
eq(player.speed, 0, "speed back after unequip")
eq(M.playerBonus(player, "movespeed"), 0)
player.slots[CONST_SLOT_RIGHT] = fast
move(player, fast, 1, {x = 0xFFFF, y = 64, z = 0}, {x = 0xFFFF, y = CONST_SLOT_RIGHT, z = 0})
eq(player.speed, 0, "boots held in a hand do nothing")
unequip(CONST_SLOT_RIGHT)
-- level up: the share follows the base speed
equip(fast, CONST_SLOT_FEET)
player.baseSpeed = 500
events.ChaosItemModsAdvance.onAdvance(player, SKILL_LEVEL, 10, 11)
eq(player.speed, 30, "6% of 500")
-- an item that leaves its slot without a move event is caught by the periodic check
player.slots[CONST_SLOT_FEET] = nil
local steps, elapsed = runCheckCycle()
eq(steps, 12, "the check runs in 12 groups")
eq(elapsed, 3000, "every group once in 3 s")
eq(player.speed, 0, "periodic check removed it")

-- experience
local xp = callbacks.onGainExperience[1]
eq(xp(player, {}, 1000, 1000), 1000, "no bonus")
equip(amulet, CONST_SLOT_NECKLACE)
eq(xp(player, {}, 1000, 1000), 1040, "+4%")
eq(xp(player, nil, 1000, 1000), 1000, "no source (a script), no bonus")

-- life and mana on kill (monsters only, once per kill)
local monster = newCreature("monster")
local kill = events.ChaosItemModsKill
player.health = 100
kill.onKill(player, monster)
eq(player.health, 118, "life on kill +18")
kill.onKill(player, monster)
eq(player.health, 118, "only once per kill")
kill.onKill(player, newCreature("player"))
eq(player.health, 118, "players give nothing")

-- hits taken: damage from monsters, reflect, thorns, dodge
local armor = newItem(2466)
M.set(armor, "monsterreduction", 4)
M.set(armor, "reflect", 5)
M.set(armor, "thorns", 30)
M.set(armor, "dodge", 3)
equip(armor, CONST_SLOT_ARMOR)
local taken = events.ChaosItemModsTaken
player.health = 1000
local realRandom = math.random
math.random = function(a, b) return b end -- no dodge
hits = {}
local p1 = taken.onHealthChange(player, monster, 200, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(p1, 192, "-4% from monsters")
eq(#hits, 1, "one hit back")
eq(hits[1].to, monster:getId())
eq(hits[1].min, -(9 + 30), "reflect 5% of 192 + thorns 30")
hits = {}
taken.onHealthChange(player, monster, 200, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(hits[1].min, -9, "no thorns against a spell")
hits = {}
local other = newCreature("player")
local p2 = taken.onHealthChange(player, other, 200, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(p2, 200, "the reduction is against monsters only")
math.random = function(a, b) return a end -- dodge roll 1 <= 3
hits = {}
local p3, _, s3 = taken.onHealthChange(player, monster, 200, COMBAT_PHYSICALDAMAGE, 50, COMBAT_FIREDAMAGE, ORIGIN_MELEE)
eq(p3, 0, "dodged")
eq(s3, 0, "the whole hit")
eq(#hits, 0, "nothing reflected from a dodged hit")
math.random = realRandom
unequip(CONST_SLOT_ARMOR)
hits = {}
eq(taken.onHealthChange(player, monster, 200, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 200, "armor off")
eq(#hits, 0)

-- healing done: the healer's bonus on the healed player
local wand = newItem(2400)
M.set(wand, "healing", 8)
equip(wand, CONST_SLOT_LEFT)
eq(taken.onHealthChange(other, player, 100, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL), 108, "+8% healing")
eq(taken.onHealthChange(player, player, 100, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL), 108, "own heals too")

-- elites and bosses
M.set(wand, "bossdamage", 10)
unequip(CONST_SLOT_LEFT)
equip(wand, CONST_SLOT_LEFT)
local target = callbacks.onTargetCombat[1]
local elite = newCreature("monster", {tier = "rare"})
eq(target(player, elite), RETURNVALUE_NOERROR)
eq(elite.registered.ChaosItemModsDealt, true, "event on the target")
local dealt = events.ChaosItemModsDealt
eq(dealt.onHealthChange(elite, player, 100, COMBAT_PHYSICALDAMAGE, 20, COMBAT_FIREDAMAGE, ORIGIN_MELEE), 110, "+10% on a rare")
eq(dealt.onHealthChange(monster, player, 100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 100, "normal monster")
eq(dealt.onHealthChange(newCreature("monster", {boss = true}), player, 100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE,
	ORIGIN_MELEE), 110, "a boss")

-- gold find
local ring = newItem(2123)
M.set(ring, "goldfind", 10)
equip(ring, CONST_SLOT_RING)
local corpseItems, added = {}, {}
local corpse = {
	getCorpseOwner = function() return player end,
	getSize = function() return #corpseItems end,
	getItem = function(_, i) return corpseItems[i + 1] end,
	addItem = function(_, id, n) added[#added + 1] = {id, n} end
}
Player = function(p) return p end
local coins = newItem(2148)
coins.count = 50
function coins:getCount() return 50 end
corpseItems[1] = coins
math.random = function() return 0.99 end
callbacks.onDropLoot[1](monster, corpse)
math.random = realRandom
eq(#added, 1, "extra coins")
eq(added[1][1], 2148); eq(added[1][2], 5, "10% of 50 gold")
eq(M.playerBonus(player, "itemfind"), 0, "item find read by the loot layer")
-- Treasure Goblin Chance on the character: read by treasure_goblin.lua through playerBonus
M.set(ring, "goblinchance", 30)
M.refresh(player)
eq(M.playerBonus(player, "goblinchance"), 30, "goblin chance read by the goblin respawn roll")
M.remove(ring, "goblinchance")
M.refresh(player)
eq(M.playerBonus(player, "goblinchance"), 0)

-- after a drop: loot.lua forged the item and kept its rarity as text through the engine's pass; the marked corpse
-- gives it back as a number next tick
local dropped = newItem(2466)
dropped:setCustomAttribute("rarity", "2")
eq(C.rarityOf(dropped), 2, "a shielded rarity reads as a number")
local marked = newItem(2160)
marked.isContainer = function() return true end
marked.getItems = function() return {dropped} end
marked.getPosition = function() return {x = 1, y = 2, z = 7} end
Tile = function() return {getItems = function() return {marked} end} end
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end
timers = {}
M.afterDrop(marked)
eq(marked:getCustomAttribute("chaos_mods_pending"), 1, "corpse marked")
timers[#timers].fn(table.unpack and table.unpack(timers[#timers].args) or unpack(timers[#timers].args))
eq(dropped:getCustomAttribute("rarity"), 2, "a number again")
eq(marked:getCustomAttribute("chaos_mods_pending"), nil, "marker gone")
-- an item looted before that tick: any move gives it back
local early = newItem(2466)
early:setCustomAttribute("rarity", "5")
move(player, early, 1, {x = 100, y = 100, z = 7}, {x = 0xFFFF, y = 64, z = 0})
eq(early:getCustomAttribute("rarity"), 5, "unshielded on its first move")

-- ---------------------------------------------------------------- the new modifiers in combat
ORIGIN_CONDITION, ORIGIN_RANGED = 1, 4
COMBAT_ICEDAMAGE = 512
CONDITION_BLEEDING, CONDITION_FIRE, CONDITION_POISON, CONDITION_PARALYZE = 1, 2, 3, 4
CONDITION_PARAM_OWNER, CONDITION_PARAM_DELAYED, CONDITION_PARAM_TICKS = 1, 2, 3
local conditions = {}
Condition = function(kind)
	local c = {kind = kind, params = {}}
	function c:setParameter(k, v) self.params[k] = v end
	function c:addDamage(rounds, time, value) self.rounds, self.time, self.value = rounds, time, value end
	function c:setFormula(a, b, c2, d) self.formula = {a, b, c2, d} end
	return c
end
function Creature:addCondition(c) conditions[#conditions + 1] = {to = self, c = c} end
function Creature:getName() return self.name or "orc" end
function Creature:getMaxMana() return 1000 end
local RES = {orc = {[COMBAT_PHYSICALDAMAGE] = 20, [COMBAT_ICEDAMAGE] = 50}}
function Creature:getType()
	local me = self
	return {isBoss = function() return me.boss == true end, getElementList = function() return RES[me.name or "orc"] or {} end}
end

local weapon = newItem(2400)
M.set(weapon, "physpen", 10); M.set(weapon, "elepen", 25); M.set(weapon, "lifeonhit", 7); M.set(weapon, "manaonhit", 3)
M.set(weapon, "execute", 5); M.set(weapon, "dot", 20)
for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
	if player.slots[slot] then
		unequip(slot)
	end
end
equip(weapon, CONST_SLOT_LEFT)
local orc = newCreature("monster", {health = 100000})
orc.name = "orc"
eq(target(player, orc), RETURNVALUE_NOERROR)
eq(orc.registered.ChaosItemModsDealt, true, "any offensive modifier registers the hit event")
math.random = function(a, b) return b end -- no ailment
player.health, player.mana = 100, 0
-- O464: penetration is the monster defence layer's (tests/monster_defence_test.lua), not this event's: the hit stays as it is
eq(dealt.onHealthChange(orc, player, 80, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 80, "no penetration here any more")
eq(M.playerBonus(player, "physpen"), 10, "the totals still carry physical penetration for the monster layer")
eq(M.playerBonus(player, "elepen"), 25, "... and elemental penetration")
eq(player.health, 107, "health on hit"); eq(player.mana, 3, "mana on hit")
local _, _, sIce = dealt.onHealthChange(orc, player, 0, COMBAT_PHYSICALDAMAGE, 50, COMBAT_ICEDAMAGE, ORIGIN_SPELL)
eq(sIce, 50, "the secondary part is not changed here either")
-- damage over time: hits of conditions you own, no on-hit
player.health = 100
eq(dealt.onHealthChange(orc, player, 50, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_CONDITION), 60, "+20% damage over time")
eq(player.health, 100, "a condition tick is no hit")
-- execute: a non-boss monster left at or below 5% dies
orc.health = 5400
eq(dealt.onHealthChange(orc, player, 500, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 5400, "4900 of 100000 left: executed")
orc.health = 9000
eq(dealt.onHealthChange(orc, player, 500, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 500, "8500 left: not yet")
local bossMon = newCreature("monster", {boss = true, health = 5400})
eq(dealt.onHealthChange(bossMon, player, 500, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 500, "bosses are never executed")
eq(M.executes(5400, 100000, 500, 5), true); eq(M.executes(400, 100000, 500, 5), false, "the hit kills anyway")
-- ailments: forced rolls
M.set(weapon, "bleedchance", 10); M.set(weapon, "chillchance", 10); M.set(weapon, "shockchance", 10)
M.refresh(player)
conditions = {}
math.random = function(a, b) return a end -- every roll hits
orc.health = 100000
dealt.onHealthChange(orc, player, 400, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
local kinds = {}
for _, c in ipairs(conditions) do kinds[c.c.kind] = c.c end
eq(kinds[CONDITION_BLEEDING].value, -M.ailmentTick(400), "bleeding: a share of the hit per tick")
eq(kinds[CONDITION_BLEEDING].params[CONDITION_PARAM_OWNER], player:getId(), "owned by the player")
eq(kinds[CONDITION_BLEEDING].rounds, 4)
eq(kinds[CONDITION_PARALYZE].formula[1], -0.3, "chill slows by 30%")
eq(kinds[CONDITION_FIRE], nil, "no ignite chance, no ignite")
eq(M.ailmentTick(400), 40, "40% of 400 over 4 ticks")
-- shocked: +15% damage from everyone
math.random = function(a, b) return b end
local other2 = newCreature("player")
eq(dealt.onHealthChange(orc, other2, 100, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 115, "shocked: +15% for another player")
M.shocked[orc:getId()] = 0
eq(dealt.onHealthChange(orc, other2, 100, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 100, "shock over")
unequip(CONST_SLOT_LEFT)
-- block: physical melee and ranged hits only
local buckler = newItem(2514)
M.set(buckler, "block", 10)
equip(buckler, CONST_SLOT_RIGHT)
math.random = function(a, b) return a end
eq(taken.onHealthChange(player, monster, 200, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED), 0, "a blocked arrow")
eq(taken.onHealthChange(player, monster, 200, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 200, "spells are not blocked")
math.random = realRandom
unequip(CONST_SLOT_RIGHT)
-- health regeneration: the 3 s check heals 3 x the total
local plate = newItem(2466)
M.set(plate, "regen", 10)
equip(plate, CONST_SLOT_ARMOR)
player.health = 100
runCheckCycle()
eq(player.health, 130, "+10 per second, every 3 s (one check of this player per cycle)")
-- each player is in exactly one group: player id modulo 12
do
	local seen = {}
	for slice = 0, 11 do
		seen[slice] = 0
	end
	for id = 0x10000001, 0x10000030 do
		seen[id % 12] = seen[id % 12] + 1
	end
	local even = true
	for slice = 0, 11 do
		even = even and seen[slice] == 4
	end
	eq(even, true, "48 consecutive player ids: 4 in each group")
end
eq(M.regenAmount(10, 3000), 30)
unequip(CONST_SLOT_ARMOR)
-- equipped items for the spell side (cooldown and mana cost reduction)
local hood = newItem(2471)
M.set(hood, "cdr", 8); M.set(hood, "manacost", 6)
equip(hood, CONST_SLOT_HEAD)
local eqT = M.totals(M.equippedItems(player))
eq(eqT.cdr, 8, "the spell side reads the equipped items"); eq(eqT.manacost, 6)
unequip(CONST_SLOT_HEAD)
eq(M.penetrate, nil, "the re-derivation of a rounded hit left the file with the penetration move (O464)")

-- logout forgets everything
events.ChaosItemModsLogout.onLogout(player)
eq(M.playerBonus(player, "goldfind"), 0, "forgotten")

print(string.format("item_mods_test: %d checks OK", checks))
