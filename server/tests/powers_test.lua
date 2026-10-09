-- Run from the server/ folder: luajit tests/powers_test.lua (and lua5.3; CI runs both)
-- The legendary powers: data/lib/chaos_powers.lua (catalogue, maths, cooldowns, stacks) and data/scripts/chaos/item_powers.lua
-- against a mocked engine: Death Blast, Glacial Ward, Echo Shot, Critical Echo, Arc Lightning, Crimson Burst, Bloodrush,
-- Shatter Splash, Last Breath, Ember Step, Hunter's Rush and Smoldering Aura; their cooldowns, caps and the recursion guard.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "assertion failed", 2)
	end
end

-- ---------------------------------------------------------------- engine mock
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME = 1, 2
CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_ARMOR, CONST_SLOT_RIGHT, CONST_SLOT_LEFT = 1, 2, 3, 4, 5, 6
CONST_SLOT_LEGS, CONST_SLOT_FEET, CONST_SLOT_RING, CONST_SLOT_AMMO = 7, 8, 9, 10
SLOTP_HEAD, SLOTP_NECKLACE, SLOTP_BACKPACK, SLOTP_ARMOR, SLOTP_RIGHT, SLOTP_LEFT = 1, 2, 4, 8, 16, 32
SLOTP_LEGS, SLOTP_FEET, SLOTP_RING, SLOTP_AMMO = 64, 128, 256, 512
WEAPON_NONE, WEAPON_SWORD, WEAPON_SHIELD, WEAPON_AMMO = 0, 1, 4, 7
COMBAT_PHYSICALDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_ICEDAMAGE, COMBAT_FIREDAMAGE, COMBAT_HEALING = 1, 2, 16, 8, 128
ORIGIN_NONE, ORIGIN_CONDITION, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED = 0, 1, 2, 3, 4
CONST_ME_BLOCKHIT, CONST_ME_NONE = 9, 0
RETURNVALUE_NOERROR = 0
SKILL_LEVEL = 8
CONDITION_HASTE, CONDITION_PARAM_TICKS, CONDITION_PARAM_SPEED, CONDITION_PARALYZE = 1, 2, 3, 4
CONTAINER_POSITION = 0xFFFF
Chaos = {} -- the scripts skip chaos_constants.lua

local TYPES = {
	[2400] = {name = "magic sword", weaponType = WEAPON_SWORD, attack = 48, slot = 48},
	[2466] = {name = "golden armor", armor = 14, slot = SLOTP_ARMOR},
	[2195] = {name = "boots of haste", armor = 0, slot = SLOTP_FEET}
}
function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getId = function() return id end, getName = function() return t.name or "" end,
		isContainer = function() return false end, isStackable = function() return false end,
		getWeaponType = function() return t.weaponType or 0 end, getSlotPosition = function() return t.slot or 0 end,
		getArmor = function() return t.armor or 0 end, getAttack = function() return t.attack or 0 end,
		getDefense = function() return 0 end, getHitChance = function() return 0 end,
		getElementDamage = function() return 0 end, getAttackSpeed = function() return 0 end,
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
function Item:getCount() return 1 end
function Item:getName() return ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:getAttribute(k) return self.attrs[k] or (k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil) end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:removeAttribute(k) self.attrs[k] = nil end
function Item:getActionId() return 0 end

local events, callbacks, timers = {}, {}, {}
local function registry(kind)
	return function(name)
		local obj = {name = name, kind = kind}
		obj.register = function(self) events[name] = self return true end
		obj.type = function() end
		return obj
	end
end
CreatureEvent, GlobalEvent = registry("creature"), registry("global")
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
local function runTimers()
	local list = timers
	timers = {}
	local unp = unpack or table.unpack
	for _, t in ipairs(list) do t.fn(unp(t.args)) end
end

local clock = 1000000
os.mtime = function() return clock end

local hits = {}
local effects = {}
local handlerGuard
-- doTargetCombatHealth: records the hit and, like the engine, runs the target's onHealthChange events on it
function doTargetCombatHealth(cid, target, ctype, min, max, effect)
	hits[#hits + 1] = {from = cid, to = target, type = ctype, amount = -min}
	local t = Creature(target)
	if t and t.onDamage then t.onDamage(t, cid, -min, ctype) end
end

local Creature_ = {}
Creature_.__index = Creature_
local nextId, all = 1, {}
local function newCreature(kind, t)
	t = t or {}
	nextId = nextId + 1
	local c = setmetatable({cid = 0x10000000 + nextId, kind = kind, slots = {}, speed = 0, health = t.health or 1000,
		maxHealth = t.maxHealth or 1000, registered = {}, level = t.level or 100, storage = {}, pos = t.pos or {x = 100, y = 100, z = 7},
		conditions = {}, master = t.master}, Creature_)
	all[c.cid] = c
	return c
end
function Creature(id) return all[id] end
function Player(id) local c = all[id] return c and c.kind == "player" and c or nil end
function Creature_:getId() return self.cid end
function Creature_:isPlayer() return self.kind == "player" end
function Creature_:isMonster() return self.kind == "monster" end
function Creature_:getMaster() return self.master end
function Creature_:getSlotItem(slot) return self.slots[slot] end
function Creature_:getBaseSpeed() return 400 end
function Creature_:changeSpeed() end
function Creature_:getHealth() return self.health end
function Creature_:getMaxHealth() return self.maxHealth end
function Creature_:getLevel() return self.level end
function Creature_:addHealth(a, b) if type(a) == "string" then self.health = math.min(self.maxHealth, self.health + b) end end
function Creature_:addMana() end
function Creature_:registerEvent(name) self.registered[name] = true end
function Creature_:getStorageValue(k) return self.storage[k] or -1 end
function Creature_:setStorageValue(k, v) self.storage[k] = v end
function Creature_:addCondition(c) self.conditions[#self.conditions + 1] = c end
function Creature_:teleportTo(p) self.pos = {x = p.x, y = p.y, z = p.z} self.teleported = p end
function Creature_:getPosition()
	local pos = self.pos
	return setmetatable({sendMagicEffect = function(_, e) effects[#effects + 1] = e end}, {__index = pos})
end
function Creature_:getType() return {isBoss = function() return false end} end
function ChaosTierOf() return "normal" end
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end
Tile = function(pos)
	return {getGround = function() return true end, getCreatureCount = function() return 0 end,
		queryAdd = function() return RETURNVALUE_NOERROR end, hasFlag = function() return false end}
end
TILESTATE_PROTECTIONZONE = 1
Condition = function(kind)
	return {kind = kind, params = {}, setParameter = function(self, k, v) self.params[k] = v end,
		setFormula = function(self, a) self.formula = a end}
end

local online = {}
local nearby = {}
Game = {getPlayers = function() return online end, getSpectators = function(pos, multi, onlyPlayers, a, b, c, d)
	local out = {}
	for _, m in ipairs(nearby) do out[#out + 1] = m end
	return out
end}

dofile("data/scripts/chaos/item_mods.lua")
dofile("data/scripts/chaos/item_powers.lua")
local M, P = ChaosItemMods, ChaosPowers
local cache = ChaosItemModsCache
local CFG = P.config

-- ---------------------------------------------------------------- catalogue
eq(#P.keys, 12)
local sides = {prefix = 0, suffix = 0}
for _, def in ipairs(P.defs) do
	sides[def.side] = sides[def.side] + 1
	eq(#def.tiers, 8, def.key .. " has eight tiers")
	for t = 2, 8 do
		ok(def.tiers[t][2] >= def.tiers[t - 1][2], def.key .. ": higher tiers are not weaker")
	end
	ok(def.cap >= def.tiers[8][2], def.key .. ": the cap holds one top roll")
	ok(def.weight > 0 and def.kinds ~= nil, def.key)
	ok(M.byKey[def.key] == def, def.key .. " is a modifier of ChaosItemMods")
end
eq(sides.prefix, 7); eq(sides.suffix, 5)

-- ---------------------------------------------------------------- the maths
eq(P.roll(0, function() return 1 end), false)
eq(P.roll(100, function() return 10000 end), true)
eq(P.roll(5, function(a, b) return 500 end), true, "5% = rolls 1..500 of 10000")
eq(P.roll(5, function(a, b) return 501 end), false)
local cd = {}
eq(P.ready(cd, "a", 1000, 500), true); eq(P.ready(cd, "a", 1200, 500), false, "cooldown running")
eq(P.ready(cd, "a", 1500, 500), true, "over"); eq(P.ready(cd, "b", 1200, 500), true, "another power")
eq(P.blastDamage(10000, 100), 850, "25% of 10000 = 2500, capped at 50 + 8 x 100")
eq(P.blastDamage(1000, 500), 250, "25% of the health when below the cap")
eq(P.blastDamage(0, 10), 1, "at least 1")
eq(P.novaDamage(100), 540); eq(P.burnDamage(100), 660)
eq(P.share(1000, 30), 300); eq(P.share(1, 30), 1, "at least 1")
eq(P.burstHeal(2000), 80)
local dmg, to = P.lastBreath(100, 1000, 500, 30)
eq(dmg, 99, "the lethal hit leaves 1 health"); eq(to, 300, "then healed to 30%")
eq(P.lastBreath(600, 1000, 500, 30), nil, "not lethal")
eq(P.lastBreath(500, 1000, 500, 30) ~= nil, true, "exactly lethal")
eq(P.hardHit(200, 1000), true); eq(P.hardHit(199, 1000), false)
local rush = {}
eq(P.rushKill(rush, 0), 1); eq(P.rushKill(rush, 1000), 2)
for i = 1, 10 do P.rushKill(rush, 2000 + i) end
eq(rush.stacks, 5, "five stacks at most")
eq(P.rushStacks(rush, 2010 + 6000), 5, "still running at the edge")
eq(P.rushStacks(rush, 2010 + 6001), 0, "over after the window")
eq(P.rushKill(rush, 9000), 1, "the old stacks are gone")
eq(P.rushBonus(5, 4), 20); eq(P.rushBonus(9, 4), 20, "never above the stack limit")
eq(P.auraTick(100), 300, "per second x 3 s")

-- ---------------------------------------------------------------- a character with powers
local function equipPower(player, key, value, slot, itemId)
	local it = newItem(itemId or 2400)
	it:setCustomAttribute("rarity", 5)
	it:setCustomAttribute("chaos_mod_" .. key, value)
	player.slots[slot or CONST_SLOT_RIGHT] = it
	M.refresh(player, true)
end
local function newPlayer()
	local p = newCreature("player", {health = 1000, maxHealth = 1000, level = 100})
	online[#online + 1] = p
	events.ChaosItemModsLogin.onLogin(p)
	events.ChaosPowersLogin.onLogin(p)
	return p
end
local function monster(health, maxHealth)
	local m = newCreature("monster", {health = health or 1000, maxHealth = maxHealth or health or 1000})
	return m
end
local function reset()
	hits, effects, timers = {}, {}, {}
	nearby = {}
	clock = clock + 100000
end
local function dealtHit(player, target, amount, origin, critical)
	return events.ChaosPowersDealt.onHealthChange(target, player, amount, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE,
		origin or ORIGIN_MELEE, critical or false)
end
local function countHits(ctype)
	local n = 0
	for _, h in ipairs(hits) do if not ctype or h.type == ctype then n = n + 1 end end
	return n
end

-- the hit event is put on the monsters a character with a hit power attacks
local p = newPlayer()
equipPower(p, "crimsonburst", 10)
local victim = monster()
for _, cb in ipairs(callbacks.onTargetCombat) do cb(p, victim) end
eq(victim.registered.ChaosPowersDealt, true, "the dealt event goes on the target")
local plain = newPlayer()
local victim2 = monster()
for _, cb in ipairs(callbacks.onTargetCombat) do cb(plain, victim2) end
eq(victim2.registered.ChaosPowersDealt, nil, "not for a character without powers")
eq(p.registered.ChaosPowersTaken, true); eq(p.registered.ChaosPowersKill, true)

-- ---------------------------------------------------------------- Crimson Burst
reset()
p.health = 500
math.random = function(a, b) return 1 end -- every roll succeeds
dealtHit(p, victim, 50)
eq(p.health, 540, "4% of the maximum health")
dealtHit(p, victim, 50)
eq(p.health, 540, "the cooldown (2.5 s) holds")
clock = clock + 2600
dealtHit(p, victim, 50)
eq(p.health, 580, "after the cooldown again")
dealtHit(p, victim, 50, ORIGIN_CONDITION)
clock = clock + 5000
local before = p.health
dealtHit(p, victim, 50, ORIGIN_CONDITION)
eq(p.health, before, "damage over time does not proc")
-- no proc without luck
math.random = function(a, b) return b end
clock = clock + 5000
before = p.health
dealtHit(p, victim, 50)
eq(p.health, before, "a failed roll")
math.random = function(a, b) return 1 end

-- ---------------------------------------------------------------- Arc Lightning
reset()
local arcer = newPlayer()
equipPower(arcer, "arclightning", 10)
local main = monster(5000)
local others = {monster(), monster(), monster(), monster(), monster()}
nearby = {main, others[1], others[2], others[3], others[4], others[5]}
dealtHit(arcer, main, 1000)
eq(countHits(COMBAT_ENERGYDAMAGE), 3, "three other monsters")
for _, h in ipairs(hits) do
	eq(h.amount, 300, "30% of the hit"); eq(h.from, arcer:getId())
	ok(h.to ~= main:getId(), "never the target itself")
end
-- the arc does not start more arcs (guard) and the cooldown holds
local n = #hits
dealtHit(arcer, main, 1000)
eq(#hits, n, "cooldown 700 ms")
-- a summon of somebody is not hit
reset()
local pet = newCreature("monster", {master = arcer})
nearby = {main, pet}
clock = clock + 5000
dealtHit(arcer, main, 1000)
eq(countHits(), 0, "a summon is not an arc target")

-- ---------------------------------------------------------------- Echo Shot and Critical Echo
reset()
local ranger = newPlayer()
equipPower(ranger, "echoshot", 10)
local target = monster(5000)
dealtHit(ranger, target, 200, ORIGIN_MELEE)
runTimers()
eq(countHits(), 0, "a melee hit is not echoed")
dealtHit(ranger, target, 200, ORIGIN_RANGED)
eq(countHits(), 0, "the echo comes a moment later")
eq(timers[1].ms, CFG.echoshot.delayMs)
runTimers()
eq(countHits(), 1); eq(hits[1].amount, 120, "60% of the shot")
local nh = #hits
dealtHit(ranger, target, 200, ORIGIN_RANGED)
runTimers()
eq(#hits, nh, "cooldown 800 ms")
reset()
local critter = newPlayer()
equipPower(critter, "critecho", 10)
dealtHit(critter, target, 300, ORIGIN_MELEE, false)
runTimers()
eq(countHits(), 0, "only critical hits")
dealtHit(critter, target, 300, ORIGIN_MELEE, true)
runTimers()
eq(countHits(), 1); eq(hits[1].amount, 150, "half of the hit")
-- the echo itself does not echo (guard while it lands)
target.onDamage = function(t, cid, amount) dealtHit(critter, t, amount, ORIGIN_MELEE, true) end
clock = clock + 5000
hits = {}
dealtHit(critter, target, 300, ORIGIN_MELEE, true)
runTimers()
eq(countHits(), 1, "no echo of an echo")
target.onDamage = nil

-- ---------------------------------------------------------------- Bloodrush
reset()
local rusher = newPlayer()
equipPower(rusher, "bloodrush", 4)
local k = monster(100)
local _, _, _ = dealtHit(rusher, k, 1000)
local d1 = select(1, dealtHit(rusher, k, 1000))
eq(d1, 1000, "no stacks, no bonus")
for i = 1, 3 do
	events.ChaosPowersKill.onKill(rusher, monster())
end
eq(select(1, dealtHit(rusher, k, 1000)), 1120, "three stacks of 4%")
for i = 1, 6 do events.ChaosPowersKill.onKill(rusher, monster()) end
eq(select(1, dealtHit(rusher, k, 1000)), 1200, "five stacks at most: +20%")
clock = clock + 6500
eq(select(1, dealtHit(rusher, k, 1000)), 1000, "the stacks run out after six seconds")

-- ---------------------------------------------------------------- Death Blast and Shatter Splash
reset()
local blaster = newPlayer()
equipPower(blaster, "deathblast", 10)
local dead = monster(5000, 20000)
local a, b = monster(), monster()
nearby = {dead, a, b}
events.ChaosPowersKill.onKill(blaster, dead)
eq(countHits(COMBAT_FIREDAMAGE), 2, "fire on the two monsters around")
eq(hits[1].amount, 850, "25% of 20000 capped at 50 + 8 x level 100")
local nb = #hits
events.ChaosPowersKill.onKill(blaster, monster())
eq(#hits, nb, "cooldown 1.5 s")
-- explosion kills do not blast again (guard while the damage is dealt)
reset()
clock = clock + 10000
a.onDamage = function() events.ChaosPowersKill.onKill(blaster, a) end
nearby = {dead, a}
events.ChaosPowersKill.onKill(blaster, dead)
eq(countHits(), 1, "a kill by the explosion does not blast")
a.onDamage = nil
-- summons do not count as kills
reset()
clock = clock + 10000
events.ChaosPowersKill.onKill(blaster, newCreature("monster", {master = blaster}))
eq(countHits(), 0)

reset()
local splasher = newPlayer()
equipPower(splasher, "shattersplash", 40)
local brute = monster(100, 100)
nearby = {brute, a, b}
dealtHit(splasher, brute, 500) -- lethal: more than its health
events.ChaosPowersKill.onKill(splasher, brute)
eq(countHits(COMBAT_PHYSICALDAMAGE), 2, "the killing blow bursts onto the two around")
eq(hits[1].amount, 200, "40% of the killing blow")
-- a kill without a recorded blow (a condition, another player) does not splash
reset()
clock = clock + 10000
events.ChaosPowersKill.onKill(splasher, monster(10, 10))
eq(countHits(), 0)

-- ---------------------------------------------------------------- Hunter's Rush
reset()
local hunter = newPlayer()
equipPower(hunter, "hunterrush", 10, CONST_SLOT_FEET, 2195)
events.ChaosPowersKill.onKill(hunter, monster())
eq(#hunter.conditions, 1); eq(hunter.conditions[1].params[CONDITION_PARAM_SPEED], 40)
eq(hunter.conditions[1].params[CONDITION_PARAM_TICKS], 4000)
events.ChaosPowersKill.onKill(hunter, monster())
eq(#hunter.conditions, 1, "cooldown 8 s")

-- ---------------------------------------------------------------- Last Breath
reset()
local tank = newPlayer()
equipPower(tank, "lastbreath", 30, CONST_SLOT_ARMOR, 2466)
tank.health = 400
local d, _, s2 = events.ChaosPowersTaken.onHealthChange(tank, monster(), 900, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
eq(d, 399, "the lethal hit leaves 1 health"); eq(s2, 0)
eq(tank.storage[CFG.lastbreath.storage] ~= nil, true, "the time is kept in a player storage")
tank.health = 1
runTimers()
eq(tank.health, 300, "healed to 30% of the maximum")
-- again within 5 minutes: nothing
clock = clock + 1000
d = events.ChaosPowersTaken.onHealthChange(tank, monster(), 900, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
eq(d, 900, "once per five minutes (also after a relog: the storage)")
-- a hit that is not lethal is left alone
tank.storage[CFG.lastbreath.storage] = nil
tank.health = 800
d = events.ChaosPowersTaken.onHealthChange(tank, monster(), 100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
eq(d, 100)
-- after the cooldown it works again
tank.storage[CFG.lastbreath.storage] = os.time() - 301
tank.health = 50
d = events.ChaosPowersTaken.onHealthChange(tank, monster(), 100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
eq(d, 49)

-- ---------------------------------------------------------------- Ember Step
reset()
local stepper = newPlayer()
equipPower(stepper, "emberstep", 10, CONST_SLOT_FEET, 2195)
local foe = monster()
nearby = {foe}
events.ChaosPowersTaken.onHealthChange(stepper, foe, 50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
runTimers()
eq(stepper.teleported, nil, "a light hit does not blink")
events.ChaosPowersTaken.onHealthChange(stepper, foe, 300, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
eq(stepper.teleported, nil, "the blink comes after the hit")
runTimers()
ok(stepper.teleported ~= nil, "a hit of 30% blinks the character away")
ok(math.max(math.abs(stepper.teleported.x - 100), math.abs(stepper.teleported.y - 100)) >= 2
	and math.max(math.abs(stepper.teleported.x - 100), math.abs(stepper.teleported.y - 100)) <= CFG.emberstep.range, "within range")
eq(countHits(COMBAT_FIREDAMAGE), 1, "burns where it stood"); eq(hits[1].amount, 660)
stepper.teleported = nil
events.ChaosPowersTaken.onHealthChange(stepper, foe, 300, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
runTimers()
eq(stepper.teleported, nil, "cooldown 15 s")
-- a hit that kills is Last Breath's business, not a blink
reset()
stepper.teleported = nil
stepper.health = 100
events.ChaosPowersTaken.onHealthChange(stepper, foe, 300, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
runTimers()
eq(stepper.teleported, nil, "no blink on a lethal hit")

-- ---------------------------------------------------------------- Glacial Ward
reset()
local ward = newPlayer()
equipPower(ward, "frostward", 10, CONST_SLOT_ARMOR, 2466)
local brawler, other = monster(), monster()
nearby = {brawler, other}
M.onAvoid(ward, brawler, "dodge")
eq(countHits(COMBAT_ICEDAMAGE), 2, "an ice nova on the monsters around")
eq(hits[1].amount, 540, "40 + 5 x level 100")
eq(brawler.conditions[1].params[CONDITION_PARAM_TICKS], 3000, "slowed for three seconds")
eq(brawler.conditions[1].formula, -0.35, "by 35%")
n = #hits
M.onAvoid(ward, brawler, "block")
eq(#hits, n, "cooldown 4 s")
reset()
M.onAvoid(ward, nil, "dodge")
eq(countHits(), 0, "an attack without an attacker does not count")
-- through the real dodge: item_mods.lua calls the hook
reset()
nearby = {brawler, other}
equipPower(ward, "dodge", 100, CONST_SLOT_LEGS, 2466)
ward.slots[CONST_SLOT_LEGS] = ward.slots[CONST_SLOT_LEGS]
cache[ward:getId()].dodge = 100
local pd = events.ChaosItemModsTaken.onHealthChange(ward, brawler, 100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
eq(pd, 0, "dodged")
eq(countHits(COMBAT_ICEDAMAGE), 2, "the dodge started the nova")

-- ---------------------------------------------------------------- Smoldering Aura
reset()
local burner = newPlayer()
equipPower(burner, "smolderaura", 100, CONST_SLOT_ARMOR, 2466)
nearby = {monster(), monster(), monster(), monster(), monster(), monster(), monster(), monster()}
for i = 1, #online do online[i] = nil end
online[1] = burner
timers = {}
events.ChaosPowersStartup.onStartup()
timers[1].fn() -- the first tick
eq(countHits(COMBAT_FIREDAMAGE), CFG.smolderaura.targets, "at most six monsters per tick")
eq(hits[1].amount, 300, "100 per second x 3 s")
eq(timers[#timers].ms, CFG.smolderaura.tickMs, "the next tick is scheduled")

-- ---------------------------------------------------------------- logout
events.ChaosPowersLogout.onLogout(p)
eq(ChaosPowersState[p:getId()], nil, "state cleared")

print("powers_test: " .. checks .. " checks OK")
