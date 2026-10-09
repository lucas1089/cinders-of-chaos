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
function Creature:getPosition() return {sendMagicEffect = function() end} end
function Creature:getType() return {isBoss = function() return self.boss == true end} end
function ChaosTierOf(c) return c.tier end

local online = {}
Game = {getPlayers = function() return online end}

dofile("data/scripts/chaos/item_mods.lua")
local M = ChaosItemMods
local C = ChaosCrafting

-- ---------------------------------------------------------------- catalogue
eq(#M.config.mods, 15, "fifteen modifiers")
for _, def in ipairs(M.config.mods) do
	eq(#def.tiers, 5, def.key .. ": five tiers")
	assert(def.cap > 0 and def.weight > 0, def.key)
	local prevLo, prevHi = 0, 0
	for t, r in ipairs(def.tiers) do
		assert(r[1] >= 1 and r[1] <= r[2], def.key .. " tier " .. t .. " range")
		assert(r[1] >= prevLo and r[2] >= prevHi, def.key .. " ranges grow with the tier")
		prevLo, prevHi = r[1], r[2]
	end
	assert(def.tiers[5][2] <= def.cap, def.key .. ": one item never beats the cap")
	assert(next(def.kinds), def.key .. ": allowed somewhere")
end
-- balance: percent modifiers stay in the passive tree's range (a few percent per item)
eq(M.byKey.attackspeed.tiers[5][2], 10)
eq(M.byKey.movespeed.cap, 12)
eq(M.byKey.dodge.cap, 10)
eq(M.byKey.experience.cap, 15)

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

-- ---------------------------------------------------------------- tiers and roll ranges
eq(M.tierOf(1), 1); eq(M.tierOf(3), 1); eq(M.tierOf(4), 2); eq(M.tierOf(9), 3); eq(M.tierOf(13), 5); eq(M.tierOf(15), 5)
eq(M.tierOf(99), 5, "clamped")
local as = M.byKey.attackspeed
local r = M.range(as, 1, 1)
eq(r[1], 2); eq(r[2], 3)
r = M.range(as, 13, 121) -- tier 5 window starts at level 121: no pull
eq(r[1], 7); eq(r[2], 10)
r = M.range(as, 15, 150) -- top of the window: the low end rises by half the range (7 + floor(3 x 0.5))
eq(r[1], 8); eq(r[2], 10)
r = M.range(M.byKey.lifeonkill, 9, 90) -- tier 3 (20..40) at the top of 61..90: 20 + 10
eq(r[1], 30); eq(r[2], 40)
-- every roll of every modifier at every rarity and level stays in the tier's range
for _, def in ipairs(M.config.mods) do
	for rarity = 1, 15 do
		local t = def.tiers[M.tierOf(rarity)]
		for _, level in ipairs({0, rarity * 10 - 9, rarity * 10, 200}) do
			for _, pickLow in ipairs({true, false}) do
				local v = M.rollValue(def, rarity, level, function(a, b) return pickLow and a or b end)
				assert(v >= t[1] and v <= t[2], def.key .. " roll in range")
			end
		end
	end
end

-- ---------------------------------------------------------------- drop rolls
eq(M.rollCount(0, function(a, b) return a end), 0, "no rarity, nothing")
eq(M.rollCount(1, function(a, b) return a end), 1, "Common: one at most (second chance 0)")
eq(M.rollCount(9, function(a, b) return a end), 2, "Eternal: a second one possible")
eq(M.rollCount(15, function(a, b) return b end), 0, "a failed roll")
local seq = {40, 21} -- rarity 15: 40 <= 40 hits, 21 > 20 misses
eq(M.rollCount(15, function(a, b) return table.remove(seq, 1) end), 1)
local boots = newItem(2195)
local added = M.rollNew(boots, 9, 85, 1, function(a, b) return a end)
eq(#added, 1, "limited by the free slots")
eq(added[1].key, "movespeed", "the only boots modifier of the first weight")
eq(boots:getCustomAttribute("chaos_mod_movespeed"), 4, "tier 3 (4..6) at level 85 of 61..90: 4 + floor(2 x 0.83 x 0.5) = 4")
eq(#M.rollNew(newItem(2195), 9, 85, 0, function(a, b) return a end), 0, "no free slot, nothing")

-- ---------------------------------------------------------------- text and description
eq(M.text("attackspeed", 6), "Attack Speed +6%")
eq(M.text("lifeonkill", 25), "Life on Kill +25")
eq(M.text("monsterreduction", 3), "Damage Taken from Monsters -3%")
eq(M.text("rarityfind", 7), "Rarity Find +7%")
local amulet = newItem(2171)
amulet:setCustomAttribute("rarity", 6)
amulet:setCustomAttribute("combatPowerLevel", 55)
amulet:setCustomAttribute("rarity_holyAbsorb", 3)
M.set(amulet, "experience", 4)
M.set(amulet, "lifeonkill", 18)
eq(C.rewriteDescription(amulet), "Level: 55, Holy +3%, Life on Kill +18, Experience +4%", "engine format, catalogue order")
eq(M.summary(amulet), "Life on Kill +18; Experience +4%")
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
eq(t.experience, 15, "capped at 15")
eq(t.goldfind, 5)
eq(t.dodge, 0, "every key present")
eq(M.speedBonus(437, 7), 30)
eq(M.scale(100, 10), 110); eq(M.scale(-100, 10), -110); eq(M.scale(100, -3), 97)
eq(M.reflected(250, 6), 15)
eq(M.experience(1000, 4), 1040)

-- ---------------------------------------------------------------- Treasure Goblin Chance (treasure_goblin.lua)
do
	local gc = M.byKey.goblinchance
	eq(gc.label, "Treasure Goblin Chance"); eq(gc.fmt, "pct"); eq(gc.cap, 100)
	eq(gc.tiers[1][1], 10, "+10% at the bottom"); eq(gc.tiers[5][2], 40, "+40% at the top")
	eq(M.text("goblinchance", 25), "Treasure Goblin Chance +25%")
	eq(addableKeys(newItem(2471)).goblinchance, true, "on helmets")
	eq(addableKeys(newItem(2171)).goblinchance, true, "on amulets")
	eq(addableKeys(newItem(2123)).goblinchance, true, "on rings")
	eq(addableKeys(newItem(2466)).goblinchance, nil, "not on armor")
	eq(addableKeys(newItem(2400)).goblinchance, nil, "not on weapons")
	eq(addableKeys(newItem(2195)).goblinchance, nil, "not on boots")
	-- rolls: tier 1 at Common, tier 5 at Transcendent with the level pull
	local lo = M.rollValue(gc, 1, 1, function(a, b) return a end)
	local hi = M.rollValue(gc, 15, 150, function(a, b) return b end)
	eq(lo, 10); eq(hi, 40)
	eq(M.range(gc, 15, 150)[1], 34, "28 + floor(12 x 0.5) at the top of the window")
	-- an Exalted-style add on a helmet can pick it (weighted pick: force the last row)
	local helm = newItem(2471)
	local rows = M.addable(helm)
	local last = rows[#rows].entry
	eq(last.key, "goblinchance", "last in catalogue order (stored keys of older items unchanged)")
	-- cap: helmet 40 + amulet 40 + ring 40 = 120 -> 100
	local h, am, rg = newItem(2471), newItem(2171), newItem(2123)
	M.set(h, "goblinchance", 40); M.set(am, "goblinchance", 40); M.set(rg, "goblinchance", 40)
	eq(M.totals({h, am, rg}).goblinchance, 100, "capped at +100% per character")
	eq(M.totals({h, am}).goblinchance, 80)
	eq(M.summary(h), "Treasure Goblin Chance +40%")
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
events.ChaosItemModsStartup.onStartup()
for _, timer in ipairs(timers) do
	if timer.ms == 3000 then
		timer.fn()
		break
	end
end
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

-- after a drop: the engine appends its rarity text after the Lua callbacks; the marked corpse is rewritten next tick
local dropped = newItem(2466)
dropped:setCustomAttribute("rarity", 2)
dropped:setCustomAttribute("combatPowerLevel", 17)
dropped:setCustomAttribute("rarity_iceAbsorb", 1)
M.set(dropped, "thorns", 6)
dropped:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "Level: 0, Thorns +6, Level: 17, Ice +1%")
local marked = newItem(2160)
marked.isContainer = function() return true end
marked.getItems = function() return {dropped} end
marked.getPosition = function() return {x = 1, y = 2, z = 7} end
Tile = function() return {getItems = function() return {marked} end} end
Position = function(x, y, z) return {x = x, y = y, z = z} end
timers = {}
M.afterDrop(marked)
eq(marked:getCustomAttribute("chaos_mods_pending"), 1, "corpse marked")
timers[#timers].fn(table.unpack and table.unpack(timers[#timers].args) or unpack(timers[#timers].args))
eq(dropped:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Level: 17, Ice +1%, Thorns +6", "description rebuilt")
eq(marked:getCustomAttribute("chaos_mods_pending"), nil, "marker gone")

-- logout forgets everything
events.ChaosItemModsLogout.onLogout(player)
eq(M.playerBonus(player, "goldfind"), 0, "forgotten")

print(string.format("item_mods_test: %d checks OK", checks))
