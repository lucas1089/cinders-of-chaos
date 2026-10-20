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
local pendingCb
EventCallback = setmetatable({}, {__index = function(_, k) if k == "register" then return function() end end end,
	__newindex = function(_, k, v) pendingCb = {k, v} end})
function addEvent() end
ChaosSpell = {canAttack = function() return true end}
local added = {}
function Condition(t) local c = {type = t, p = {}} function c:setParameter(k, v) c.p[k] = v end function c:addDamage(a, b, d) c.dmg = {a, b, d} end return c end
local M = {} M.__index = M
function M:getId() return self.id end
function M:isPlayer() return self.player == true end
function M:getPlayer() return self.player and self or nil end
function M:getVocation() local v = self.voc return {getId = function() return v end} end
function M:getCondition(t, id, sub) return self.conds[sub] end
function M:addCondition(c) added[#added + 1] = {self.id, c} end
function M:registerEvent() end
function M:getStorageValue() return -1 end
function M:setStorageValue() end
function M:getPosition() return {sendMagicEffect = function() end} end
function M:getSlotItem() return nil end
local function mk(o) return setmetatable({id = o.id, voc = o.voc, player = o.player, conds = {}}, M) end
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

print("thief_poison_test: OK")
