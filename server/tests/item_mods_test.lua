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
eq(#M.config.mods, 30, "thirty modifiers (fifteen old, fifteen new)")
local sides = {prefix = 0, suffix = 0}
for _, def in ipairs(M.config.mods) do
	eq(#def.tiers, 8, def.key .. ": eight tiers")
	assert(def.cap > 0 and def.weight > 0, def.key)
	assert(def.side == "prefix" or def.side == "suffix", def.key .. ": a side")
	sides[def.side] = sides[def.side] + 1
	local prevLo, prevHi = 0, 0
	for t, r in ipairs(def.tiers) do
		assert(r[1] >= 1 and r[1] <= r[2], def.key .. " tier " .. t .. " range")
		assert(r[1] >= prevLo and r[2] >= prevHi, def.key .. " ranges grow with the tier")
		prevLo, prevHi = r[1], r[2]
	end
	assert(def.tiers[8][2] <= def.cap, def.key .. ": one item never beats the cap")
	assert(next(def.kinds), def.key .. ": allowed somewhere")
end
eq(sides.prefix, 15, "fifteen prefixes"); eq(sides.suffix, 15, "fifteen suffixes")
-- the five tiers of before are T2 .. T6, so old items keep their meaning
local OLD = {attackspeed = {{2, 3}, {3, 5}, {4, 6}, {5, 8}, {7, 10}}, lifeonkill = {{5, 10}, {10, 20}, {20, 40}, {35, 60},
	{50, 90}}, goblinchance = {{10, 15}, {14, 20}, {18, 27}, {22, 33}, {28, 40}}, dodge = {{1, 1}, {1, 2}, {1, 2}, {2, 3},
	{2, 4}}, movespeed = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}}}
for key, old in pairs(OLD) do
	for t, r in ipairs(old) do
		local n = M.byKey[key].tiers[M.config.oldTiers[t]]
		eq(n[1], r[1], key .. " old tier " .. t .. " low"); eq(n[2], r[2], key .. " old tier " .. t .. " high")
	end
end
eq(M.byKey.movespeed.cap, 12)
eq(M.byKey.dodge.cap, 10)
eq(M.byKey.experience.cap, 15)
eq(M.byKey.attackspeed.side, "suffix", "speed is a suffix")
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
eq(addableKeys(newItem(2514)).block, true, "block on shields")
eq(addableKeys(newItem(2400)).block, nil, "not on weapons")
eq(addableKeys(newItem(2400)).execute, true, "execute on weapons")
eq(addableKeys(newItem(2471)).cdr, true, "cooldown reduction on helmets")

-- ---------------------------------------------------------------- tiers
eq(M.maxTierFor(1), 1); eq(M.maxTierFor(14), 1); eq(M.maxTierFor(15), 2); eq(M.maxTierFor(69), 4)
eq(M.maxTierFor(70), 5); eq(M.maxTierFor(139), 7); eq(M.maxTierFor(140), 8); eq(M.maxTierFor(150), 8)
eq(M.maxTierFor(0), 1, "no level: T1")
local rows = M.tierRows(150)
eq(#rows, 5, "five tiers can roll"); eq(rows[1][1], 8, "best first"); eq(rows[5][1], 4, "T4 the lowest at 150")
eq(#M.tierRows(40), 3, "T1-T3 at item level 40")
-- higher tiers are rarer
for t = 2, 8 do
	assert(M.config.tierWeights[t] < M.config.tierWeights[t - 1], "weights fall with the tier")
end
local ch = M.tierChances(150)
eq(ch[8], 6.5, "T8 at item level 150: 12 / 184"); eq(ch[4], 35.3); eq(ch[1], nil, "T1 cannot roll at 150")
eq(M.tierChances(10)[1], 100, "item level 10: only T1")
-- the roll: forced dice pick the tiers
eq(M.rollTier(150, function(a, b) return a end), 8, "lowest dice: the first row (best tier)")
eq(M.rollTier(150, function(a, b) return b end), 4, "highest dice: the last row")
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
eq(M.range(as, 1)[1], 1); eq(M.range(as, 8)[2], 14); eq(M.range(as, 99)[2], 14, "clamped")
eq(M.tierOfValue(as.tiers, 10), 6, "+10% attack speed: the lowest tier that holds it, T6 (7-10)")
eq(M.tierOfValue(as.tiers, 3), 2, "+3%: T2 (2-3)")
eq(M.tierOfValue(as.tiers, 20), 8, "above every range: the top tier")
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
eq(M.modCount(1), 2); eq(M.sideLimit(1), 1); eq(M.maxMods(1), 2, "Common: one prefix, one suffix")
eq(M.modCount(4), 3); eq(M.maxMods(4), 4)
eq(M.modCount(15), 6); eq(M.sideLimit(15), 3); eq(M.maxMods(15), 6, "top rarities: 3 + 3")
eq(M.modCount(0), 0); eq(M.maxMods(0), 0)
for r = 1, 15 do
	assert(M.modCount(r) <= M.maxMods(r), "count within the limits at rarity " .. r)
	assert(r == 1 or M.modCount(r) >= M.modCount(r - 1), "never fewer at a higher rarity")
end

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
	eq(gc.tiers[1][1], 6, "+6% at the bottom"); eq(gc.tiers[6][2], 40, "+40% at the top of the old tiers")
	eq(gc.tiers[8][2], 60, "+60% at T8")
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
	eq(lo, 6); eq(hi, 60)
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
Position = function(x, y, z) return {x = x, y = y, z = z} end
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
-- physical: 20% resistance, 10 points ignored: 80 landed = 100 raw -> 90
eq(dealt.onHealthChange(orc, player, 80, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 90, "physical penetration")
eq(player.health, 107, "health on hit"); eq(player.mana, 3, "mana on hit")
-- ice: 50% resistance, 25 ignored: 50 landed = 100 raw -> 75
local _, _, sIce = dealt.onHealthChange(orc, player, 0, COMBAT_PHYSICALDAMAGE, 50, COMBAT_ICEDAMAGE, ORIGIN_SPELL)
eq(sIce, 75, "elemental penetration on the secondary part")
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
eq(kinds[CONDITION_BLEEDING].value, -M.ailmentTick(450), "bleeding: a share of the hit (400 -> 450 after penetration) per tick")
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
timers = {}
events.ChaosItemModsStartup.onStartup()
for _, timer in ipairs(timers) do
	if timer.ms == 3000 then
		timer.fn()
		break
	end
end
eq(player.health, 130, "+10 per second, every 3 s")
eq(M.regenAmount(10, 3000), 30)
unequip(CONST_SLOT_ARMOR)
-- equipped items for the spell side (cooldown and mana cost reduction)
local hood = newItem(2471)
M.set(hood, "cdr", 8); M.set(hood, "manacost", 6)
equip(hood, CONST_SLOT_HEAD)
local eqT = M.totals(M.equippedItems(player))
eq(eqT.cdr, 8, "the spell side reads the equipped items"); eq(eqT.manacost, 6)
unequip(CONST_SLOT_HEAD)
eq(M.penetrate(80, 20, 10), 90); eq(M.penetrate(80, 0, 10), 80, "no resistance, nothing to ignore")
eq(M.penetrate(80, 100, 10), 80, "immune stays immune"); eq(M.penetrate(80, 5, 10), 84, "never below 0 resistance")

-- logout forgets everything
events.ChaosItemModsLogout.onLogout(player)
eq(M.playerBonus(player, "goldfind"), 0, "forgotten")

print(string.format("item_mods_test: %d checks OK", checks))
