-- Run from the server/ folder: luajit tests/fist_sync_test.lua && lua5.3 tests/fist_sync_test.lua (CI runs both)
-- O505: a Monk's bare-fist hit with and without engine patch 0091 (Player:setFistAttack). The numbers (ChaosMonk.enginePush,
-- pushCorrection, ChaosArchetypesCore.openHandPush: the engine rolls the Monk's fist, the scripts only correct a stale push), the
-- capability test, fist_sync.lua (what it pushes, when, to whom, dropped at logout) and the glue in monk_combat.lua against a mocked
-- engine: on a stock engine the hit is scaled by the old factor, on an engine with the patch by 1 (the hit already has the size), and
-- the two end at the same damage; the monster layer measures the armour on the scaled size either way (ChaosMonk.fistUnits).
local checks, fails = 0, 0
local function ok(c, m)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. (m or ""))
	end
end
local function eq(a, b, m) ok(a == b, (m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b, tol, m) ok(math.abs(a - b) <= tol, (m or "") .. ": " .. tostring(a) .. " vs " .. tostring(b)) end

-- the engine's constants: any unknown NAME_LIKE_THIS is a number of its own (as tests/monk_pvp_stun_test.lua)
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/monk_chi_core.lua")
dofile("data/scripts/chaos/archetypes_core.lua")
local M, A = ChaosMonk, ChaosArchetypesCore
local ID = M.ids

-- ---------------------------------------------------------------- the capability is the method
local realPlayer = rawget(_G, "Player")
Player = nil
eq(M.engineFist(), false, "no Player table: no capability")
Player = {}
eq(M.engineFist(), false, "a Player table without setFistAttack: no capability")
Player = {setFistAttack = function() end}
eq(M.engineFist(), true, "Player.setFistAttack is the capability")
Player = {setFistAttack = "nope"}
eq(M.engineFist(), false, "only a function counts")

-- ---------------------------------------------------------------- the numbers
-- what the engine rolls with the pushed pair is what the old factor made of the stock hit: the same expected maximum
for _, level in ipairs({8, 20, 100, 300, 500, 1000, 2000}) do
	for _, voc in ipairs({ID.vocation.monk, ID.vocation.shadowfist, ID.vocation.ironsage}) do
		for _, skill in ipairs({10, 70, 135}) do
			for _, af in ipairs({1.0, 1.2, 2.0}) do
				local a, m = M.enginePush(voc, level, 0)
				local pushed = M.maxWeaponDamage(level, skill, a, af) * m
				local old = M.maxWeaponDamage(level, skill, 7, af) * M.unarmedFactor(voc, level, skill, 0, af)
				near(pushed, old, math.max(0.01, old * 0.001), "push = old factor: voc " .. voc .. " level " .. level .. " skill " .. skill)
			end
		end
	end
end
local a, m = M.enginePush(ID.vocation.monk, 100, 0)
near(a, M.fistAttack(100, 0), 1e-9, "the pushed attack is the fist attack of the level")
eq(m, 1.2, "the Monk's meleeDamage is the multiplier")
eq(select(2, M.enginePush(ID.vocation.ironsage, 100, 0)), 1.1, "the Iron Sage's meleeDamage")
a = M.enginePush(ID.vocation.monk, 100, 500)
eq(a, 500, "a fist weapon of attack 500 counts when it is higher")
-- the correction: nothing when the push is right, the ratio when it is stale
eq(M.pushCorrection(100, 70, 1.0, 42.5, 1.2, 42.5, 1.2), 1, "a right push needs no correction")
eq(M.pushCorrection(100, 70, 1.0, 42.5, 1.2, 42.501, 1.2), 1, "under 0.2% is none")
local f = M.pushCorrection(100, 70, 1.0, 42.5, 1.2, 80, 1.2)
ok(f > 1.5 and f < 2, "a fist weapon of 80 picked up after the push: the hit is lifted (" .. f .. ")")
ok(M.pushCorrection(100, 70, 1.0, 80, 1.2, 42.5, 1.2) < 1, "a fist weapon put down: the hit is cut")
eq(M.pushCorrection(100, 70, 1.0, 0, 1, 42.5, 1.2) > 1, true, "a push of nothing (attack 0) is read as a tiny hit, never divided by 0")
eq(M.pushCorrection(0, 0, 1.0, 0, 1, 0, 1), 1, "no hit at all: 1")

-- Open Hand Creed: the pair makes the engine's maximum (its own fist skill) the maximum openHandFactor wants (the better skill)
local o = ChaosArchetypesCore.cfg and nil
for _, level in ipairs({20, 100, 500, 1000}) do
	for _, keystone in ipairs({true, false}) do
		local unique = not keystone
		local fist, best, af = 40, 120, 1.0
		local attack, mult = A.openHandPush(level, fist, best, af, keystone, unique)
		ok(attack and mult, "open hand push exists at level " .. level)
		local want = A.openHandFactor(level, fist, best, af, keystone, unique) * A.maxWeaponDamage(level, fist, 7, af)
		near(A.maxWeaponDamage(level, fist, attack, af) * mult, want, want * 0.001, "open hand: pushed maximum = wanted maximum, level " .. level)
	end
end
eq(A.openHandPush(100, 40, 120, 1.0, false, false), nil, "neither the keystone nor the unique: nothing to push")

-- ---------------------------------------------------------------- the mocked engine
local events, clock = {}, 100000
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
local callbacks = {}
EventCallback = setmetatable({}, {__index = function(_, k) if k == "register" then return function() end end end,
	__newindex = function(_, k, v) callbacks[k] = v end})
function addEvent() end
function Condition(ctype, cid) return {type = ctype, id = cid, params = {}, setParameter = function() end, setFormula = function() end} end

local C_mt = {}
C_mt.__index = C_mt
local all = {}
local function creature(id, opts)
	local c = setmetatable({id = id, voc = opts.voc or 4, name = opts.name or ("c" .. id), isP = opts.player ~= false, level = opts.level or 300,
		skill = opts.skill or 100, mode = opts.mode or 1, pushes = {}, events = {}, store = {}, slots = opts.slots or {}}, C_mt)
	all[id] = c
	return c
end
function C_mt:getId() return self.id end
function C_mt:getName() return self.name end
function C_mt:isPlayer() return self.isP end
function C_mt:isMonster() return not self.isP end
function C_mt:getPlayer() return self.isP and self or nil end
function C_mt:getVocation() local v = self.voc; return {getId = function() return v end} end
function C_mt:getLevel() return self.level end
function C_mt:getEffectiveSkillLevel() return self.skill end
function C_mt:getFightMode() return self.mode end
function C_mt:getHealth() return 5000 end
function C_mt:getStorageValue(k) return self.store[k] or -1 end
function C_mt:setStorageValue(k, v) self.store[k] = v end
function C_mt:getCondition() return nil end
function C_mt:addCondition() end
function C_mt:removeCondition() end
function C_mt:registerEvent(n) self.events[n] = true end
function C_mt:unregisterEvent(n) self.events[n] = nil end
function C_mt:getPosition() return {sendMagicEffect = function() end} end
function C_mt:getSlotItem(slot) return self.slots[slot] end
function C_mt:setFistAttack(a, m) self.pushes[#self.pushes + 1] = {a, m}; self.engine = {a, m}; return true end
function C_mt:say() end
function C_mt:sendTextMessage() end
Player = setmetatable({setFistAttack = C_mt.setFistAttack}, {__call = function(_, id) return all[id] end})
ChaosBuffs = {forget = function() end, nowMs = function() return clock end}
ChaosBuffBar = {watch = {}, update = function() end}
ChaosCasting = {interrupt = function() end}

dofile("data/scripts/chaos/monk_combat.lua")
dofile("data/scripts/chaos/fist_sync.lua")
local FS = ChaosFistSync
local onHealth = events.ChaosMonkCombat.onHealthChange
local WP = ChaosWeaponPower
local function hit(monk, monster, amount)
	local p = onHealth(monster, monk, amount, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	return p
end
local monster = creature(100, {player = false})

-- a Monk (level 300, skill 100) with bare hands on an engine WITH the patch
local monk = creature(1, {voc = ID.vocation.monk})
ok(FS.capable(), "the engine has the capability")
eq(FS.pushed[1], nil, "nothing pushed before the first target")
callbacks.onTargetCombat(monk, monster)
local aWant, mWant = M.enginePush(ID.vocation.monk, 300, 0)
ok(FS.pushed[1] ~= nil and #monk.pushes == 1, "the first target pushes the pair")
near(monk.pushes[1][1], aWant, 1e-9, "pushed attack"); eq(monk.pushes[1][2], mWant, "pushed multiplier")
callbacks.onTargetCombat(monk, monster)
eq(#monk.pushes, 1, "a second attack with the same numbers pushes nothing")
local capHit = hit(monk, monster, -40)
-- the same Monk on a stock engine (the capability removed): the old factor
Player = {}
local stockMonk = creature(2, {voc = ID.vocation.monk})
eq(FS.capable(), false, "no capability on the stock engine")
callbacks.onTargetCombat(stockMonk, monster)
eq(#stockMonk.pushes, 0, "a stock engine is never pushed to")
local stockHit = hit(stockMonk, monster, -40)
local factor = M.unarmedFactor(ID.vocation.monk, 300, 100, 0, 1.0)
ok(factor > 4, "the stock hit is scaled by a factor above 4 (" .. factor .. ")")
near(math.abs(stockHit) / math.abs(capHit), factor, factor * 0.03, "the stock engine scales the hit it rolled by the factor; the patched one does not")
-- both ended at the same damage when each engine rolled its own hit: stock rolls 40, patched rolls 40 x factor
local capHit2 = hit(monk, monster, -math.floor(40 * factor + 0.5)) -- (the patched engine rolled the bigger hit)
Player = {setFistAttack = C_mt.setFistAttack}
local capHit3 = hit(monk, monster, -math.floor(40 * factor + 0.5))
near(math.abs(capHit3), math.abs(stockHit), math.abs(stockHit) * 0.03, "the patched engine's bigger hit ends at the stock engine's scaled hit")

-- the layer's units: 1 with the push, the factor without
eq(M.fistUnits(monk), 1, "fistUnits: 1 once the engine rolls the Monk's fist")
Player = {}
near(M.fistUnits(stockMonk), factor, 1e-9, "fistUnits: the old factor on a stock engine")
Player = {setFistAttack = C_mt.setFistAttack}
local warrior = creature(3, {voc = 4})
eq(M.fistUnits(warrior), nil, "fistUnits: nil for a class with no fist rule")
local armed = creature(4, {voc = ID.vocation.monk, slots = {[CONST_SLOT_LEFT] = {getId = function() return 2400 end}}})
ItemType = function() return {getWeaponType = function() return WEAPON_SWORD end} end
eq(M.fistUnits(armed), nil, "fistUnits: nil with a weapon in the hands")
callbacks.onTargetCombat(armed, monster)
eq(#armed.pushes, 0, "no push with a weapon in the hands")
ItemType = nil

-- a stale push: a level up since the last attack is corrected on the hit, and pushed for the next swing
monk.level = 600
local before = #monk.pushes
local up = hit(monk, monster, -40)
local a600, m600 = M.enginePush(ID.vocation.monk, 600, 0)
local right = creature(6, {voc = ID.vocation.monk, level = 600}) -- the same Monk with a push that was right for level 600
callbacks.onTargetCombat(right, monster)
near(math.abs(up) / math.abs(hit(right, monster, -40)), M.pushCorrection(600, 100, 1.0, aWant, mWant, a600, m600), 0.05,
	"a level up is corrected on the hit (against a Monk whose push was right)")
ok(#monk.pushes == before + 1, "and the new pair is pushed after it")
near(monk.pushes[#monk.pushes][1], select(1, M.enginePush(ID.vocation.monk, 600, 0)), 1e-9, "the new attack")

-- the first swing on a patched engine before any push (the engine rolled attack 7): the old factor, then a push for the next
local fresh = creature(5, {voc = ID.vocation.monk})
local freshHit = hit(fresh, monster, -40)
near(math.abs(freshHit), math.abs(stockHit), math.abs(stockHit) * 0.03, "an unpushed first swing is scaled by the old factor")
eq(#fresh.pushes, 1, "and the pair is pushed for the next swing")

-- logout forgets
events.ChaosFistSyncLogout.onLogout(monk)
eq(FS.pushed[1], nil, "logout drops the pushed pair")
events.ChaosFistSyncLogin.onLogin(monk)
eq(monk.events.ChaosFistSyncLogout, true, "login registers the logout event")

-- non-Monk with no rule is never pushed
callbacks.onTargetCombat(warrior, monster)
eq(#warrior.pushes, 0, "a Warrior is never pushed to")
-- a monster attacking never pushes
callbacks.onTargetCombat(monster, warrior)
eq(#monster.pushes, 0, "a monster is not pushed to")

Player = realPlayer
if fails > 0 then
	error("fist_sync_test: " .. fails .. " failure(s)")
end
print("fist_sync_test: " .. checks .. " checks ok")
