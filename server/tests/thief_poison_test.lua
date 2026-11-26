-- Run from the server/ folder: luajit tests/thief_poison_test.lua (and lua5.3; CI runs both)
-- Poison Blades (thief_combat.lua onOffence, mock engine): the poison goes on the target for a melee hit AND for a ranged
-- weapon hit (bow, crossbow, thrown: ORIGIN_RANGED), by a spell strike (ORIGIN_SPELL) it does not; Blackblood Creed
-- poisons without the buff; a non-thief, zero damage and healing never poison.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

local events = {}
local function obj(name) local o = {} function o:register() events[name] = o end function o:interval() end return o end
function CreatureEvent(name) return obj(name) end
function GlobalEvent(name) return obj(name) end
local callbacks = {}
EventCallback = setmetatable({}, {__index = function(_, k) if k == "register" then return function() end end end,
	__newindex = function(_, k, v) callbacks[k] = callbacks[k] or {}; table.insert(callbacks[k], v) end})
function addEvent() end
ChaosSpell = {canAttack = function() return true end}
local added = {}
function Condition(t) local c = {type = t, p = {}} function c:setParameter(k, v) c.p[k] = v end function c:addDamage(a, b, d) c.dmg = {a, b, d} end return c end
local M = {} M.__index = M
function M:getId() return self.id end
function M:isPlayer() return self.player == true end
function M:isMonster() return self.player ~= true end
function M:getPlayer() return self.player and self or nil end
function M:getVocation() local v = self.voc return {getId = function() return v end} end
function M:getCondition(t, id, sub) return self.conds[sub] end
function M:addCondition(c) added[#added + 1] = {self.id, c} end
function M:registerEvent(name) self.events = self.events or {}; self.events[name] = true end
function M:getStorageValue() return -1 end
function M:setStorageValue() end
function M:getPosition() return {sendMagicEffect = function() end} end
function M:getSlotItem() return nil end
local function mk(o) return setmetatable({id = o.id, voc = o.voc, player = o.player, conds = {}, events = {}}, M) end
function Player() return nil end
dofile("data/scripts/chaos/thief_combat.lua")

local ev = events.ChaosThiefCombat
local sub = Chaos.classes.subId.poisonBlades
local function poisons(attacker, origin, dmg, ctype)
	added = {}
	ev.onHealthChange(mk{id = 50}, attacker, dmg or -100, ctype or COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, origin)
	return #added
end

local thief = mk{id = 1, voc = 11, player = true}
eq(poisons(thief, ORIGIN_MELEE), 0, "no buff, no poison")
eq(poisons(thief, ORIGIN_RANGED), 0, "no buff, no poison (ranged)")
thief.conds[sub] = true
eq(poisons(thief, ORIGIN_MELEE), 1, "melee")
eq(poisons(thief, ORIGIN_RANGED), 1, "bow / crossbow / thrown")
eq(poisons(thief, ORIGIN_SPELL), 0, "a spell hit is not a weapon hit")
eq(poisons(thief, ORIGIN_RANGED, 0), 0, "zero damage")
eq(poisons(thief, ORIGIN_RANGED, 50, COMBAT_HEALING), 0, "healing")
added = {}
ev.onHealthChange(mk{id = 50}, thief, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED)
eq(added[1][2].type, CONDITION_POISON)
eq(added[1][2].p[CONDITION_PARAM_OWNER], 1, "the thief owns the poison")
eq(added[1][2].dmg[1], Chaos.classes.poisonBlades.ticks)
eq(added[1][2].dmg[3] < 0, true, "negative tick")
-- a thief of the line's other classes
local ninja = mk{id = 2, voc = 12, player = true}
ninja.conds[sub] = true
eq(poisons(ninja, ORIGIN_RANGED), 1, "line class, ranged")
-- a non-thief with the buff condition
local knight = mk{id = 3, voc = 4, player = true}
knight.conds[sub] = true
eq(poisons(knight, ORIGIN_MELEE), 0, "not a thief")
eq(poisons(knight, ORIGIN_RANGED), 0, "not a thief (ranged)")
-- the buff is gone: no poison again
thief.conds[sub] = nil
eq(poisons(thief, ORIGIN_RANGED), 0, "buff ended")
-- Blackblood Creed: no buff needed
local real = ChaosClasses.weaponPoisons
eq(real(true, false, true), true) eq(real(false, true, true), false, "a spell hit never")

-- Blackblood Creed: EVERY attack poisons (auto attack, single target spell, area spell), once per target per hit
local ct = ChaosClassTree
local realHas = ct.has
local function withCreed(on, fn)
	ct.has = function(pl, key) if key == "ksBlackbloodCreed" then return on end return realHas(pl, key) end
	local ok, err = pcall(fn)
	ct.has = realHas
	if not ok then error(err, 0) end
end
local creedThief = mk{id = 7, voc = 11, player = true} -- no Poison Blades buff
withCreed(true, function()
	eq(poisons(creedThief, ORIGIN_MELEE), 1, "creed: auto attack")
	eq(poisons(creedThief, ORIGIN_RANGED), 1, "creed: ranged auto attack")
	eq(poisons(creedThief, ORIGIN_SPELL, 120, COMBAT_PHYSICALDAMAGE), 1, "creed: single target spell")
	eq(poisons(creedThief, ORIGIN_SPELL, 120, COMBAT_FIREDAMAGE), 1, "creed: elemental spell")
	-- an area spell hits three monsters: one poison on each
	added = {}
	for id = 60, 62 do
		ev.onHealthChange(mk{id = id}, creedThief, -80, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
	end
	eq(#added, 3, "creed: area spell, one poison per target")
	eq(added[1][1] ~= added[2][1], true, "different targets")
	eq(added[1][2].dmg[3], -ChaosClasses.poisonTick(80, ct.fx.ksBlackbloodCreed.poisonBonus, 11), "creed tick")
	-- no self-proc: the poison's tick, other damage over time, scripted strikes, healing, zero damage, self damage
	eq(poisons(creedThief, ORIGIN_CONDITION, 30, COMBAT_EARTHDAMAGE), 0, "the poison tick never poisons")
	eq(poisons(creedThief, ORIGIN_CONDITION, 30, COMBAT_FIREDAMAGE), 0, "another DoT never poisons")
	eq(poisons(creedThief, ORIGIN_NONE, 30), 0, "scripted / reflected damage never poisons")
	eq(poisons(creedThief, ORIGIN_SPELL, 50, COMBAT_HEALING), 0, "healing")
	eq(poisons(creedThief, ORIGIN_SPELL, 0), 0, "zero damage")
	added = {}
	ev.onHealthChange(creedThief, creedThief, -50, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
	eq(#added, 0, "own damage")
	eq(poisons(knight, ORIGIN_SPELL, 100), 0, "a non-thief never")
end)
withCreed(false, function()
	eq(poisons(creedThief, ORIGIN_SPELL, 120), 0, "without the keystone a spell does not poison")
	thief.conds[sub] = true
	eq(poisons(thief, ORIGIN_SPELL, 120), 0, "the Poison Blades buff alone: weapon hits only")
	thief.conds[sub] = nil
end)
-- V19 (seen in a client 2026-11-26): an area spell's hit on a monster the player never targeted. The engine's Lua
-- doTargetCombat never asks onTargetCombat, so ChaosThiefCombat is only on the attacked target; ChaosThiefPoison goes on
-- every monster at its spawn and gives the others their poison, once, and never on a monster that has the first event
local pev = events.ChaosThiefPoison
eq(pev ~= nil, true, "the spawn poison event exists")
local spawnHooks = callbacks.onSpawn or {}
eq(#spawnHooks >= 1, true, "an onSpawn callback")
local function spawned(id)
	local m = mk{id = id}
	m.events = {}
	for _, f in ipairs(spawnHooks) do f(m, nil, false, false) end
	return m
end
local function hitAll(list, attacker, origin, dmg, ctype)
	added = {}
	for _, m in ipairs(list) do
		-- the engine runs every event the monster carries
		if m.events.ChaosThiefCombat then
			ev.onHealthChange(m, attacker, dmg or -80, ctype or COMBAT_EARTHDAMAGE, 0, COMBAT_NONE, origin)
		end
		if m.events.ChaosThiefPoison then
			pev.onHealthChange(m, attacker, dmg or -80, ctype or COMBAT_EARTHDAMAGE, 0, COMBAT_NONE, origin)
		end
	end
	return #added
end
withCreed(true, function()
	local pack = {spawned(70), spawned(71), spawned(72)}
	eq(pack[1].events.ChaosThiefPoison, true, "registered at the spawn")
	eq(pack[1].events.ChaosThiefCombat, nil, "the main event waits for a target")
	eq(hitAll(pack, creedThief, ORIGIN_SPELL), 3, "creed: area spell on three untargeted monsters, three poisons")
	eq(hitAll(pack, creedThief, ORIGIN_MELEE), 3, "creed: a blade strike of an area spell")
	-- the thief targets the first one: the main event takes it over, still one poison each
	Chaos.registerOnce(pack[1], "ChaosThiefCombat")
	eq(hitAll(pack, creedThief, ORIGIN_SPELL), 3, "one poison per monster when one is the target")
	eq(added[1][1], 70, "the target's poison from the main event")
	eq(hitAll(pack, creedThief, ORIGIN_CONDITION, -30), 0, "the poison tick never poisons")
	eq(hitAll(pack, creedThief, ORIGIN_NONE), 0, "scripted damage never poisons")
	eq(hitAll(pack, knight, ORIGIN_SPELL), 0, "a non-thief never")
	local healed = hitAll({spawned(73)}, creedThief, ORIGIN_SPELL, 40, COMBAT_HEALING)
	eq(healed, 0, "healing never poisons")
end)
withCreed(false, function()
	eq(hitAll({spawned(74)}, creedThief, ORIGIN_SPELL), 0, "without the keystone an area spell does not poison")
	thief.conds[sub] = true
	eq(hitAll({spawned(75)}, thief, ORIGIN_MELEE), 1, "Poison Blades: a blade strike on an untargeted monster")
	eq(hitAll({spawned(76)}, thief, ORIGIN_SPELL), 0, "Poison Blades: a spell hit still never")
	thief.conds[sub] = nil
end)

local cp = ChaosClasses.creedPoisons
eq(cp(true, true), true) eq(cp(false, true), false) eq(cp(true, false), false)

print("thief_poison_test: OK")
