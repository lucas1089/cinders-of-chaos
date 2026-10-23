-- Run from the server/ folder: luajit tests/spell_factor_test.lua && lua5.3 tests/spell_factor_test.lua (CI runs both)
-- The class factor on spell damage (spell_factor_config.lua, spell_factor_core.lua, owner 2026-10-20): the table, the
-- rule (ORIGIN_SPELL damage only; not weapon hits, conditions, healing, keystone procs or guarded hits) and the
-- ChaosPassiveDealt event of passivetree_effects.lua that applies it, on a mocked engine.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks, fails = 0, 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		fails = fails + 1
		print("FAIL " .. (m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
	end
end

dofile("data/scripts/chaos/spell_factor_config.lua")
dofile("data/scripts/chaos/spell_factor_core.lua")
local F, C = ChaosSpellFactor, ChaosSpellFactorConfig

-- the table: the factor at the end of each class's curve (level 1000 and up; the whole factor of a class without a curve),
-- by vocation id (docs/CLASSES.md ids). O136 (2026-10-23): a level curve per class (byLevel), the end values changed.
local want = {[3] = 1.12, [4] = 1.0, [5] = 0.7, [7] = 1.25, [8] = 1.09, [10] = 0.73, [14] = 1.08, [15] = 1.17, [17] = 0.87,
	[18] = 0.8, [19] = 0.99, [20] = 0.69, [21] = 0.92, [22] = 0.71, [23] = 0.63, [24] = 0.77, [25] = 0.6}
local count = 0
for id, v in pairs(C.byVocation) do
	count = count + 1
	eq(v, want[id], "factor of vocation " .. id)
	local pts = C.byLevel[id]
	if pts then
		eq(pts[#pts][2], v, "the curve of vocation " .. id .. " ends on its byVocation value")
		for i = 2, #pts do
			eq(pts[i][1] > pts[i - 1][1], true, "curve " .. id .. " rises in level")
		end
		eq(pts[#pts][1], 1000, "curve " .. id .. " ends at level 1000")
	end
end
eq(count, 17, "seventeen classes listed")
for _, id in ipairs({1, 11, 12, 13}) do
	eq(F.forVocation(id), 1, "vocation " .. id .. " keeps 1")
	eq(F.forVocation(id, nil, 300), 1, "vocation " .. id .. " keeps 1 at level 300")
end
-- the level curve: flat below the first point, linear between points, the last value above, byVocation without a level
eq(F.forVocation(23, nil, 1), 0.6, "Templar below its first point")
eq(F.forVocation(23, nil, 30), 0.6, "Templar at 30")
eq(math.abs(F.forVocation(23, nil, 35) - 0.805) < 1e-9, true, "Templar at 35: halfway 30 (0.60) to 40 (1.01)")
eq(F.forVocation(23, nil, 40), 1.01, "Templar at 40")
eq(F.forVocation(23, nil, 50), 0.97, "Templar at 50 (O141: knots 45/50/55/59 keep the 40-60 ramp within 5% of the score before the attack kit)")
eq(F.forVocation(23, nil, 59), 1.0, "Templar at 59: the last level before Sanctified Ground")
eq(F.forVocation(23, nil, 300), 0.57, "Templar at 300")
eq(F.forVocation(23, nil, 5000), 0.63, "Templar above level 1000")
eq(F.forVocation(23), 0.63, "Templar without a level: the end of the curve")
local synth = {byVocation = {[9] = 2}, byLevel = {[9] = {{10, 1}, {20, 3}}}}
eq(F.forVocation(9, synth, 5), 1, "synthetic curve below")
eq(F.forVocation(9, synth, 15), 2, "synthetic curve between")
eq(F.forVocation(9, synth, 99), 3, "synthetic curve above")

-- the rule
local SPELL, MELEE, COND, WAND, HEAL, FIRE = 1, 2, 3, 4, 100, 7
eq(F.factor(23, SPELL, FIRE, SPELL, HEAL, false), 0.63, "a Templar spell hit (no level: the end of the curve)")
eq(F.factor(23, SPELL, FIRE, SPELL, HEAL, false, nil, 300), 0.57, "a Templar spell hit at level 300")
eq(F.factor(7, SPELL, FIRE, SPELL, HEAL, false), 1.25, "a Deadeye spell hit (no level)")
eq(F.factor(15, SPELL, FIRE, SPELL, HEAL, false, nil, 30), 1.25, "a level 30 Beastmaster spell hit")
eq(F.factor(23, MELEE, FIRE, SPELL, HEAL, false), 1, "a weapon hit")
eq(F.factor(23, WAND, FIRE, SPELL, HEAL, false), 1, "a wand hit")
eq(F.factor(23, COND, FIRE, SPELL, HEAL, false), 1, "a condition tick")
eq(F.factor(23, SPELL, HEAL, SPELL, HEAL, false), 1, "healing")
eq(F.factor(23, SPELL, 0, SPELL, HEAL, false), 1, "no secondary damage")
eq(F.factor(23, SPELL, FIRE, SPELL, HEAL, true), 1, "a keystone proc")
eq(F.factor(4, SPELL, FIRE, SPELL, HEAL, false), 1, "a Warrior spell hit")
eq(F.factor(11, SPELL, FIRE, SPELL, HEAL, false, nil, 300), 1, "a Thief spell hit")
local inside
local ok, r = F.guard(function(x)
	inside = F.factor(23, SPELL, FIRE, SPELL, HEAL, false)
	return x * 2
end, 21)
eq(ok and r, 42, "guard returns the call's results")
eq(inside, 1, "inside the guard the factor is off")
eq(F.depth, 0, "the guard restores the depth")
local bad = F.guard(function() error("x") end)
eq(bad, false, "an error inside the guard")
eq(F.depth, 0, "the depth after an error")

-- the event (passivetree_effects.lua) on a mocked engine
Chaos = {storage = {}, tables = {}, passive = {}}
function Chaos.load() end
ChaosOpcodes = {}
local registered = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
rawset(EventCallback, "register", function(self) local l = rawget(self, "_last"); registered[l[1]] = l[2] end)
function CreatureEvent(name) local o = {}; function o:register() registered[name] = o end; return o end
function Condition() local c = {p = {}}; function c:setTicks() end; function c:setParameter(k, v) self.p[k] = v end; return c end
function addEvent() end
dofile("data/scripts/chaos/passivetree_effects.lua")
local ev = registered["ChaosPassiveDealt"]
local function player(voc)
	local p = {}
	function p:getId() return 900 + voc end
	function p:isPlayer() return true end
	function p:getVocation() return {getId = function() return voc end} end
	function p:getLevel() return 300 end
	return p
end
local templar, warrior = player(23), player(4)
local d1, _, d2 = ev.onHealthChange({}, templar, -1000, COMBAT_HOLYDAMAGE, -100, COMBAT_FIREDAMAGE, ORIGIN_SPELL)
eq(d1, -570, "event: a level 300 Templar spell hit x0.57")
eq(d2, -57, "event: its secondary damage too")
d1 = ev.onHealthChange({}, templar, -1000, COMBAT_HOLYDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(d1, -1000, "event: a Templar weapon hit unchanged")
d1 = ev.onHealthChange({}, templar, 500, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(d1, 500, "event: a Templar heal unchanged")
d1 = ev.onHealthChange({}, warrior, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(d1, -1040, "event: a level 300 Warrior spell hit x1.04")
F.depth = 1
d1 = ev.onHealthChange({}, templar, -1000, COMBAT_HOLYDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
F.depth = 0
eq(d1, -1000, "event: a guarded hit (a holy strike, a minion) unchanged")
ChaosKeystones = {depth = 1}
d1 = ev.onHealthChange({}, templar, -1000, COMBAT_HOLYDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
ChaosKeystones.depth = 0
eq(d1, -1000, "event: a keystone proc unchanged")
d1 = ev.onHealthChange({}, player(7), -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(d1, -1140, "event: a level 300 Deadeye spell hit x1.14")

-- the guards in the combat scripts
local function read(p) local f = io.open(p); local s = f:read("*a"); f:close(); return s end
local templarSrc = read("data/scripts/chaos/templar_combat.lua")
eq(templarSrc:find("SF.depth = (SF.depth or 0) + 1", 1, true) ~= nil, true, "templar_combat.lua guards the holy strike")
local necroSrc = read("data/scripts/chaos/necro_minions.lua")
eq(necroSrc:find("SF.depth = (SF.depth or 0) + 1", 1, true) ~= nil, true, "necro_minions.lua guards the minion hits")

if fails > 0 then
	error("spell_factor_test: " .. fails .. " failure(s)")
end
print("spell_factor_test: " .. checks .. " checks ok")
