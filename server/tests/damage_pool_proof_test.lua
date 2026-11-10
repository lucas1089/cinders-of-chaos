-- Run from the server/ folder: luajit tests/damage_pool_proof_test.lua && lua5.3 tests/damage_pool_proof_test.lua (CI runs both)
-- O473: the audit's cases A to L of the O468 spell scaling study (SP/spellscale proof_tree.lua), rewritten to the one additive damage
-- pool. The REAL ChaosPassiveDealt event (passivetree_effects.lua with spell_factor_core.lua, spell_factor_config.lua, class_tree.lua,
-- classes.lua) on a mocked engine. Each case keeps its number of the audit when only the tree gives bonuses (the pool of one source is
-- the old factor), and a second line adds a gem and a unique passive to show the sum: the sources add into one pool, the class factor,
-- the attributes and the spell factor stay outside it.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
COMBAT_PHYSICALDAMAGE, COMBAT_FIREDAMAGE, COMBAT_HEALING = 1, 8, 256
ORIGIN_NONE, ORIGIN_CONDITION, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED, ORIGIN_WAND = 0, 1, 2, 3, 4, 5
dofile("data/scripts/chaos/chaos_constants.lua")
ChaosOpcodes = ChaosOpcodes or {}
local registered = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
rawset(EventCallback, "register", function(self) local l = rawget(self, "_last"); registered[l[1]] = l[2] end)
function CreatureEvent(name) local o = {}; function o:register() registered[name] = o end; return o end
function Condition(t) local c = {t = t, p = {}}; function c:setTicks(x) end; function c:setParameter(k, v) self.p[k] = v end; return c end
function addEvent() end
os.mtime = function() return 1000 end
dofile("data/scripts/chaos/passivetree_effects.lua")
dofile("data/scripts/chaos/class_tree.lua")
local ev = registered["ChaosPassiveDealt"]
local checks, fails = 0, 0
local function near(a, b, tol, m)
	checks = checks + 1
	if math.abs(a - b) > tol then
		fails = fails + 1
		print("FAIL " .. m .. ": " .. tostring(a) .. " vs " .. tostring(b))
	end
end
local function player(vocId, level, id)
	local p = {}
	function p:isPlayer() return true end
	function p:getId() return id or 7 end
	function p:getLevel() return level end
	function p:getVocation() return {getId = function() return vocId end} end
	function p:getCondition() return nil end
	return p
end
local function monsterOf(master)
	local m = {}
	function m:isPlayer() return false end
	function m:getId() return 99 end
	function m:getMaster() return master end
	return m
end
local target = {getId = function() return 500 end}
local function run(attacker, ptype, origin, dmg)
	local d = ev.onHealthChange(target, attacker, dmg or -1000, ptype, 0, 0, origin)
	return -d
end
local function stand(name, raw)
	ChaosDamagePool.register(name, function() return raw end)
end
for _, name in ipairs({"uniques", "gems", "masteries", "cardSets", "charms", "families"}) do
	stand(name, 0)
end

-- an Elementalist (vocation 5) at level 500 with a tree: fire +60, all elements +20, Spell Damage gear +10, intelligence 60 points
local mage = player(5, 500, 7)
ChaosPassiveCache[7] = {incrementFire = 60, multiIncrement = 20, intelligence = 60, gearSpell = 10}
local sf = ChaosSpellFactor.forVocation(5, nil, 500)
local line = ChaosPassiveLineFactor(mage)
local intm = 1 + ChaosPassiveCharStat(60, "intelligence") / 230
near(sf, 0.6433, 0.001, "the class spell factor of the audit")
near(line, 1.14, 1e-9, "the class damage of the audit")
-- A: a spell hit: spell factor x (1 + (60 + 20 + 10) / 100) x intelligence x class damage
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 1683, 2, "A  spell hit")
-- B: a condition tick: no spell factor, no worn Spell Damage
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_CONDITION), 1000 * (1 + 80 / 100) * intm * line, 2, "B  condition tick")
-- C: a wand hit: Spell Damage counts, no spell factor
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_WAND), 2618, 2, "C  wand hit")
-- D: a weapon hit: no spell factor, no worn Spell Damage
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_MELEE), 2480, 2, "D  weapon hit")
-- E: the attacker is the player's summon: the tree and the pool are not applied (only the PvP scale could, and the target is no player)
near(run(monsterOf(mage), COMBAT_FIREDAMAGE, ORIGIN_MELEE), 1000, 0, "E  a summon as the attacker")
-- F: inside the class spell factor's guard (a necromancer minion, the bite): pool and class damage, no spell factor
ChaosSpellFactor.depth = 1
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 2618, 2, "F  inside the guard")
ChaosSpellFactor.depth = 0
-- G: a keystone proc: nothing at all
ChaosKeystones = {depth = 1}
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 1000, 0, "G  a proc")
ChaosKeystones = nil
-- H: a heal: the tree's Healing and intelligence only, no pool source, no spell factor, no class damage
ChaosPassiveCache[7] = {incrementHealth = 30, intelligence = 60, gearSpell = 10}
local healer = player(10, 500, 7)
stand("gems", 25) stand("uniques", 40)
near(ev.onHealthChange(target, healer, 1000, COMBAT_HEALING, 0, 0, ORIGIN_SPELL), 1571, 2, "H  a heal takes no source of the pool")
stand("gems", 0) stand("uniques", 0)
-- I and J: a Warrior (vocation 4): melee with dexterity, a spell without it
local war = player(4, 500, 8)
ChaosPassiveCache[8] = {incrementPhysical = 40, strength = 60, dexterity = 20}
near(-ev.onHealthChange(target, war, -1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE), 1331, 2, "I  a Warrior melee hit")
near(-ev.onHealthChange(target, war, -1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_SPELL), 1088, 2, "J  a Warrior spell")
-- K: +400 raw: held by the soft cap
ChaosPassiveCache[8] = {incrementPhysical = 400}
near(-ev.onHealthChange(target, war, -1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE), 2303, 3, "K  the soft cap")
-- L: no tree state: the spell factor only
ChaosPassiveCache[7] = nil
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 643, 1, "L  no tree state")

-- the same cases with a gem (+25) and a unique passive (+10): one pool, the sum is 90 + 35
ChaosPassiveCache[7] = {incrementFire = 60, multiIncrement = 20, intelligence = 60, gearSpell = 10}
stand("gems", 25) stand("uniques", 10)
local pool = 1 + (60 + 20 + 10 + 25 + 10) / 100
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 1000 * sf * pool * intm * line, 2, "A+ spell hit with a gem and a unique power: one pool")
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_WAND), 1000 * pool * intm * line, 2, "C+ wand hit")
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_MELEE), 1000 * (1 + (60 + 20 + 25 + 10) / 100) * intm * line, 2, "D+ weapon hit: no worn Spell Damage")
ChaosSpellFactor.depth = 1
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 1000 * pool * intm * line, 2, "F+ inside the guard")
ChaosSpellFactor.depth = 0
ChaosKeystones = {depth = 1}
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 1000, 0, "G+ a proc: nothing")
ChaosKeystones = nil
ChaosPassiveCache[8] = {incrementPhysical = 400, strength = 60, dexterity = 20}
stand("gems", 12) stand("uniques", 10)
do
	local m = (1 + ChaosSoftCap(400 + 12 + 10, 150, 60) / 100) * (1 + ChaosPassiveCharStat(60, "strength") / 230)
		/ (1 - ChaosPassiveCharStat(20, "dexterity") / 100) * ChaosPassiveLineFactor(war)
	near(-ev.onHealthChange(target, war, -1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE), 1000 * m, 3, "K+ the soft cap holds the whole sum once")
end
ChaosPassiveCache[7] = nil
near(run(mage, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 1000 * sf * (1 + (12 + 10) / 100), 2, "L+ no tree state: the gem and the unique power still count, the class damage does not")

if fails > 0 then
	error(fails .. " of " .. checks .. " damage pool proof checks failed")
end
print("damage_pool_proof_test: " .. checks .. " checks OK")
