-- Run from the server/ folder: luajit tests/energy_shield_test.lua (and lua5.3; CI runs both)
-- Energy shield (engine patch 0015, server/README.md "Energy shield"): data/lib/chaos_energy_shield.lua (the three item
-- modifiers, the maximum, the recharge the engine does, the lethal-hit helper) and its glue in
-- data/scripts/chaos/item_mods.lua (the equipped items' totals set the maximum and the recharge; reflect counts a hit on
-- the shield) against a mocked engine; the lethal-hit checks of Last Breath, the arena, the trials and the tutorial with
-- the shield counted.

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
	[2466] = {name = "golden armor", armor = 14, slot = SLOTP_ARMOR},
	[2195] = {name = "boots of haste", armor = 0, slot = SLOTP_FEET},
	[2477] = {name = "knight legs", armor = 8, slot = SLOTP_LEGS},
	[2171] = {name = "platinum amulet", armor = 2, slot = SLOTP_NECKLACE},
	[2123] = {name = "ring of the sky", slot = SLOTP_RING},
	[2471] = {name = "golden helmet", armor = 12, slot = SLOTP_HEAD},
	[2514] = {name = "mastermind shield", weaponType = WEAPON_SHIELD, defense = 37, slot = 48}
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

local events, callbacks, timers = {}, {}, {}
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
local hits = {}
function doTargetCombatHealth(cid, target, ctype, min, max, effect)
	hits[#hits + 1] = {from = cid, to = target, type = ctype, min = min}
end

-- a creature; players carry the engine's energy shield methods (patch 0015), monsters do not
local Creature = {}
Creature.__index = Creature
local Player = setmetatable({}, {__index = Creature})
Player.__index = Player
local nextId = 1
local function newCreature(kind, t)
	t = t or {}
	nextId = nextId + 1
	return setmetatable({cid = 0x10000000 + nextId, kind = kind, slots = {}, speed = 0, baseSpeed = 400,
		health = t.health or 1000, maxHealth = t.maxHealth or 100000, mana = 0, registered = {}, tier = "normal",
		es = 0, esMax = 0, esRecharge = 200, esCalls = 0}, kind == "player" and Player or Creature)
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
function Creature:addHealth() end
function Creature:addMana(v) self.mana = self.mana + v end
function Creature:registerEvent(name) self.registered[name] = true end
function Creature:getPosition() return {sendMagicEffect = function() end} end
function Creature:getType() return {isBoss = function() return false end} end
function ChaosTierOf(c) return c.tier end
-- the engine: setEnergyShield clamps to 0 .. max, setMaxEnergyShield lowers the current value
function Player:getEnergyShield() return self.es end
function Player:setEnergyShield(v) self.es = math.max(0, math.min(v, self.esMax)) return true end
function Player:getMaxEnergyShield() return self.esMax end
function Player:setMaxEnergyShield(v)
	self.esCalls = self.esCalls + 1
	self.esMax = math.max(0, v)
	self.es = math.min(self.es, self.esMax)
	return true
end
function Player:getEnergyShieldRecharge() return self.esRecharge end
function Player:setEnergyShieldRecharge(v) self.esRecharge = v return true end

local online = {}
Game = {getPlayers = function() return online end}

dofile("data/scripts/chaos/item_mods.lua")
local M = ChaosItemMods
local E = ChaosEnergyShield
ok(E and E.keys, "chaos_item_mods.lua loads chaos_energy_shield.lua")

-- ---------------------------------------------------------------- catalogue
eq(#E.keys, 3, "three modifiers")
for _, key in ipairs({"energyshield", "energyshieldpct", "esrecharge"}) do
	local def = M.byKey[key]
	ok(def, key .. " in ChaosItemMods")
	eq(#def.tiers, 8, key .. ": T1 .. T8")
	ok(def.power ~= true, key .. " is no legendary power")
	for _, kind in ipairs({"armor", "shield", "helmet", "jewel"}) do
		eq(M.allowed(def, kind), true, key .. " rolls on " .. kind)
	end
	for _, kind in ipairs({"weapon", "boots", "legs", "other"}) do
		eq(M.allowed(def, kind), false, key .. " not on " .. kind)
	end
	assert(def.tiers[8][2] <= def.cap, key .. ": one item never beats the cap")
	local prev = 0
	for _, r in ipairs(def.tiers) do
		ok(r[1] <= r[2] and r[1] >= prev, key .. ": ranges grow")
		prev = r[1]
	end
end
eq(M.byKey.energyshield.side, "prefix")
eq(M.byKey.energyshieldpct.side, "prefix")
eq(M.byKey.esrecharge.side, "suffix")
eq(M.text("energyshield", 120), "Maximum Energy Shield +120")
eq(M.text("energyshieldpct", 12), "Maximum Energy Shield +12%")
eq(M.text("esrecharge", 30), "Faster Energy Shield Recharge +30%")
-- the kinds of real items: an armour, a helmet, an amulet and a shield can get them, a weapon or boots never
eq(M.allowed(M.byKey.energyshield, M.kindOf(newItem(2466))), true, "armour")
eq(M.allowed(M.byKey.energyshield, M.kindOf(newItem(2471))), true, "helmet")
eq(M.allowed(M.byKey.energyshield, M.kindOf(newItem(2171))), true, "amulet")
eq(M.allowed(M.byKey.energyshield, M.kindOf(newItem(2514))), true, "shield")
eq(M.allowed(M.byKey.energyshield, M.kindOf(newItem(2400))), false, "not on a weapon")
eq(M.allowed(M.byKey.energyshield, M.kindOf(newItem(2195))), false, "not on boots")

-- ---------------------------------------------------------------- maths
eq(E.maximum({}), 0, "no modifier, no shield")
eq(E.maximum({energyshield = 400}), 400)
eq(E.maximum({energyshield = 400, energyshieldpct = 25}), 500, "the percent raises the flat amount")
eq(E.maximum({energyshieldpct = 40}), 0, "a percent alone gives nothing")
eq(E.rechargePerMille({}), 200, "20% per second")
eq(E.rechargePerMille({esrecharge = 50}), 300, "+50% faster: 30% per second")
eq(E.rechargePerMille({esrecharge = 100}), 400, "the cap of the modifier: 40% per second")
eq(E.fullAfter(200), 5, "empty to full in 5 s at 20%")

-- the engine's recharge (Player::rechargeEnergyShield), think every 1000 ms, hit at t = 0, delay 2000 ms
do
	local cur, at, timeline = 0, 0, {}
	for t = 1000, 8000, 1000 do
		cur = E.recharge(cur, 1000, 200, t, 1000, 2000)
		timeline[#timeline + 1] = cur
		at = t
	end
	eq(table.concat(timeline, ","), "0,0,200,400,600,800,1000,1000", "2 s delay, then 20% of 1000 per second")
	eq(E.recharge(0, 1000, 200, 2500, 1000, 2000), 100, "only the part of the think after the delay")
	eq(E.recharge(990, 1000, 200, 9000, 1000, 2000), 1000, "never above the maximum")
	eq(E.recharge(0, 3, 200, 9000, 1000, 2000), 1, "at least 1 per think")
	eq(E.recharge(50, 0, 200, 9000, 1000, 2000), 0, "no maximum, no shield")
	ok(at == 8000)
end

-- the lethal-hit helper: health + shield for players, health for monsters (and an engine without the patch)
local player = newCreature("player", {health = 500})
player.esMax, player.es = 300, 300
eq(E.current(player), 300)
eq(E.effectiveHealth(player), 800)
local monster = newCreature("monster", {health = 900})
eq(E.current(monster), 0)
eq(E.effectiveHealth(monster), 900)

-- ---------------------------------------------------------------- on the character (item_mods.lua)
player.esMax, player.es = 0, 0
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
eq(player.esMax, 0, "no shield items")
eq(player.esRecharge, 200)
local helmet, amulet, armor = newItem(2471), newItem(2171), newItem(2466)
M.set(helmet, "energyshield", 150)
M.set(amulet, "energyshield", 100)
M.set(amulet, "energyshieldpct", 20)
M.set(armor, "esrecharge", 25)
equip(helmet, CONST_SLOT_HEAD)
eq(player.esMax, 150, "helmet +150")
equip(amulet, CONST_SLOT_NECKLACE)
eq(player.esMax, 300, "(150 + 100) x 1.2")
equip(armor, CONST_SLOT_ARMOR)
eq(player.esRecharge, 250, "+25% faster: 25% per second")
player.es = 300
local calls = player.esCalls
events.ChaosItemModsStartup.onStartup()
for _, timer in ipairs(timers) do
	if timer.ms == 3000 then
		timer.fn()
		break
	end
end
eq(player.esCalls, calls, "the periodic check sends nothing when the items did not change")
unequip(CONST_SLOT_NECKLACE)
eq(player.esMax, 150, "amulet off")
eq(player.es, 150, "the current value follows the lower maximum")
-- a shield on the hand (weapon slot) counts, boots never carry it
local shield = newItem(2514)
M.set(shield, "energyshield", 50)
equip(shield, CONST_SLOT_LEFT)
eq(player.esMax, 200, "shield in the hand")
unequip(CONST_SLOT_LEFT)
unequip(CONST_SLOT_HEAD)
unequip(CONST_SLOT_ARMOR)
eq(player.esMax, 0, "everything off")
eq(player.esRecharge, 200, "recharge back to the base")

-- reflect: a hit that lands on the shield is reflected too (the shield takes it after this event)
local refl = newItem(2466)
M.set(refl, "reflect", 10)
M.set(refl, "energyshield", 400)
equip(refl, CONST_SLOT_ARMOR)
player.health, player.es = 100, 400
local realRandom = math.random
math.random = function(a, b) return b end -- no dodge / block
hits = {}
events.ChaosItemModsTaken.onHealthChange(player, monster, 450, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(hits[1] and hits[1].min, -45, "10% of 450: 100 health + 400 shield take it all")
hits = {}
player.es = 0
events.ChaosItemModsTaken.onHealthChange(player, monster, 450, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(hits[1] and hits[1].min, -10, "no shield: only the 100 health that is there")
math.random = realRandom

-- ---------------------------------------------------------------- lethal-hit checks count the shield
-- Last Breath (chaos_powers.lua) gets health + shield from item_powers.lua
local P = ChaosPowers
eq(P.lastBreath(100 + 400, 10000, 450, 30), nil, "450 on 100 health + 400 shield is not lethal")
local dmg = P.lastBreath(100 + 400, 10000, 600, 30)
eq(dmg, 499, "lethal: the shield takes 400 of 499, the health 99, 1 left")
-- the scripts pass health + the engine's shield (patch 0015) to their catch functions
local function grep(path, pattern)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s:find(pattern, 1, true) ~= nil
end
ok(grep("data/scripts/chaos/item_powers.lua", "P.lastBreath(creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0)"), "Last Breath")
ok(grep("data/scripts/chaos/arena.lua", "A.catchDamage(creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0)"), "arena")
ok(grep("data/scripts/chaos/ascension_quest.lua", "Q.catchDamage(creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0)"), "ascension trial")
ok(grep("data/scripts/chaos/trials_effects.lua", "player:getHealth() + (player.getEnergyShield and player:getEnergyShield() or 0)"), "trials last stand")
ok(grep("data/scripts/chaos/newplayer_tutorial.lua", "creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0)"), "tutorial island")
-- arena_core.lua's catch with health + shield keeps exactly 1 health once the shield took its part
dofile("data/scripts/chaos/arena_core.lua")
local A = ChaosArenaCore
do
	local p, s, caught = A.catchDamage(100 + 400, 300, 0)
	eq(caught, false, "300 on 100 + 400 is no defeat")
	p, s, caught = A.catchDamage(100 + 400, 900, 50)
	eq(caught, true)
	eq(p + s, 499, "cut to 499: 400 to the shield, 99 to the health")
end

-- the opcode is free and named once
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
eq(ChaosOpcodes.energyShield, 224)
local used = {}
for name, op in pairs(ChaosOpcodes) do
	ok(not used[op], "opcode " .. op .. " used twice (" .. name .. ", " .. tostring(used[op]) .. ")")
	used[op] = name
end

-- the engine patches' defaults match the scripts (opcode, delay; patch 0016's percent armour keys)
local function read(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end
local p15 = read("src-patches/0015-energy-shield.patch")
ok(p15:find('"energyShieldOpcode", ' .. ChaosOpcodes.energyShield .. ')', 1, true), "the engine's default opcode is ChaosOpcodes.energyShield")
ok(p15:find('"energyShieldRechargeDelay", 2000)', 1, true), "2 s recharge delay")
ok(p15:find('uint32_t energyShieldRecharge = ' .. E.config.basePerMille .. ';', 1, true), "the engine's base recharge is the script's")
local p16 = read("src-patches/0016-percent-armour.patch")
ok(p16:find('"armorPercent", true)', 1, true), "percent armour on by default")
ok(p16:find('"armorPercentConstant", 250)', 1, true), "K = 250")
ok(p16:find('"armorPercentMax", 80)', 1, true), "cap 80%")

-- after a reconnect the client sends "hello" on the shield opcode and gets the engine's text again (live check of 128)
local shielded = {getEnergyShield = function() return 596 end, getMaxEnergyShield = function() return 900 end}
eq(E.helloAnswer(shielded, "hello"), "es:596:900", "hello: the engine's text")
eq(E.helloAnswer(shielded, "es:1:1"), nil, "hello: nothing for another request")
eq(E.helloAnswer({}, "hello"), nil, "hello: nothing without the engine API")
local events = {}
local realCreatureEvent = CreatureEvent
CreatureEvent = function(name)
	local ev = {name = name}
	function ev:type(t) self.kind = t end
	function ev:register() events[name] = self end
	return ev
end
dofile("data/scripts/chaos/energy_shield.lua")
CreatureEvent = realCreatureEvent
local registered, sent = {}, {}
local client = {
	registerEvent = function(_, name) registered[#registered + 1] = name end,
	sendExtendedOpcode = function(_, op, text) sent[#sent + 1] = op .. " " .. text end,
	getEnergyShield = function() return 0 end,
	getMaxEnergyShield = function() return 0 end
}
eq(events.ChaosEnergyShieldLogin.onLogin(client), true, "login goes on")
eq(registered[1], "ChaosEnergyShieldOpcode", "login registers the opcode handler")
eq(events.ChaosEnergyShieldOpcode.kind, "extendedopcode", "an extended opcode event")
events.ChaosEnergyShieldOpcode.onExtendedOpcode(client, 225, "hello")
eq(#sent, 0, "another opcode: nothing")
events.ChaosEnergyShieldOpcode.onExtendedOpcode(client, ChaosOpcodes.energyShield, "hello")
eq(sent[1], ChaosOpcodes.energyShield .. " es:0:0", "hello: max 0 is sent too, so a bar left from before hides")

print("energy_shield_test: " .. checks .. " checks OK")
