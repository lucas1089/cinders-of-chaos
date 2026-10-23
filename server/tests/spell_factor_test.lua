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

-- the table: the owner's factors by vocation id (docs/CLASSES.md ids)
-- retuned 2026-10-23 with the attack kit (server/data/spells/README.md "Attack spell parity")
local want = {[7] = 1.19, [3] = 1.06, [17] = 0.87, [21] = 0.82, [24] = 0.75, [18] = 0.74, [10] = 0.73, [5] = 0.7,
	[23] = 0.6, [20] = 0.59, [22] = 0.59, [25] = 0.57}
local count = 0
for id, v in pairs(C.byVocation) do
	count = count + 1
	eq(v, want[id], "factor of vocation " .. id)
end
eq(count, 12, "twelve classes listed")
for _, id in ipairs({1, 4, 8, 11, 12, 13, 14, 15, 19}) do
	eq(F.forVocation(id), 1, "vocation " .. id .. " keeps 1")
end

-- the rule
local SPELL, MELEE, COND, WAND, HEAL, FIRE = 1, 2, 3, 4, 100, 7
eq(F.factor(23, SPELL, FIRE, SPELL, HEAL, false), 0.6, "a Templar spell hit")
eq(F.factor(7, SPELL, FIRE, SPELL, HEAL, false), 1.19, "a Deadeye spell hit")
eq(F.factor(15, SPELL, FIRE, SPELL, HEAL, false), 1, "a Beastmaster spell hit (1 since 2026-10-23)")
eq(F.factor(23, MELEE, FIRE, SPELL, HEAL, false), 1, "a weapon hit")
eq(F.factor(23, WAND, FIRE, SPELL, HEAL, false), 1, "a wand hit")
eq(F.factor(23, COND, FIRE, SPELL, HEAL, false), 1, "a condition tick")
eq(F.factor(23, SPELL, HEAL, SPELL, HEAL, false), 1, "healing")
eq(F.factor(23, SPELL, 0, SPELL, HEAL, false), 1, "no secondary damage")
eq(F.factor(23, SPELL, FIRE, SPELL, HEAL, true), 1, "a keystone proc")
eq(F.factor(4, SPELL, FIRE, SPELL, HEAL, false), 1, "a Warrior spell hit")
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
eq(d1, -600, "event: a Templar spell hit x0.6")
eq(d2, -60, "event: its secondary damage too")
d1 = ev.onHealthChange({}, templar, -1000, COMBAT_HOLYDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(d1, -1000, "event: a Templar weapon hit unchanged")
d1 = ev.onHealthChange({}, templar, 500, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(d1, 500, "event: a Templar heal unchanged")
d1 = ev.onHealthChange({}, warrior, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(d1, -1000, "event: a Warrior spell hit unchanged")
F.depth = 1
d1 = ev.onHealthChange({}, templar, -1000, COMBAT_HOLYDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
F.depth = 0
eq(d1, -1000, "event: a guarded hit (a holy strike, a minion) unchanged")
ChaosKeystones = {depth = 1}
d1 = ev.onHealthChange({}, templar, -1000, COMBAT_HOLYDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
ChaosKeystones.depth = 0
eq(d1, -1000, "event: a keystone proc unchanged")
d1 = ev.onHealthChange({}, player(7), -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(d1, -1190, "event: a Deadeye spell hit x1.19")

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
