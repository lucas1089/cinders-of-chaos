-- Run from the server/ folder: luajit tests/weapon_families_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the melee weapon families (O454, server/README.md "Weapon families (O454)"):
--   * weapon_families_config.lua: the limits of the owner's rule (each family within 3% of today on one target, none more than
--     5% above another, the cleave pool, the daze cycle)
--   * weapon_families_core.lua: who gets the traits, tempo (stacks, window, minimum gap, player rule, factor, no change in
--     damage per second), cleave (share per neighbour, the pool, no PvP), daze (chance, rest, boss, no stun lock over a
--     simulated minute), the plan of a hit, the tooltip lines and their pt-BR
--   * weapon_families.lua with weapon_styles.lua against a mocked engine: sword, axe and club on and off, one hand and two,
--     the Monk line, launchers, wands, shields only, no weapon (Open Hand Creed), a spell's weapon strike and a keystone's
--     extra hit untouched, a player target
dofile("data/scripts/chaos/weapon_families_core.lua")
local F = ChaosWeaponFamilies

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, tol, what)
	ok(math.abs(a - b) <= tol, what .. ": " .. tostring(a) .. " ~ " .. tostring(b))
end

local C = F.config
local sword, axe, club = C.families.sword, C.families.axe, C.families.club

-- ------------------------------------------------------------------ the numbers (the limits tools/weapon_family_model.py holds)
local t = sword.tempo
-- the damage per second of one hit on one target, full stacks, against today: the family price (the edge is the sword's)
local single = {sword = F.single("sword") * (1 + t.edge), axe = F.single("axe"), club = F.single("club")}
local lo, hi = math.huge, 0
for name, v in pairs(single) do
	ok(math.abs(v - 1) <= 0.03 + 1e-9, name .. " is within 3% of today on one target (" .. v .. ")")
	lo, hi = math.min(lo, v), math.max(hi, v)
end
ok(hi / lo <= 1.05, "no family is more than 5% above another on one target (" .. hi / lo .. ")")
eq(F.single("sword"), 1, "the sword has no price")
ok(F.single("axe") < 1 and F.single("club") < 1, "the axe and the club pay")
eq(F.single("fist"), 1, "a name that is no family: 1")
-- five targets: main target and four around it; the axe may gain at most 12% over today
local share4 = F.cleaveShare(4, false)
local gain5 = F.single("axe") * (1 + 4 * share4) - 1
ok(gain5 > 0 and gain5 <= 0.12, "the axe gains at most 12% of the basic attack on 5 targets (" .. gain5 .. ")")
-- and in no pack more: the split share is the pool, whatever the number of neighbours
for n = 1, 8 do
	local s, c = F.cleaveShare(n, false)
	near(s * c, axe.cleave.pool, 1e-9, "the pool is split among " .. n .. " neighbours")
	ok(F.single("axe") * (1 + s * c) - 1 <= 0.12, "no more than +12% with " .. n .. " neighbours")
end
ok(F.dazeUptimeCap(false) <= 0.20, "a monster is dazed at most a fifth of the time (" .. F.dazeUptimeCap(false) .. ")")
ok(F.dazeUptimeCap(true) <= 0.12, "a boss is slowed at most an eighth of the time (" .. F.dazeUptimeCap(true) .. ")")
ok(club.daze.bossSlow <= 0.30 and club.daze.bossSlow * F.dazeUptimeCap(true) <= 0.05, "a boss: a small slow, a small share of the time")
ok(club.daze.stunSubId == 71034 and club.daze.immuneSubId == 71035, "the stun and its rest are the Iron Palm ones")
ok(club.daze.bossSlowSubId ~= club.daze.bossRestSubId, "the boss slow and its rest are two conditions")

-- ------------------------------------------------------------------ who gets the traits
for _, v in ipairs({4, 8, 14, 11, 12, 13, 23, 24, 25}) do
	ok(F.affected(v), "vocation " .. v .. " (Warrior, Thief and Templar lines) gets the traits")
end
for _, v in ipairs({17, 18, 19, 3, 7, 15, 1, 5, 10, 20, 21, 22, 0}) do
	ok(not F.affected(v), "vocation " .. v .. " (the Monk line, Rangers, casters) does not")
end
ok(not F.affected(nil) and not F.affected("x"), "an unknown vocation does not")
C.enabled = false
ok(not F.affected(4), "the switch turns them off")
C.enabled = true
eq(F.familyOf("sword"), "sword", "sword") eq(F.familyOf("axe"), "axe", "axe") eq(F.familyOf("club"), "club", "club")
eq(F.familyOf("fist"), nil, "fist") eq(F.familyOf("distance"), nil, "distance") eq(F.familyOf("wand"), nil, "wand") eq(F.familyOf(nil), nil, "none")

-- ------------------------------------------------------------------ sword: tempo
local st = {}
local b, a = F.tempoStep(st, 7, 1000, false)
eq(b, 0, "the first hit has no stack") eq(a, 1, "and gives one")
b, a = F.tempoStep(st, 7, 2000, false)
eq(b, 1, "the second swing had one") eq(a, 2, "and gives the second")
for i = 3, 9 do
	b, a = F.tempoStep(st, 7, 1000 + i * 1000, false)
end
eq(a, t.maxStacks, "stacks stop at the maximum") eq(b, t.maxStacks, "(the swing had them all)")
b, a = F.tempoStep(st, 8, 11000, false)
eq(b, 0, "a new target starts over") eq(a, 1, "with one")
b, a = F.tempoStep(st, 8, 11000 + t.windowMs + 1, false)
eq(b, 0, "a pause over the window starts over") eq(a, 1, "with one")
b, a = F.tempoStep(st, 8, 11000 + t.windowMs + 1 + t.windowMs, false)
eq(b, 1, "a pause of exactly the window keeps the stack") eq(a, 2, "and adds")
-- the off-hand hit of the same swing gives no stack
st = {}
F.tempoStep(st, 1, 1000, false)
b, a = F.tempoStep(st, 1, 1000 + t.minGapMs - 10, false)
eq(b, 1, "the off-hand hit sees the stack") eq(a, 1, "and adds none")
b, a = F.tempoStep(st, 1, 1000 + t.minGapMs + 5, false)
eq(a, 2, "the next swing adds one")
-- a player target: half the stacks, rounded down, never none
eq(F.tempoMax(false), t.maxStacks, "a monster: all the stacks")
eq(F.tempoMax(true), math.floor(t.maxStacks * t.pvpStackShare), "a player: pvpStackShare of them")
st = {}
for i = 1, 8 do
	b, a = F.tempoStep(st, 3, i * 1000, true)
end
eq(a, F.tempoMax(true), "against a player the stacks stop at half")
-- clear
ok(F.tempoClear(st), "clearing stacks reports that there were some")
ok(not F.tempoClear(st), "and nothing the second time")
eq(F.tempoHaste(3), 3 * t.stackPct, "the haste of three stacks")
eq(F.tempoHaste(0), 0, "none: none")
-- the factor: the interval ratio only (O473: the edge of the stacks is raw percent of the additive damage pool, F.tempoEdge)
near(F.tempoFactor(0, 1000, 1000), 1, 1e-12, "no stack: the hit as it is")
near(F.tempoFactor(t.maxStacks, 800, 1000), 0.8, 1e-12, "full stacks at 20% haste: lighter by the ratio")
near(F.tempoFactor(t.maxStacks, 1000, 1000), 1, 1e-12, "a capped swing is not lighter")
near(F.tempoFactor(2, 960, 1000), 0.96, 1e-12, "two stacks")
near(F.tempoFactor(99, 1000, 1000), 1, 1e-12, "more stacks than the maximum")
near(F.tempoFactor(1, nil, nil), 1, 1e-12, "intervals unknown: the hit as it is")
near(F.tempoEdge(0), 0, 1e-12, "the edge: no stack, none")
near(F.tempoEdge(t.maxStacks), t.edge * 100, 1e-12, "the edge at full stacks: raw percent of the pool")
near(F.tempoEdge(2), t.edge * 100 * 2 / t.maxStacks, 1e-12, "the edge of two stacks")
near(F.tempoEdge(99), t.edge * 100, 1e-12, "more stacks than the maximum count as the maximum")
do -- the stacks the next hit will be swung with, without changing the state
	local st2 = {}
	eq(F.tempoPeek(st2, 1, 0, false), 0, "peek: no state, no stacks")
	F.tempoStep(st2, 1, 0, false) F.tempoStep(st2, 1, 500, false) F.tempoStep(st2, 1, 1000, false)
	eq(F.tempoPeek(st2, 1, 1500, false), 3, "peek: the stacks before the next hit (three hits: three)")
	eq(F.tempoPeek(st2, 2, 1500, false), 0, "peek: another target starts over")
	eq(F.tempoPeek(st2, 1, 1000 + t.windowMs + 1, false), 0, "peek: a pause over the window starts over")
	eq(st2.stacks, 3, "peek changes nothing")
end
-- the damage per second over a long fight on one target: the haste and the lighter hits cancel, the edge is what is left
do
	local state, time, damage, base = {}, 0, 0, 1000
	local interval0 = 1000
	local stacks = 0
	for _ = 1, 120 do
		local before, after = F.tempoStep(state, 1, time, false)
		local now = interval0 * (1 - F.tempoHaste(before) / 100)
		damage = damage + 100 * F.tempoFactor(before, now, interval0)
		time = time + now
		stacks = after
	end
	local dps = damage / (time / 1000)
	local baseline = 100 / (interval0 / 1000)
	ok(math.abs(dps / baseline - 1) < 1e-3, "the sword's damage per second on one target without the edge is today's (" .. dps / baseline .. "), the edge is in the pool")
	eq(stacks, t.maxStacks, "(full stacks at the end)")
end

-- ------------------------------------------------------------------ axe: cleave
do
	local s, n = F.cleaveShare(1, false)
	near(s, axe.cleave.pool, 1e-12, "one neighbour takes the pool") eq(n, 1, "one")
	s, n = F.cleaveShare(4, false)
	near(s, axe.cleave.pool / 4, 1e-12, "four share it") eq(n, 4, "four")
	s, n = F.cleaveShare(8, false)
	near(s, axe.cleave.pool / 8, 1e-12, "eight share it") eq(n, 8, "eight")
	s, n = F.cleaveShare(20, false)
	eq(n, axe.cleave.maxTargets, "never more than maxTargets") near(s * n, axe.cleave.pool, 1e-12, "still the pool")
	eq(F.cleaveShare(0, false), 0, "nobody next to it: nothing")
	eq(F.cleaveShare(-3, false), 0, "a bad count: nothing")
	s, n = F.cleaveShare(3, true)
	eq(s, 0, "against a player nothing is split") eq(n, 0, "nobody")
	eq(F.cleaveAmount(1000, 0.035), 35, "35 of 1000")
	eq(F.cleaveAmount(-1000, 0.035), 35, "a hit is negative: the amount is a size")
	eq(F.cleaveAmount(10, 0.01), 1, "at least 1 when something is split")
	eq(F.cleaveAmount(1000, 0), 0, "nothing split: 0")
end

-- ------------------------------------------------------------------ club: daze
do
	local d = club.daze
	local p = F.dazePlan(false, false, false, 0.1)
	eq(p.kind, "stun", "a roll under the chance stuns") eq(p.ms, d.stunMs, "for the stun time") eq(p.restMs, d.stunMs + d.immuneMs, "and the rest runs from its start")
	eq(F.dazePlan(false, false, false, d.chance), nil, "a roll at the chance does not")
	eq(F.dazePlan(false, false, false, 0.99), nil, "a high roll does not")
	eq(F.dazePlan(false, true, false, 0), nil, "a monster in its rest cannot be dazed")
	p = F.dazePlan(true, false, false, 0.05)
	eq(p.kind, "slow", "a boss is slowed") eq(p.slow, d.bossSlow, "by its slow") eq(p.ms, d.bossSlowMs, "for its time")
	eq(p.restMs, d.bossSlowMs + d.bossImmuneMs, "and rests")
	eq(F.dazePlan(true, false, false, d.bossChance + 0.01), nil, "a boss is slowed less often")
	eq(F.dazePlan(true, false, true, 0), nil, "a boss at rest is not slowed again")
	eq(F.dazePlan(true, true, false, 0).kind, "slow", "the stun rest does not count for a boss: its own rest does")
	ok(F.isBoss(true, 10), "the type says boss") ok(F.isBoss(false, d.bossHealth + 1), "more than bossHealth is a boss (the Monk's rule)")
	ok(not F.isBoss(false, d.bossHealth), "a monster at bossHealth is not") ok(not F.isBoss(nil, nil), "unknown: not a boss")
	-- no stun lock: a monster hit every 50 ms for a minute, every roll a daze; the rest is a timer of restMs from the stun's start
	local function minute(boss)
		local restEnd, held, holdEnd, last = 0, 0, 0, 0
		for time = 0, 60000, 50 do
			local plan = F.dazePlan(boss, not boss and time < restEnd, boss and time < restEnd, 0)
			if plan then
				holdEnd, restEnd = time + plan.ms, time + plan.restMs
			end
			if time < holdEnd then
				held = held + 50
			end
		end
		return held / 60000
	end
	local up, bossUp = minute(false), minute(true)
	ok(up <= F.dazeUptimeCap(false) + 0.01, "a minute of hits at every roll: uptime " .. up .. " within the cap")
	ok(bossUp <= F.dazeUptimeCap(true) + 0.01, "a boss: uptime " .. bossUp .. " within its cap")
	ok(up > 0.15, "(and the daze does hold it that long)")
end

-- ------------------------------------------------------------------ the plan of a hit
do
	local function ctx(family, extra)
		local c = {family = family, vocId = 4, pvp = false, targetId = 1, now = 1000, intervalNow = 1000, intervalBase = 1000,
			neighbors = 4, gate = function() return true end, boss = false, immune = false, bossRest = false, roll = 0.9}
		for k, v in pairs(extra or {}) do
			c[k] = v
		end
		return c
	end
	local s = {}
	local plan = F.plan(s, ctx("sword"))
	near(plan.factor, 1, 1e-12, "a sword's first hit: as it is") eq(plan.haste, t.stackPct, "one stack of haste") eq(plan.stacks, 1, "one stack")
	eq(plan.cleave, nil, "no cleave") eq(plan.daze, nil, "no daze")
	plan = F.plan(s, ctx("sword", {now = 2000, intervalNow = 960}))
	near(plan.factor, 0.96, 1e-12, "the second hit: lighter by the swing")
	eq(plan.haste, 2 * t.stackPct, "two stacks")
	-- a player target: the stacks stop at half
	s = {}
	local last
	for i = 1, 8 do
		last = F.plan(s, ctx("sword", {pvp = true, now = i * 1000}))
	end
	eq(last.stacks, F.tempoMax(true), "a sword against a player: half the stacks")
	-- the axe
	s = {}
	plan = F.plan(s, ctx("axe"))
	near(plan.factor, axe.single, 1e-12, "the axe pays") eq(plan.cleave.count, 4, "four neighbours") near(plan.cleave.share, axe.cleave.pool / 4, 1e-12, "a quarter of the pool each")
	eq(plan.haste, nil, "no tempo") eq(plan.daze, nil, "no daze")
	plan = F.plan(s, ctx("axe", {neighbors = 0}))
	eq(plan.cleave, nil, "alone: no cleave") near(plan.factor, axe.single, 1e-12, "(the price stays on one target)")
	plan = F.plan(s, ctx("axe", {gate = function() return false end}))
	eq(plan.cleave, nil, "the per-second limit holds the cleave back")
	plan = F.plan(s, ctx("axe", {pvp = true}))
	eq(plan.cleave, nil, "no cleave against a player") eq(plan.factor, 1, "and no price: the hit is the hit of before")
	-- the neighbour count is read only when it is needed
	local reads = 0
	F.plan(s, ctx("axe", {neighbors = function() reads = reads + 1 return 2 end}))
	eq(reads, 1, "the neighbours are counted for an axe")
	F.plan(s, ctx("axe", {pvp = true, neighbors = function() reads = reads + 1 return 2 end}))
	F.plan(s, ctx("sword", {neighbors = function() reads = reads + 1 return 2 end}))
	F.plan(s, ctx("club", {neighbors = function() reads = reads + 1 return 2 end}))
	eq(reads, 1, "and not for a player target, a sword or a club")
	-- the club
	plan = F.plan(s, ctx("club", {roll = 0.1}))
	near(plan.factor, club.single, 1e-12, "the club pays") eq(plan.daze.kind, "stun", "a stun on a low roll") eq(plan.cleave, nil, "no cleave") eq(plan.haste, nil, "no tempo")
	plan = F.plan(s, ctx("club", {roll = 0.9}))
	eq(plan.daze, nil, "no daze on a high roll")
	plan = F.plan(s, ctx("club", {roll = 0.1, pvp = true}))
	eq(plan.daze, nil, "no daze against a player") eq(plan.factor, 1, "and no price")
	local costly = 0
	F.plan(s, ctx("club", {roll = 0.9, boss = function() costly = costly + 1 return false end,
		immune = function() costly = costly + 1 return false end}))
	eq(costly, 0, "the conditions are not read for a hit that does not roll a daze")
	plan = F.plan(s, ctx("club", {roll = 0.1, boss = true}))
	eq(plan.daze.kind, "slow", "a boss is only slowed")
	plan = F.plan(s, ctx("club", {roll = 0.2, boss = true}))
	eq(plan.daze, nil, "a boss: 0.2 is over its chance")
	plan = F.plan(s, ctx("club", {roll = 0.1, immune = true}))
	eq(plan.daze, nil, "a rested monster is left alone")
	-- not for the others
	eq(F.plan({}, ctx("axe", {vocId = 17})), nil, "the Monk line: nothing")
	eq(F.plan({}, ctx("sword", {vocId = 3})), nil, "a Ranger: nothing")
	eq(F.plan({}, ctx("fist")), nil, "no family: nothing")
	-- another weapon in the hands ends the tempo
	s = {}
	F.plan(s, ctx("sword"))
	plan = F.plan(s, ctx("axe"))
	eq(plan.haste, 0, "an axe after a sword: the haste goes") eq(s.stacks, 0, "and the stacks")
	plan = F.plan(s, ctx("axe"))
	eq(plan.haste, nil, "(once)")
end

-- ------------------------------------------------------------------ the tooltip lines and their pt-BR
do
	local S = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
	for _, family in ipairs(F.FAMILIES) do
		local note = F.note(family)
		ok(type(note) == "string" and note:find("^" .. family:sub(1, 1):upper() .. family:sub(2) .. ": "), family .. " has a line that starts with its name")
		ok(#note < 200, family .. " line is short (" .. #note .. ")")
		local key = note:gsub("%%", "%%%%")
		local pt = S[key]
		ok(pt ~= nil, family .. " line has a pt-BR entry")
		if pt then
			local _, a1 = key:gsub("%%%%", "")
			local _, a2 = pt:gsub("%%%%", "")
			eq(a2, a1, family .. " pt-BR keeps the percent signs")
		end
	end
	eq(F.note("fist"), nil, "no line for a name that is no family")
	ok(F.note("sword"):find("20%%") and F.note("sword"):find("2%%"), "the sword line names its numbers")
	ok(F.note("axe"):find("14%%") and F.note("axe"):find("2.5%%"), "the axe line names its numbers")
	ok(F.note("club"):find("25%%") and F.note("club"):find("0.7 s") and F.note("club"):find("2.5%%"), "the club line names its numbers")
end

-- ------------------------------------------------------------------ engine constants and mocks (weapon_families.lua, weapon_styles.lua)
SKILL_FIST, SKILL_CLUB, SKILL_SWORD, SKILL_AXE, SKILL_DISTANCE, SKILL_SHIELD = 0, 1, 2, 3, 4, 5
WEAPON_NONE, WEAPON_SWORD, WEAPON_CLUB, WEAPON_AXE, WEAPON_SHIELD, WEAPON_DISTANCE, WEAPON_WAND, WEAPON_AMMO = 0, 1, 2, 3, 4, 5, 6, 7
WEAPON_QUIVER = 8
CONST_SLOT_LEFT, CONST_SLOT_RIGHT = 6, 5
SLOTP_TWO_HAND = 2048
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_ATTACK_SPEED = 2, 3
COMBAT_NONE, COMBAT_PHYSICALDAMAGE, COMBAT_HEALING = 0, 1, 128
ORIGIN_NONE, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED, ORIGIN_WAND = 0, 2, 3, 4, 5
CONDITION_ATTRIBUTES, CONDITION_PARALYZE = 1, 2
CONDITIONID_COMBAT = 3
CONDITION_PARAM_TICKS, CONDITION_PARAM_SUBID = 10, 11
CONST_ME_STUN, CONST_ME_HITAREA, CONST_ME_NONE = 21, 22, 0
bit = bit or {band = function(a, b)
	local r, p = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then
			r = r + p
		end
		a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
	end
	return r
end}

local clock = 100000
os.mtime = function() return clock end

local styleEvents, queue = {}, {}
CreatureEvent = function(n)
	local o = {}
	o.register = function() styleEvents[n] = o end
	return o
end
EventCallback = setmetatable({}, {__newindex = function() end, __index = function(_, k)
	if k == "register" then return function() end end end})
createCombatArea = function(x) return x end
addEvent = function(fn, ms, ...) queue[#queue + 1] = {fn = fn, ms = ms, args = {...}} end
doAreaCombat = function() end
local dealt = {}
doTargetCombatHealth = function(attackerId, victim, ctype, mn, mx, effect, origin)
	dealt[#dealt + 1] = {attacker = attackerId, victim = victim.id, ctype = ctype, min = mn, max = mx, effect = effect, origin = origin,
		depth = ChaosKeystones and ChaosKeystones.depth or 0}
	return true
end
ChaosCombatFx = {crit = function() end}
ChaosItemModsCache = {}
local spectators = {}
Game = {getSpectators = function() return spectators end}

-- the real item mods library: effectiveInterval, the player attack speed bonus with its sources
dofile("data/lib/chaos_item_mods.lua")
local IM = ChaosItemMods

local creatures = {}
local conditions = {}
local function addCond(owner, c)
	conditions[owner] = conditions[owner] or {}
	table.insert(conditions[owner], c)
end
Condition = function(ctype)
	local c = {ctype = ctype, params = {}}
	function c:setParameter(k, v) self.params[k] = v end
	function c:setFormula(a, b, c2, d) self.formula = {a, b, c2, d} end
	return c
end
local function findCond(owner, ctype, subId)
	for _, c in ipairs(conditions[owner] or {}) do
		if c.ctype == ctype and c.params[CONDITION_PARAM_SUBID] == subId then
			return c
		end
	end
	return nil
end
local nextId = 100
local fx = {}
local function monster(opts)
	opts = opts or {}
	nextId = nextId + 1
	local m = {id = nextId, hp = opts.hp or 1000, maxHp = opts.maxHp or 5000, boss = opts.boss == true, master = opts.master,
		player = opts.player == true}
	function m:getId() return self.id end
	function m:isPlayer() return self.player end
	function m:isMonster() return not self.player end
	function m:getHealth() return self.hp end
	function m:getMaxHealth() return self.maxHp end
	function m:getMaster() return self.master end
	function m:getPosition() return {x = 100, y = 100, z = 7, sendMagicEffect = function(_, e) fx[#fx + 1] = e end} end
	function m:getType() local me = self return {isBoss = function() return me.boss end} end
	function m:getCondition(ctype, cid, subId) return findCond(self.id, ctype, subId) end
	function m:addCondition(c) addCond(self.id, c) return true end
	creatures[m.id] = m
	return m
end
Creature = function(id) return creatures[id] end
Monster = function(id) local m = creatures[id] return m and m:isMonster() and m or nil end
local players = {}
Player = function(id) return players[id] end

local ITEMS = {
	[1] = {weaponType = WEAPON_SWORD, attack = 50, slot = 0},
	[2] = {weaponType = WEAPON_AXE, attack = 50, slot = 0},
	[3] = {weaponType = WEAPON_AXE, attack = 53, slot = SLOTP_TWO_HAND},
	[4] = {weaponType = WEAPON_CLUB, attack = 50, slot = 0},
	[5] = {weaponType = WEAPON_SHIELD, attack = 0, slot = 0},
	[6] = {weaponType = WEAPON_WAND, attack = 0, slot = 0},
	[7] = {weaponType = WEAPON_DISTANCE, attack = 40, slot = SLOTP_TWO_HAND},
	[8] = {weaponType = WEAPON_SWORD, attack = 53, slot = SLOTP_TWO_HAND}
}
function ItemType(id)
	local it = ITEMS[id]
	return {
		getId = function() return id end,
		getWeaponType = function() return it.weaponType end,
		getSlotPosition = function() return it.slot end,
		getAttack = function() return it.attack end,
		getAttackSpeed = function() return 2000 end,
		getAmmoType = function() return 0 end,
		getName = function() return "item" .. id end,
		isContainer = function() return false end,
		isStackable = function() return false end
	}
end
local function newItem(id)
	return {
		getId = function() return id end,
		getAttribute = function(_, attr) return 0 end
	}
end

dofile("data/scripts/chaos/weapon_families.lua")
local Glue = ChaosWeaponFamiliesGlue
dofile("data/scripts/chaos/weapon_styles.lua")
local hit = styleEvents.ChaosWeaponStyle
ok(hit ~= nil and Glue ~= nil, "the weapon style event and the family glue are there")

local nextPlayer = 0
local function attacker(voc)
	nextPlayer = nextPlayer + 1
	local p = {id = 5000 + nextPlayer, slots = {}, level = 100, voc = voc, storage = {}, bonus = nil}
	function p:getId() return self.id end
	function p:isPlayer() return true end
	function p:getLevel() return self.level end
	function p:getSlotItem(s) return self.slots[s] end
	function p:getEffectiveSkillLevel() return 100 end
	function p:getFightMode() return 1 end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:getVocation()
		local v = self.voc
		return {getId = function() return v end, getAttackSpeed = function() return 1000 end}
	end
	function p:setAttackSpeedBonus(v) self.bonus = v end
	players[p.id] = p
	return p
end
local function wield(p, id)
	p.slots = {[CONST_SLOT_LEFT] = id and newItem(id) or nil}
end
local function swing(p, victim, damage, origin)
	return (hit.onHealthChange(victim, p, damage, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, origin or ORIGIN_MELEE))
end
local unp = table.unpack or unpack
local function flush()
	local rest = {}
	local run = queue
	queue = {}
	for _, e in ipairs(run) do
		if e.ms == 0 then
			e.fn(unp(e.args))
		else
			rest[#rest + 1] = e
		end
	end
	for _, e in ipairs(queue) do
		rest[#rest + 1] = e
	end
	queue = rest
end
local function reset()
	queue, dealt, fx, conditions = {}, {}, {}, {}
	ChaosKeystones = {depth = 0}
end

local BIG = -100000
local function near2(a, b, what) near(a, b, math.abs(b) * 0.0005 + 1, what) end

-- a Monk (vocation 17) swinging the same weapon is the plain hit: the reference of every weapon below
local monk = attacker(17)

-- ------------------------------------------------------------------ the axe
do
	reset()
	local warrior = attacker(4)
	local target = monster()
	local n1, n2, n3, n4 = monster(), monster(), monster(), monster()
	local dead = monster({hp = 0})
	local summon = monster({master = {isPlayer = function() return true end}})
	local other = monster({player = true})
	spectators = {target, n1, n2, n3, n4, dead, summon, other}
	for _, id in ipairs({2, 3}) do
		wield(monk, id) wield(warrior, id)
		local plain = swing(monk, target, BIG)
		clock = clock + 5000
		reset()
		local h = swing(warrior, target, BIG)
		near2(h, plain * axe.single, (id == 2 and "one-handed" or "two-handed") .. " axe: the price on one target")
		eq(#queue, 1, "one event: the cleave")
		flush()
		eq(#dealt, 4, "four neighbours take a share (not the target, the dead, a summon or a player)")
		local sum = 0
		local seen = {}
		for _, d in ipairs(dealt) do
			sum = sum - d.min
			eq(d.origin, ORIGIN_NONE, "a scripted hit: no tempo, no cleave of a cleave")
			eq(d.depth, 1, "inside the keystone guard: the tree does not apply twice")
			eq(d.min, d.max, "a plain amount")
			eq(d.attacker, warrior.id, "dealt by the player")
			eq(d.effect, CONST_ME_HITAREA, "the hit area effect")
			seen[d.victim] = true
		end
		ok(seen[n1.id] and seen[n2.id] and seen[n3.id] and seen[n4.id] and not seen[target.id] and not seen[dead.id]
			and not seen[summon.id] and not seen[other.id], "the right monsters")
		near(sum, -h * axe.cleave.pool, 4, "together the pool of the hit")
		eq(ChaosKeystones and ChaosKeystones.depth or 0, 0, "the guard is down again")
	end
	-- no neighbour: no event
	reset()
	clock = clock + 5000
	spectators = {target}
	swing(warrior, target, BIG)
	eq(#queue, 0, "alone: no cleave event")
	-- eight neighbours: eight smaller shares
	reset()
	clock = clock + 5000
	spectators = {target}
	for i = 1, 8 do spectators[#spectators + 1] = monster() end
	local h = swing(warrior, target, BIG)
	flush()
	eq(#dealt, 8, "eight neighbours")
	local sum = 0
	for _, d in ipairs(dealt) do sum = sum - d.min end
	near(sum, -h * axe.cleave.pool, 8, "the same pool")
	-- the per-second limit of the extras
	reset()
	clock = clock + 5000
	spectators = {target, n1}
	swing(warrior, target, BIG)
	eq(#queue, 1, "the first swing cleaves")
	queue = {}
	clock = clock + 100
	swing(warrior, target, BIG)
	eq(#queue, 0, "a second swing 100 ms later: the limit (1.5 a second) holds the cleave back")
	clock = clock + 2000
	swing(warrior, target, BIG)
	eq(#queue, 1, "two seconds later: it cleaves again")
	queue = {}
	-- a player target: no cleave, no price
	reset()
	clock = clock + 5000
	local victimPlayer = monster({player = true})
	spectators = {victimPlayer, n1}
	wield(monk, 2) wield(warrior, 2)
	local plain = swing(monk, victimPlayer, BIG)
	eq(swing(warrior, victimPlayer, BIG), plain, "against a player the hit is the hit of before")
	eq(#queue, 0, "and nothing is split")
	-- the Monk line: the plain hit, nothing queued
	reset()
	clock = clock + 5000
	spectators = {target, n1, n2}
	for _, voc in ipairs({17, 18, 19}) do
		local m = attacker(voc)
		wield(m, 2)
		eq(swing(m, target, BIG), swing(monk, target, BIG), "vocation " .. voc .. ": the plain hit")
		eq(#queue, 0, "vocation " .. voc .. ": no cleave")
	end
	-- the Thief and Templar lines get it too
	for _, voc in ipairs({8, 14, 11, 12, 13, 23, 24, 25}) do
		reset()
		clock = clock + 5000
		local p = attacker(voc)
		wield(p, 2)
		near2(swing(p, target, BIG), swing(monk, target, BIG) * axe.single, "vocation " .. voc .. ": the axe price")
		eq(#queue, 1, "vocation " .. voc .. ": a cleave")
	end
	queue = {}
end

-- ------------------------------------------------------------------ untouched hits
do
	reset()
	clock = clock + 5000
	local warrior = attacker(4)
	local target = monster()
	spectators = {target, monster(), monster()}
	-- a spell's weapon strike, a ranged hit, a spell, a heal
	wield(warrior, 2)
	warrior.storage[7100028] = 1
	wield(monk, 2)
	monk.storage[7100028] = 1
	eq(swing(warrior, target, BIG), swing(monk, target, BIG), "a scripted weapon strike is left alone")
	eq(#queue, 0, "and has no trait")
	warrior.storage[7100028] = 0
	monk.storage[7100028] = 0
	eq(swing(warrior, target, BIG, ORIGIN_SPELL), BIG, "a spell is untouched")
	eq(#queue, 0, "no trait")
	eq((hit.onHealthChange(target, warrior, 100, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_MELEE)), 100, "a heal is untouched")
	-- a keystone's extra hit (the guard is up): no trait, no tempo
	ChaosKeystones = {depth = 1}
	eq(swing(warrior, target, BIG), swing(monk, target, BIG), "an extra hit of a keystone is left alone")
	eq(#queue, 0, "no trait")
	ChaosKeystones = {depth = 0}
	-- no weapon in the hands (the fists, Open Hand Creed): nothing
	wield(warrior, nil)
	eq(swing(warrior, target, BIG), BIG, "no weapon in the hands: the hit stays")
	eq(#queue, 0, "no trait")
	-- a shield only
	wield(warrior, 5)
	eq(swing(warrior, target, BIG), BIG, "a shield only: the hit stays")
	-- a bow: ranged, not a melee family
	wield(warrior, 7)
	local bow = swing(warrior, target, BIG, ORIGIN_RANGED)
	wield(monk, 7)
	monk.storage[7100028] = 0
	eq(bow, swing(monk, target, BIG, ORIGIN_RANGED), "a bow in the hands of a Warrior: as for anyone")
	flush()
	eq(#dealt, 0, "no family effect (the arrow splash is its own event)")
	queue = {}
	-- a wand
	wield(warrior, 6)
	function warrior:getMagicLevel() return 100 end
	function monk:getMagicLevel() return 100 end
	wield(monk, 6)
	eq(swing(warrior, target, BIG, ORIGIN_WAND), swing(monk, target, BIG, ORIGIN_WAND), "a wand: as for anyone")
	ok(Glue.states[warrior.id] == nil or (Glue.states[warrior.id].stacks or 0) == 0, "no tempo state for a wand or a bow")
	queue = {}
	-- the switch
	reset()
	clock = clock + 5000
	wield(warrior, 2) wield(monk, 2)
	C.enabled = false
	eq(swing(warrior, target, BIG), swing(monk, target, BIG), "switched off: the hit of before")
	eq(#queue, 0, "no cleave")
	C.enabled = true
end

-- ------------------------------------------------------------------ the club
do
	reset()
	clock = clock + 5000
	local warrior = attacker(8)
	local target = monster()
	spectators = {target}
	local realRandom = math.random
	local roll = 0.1
	math.random = function(a, b) if a then return realRandom(a, b) end return roll end
	wield(monk, 4) wield(warrior, 4)
	local plain = swing(monk, target, BIG)
	local h = swing(warrior, target, BIG)
	near2(h, plain * club.single, "the club: the price on one target")
	eq(#queue, 1, "a daze is queued on a low roll")
	flush()
	local stun = findCond(target.id, CONDITION_PARALYZE, club.daze.stunSubId)
	ok(stun ~= nil, "the monster has the stun condition (the one monk_combat.lua cancels attacks for)")
	eq(stun.params[CONDITION_PARAM_TICKS], club.daze.stunMs, "for the stun time")
	eq(stun.formula[1], -1, "and it stands still")
	local rest = findCond(target.id, CONDITION_ATTRIBUTES, club.daze.immuneSubId)
	ok(rest ~= nil, "and the rest timer of Iron Palm is on it")
	eq(rest.params[CONDITION_PARAM_TICKS], club.daze.stunMs + club.daze.immuneMs, "for the whole cycle")
	eq(fx[1], CONST_ME_STUN, "the stun effect")
	-- at rest: no second daze
	reset()
	conditions[target.id] = {rest}
	swing(warrior, target, BIG)
	eq(#queue, 0, "a monster at rest is not dazed again")
	-- no stun lock with the Iron Palm: its rest blocks the daze too (the same condition)
	-- a high roll: nothing
	reset()
	roll = 0.9
	swing(warrior, target, BIG)
	eq(#queue, 0, "a high roll: no daze")
	-- a boss: a slow, rarely, with its own rest
	reset()
	roll = 0.1
	local boss = monster({boss = true})
	spectators = {boss}
	swing(warrior, boss, BIG)
	flush()
	ok(findCond(boss.id, CONDITION_PARALYZE, club.daze.stunSubId) == nil, "a boss is not stunned")
	local slow = findCond(boss.id, CONDITION_PARALYZE, club.daze.bossSlowSubId)
	ok(slow ~= nil, "a boss is slowed")
	eq(slow.params[CONDITION_PARAM_TICKS], club.daze.bossSlowMs, "for its time")
	eq(slow.formula[1], -club.daze.bossSlow, "by its share")
	ok(findCond(boss.id, CONDITION_ATTRIBUTES, club.daze.bossRestSubId) ~= nil, "and it rests")
	queue = {}
	swing(warrior, boss, BIG)
	eq(#queue, 0, "a boss at rest is not slowed again")
	-- a big monster that is not a boss by type is treated as one (the Monk's rule)
	reset()
	local big = monster({maxHp = club.daze.bossHealth + 1})
	swing(warrior, big, BIG)
	flush()
	ok(findCond(big.id, CONDITION_PARALYZE, club.daze.stunSubId) == nil and findCond(big.id, CONDITION_PARALYZE, club.daze.bossSlowSubId) ~= nil,
		"more than 50000 health: slowed, not stunned")
	-- a player: no daze, no price
	reset()
	local victimPlayer = monster({player = true})
	local plainP = swing(monk, victimPlayer, BIG)
	eq(swing(warrior, victimPlayer, BIG), plainP, "against a player: the hit of before")
	eq(#queue, 0, "no daze")
	-- the monster died before the event ran
	reset()
	roll = 0.1
	local dying = monster()
	swing(warrior, dying, BIG)
	dying.hp = 0
	flush()
	ok(findCond(dying.id, CONDITION_PARALYZE, club.daze.stunSubId) == nil, "a monster that died is left alone")
	math.random = realRandom
	queue = {}
end

-- ------------------------------------------------------------------ the sword
do
	reset()
	clock = clock + 10000
	local warrior = attacker(4)
	local target = monster()
	local target2 = monster()
	spectators = {target, target2}
	wield(monk, 1) wield(warrior, 1)
	local plain = swing(monk, target, BIG)
	-- the first hit: the plain hit, one stack of haste
	local h = swing(warrior, target, BIG)
	eq(h, plain, "a sword's first hit on a target: the plain hit")
	eq(#queue >= 1 and 1 or 0, 1, "the haste ends by a timer")
	local row = IM.playerSpeed[warrior.id]
	eq(row.tempo, t.stackPct, "one stack of haste is a source of the player attack speed bonus")
	eq(row.total, t.stackPct, "(the engine gets it)")
	eq(warrior.bonus, t.stackPct, "(set on the player)")
	eq(IM.playerAttackSpeed(warrior), 0, "(the tooltips do not show it)")
	-- the second hit: lighter by the swing
	clock = clock + 1000
	local h2 = swing(warrior, target, BIG)
	-- vocation 1000 ms, item 2000 ms: base 1000; with 4% haste 960 ms
	near2(h2, plain * 0.96, "the second hit is lighter by the ratio of the swings (the edge is a pool entry)")
	near(Glue.poolRaw(warrior, target, ORIGIN_MELEE), t.edge * 100 * 2 / t.maxStacks, 1e-9, "the pool entry: the edge of the two stacks before the next hit")
	eq(Glue.poolRaw(warrior, target, ORIGIN_RANGED), 0, "no edge for a ranged hit")
	-- on to full stacks
	local last
	for i = 1, 8 do
		clock = clock + 800
		last = swing(warrior, target, BIG)
	end
	eq(IM.playerSpeed[warrior.id].tempo, t.maxStacks * t.stackPct, "full stacks: the maximum haste")
	near2(last, plain * 0.8, "full stacks: a hit swung at 800 ms is 0.8 of the plain one")
	near((last / 0.8) / plain, 1, 0.001, "its damage per second is the plain one (the edge is in the pool)")
	near(Glue.poolRaw(warrior, target, ORIGIN_MELEE), t.edge * 100, 1e-9, "the pool entry at full stacks: the whole edge")
	-- a new target starts over: the plain hit again, one stack
	clock = clock + 800
	local h3 = swing(warrior, target2, BIG)
	near2(h3, plain * 0.8, "a new target: the swing was made at the hasted interval, so the hit is as light as it was swung, and no edge")
	eq(IM.playerSpeed[warrior.id].tempo, t.stackPct, "(and the haste starts over)")
	-- the player's own attack speed from the tree adds to the haste, and the cap holds it
	IM.setPlayerAttackSpeed(warrior, "tree", 10)
	eq(IM.playerAttackSpeed(warrior), 10, "the tree's speed is shown")
	eq(IM.playerSpeed[warrior.id].total, 14, "and adds to the tempo")
	-- a source set twice counts once (before O454 the old total was summed into the new one)
	IM.setPlayerAttackSpeed(warrior, "tree", 10)
	IM.setPlayerAttackSpeed(warrior, "tree", 10)
	eq(IM.playerSpeed[warrior.id].total, 10 + t.stackPct, "the same source twice: counted once")
	-- the tree's speed at its cap: the haste adds nothing, so the swing is not faster and the hit is not lighter
	IM.setPlayerAttackSpeed(warrior, "tree", 0)
	local capped = attacker(4)
	wield(capped, 1)
	IM.setPlayerAttackSpeed(capped, "tree", IM.config.playerSpeedCap)
	local cappedPlain = swing(monk, target, BIG)
	clock = clock + 5000
	swing(capped, target, BIG) -- one stack
	eq(IM.playerSpeed[capped.id].total, IM.config.playerSpeedCap, "at the cap the haste adds nothing")
	clock = clock + 1000
	local ch = swing(capped, target, BIG)
	near2(ch, cappedPlain, "a capped swing is as heavy as ever")
	-- the timer: after the window with no hit the haste is gone
	local pending = 0
	for _, e in ipairs(queue) do
		if e.ms > 0 then pending = pending + 1 end
	end
	ok(pending >= 1, "a decay timer is pending")
	clock = clock + t.windowMs + 500
	for _ = 1, 4 do
		local run = queue
		queue = {}
		for _, e in ipairs(run) do
			if e.ms == 0 then
				e.fn(unp(e.args))
			elseif e.args[1] == nil then
				e.fn()
			end
		end
	end
	eq(IM.playerSpeed[warrior.id].tempo, 0, "the haste ends when the hits stop")
	eq(IM.playerSpeed[capped.id].tempo, 0, "(for the other player too)")
	-- the Monk line and the others: no haste, the plain hit
	reset()
	clock = clock + 5000
	local m18 = attacker(18)
	wield(m18, 1)
	eq(swing(m18, target, BIG), plain, "the Shadowfist's sword hit is plain")
	clock = clock + 1000
	eq(swing(m18, target, BIG), plain, "and stays plain")
	ok(IM.playerSpeed[m18.id] == nil, "no tempo source")
	-- a sword in a two-handed grip: the level's factor stays, the family adds its own
	reset()
	clock = clock + 5000
	local twoH = attacker(14)
	wield(twoH, 8) wield(monk, 8)
	local plain2 = swing(monk, target, BIG)
	eq(swing(twoH, target, BIG), plain2, "a two-handed sword's first hit: the plain two-handed hit")
	clock = clock + 1000
	local hh = swing(twoH, target, BIG)
	near2(hh, plain2 * 0.96, "its second hit: lighter by the swing as the one-handed one")
	-- another weapon in the hands ends the tempo at once
	wield(twoH, 2)
	clock = clock + 100
	spectators = {}
	swing(twoH, target, BIG)
	eq(IM.playerSpeed[twoH.id].tempo, 0, "an axe in the hands: the sword's haste is gone")
	-- a player target: half the stacks
	reset()
	clock = clock + 10000
	local pvper = attacker(4)
	wield(pvper, 1)
	local victimPlayer = monster({player = true})
	for _ = 1, 8 do
		clock = clock + 1000
		swing(pvper, victimPlayer, BIG)
	end
	eq(IM.playerSpeed[pvper.id].tempo, F.tempoMax(true) * t.stackPct, "against a player: half the haste")
	queue = {}
end

print(string.format("weapon families: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
