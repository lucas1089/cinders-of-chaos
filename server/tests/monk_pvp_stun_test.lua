-- Run from the server/ folder: luajit tests/monk_pvp_stun_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Covers the Iron Palm stun on players (docs/CLASSES.md "Monk"): the numbers (ChaosMonk.pvpStunFor: 0.5 s + 0.1 s per
-- chi, at most 1 s; half within the diminishing window), and the glue in monk_combat.lua against a mocked engine: a
-- landed Iron Palm stuns (movement block + no-move + CONDITION_PACIFIED, immunity and window timers, text, buff bar
-- pushed, a cast interrupted), the timer releases it on time, immunity refuses a second stun, the window halves the
-- next one, a dodged / lethal / non-Iron-Palm hit does not stun, another script's movement block is left alone, the
-- think fallback frees a stun whose timer was lost. Also the glue of Scarred Discipline (the Monk line keystone).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

dofile("data/scripts/chaos/monk_chi_core.lua")
local M = ChaosMonk
local ID = M.ids
local P = M.cfg.stun.pvp

-- ------------------------------------------------------------------ numbers
eq(M.pvpStunFor(1, false, false), 600, "1 chi: 0.6 s")
eq(M.pvpStunFor(5, false, false), 1000, "5 chi: 1 s")
eq(M.pvpStunFor(9, false, false), 1000, "never above 1 s")
eq(M.pvpStunFor(0, false, false), 0, "no chi, no stun")
eq(M.pvpStunFor(5, true, false), 0, "immune")
eq(M.pvpStunFor(5, false, true), 500, "within the window: half")
eq(M.pvpStunFor(1, false, true), P.minMs, "never below the minimum")
eq(P.immuneMs >= 5 * P.maxMs, true, "immunity is far longer than a stun: no chain-stuns")
eq(ID.storage.palmChi >= 7100800 and ID.storage.palmChi <= 7100809, true, "storage in the Monk range")
eq(ID.subId.stunDr >= 71030 and ID.subId.stunDr <= 71044, true, "sub id in the Monk range")
local subs = {}
for k, v in pairs(ID.subId) do
	if type(v) == "number" then
		eq(subs[v], nil, "sub id twice: " .. k); subs[v] = k
	end
end

-- ------------------------------------------------------------------ mocked engine
local events, scheduled, clock = {}, {}, 100000
M.now = function() return clock end
local function obj(store, name)
	local o = {}
	function o:register() if name then store[name] = o end end
	function o:interval() end
	function o:type() end
	return o
end
function CreatureEvent(name) return obj(events, name) end
function GlobalEvent(name) return obj(events, name) end
EventCallback = setmetatable({}, {__index = function(_, k) if k == "register" then return function() end end end,
	__newindex = function() end})
function addEvent(fn, ms, ...) scheduled[#scheduled + 1] = {fn = fn, ms = ms, args = {...}} end
local function runTimers()
	local list = scheduled
	scheduled = {}
	for _, e in ipairs(list) do
		e.fn((unpack or table.unpack)(e.args))
	end
end
function Condition(ctype, cid)
	local c = {type = ctype, id = cid or CONDITIONID_COMBAT, params = {}}
	function c:setParameter(k, v) self.params[k] = v end
	function c:setFormula() end
	return c
end
function Position(p) return p end

local C_mt = {}
C_mt.__index = C_mt
local all = {}
local function player(id, voc, name)
	local c = setmetatable({id = id, voc = voc, name = name, conds = {}, store = {}, health = 5000, said = {}, msgs = {},
		blocked = false, noMove = false, events = {}, fx = {}}, C_mt)
	all[id] = c
	return c
end
function C_mt:getId() return self.id end
function C_mt:getName() return self.name end
function C_mt:isPlayer() return true end
function C_mt:isMonster() return false end
function C_mt:getPlayer() return self end
function C_mt:getVocation() local v = self.voc; return {getId = function() return v end} end
function C_mt:getHealth() return self.health end
function C_mt:getStorageValue(k) return self.store[k] or -1 end
function C_mt:setStorageValue(k, v) self.store[k] = v end
local function key(t, id, sub) return t .. ":" .. (id or CONDITIONID_COMBAT) .. ":" .. (sub or 0) end
function C_mt:getCondition(t, id, sub) return self.conds[key(t, id, sub)] end
function C_mt:addCondition(c) self.conds[key(c.type, c.id, c.params[CONDITION_PARAM_SUBID])] = c end
function C_mt:removeCondition(t, id, sub) self.conds[key(t, id, sub)] = nil end
function C_mt:isMovementBlocked() return self.blocked end
function C_mt:setMovementBlocked(v) self.blocked = v end
function C_mt:canMove() return not self.noMove end
function C_mt:setNoMove(v) self.noMove = v end
function C_mt:registerEvent(name) self.events[name] = true end
function C_mt:unregisterEvent(name) self.events[name] = nil end
function C_mt:say(text) self.said[#self.said + 1] = text end
function C_mt:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
function C_mt:getPosition() local me = self; return {sendMagicEffect = function(_, e) me.fx[#me.fx + 1] = e end} end
function C_mt:getSlotItem() return nil end
function C_mt:getLevel() return 300 end
function C_mt:getEffectiveSkillLevel() return 100 end
function Player(id) return all[id] end

local pushed, interrupted = {}, {}
ChaosBuffs = {forget = function() end, nowMs = function() return clock end}
ChaosBuffBar = {watch = {[2] = {}}, update = function(p) pushed[#pushed + 1] = p:getId() end}
ChaosCasting = {interrupt = function(p, reason) interrupted[#interrupted + 1] = reason end}

dofile("data/scripts/chaos/monk_combat.lua")
local onHealth = events.ChaosMonkCombat.onHealthChange
local monk = player(1, ID.vocation.ironsage, "Sage")
local victim = player(2, 4, "Brann")
-- the attack lock: CONDITION_PACIFIED, default id, sub id 0 (the only one the engine checks), as long as the stun
local function pacified(p) local c = p:getCondition(CONDITION_PACIFIED, CONDITIONID_DEFAULT, 0); return c and c.params[CONDITION_PARAM_TICKS] end
local function stunned(p) return M.pvpStun[p:getId()] ~= nil and p.blocked end
local function palm(chi, dmg)
	monk.store[ID.storage.palmChi] = chi
	-- evasion only applies to Monk victims; the victim here is a Warrior
	return onHealth(victim, monk, dmg or -300, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
end

-- a landed Iron Palm at 5 chi
palm(5)
eq(pacified(victim), 1000, "pacified for the stun: no attacks, no attack spells")
eq(victim:getCondition(CONDITION_PACIFIED, CONDITIONID_COMBAT, 0), nil, "not the buff bar's Pacified row")
eq(victim.blocked and victim.noMove, true, "cannot move")
eq(M.pvpStunLeft(2, clock), 1000, "1 s")
eq(monk.store[ID.storage.palmChi], -1, "the chi is used once")
eq(victim:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, ID.subId.stunImmune).params[CONDITION_PARAM_TICKS],
	1000 + P.immuneMs, "immune until 6 s after the stun")
eq(victim.said[1], "Stunned!", "text over the victim"); eq(victim.fx[1], CONST_ME_STUN, "stun effect")
eq(victim.msgs[1], "You are stunned for 1.0 s by Sage.", "the victim is told")
eq(monk.msgs[1], "Brann is stunned for 1.0 s.", "the monk is told")
eq(pushed[#pushed], 2, "buff bar told at once"); eq(interrupted[1], "paralysed", "a cast is interrupted")
eq(victim.events.ChaosMonkStunThink, true, "think fallback registered")
eq(scheduled[1].ms, 1000, "release timer")
-- the timer frees it
clock = clock + 1000
runTimers()
eq(stunned(victim), false, "stun over"); eq(victim.blocked or victim.noMove, false, "can move again")
eq(M.pvpStun[2], nil, "state cleared"); eq(victim.events.ChaosMonkStunThink, nil, "think fallback removed")

-- immune: a second Iron Palm right after does nothing
victim:removeCondition(CONDITION_PACIFIED, CONDITIONID_DEFAULT, 0) -- (the engine ends it on time)
palm(5)
eq(stunned(victim), false, "immune: no chain-stun"); eq(pacified(victim), nil, "no attack lock either"); eq(monk.msgs[#monk.msgs], "Brann cannot be stunned again yet.")
-- after the immunity, inside the window: half as long
victim:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, ID.subId.stunImmune)
palm(5)
eq(M.pvpStunLeft(2, clock), 500, "diminished: 0.5 s"); eq(pacified(victim), 500, "the attack lock too")
clock = clock + 500; runTimers()
eq(stunned(victim), false, "released")
victim.conds = {}

-- no stun: no Iron Palm chi, a melee hit, a heal, a lethal hit, a fully absorbed hit
onHealth(victim, monk, -300, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(stunned(victim), false, "another Monk spell does not stun")
monk.store[ID.storage.palmChi] = 3
onHealth(victim, monk, -300, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(stunned(victim), false, "a melee hit does not stun")
monk.store[ID.storage.palmChi] = 3
onHealth(victim, monk, 300, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(stunned(victim), false, "a heal does not stun")
palm(3, -6000)
eq(stunned(victim), false, "a lethal hit does not stun")
palm(3, 0)
eq(stunned(victim), false, "a hit that does no damage does not stun")

-- another script's movement block stays when the stun ends
victim.blocked = true
palm(2)
eq(stunned(victim), true, "stunned"); eq(M.pvpStunLeft(2, clock), 700, "2 chi: 0.7 s")
clock = clock + 700; runTimers()
eq(victim.blocked, true, "a movement block from elsewhere is kept"); eq(victim.noMove, false, "ours is undone")
victim.blocked = false; victim.conds = {}

-- a lost timer: the think frees the stun once it is over
palm(1)
scheduled = {}
events.ChaosMonkStunThink.onThink(victim, 1000)
eq(stunned(victim), true, "not over yet")
clock = clock + 600
events.ChaosMonkStunThink.onThink(victim, 1000)
eq(stunned(victim), false, "freed by the think"); eq(victim.blocked, false)

-- logout forgets the state
victim.conds = {}
palm(1)
events.ChaosMonkLogout.onLogout(victim)
eq(M.pvpStun[2], nil, "logout clears")

-- Scarred Discipline (the Monk line's keystone in the main tree, class_tree.lua): no dodge, a hit taken gives a chi
-- (one every 2 s), 10% less damage taken while holding 3 chi or more
local CT = ChaosClassTree
local brawler = player(3, ID.vocation.monk, "Ash")
local hitter = player(4, 4, "Orc")
local realRandom = math.random
math.random = function() return 0 end -- every roll would dodge
local function hitMonk(dmg)
	return onHealth(brawler, hitter, dmg or -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
end
eq(hitMonk(), 0, "without the keystone a roll of 0 is a dodge")
CT.write(brawler, {ksScarredDiscipline = 1})
eq(M.getChi(brawler), 0)
eq(hitMonk(), -1000, "with it: no dodge, 0 chi: the full hit")
eq(M.getChi(brawler), 1, "the hit gave a chi")
eq(hitMonk(), -1000, "a second hit at once"); eq(M.getChi(brawler), 1, "no chi within 2 s")
clock = clock + 2000
M.setChi(brawler, 3)
eq(hitMonk(), -900, "3 chi: -10%"); eq(M.getChi(brawler), 4, "and a chi")
clock = clock + 2000
eq(onHealth(brawler, hitter, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), -900, "spells too (a creature's hit)")
eq(M.getChi(brawler), 5)
clock = clock + 2000
M.setChi(brawler, 0)
eq(onHealth(brawler, hitter, -1000, COMBAT_EARTHDAMAGE, 0, COMBAT_NONE, ORIGIN_CONDITION), -1000, "a poison tick: nothing")
eq(M.getChi(brawler), 0, "and no chi")
math.random = realRandom

print("monk pvp stun tests OK")
