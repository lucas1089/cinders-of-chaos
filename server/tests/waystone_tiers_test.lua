-- Run from the server/ folder: luajit tests/waystone_tiers_test.lua (or lua5.3; CI runs both)
-- Waystone tiers: waystone_tiers_core.lua (tier of a monster by type and map, level, the engine's level factors, the
-- shielded share) and waystone_tiers.lua against a mocked engine (the shown level at the spawn, health at the first
-- think, experience, damage, the pillar boss hint, the cleared paths at startup).
local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end
local function near(a, b, eps, label)
	check(type(a) == "number" and math.abs(a - b) <= (eps or 1e-9), label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

-- ================================================================== the core
dofile("data/scripts/chaos/waystone_tiers_core.lua")
local K = ChaosWaystoneTiersCore
local cfg = dofile("data/scripts/chaos/waystone_tiers_config.lua")
local idx = K.index(cfg)

eq(#cfg.levelMult, 6, "six tiers")
eq(#cfg.monsters, 6, "monsters of six tiers")
eq(#cfg.bosses, 6, "six bosses")
eq(#cfg.maps, 12, "two maps per tier")
local seen = {}
for t, list in ipairs(cfg.monsters) do
	for _, n in ipairs(list) do
		check(not seen[n:lower()], "a monster belongs to one tier: " .. n)
		seen[n:lower()] = t
	end
end
for i = 2, 6 do
	check(cfg.levelMult[i] > cfg.levelMult[i - 1], "level rises by tier " .. i)
	check(cfg.bossDamage[i] >= cfg.bossDamage[i - 1], "boss damage does not fall by tier " .. i)
end
eq(cfg.levelMult[1], 1.0, "tier I keeps its level")
-- the maps of different tiers never overlap (a position belongs to one tier)
for i, a in ipairs(cfg.maps) do
	for j, b in ipairs(cfg.maps) do
		if i < j and a.from.z == b.from.z then
			local apart = a.to.x < b.from.x or b.to.x < a.from.x or a.to.y < b.from.y or b.to.y < a.from.y
			check(apart, "maps " .. i .. " and " .. j .. " do not overlap")
		end
	end
end

local T1 = {x = 33400, y = 33100, z = 8} -- tier I underground
local T5 = {x = 33450, y = 33250, z = 7} -- tier V desert
local T6 = {x = 33300, y = 33400, z = 7} -- tier VI forest & desert
eq(K.mapTier(cfg, T1), 1, "a tier I map")
eq(K.mapTier(cfg, T6), 6, "a tier VI map")
eq(K.mapTier(cfg, {x = 32369, y = 32241, z = 7}), nil, "the temple is no tier map")
eq(K.mapTier(cfg, {x = 33590, y = 33100, z = 7}), nil, "the tier I map's place on another floor")
local e = K.classify(cfg, idx, "Armorcoil", T1)
check(e and e.tier == 1 and not e.boss, "a tier I monster in a tier I map")
eq(K.classify(cfg, idx, "ARMORCOIL", T6), nil, "a tier I monster elsewhere (a rift, another tier's map): untouched")
eq(K.classify(cfg, idx, "Rat", T1), nil, "another monster in a tier map: untouched")
e = K.classify(cfg, idx, "Morgrath the Umbral Archmage", T5)
check(e and e.tier == 5 and e.boss, "the tier V boss")
eq(K.classify({enabled = false, maps = cfg.maps}, idx, "Armorcoil", T1), nil, "switched off")

-- the player report: 468-612 in every tier. Now x levelMult
eq(K.level(cfg, 1, 474), 474, "tier I: as before")
eq(K.level(cfg, 4, 474), 758, "tier IV: x1.6")
eq(K.level(cfg, 6, 612), 1224, "tier VI: x2")
eq(K.level(cfg, 3, 0), nil, "no level: none")
eq(K.level(cfg, 3, 0 / 0), nil, "NaN: none")
local sc = K.scale(cfg, 500, 1000)
near(sc.health, (1 + 0.0074 * 1000) / (1 + 0.0074 * 500), 1e-12, "health: the engine's x(1 + 0.0074 L)")
near(sc.damage, (1 + 0.0015 * 1000) / (1 + 0.0015 * 500), 1e-12, "damage: the engine's x(1 + 0.0015 L)")
near(sc.experience, 2, 1e-12, "experience x L")
sc = K.scale(cfg, 474, 474)
check(sc.health == 1 and sc.damage == 1 and sc.experience == 1, "tier I: x1")
near(K.damageMult(cfg, {tier = 6, boss = false}, 500), (1 + 0.0015 * 1000) / (1 + 0.0015 * 500), 1e-12, "a monster's damage")
eq(K.damageMult(cfg, {tier = 6, boss = true}), cfg.bossDamage[6], "a boss's damage: bossDamage")
eq(K.damageMult(cfg, nil, 500), 1, "nothing: x1")
eq(K.health(40000, 1.5), 60000, "health")
eq(K.health(2000000000, 5), 2147483647, "never above int32")
eq(K.health(0, 2), nil, "no health: none")
local p, s = K.shielded(cfg, 1000, 401)
eq(p, 250, "shielded keeps the share (primary)")
eq(s, 100, "and the secondary, whole")
p, s = K.shielded({shieldedShare = 0}, 1000, 400)
check(p == 0 and s == 0, "share 0: the base rule (nothing)")
p = K.shielded({shieldedShare = 7}, 1000, 0)
eq(p, 1000, "share capped at 1")

-- ================================================================== the engine file
Chaos = {spawnLevel = nil, t = function(_, fmt, ...) return string.format(fmt, ...) end}
function Chaos.monsterTypeName(m) return m.typeName or m.name end
local callbacks = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v)
	rawset(t, k, v)
	callbacks[k] = v
end})
function EventCallback.register() end
local events = {}
CreatureEvent = function(name)
	local ev = {name = name}
	function ev:type() end
	function ev:register() events[name] = self end
	return ev
end
local globals = {}
GlobalEvent = function(name)
	local ev = {name = name}
	function ev:register() globals[name] = self end
	return ev
end
MESSAGE_STATUS_SMALL = 1
local clock = 1000
os.time = function() return clock end -- luacheck: ignore

local pool = {armorcoil = 474, ["plague warbringer"] = 612}
ChaosLoot = {}
function ChaosLoot.baseMonsterLevel(m) return pool[m.name:lower()] or 1610 end

local function monster(name, pos, hp)
	local m = {name = name, pos = pos, hp = hp or 40000, events = {}}
	function m:getId() return 7 end
	function m:isMonster() return true end
	function m:isPlayer() return false end
	function m:getMaster() return nil end
	function m:getName() return self.name end
	function m:getPosition() return self.pos end
	function m:getMaxHealth() return self.hp end
	function m:setMaxHealth(v) self.hp = v end
	function m:setHealth(v) self.health = v end
	function m:registerEvent(n) self.events[n] = true end
	function m:unregisterEvent(n) self.events[n] = nil end
	return m
end

dofile("data/scripts/chaos/waystone_tiers.lua")
local WT = ChaosWaystoneTiers

-- spawn: the tier level is passed to monster_levels.lua (Chaos.spawnLevel), the health waits for the first think
local m = monster("Plague Warbringer", {x = 0, y = 0, z = 0}, 120000)
callbacks.onSpawn(m, T5, false, false)
eq(Chaos.spawnLevel, 1102, "tier V: 612 x 1.8 shown after the name")
check(m.events.ChaosWaystoneTierInit, "health at the first think")
Chaos.spawnLevel = 900
local m2 = monster("Plague Warbringer", {x = 0, y = 0, z = 0})
callbacks.onSpawn(m2, T5, false, false)
eq(Chaos.spawnLevel, 900, "a level another system set wins")
Chaos.spawnLevel = nil
local rat = monster("Rat", T5)
callbacks.onSpawn(rat, T5, false, false)
eq(Chaos.spawnLevel, nil, "another monster: nothing")
check(not rat.events.ChaosWaystoneTierInit, "and no think event")
local boss = monster("Morgrath the Umbral Archmage", T5, 650000)
callbacks.onSpawn(boss, T5, false, false)
check(Chaos.spawnLevel == nil and not boss.events.ChaosWaystoneTierInit, "a boss keeps its own level and health")

m.pos = T5
events.ChaosWaystoneTierInit.onThink(m, 100)
local want = math.floor(120000 * (1 + 0.0074 * 1102) / (1 + 0.0074 * 612) + 0.5)
eq(m.hp, want, "health at the tier level")
eq(m.health, want, "full health")
check(not m.events.ChaosWaystoneTierInit, "once")

-- level for loot.lua / monster_damage.lua / pace.lua
eq(WT.levelOf(m, 612), 1102, "levelOf in its map")
eq(WT.levelOf(m), 1102, "levelOf reads the base level itself")
eq(WT.levelOf(boss), nil, "a boss: its own level")
m.pos = {x = 32369, y = 32241, z = 7}
eq(WT.levelOf(m), nil, "out of the tier maps: its own level")
m.pos = T5
near(WT.damageMultOf(m), (1 + 0.0015 * 1102) / (1 + 0.0015 * 612), 1e-12, "damage of a tier V monster")
eq(WT.damageMultOf(boss), cfg.bossDamage[5], "damage of the tier V boss")
eq(WT.damageMultOf(rat), 1, "anything else: x1")

-- experience
eq(callbacks.onGainExperience({}, m, 10000, 10000), math.floor(10000 * 1102 / 612 + 1e-9), "experience x L / N")
eq(callbacks.onGainExperience({}, boss, 10000, 10000), 10000, "a boss: as before")
eq(callbacks.onGainExperience({}, nil, 10000, 10000), 10000, "no source")

-- the pillar boss away from its pillar: the share, and the attacker told (not every hit)
local pl = {msgs = {}}
function pl:isPlayer() return true end
function pl:getId() return 99 end
function pl:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
local a, b = WT.shielded(boss, pl, 4000, 0)
eq(a, 1000, "a quarter of the hit")
eq(b, 0, "secondary")
eq(#pl.msgs, 1, "told")
check(pl.msgs[1]:find("Morgrath the Umbral Archmage is shielded", 1, true) ~= nil, "the text: " .. tostring(pl.msgs[1]))
WT.shielded(boss, pl, 4000, 0)
eq(#pl.msgs, 1, "not on every hit")
clock = clock + 20
WT.shielded(boss, pl, 4000, 0)
eq(#pl.msgs, 2, "again after hintSeconds")
a = WT.shielded(boss, nil, 4000, 0)
eq(a, 1000, "no attacker (a field): the share")

-- startup: the blocking items on the way to the tier IV levers come off (skipped when gone)
local removed = {}
local present = {["33217:33237:7"] = 2768, ["33264:33412:8"] = 3770}
Position = function(x, y, z) return {x = x, y = y, z = z} end
Tile = function(pos)
	local key = pos.x .. ":" .. pos.y .. ":" .. pos.z
	return {getItemById = function(_, id)
		if present[key] == id then
			return {remove = function() present[key] = nil removed[#removed + 1] = key end}
		end
		return nil
	end}
end
eq(WT.clearPaths(), 2, "two present items removed")
eq(present["33217:33237:7"], nil, "the fir tree")
eq(WT.clearPaths(), 0, "a second run: nothing left")
check(globals.ChaosWaystoneTiersStartup ~= nil, "startup event registered")

print(string.format("waystone_tiers_test: %d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)
