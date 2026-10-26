-- Run from the server/ folder: luajit tests/templar_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Covers the Templar line: the ids (vocations, client bytes, spell ids below 256 and outside the other lines' blocks),
-- the defence aura (who is covered, which aura wins, holding, reduction, the Sentinel's regeneration), Radiant Strikes,
-- Judgement, Zealotry, Aegis of Faith, the heals and the level factor (templar_aura_core.lua), and the combat glue
-- (templar_combat.lua): the damage a covered / judged / shielded creature takes and the holy strike after a melee hit.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function near(a, b, m) if math.abs(a - b) > 1e-9 then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

dofile("data/scripts/chaos/templar_aura_core.lua")
local T = ChaosTemplar
local cfg = T.cfg
local TEMPLAR, INQ, SENT = 23, 24, 25

-- ------------------------------------------------------------------ ids
eq(cfg.ids.vocation.templar, TEMPLAR); eq(cfg.ids.vocation.inquisitor, INQ); eq(cfg.ids.vocation.sentinel, SENT)
eq(cfg.ids.clientByte.templar, 9); eq(cfg.ids.clientByte.inquisitor, 19); eq(cfg.ids.clientByte.sentinel, 29)
local seen, count = {}, 0
for name, id in pairs(cfg.ids.spell) do
	count = count + 1
	assert(id < 256, name .. " below 256 (one byte in the cooldown packet)")
	assert(not seen[id], "spell id used twice: " .. id); seen[id] = true
	assert(not (id >= 180 and id <= 188), "not the Necromancer's block")
	assert(not (id >= 63 and id <= 74), "not the Monk's block")
	assert(not (id >= 200 and id <= 249), "not the Chaos spells' block")
	local ok = (id >= 189 and id <= 191) or id == 198 or id == 199 or (id >= 250 and id <= 253)
	assert(ok, "reserved ids only: " .. id)
end
eq(count, 9, "nine spells")
eq(cfg.ascension.inquisitor, INQ); eq(cfg.ascension.sentinel, SENT)
eq(cfg.ids.unlockKey, "templar")
eq(T.isTemplarLine(TEMPLAR) and T.isTemplarLine(INQ) and T.isTemplarLine(SENT), true)
eq(T.isTemplarLine(4), false); eq(T.isTemplarLine(22), false); eq(T.isTemplarLine(26), false)
eq(T.baseOf(SENT), TEMPLAR); eq(T.baseOf(8), nil)
eq(T.isInquisitor(INQ), true); eq(T.isSentinel(INQ), false)

-- ------------------------------------------------------------------ the aura: who is covered
local function pos(x, y, z) return {x = x, y = y, z = z or 7} end
eq(T.distance(pos(0, 0), pos(3, -4)), 4); eq(T.distance(pos(0, 0), pos(0, 0, 6)), math.huge, "other floor")
local templar = {id = 1, voc = TEMPLAR, pos = pos(100, 100), party = "A"}
local players = {
	{id = 1, pos = pos(100, 100), party = "A"},
	{id = 2, pos = pos(104, 100), party = "A"}, -- radius 4: in
	{id = 3, pos = pos(105, 100), party = "A"}, -- out
	{id = 4, pos = pos(101, 100), party = "B"}, -- another party
	{id = 5, pos = pos(101, 100), party = nil}, -- no party
	{id = 6, pos = pos(101, 100, 6), party = "A"}, -- other floor
	{id = 7, pos = pos(101, 101), party = "A", dead = true},
}
local covered = T.coveredBy(templar, players)
eq(#covered, 2, "self + one member"); eq(covered[1], 1); eq(covered[2], 2)
local solo = {id = 5, voc = TEMPLAR, pos = pos(101, 100), party = nil}
covered = T.coveredBy(solo, players)
eq(#covered, 1, "without a party only itself"); eq(covered[1], 5)
eq(#T.coveredBy({id = 9, voc = 4, pos = pos(0, 0)}, players), 0, "no aura for other classes")

-- the strongest aura wins, no stacking
local sentinel = {id = 3, voc = SENT, pos = pos(105, 100), party = "A"}
local inq = {id = 2, voc = INQ, pos = pos(104, 100), party = "A"}
local auras = T.collectAuras({templar, inq, sentinel}, players, 1000)
near(auras[1].reduction, 0.12, "the Sentinel (5 sqm away) covers the Templar"); eq(auras[1].source, 3)
near(auras[2].reduction, 0.12, "and the Inquisitor")
near(auras[3].reduction, 0.12, "and itself"); near(auras[3].regenPct, 0.004)
eq(auras[4], nil, "never another party"); eq(auras[7], nil, "never the dead")
eq(auras[1].untilMs, 1000 + cfg.aura.holdMs)
auras = T.collectAuras({templar, inq}, players, 1000)
near(auras[2].reduction, 0.06, "the Templar's beats the Inquisitor's own"); eq(auras[2].source, 1)
eq(T.stronger({reduction = 0.1, regenPct = 0.01}, {reduction = 0.1, regenPct = 0}), true, "regen breaks a tie")
eq(T.stronger({reduction = 0.05}, {reduction = 0.1}), false)

-- holding and expiry
T.auraState = {}
T.applyAuras(T.collectAuras({templar}, players, 0), 0)
near(T.activeAura(2, 1000).reduction, 0.06, "still covered 1 s later")
eq(T.activeAura(2, 1500), nil, "gone after holdMs without a check")
T.applyAuras(T.collectAuras({sentinel}, players, 0), 0)
T.applyAuras(T.collectAuras({templar}, players, 100), 100)
near(T.activeAura(1, 200).reduction, 0.12, "a weaker check in the same second does not overwrite a valid stronger aura")
T.applyAuras(T.collectAuras({templar}, players, 2000), 2000)
near(T.activeAura(1, 2100).reduction, 0.06, "once the stronger one expired the weaker one counts")
T.applyAuras({}, 5000)
eq(T.activeAura(1, 5000), nil)

-- reduction and regeneration
eq(T.scale(-1000, 0.5), -500); eq(T.scale(1001, 0.5), 501); eq(T.scale(0, 2), 0)
near(T.damageTakenFactor(nil, false), 1)
near(T.damageTakenFactor({reduction = 0.12}, false), 0.88)
near(T.damageTakenFactor({reduction = 0.12}, true), 0.88 * 0.6, "aura and Aegis multiply")
eq(T.regenAmount(9000, 10000, {regenPct = 0.004}), 40)
eq(T.regenAmount(9990, 10000, {regenPct = 0.004}), 10, "never above the maximum")
eq(T.regenAmount(10000, 10000, {regenPct = 0.004}), 0)
eq(T.regenAmount(100, 200, {regenPct = 0.004}), 1, "at least 1")
eq(T.regenAmount(100, 200, {reduction = 0.06, regenPct = 0}), 0, "the Templar's aura does not heal")

-- ------------------------------------------------------------------ weapon hits, Judgement
eq(T.radiantDamage(TEMPLAR, 1000, false), 150); eq(T.radiantDamage(INQ, -1000, false), 250)
eq(T.radiantDamage(SENT, 1000, true), 200, "against players from the unhalved hit")
eq(T.radiantDamage(4, 1000, false), 0); eq(T.radiantDamage(TEMPLAR, 0, false), 0)
-- Radiant Smite: cooldown 2 s since the rotation pass, damage x the class scale (tools/rotation_sim.py keeps each
-- class's spell damage where it was with 4 s)
eq(T.smiteScale(TEMPLAR, 300), 0.56); eq(T.smiteScale(INQ, 300), 0.69); eq(T.smiteScale(SENT, 300), 0.56)
eq(T.smiteScale(4, 300), 1); eq(T.smiteScale(INQ, 119), 0.55, "no Purging Nova yet"); eq(T.smiteScale(INQ, 120), 0.69)
eq(T.smiteScale(TEMPLAR, 50), 0.56)
near(T.judgementFactor(true, true), 1.2); near(T.judgementFactor(false, true), 1); near(T.judgementFactor(true, false), 1)


-- ------------------------------------------------------------------ heals and spells
eq(T.novaHeal(10000, 20000), 1000, "10% of the damage")
eq(T.novaHeal(100000, 20000), 1000, "at most 5% of the maximum health")
eq(T.layOnHandsAmount(10000, 50), 4000)
eq(T.vowAmount(10000, 300, 20), 800 + 60 + 80)
eq(T.pickHealTarget({{id = 1, health = 50, maxHealth = 100}, {id = 2, health = 30, maxHealth = 100},
	{id = 3, health = 30, maxHealth = 100}}), 2, "lowest share, first on a tie")
eq(T.pickHealTarget({}), nil)
near(T.levelScale(100), 1); near(T.levelScale(300), 1); near(T.levelScale(1000), 1, "dropped with the class trees")
local mn, mx = T.strikeValues(300, 5500, 20, 0.10, 0.16, 1.0, 1.5, 30, 60)
near(mn, 60 + 550 + 20 + 30); near(mx, 60 + 880 + 30 + 60)
mn = T.strikeValues(1000, 5500, 20, 0.10, 0.16, 1.0, 1.5, 30, 60)
near(mn, 200 + 550 + 20 + 30, "no level factor at 1000")

-- ================================================================== the combat glue (mocks)
local events, callbacks, scheduled = {}, {}, {}
local function obj(store, name)
	local o = {}
	function o:register() if name then store[name] = o end end
	function o:interval() end
	return o
end
function CreatureEvent(name) return obj(events, name) end
function GlobalEvent(name) return obj(events, name) end
local pendingCb
EventCallback = setmetatable({}, {
	__index = function(_, k)
		if k == "register" then return function() callbacks[pendingCb[1]] = pendingCb[2] end end
	end,
	__newindex = function(_, k, v) pendingCb = {k, v} end
})
function addEvent(fn, ms, ...) scheduled[#scheduled + 1] = {fn = fn, ms = ms, args = {...}} end
ChaosSpell = {canAttack = function() return true end}
local strikes = {}
function doTargetCombat(a, t, ctype, min, max, effect, origin)
	strikes[#strikes + 1] = {attacker = a, target = t, type = ctype, min = min, origin = origin}
	return true
end
T.now = function() return 50000 end

local C_mt = {}
C_mt.__index = C_mt
local all = {}
local function creature(o)
	local c = setmetatable({id = o.id, voc = o.voc, player = o.player, conds = {}, health = 1000}, C_mt)
	all[c.id] = c
	return c
end
function C_mt:getId() return self.id end
function C_mt:isPlayer() return self.player == true end
function C_mt:getPlayer() return self.player and self or nil end
function C_mt:getVocation() local v = self.voc; return {getId = function() return v end} end
function C_mt:getCondition(t, id, sub) return self.conds[sub] end
function C_mt:getHealth() return self.health end
function C_mt:registerEvent() end
function Player(id) local c = all[id]; return c and c.player and c or nil end
function Creature(id) return all[id] end

dofile("data/scripts/chaos/templar_combat.lua")
local onHealth = events.ChaosTemplarCombat.onHealthChange
local tp = creature({id = 11, voc = TEMPLAR, player = true})
local iq = creature({id = 12, voc = INQ, player = true})
local se = creature({id = 13, voc = SENT, player = true})
local ally = creature({id = 14, voc = 4, player = true})
local mob = creature({id = 50})

-- a Templar's melee hit on a monster: unchanged, a holy strike of 15% follows
local p, pt, s = onHealth(mob, tp, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(p, 1000, "the hit itself is unchanged"); eq(#scheduled, 1, "a holy strike is scheduled")
scheduled[1].fn((unpack or table.unpack)(scheduled[1].args))
eq(strikes[1].type, COMBAT_HOLYDAMAGE); eq(strikes[1].min, -150); eq(strikes[1].origin, ORIGIN_SPELL)
-- a spell hit gives no strike
scheduled = {}
onHealth(mob, tp, 1000, COMBAT_HOLYDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(#scheduled, 0, "no strike after spells")

-- Judgement: holy damage from anyone (a Warrior's too) +20%, physical unchanged
mob.conds[cfg.ids.subId.judgement] = true
p = onHealth(mob, ally, 1000, COMBAT_HOLYDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(p, 1200, "judged: holy +20%")
p = onHealth(mob, ally, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(p, 1000, "judged: physical unchanged")
mob.conds = {}

-- Zealotry is gone (O254): an Inquisitor melee hit is not scaled by any buff
iq.conds = {}
p = onHealth(mob, iq, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(p, 1000, "no stack mechanic")
eq(T.zealHit, nil, "no zeal functions left")
eq(cfg.zealotry, nil, "no zealotry config left")
eq(cfg.ids.subId.zealotry, nil, "no zealotry sub id")

-- the aura: a covered party member takes less; healing is never touched
T.auraState = {}
T.applyAuras({[14] = {reduction = 0.12, regenPct = 0.004, source = 13, untilMs = 60000}}, 50000)
p = onHealth(ally, mob, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(p, 880, "covered: -12%")
p = onHealth(ally, mob, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_NONE)
eq(p, 1000, "healing untouched")
-- Aegis of Faith on the Sentinel (only on the Sentinel)
se.conds[cfg.ids.subId.aegis] = true
p = onHealth(se, mob, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(p, 600, "aegis -40%")
tp.conds[cfg.ids.subId.aegis] = true
p = onHealth(tp, mob, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(p, 1000, "a Templar with the condition from elsewhere gets nothing")

-- the target callback hands the event to what a Templar attacks
eq(callbacks.onTargetCombat(tp, mob), RETURNVALUE_NOERROR)

-- Penitent's Wrath (the Templar line's keystone in the main tree, class_tree.lua): a melee / ranged hit taken is answered
-- with a holy strike of 40% of what was taken + 4 x magic level, one every 0.5 s
local CT = ChaosClassTree
local store = {}
function C_mt:getStorageValue(k) return (store[self.id] or {})[k] or -1 end
function C_mt:setStorageValue(k, v) store[self.id] = store[self.id] or {}; store[self.id][k] = v end
function C_mt:getMagicLevel() return 25 end
function C_mt:getPosition() return {sendDistanceEffect = function() end, sendMagicEffect = function() end} end
local pen = creature({id = 15, voc = TEMPLAR, player = true})
local brute = creature({id = 51})
T.auraState = {}
scheduled, strikes = {}, {}
p = onHealth(pen, brute, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(#scheduled, 0, "without the keystone: no answer")
CT.write(pen, {ksPenitentWrath = 1})
local clockT = 50000
T.now = function() return clockT end
p = onHealth(pen, brute, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(p, -1000, "the hit itself is unchanged"); eq(#scheduled, 1, "an answer is scheduled")
scheduled[1].fn((unpack or table.unpack)(scheduled[1].args))
eq(strikes[1].target, brute, "on the attacker"); eq(strikes[1].type, COMBAT_HOLYDAMAGE); eq(strikes[1].min, -(400 + 100))
eq(strikes[1].origin, ORIGIN_SPELL)
eq(ChaosKeystones == nil or ChaosKeystones.depth == 0, true, "the proc guard is down again")
scheduled = {}
onHealth(pen, brute, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(#scheduled, 0, "one every 0.5 s")
clockT = clockT + 500
onHealth(pen, brute, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED)
eq(#scheduled, 1, "a ranged hit after the cooldown")
scheduled = {}
clockT = clockT + 500
onHealth(pen, brute, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(#scheduled, 0, "a spell is not answered")
-- under an aura the answer is of what was really taken
T.applyAuras({[15] = {reduction = 0.12, regenPct = 0, source = 13, untilMs = clockT + 1000}}, clockT)
strikes = {}
p = onHealth(pen, brute, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(p, -880); scheduled[1].fn((unpack or table.unpack)(scheduled[1].args))
eq(strikes[1].min, -(352 + 100), "40% of 880 + 100")

print("templar_test: OK")
