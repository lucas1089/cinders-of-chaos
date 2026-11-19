-- Run from the server/ folder: luajit tests/waystone_tiers_test.lua (or lua5.3; CI runs both)
-- Waystone tiers: waystone_tiers_core.lua (15 tiers 1100-2500, bands, a monster by type and map, its run's level, the
-- engine's level factors, drops, the shielded share) and waystone_tiers.lua against a mocked engine (the shown level at
-- the spawn, health at the first think, a run rescaling its map, experience, damage, drops, the pillar boss hint, the
-- cleared paths at startup).
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

eq(K.tierCount(cfg), 25, "twenty-five tiers (O666: the fourth band, O672: at the cap level)")
eq(K.tierLevel(cfg, 1), 1100, "the first waystone: level 1100 (owner 2026-10-23)")
eq(K.tierLevel(cfg, 15), 2500, "the last of the third band: level 2500")
eq(K.tierLevel(cfg, 16), 2500, "the fourth band opens at the cap level 2500 (O672, owner 2026-11-19)")
eq(K.tierLevel(cfg, 25), 2500, "the last: still level 2500, the player cap")
for t = 2, 15 do
	eq(K.tierLevel(cfg, t) - K.tierLevel(cfg, t - 1), 100, "a gradual rise: +100 at tier " .. t)
end
for t = 16, 25 do
	eq(K.tierLevel(cfg, t), 2500, "the deep tier " .. t .. " is at the cap, no level above 2500")
end
for t = 1, 25 do
	check(K.tierLevel(cfg, t) <= 2500, "no tier above the player cap: " .. t)
end
eq(K.tierLevel(cfg, 26), nil, "no tier XXVI")
eq(#cfg.monsters, 6, "monsters of six base tiers")
eq(#cfg.bosses, 6, "six bosses")
eq(#cfg.maps, 12, "two maps per base tier")
local items = {}
for t, e in ipairs(cfg.tiers) do
	check(not items[e.item], "one item per tier: " .. t)
	items[e.item] = t
	eq(e.base == true, t <= 6, "tiers I-VI are the base items: " .. t)
end
-- every tier in exactly one band; every base tier's maps in exactly one band; 2-3+ scenarios a band
local inBand, mapBand = {}, {}
for bi, bnd in ipairs(cfg.bands) do
	for t = bnd.first, bnd.last do
		check(not inBand[t], "tier " .. t .. " in one band")
		inBand[t] = bi
	end
	local scenarios = 0
	for _, bt in ipairs(bnd.maps) do
		-- the deep band (4) reuses the maps of bands 2 and 3 on purpose; the first three keep one band per base tier
		check(bi == 4 or not mapBand[bt], "base tier " .. bt .. " maps in one band")
		mapBand[bt] = mapBand[bt] or bi
		for _, m in ipairs(cfg.maps) do
			if m.tier == bt then
				scenarios = scenarios + 1
			end
		end
	end
	check(scenarios >= 2, "band " .. bnd.name .. ": at least 2 scenarios (" .. scenarios .. ")")
end
for t = 1, 15 do
	check(inBand[t] ~= nil, "tier " .. t .. " has a band")
end
for bt = 1, 6 do
	check(mapBand[bt] ~= nil, "base tier " .. bt .. " maps are used")
end
for i = 2, 6 do
	check(cfg.bossDamage[i] >= cfg.bossDamage[i - 1], "boss damage does not fall by base tier " .. i)
end
eq(K.tierOfItem(cfg, 29845), 1, "Tier I item")
eq(K.tierOfItem(cfg, 41959), 15, "Tier XV item")
eq(K.tierOfItem(cfg, 2160), nil, "not a waystone")
eq((K.bandOf(cfg, 5)), 1, "tier V: low band")
eq((K.bandOf(cfg, 6)), 2, "tier VI: mid band")
eq((K.bandOf(cfg, 15)), 3, "tier XV: high band")
local bt = K.baseTiersOf(cfg, 12)
check(bt[1] == 5 and bt[2] == 6, "a high tier opens the maps of base tiers V and VI")
-- the maps of different tiers never overlap (a position belongs to one map)
for i, a in ipairs(cfg.maps) do
	for j, b in ipairs(cfg.maps) do
		if i < j and a.from.z == b.from.z then
			local apart = a.to.x < b.from.x or b.to.x < a.from.x or a.to.y < b.from.y or b.to.y < a.from.y
			check(apart, "maps " .. i .. " and " .. j .. " do not overlap")
		end
	end
end

local T1 = {x = 33400, y = 33100, z = 8} -- base tier I underground (map 1)
local T5 = {x = 33450, y = 33250, z = 7} -- base tier V desert (map 9)
local T6 = {x = 33300, y = 33400, z = 7} -- base tier VI forest & desert
eq(K.mapTier(cfg, T1), 1, "a tier I map")
eq(K.mapTier(cfg, T6), 6, "a tier VI map")
eq((K.mapAt(cfg, T5)), 9, "the desert is map 9")
eq(K.mapTier(cfg, {x = 32369, y = 32241, z = 7}), nil, "the temple is no tier map")
eq(K.mapTier(cfg, {x = 33590, y = 33100, z = 7}), nil, "the tier I map's place on another floor")
eq(K.defaultTier(cfg, 1), 1, "a low map before any run: tier I")
eq(K.defaultTier(cfg, 9), 11, "a high map before any run: tier XI")
eq(K.mapOfArea(cfg, {x = 33351, y = 33170, z = 7}), 9, "the base area's fromPos finds the map")
eq(K.mapOfArea(cfg, {x = 1, y = 1, z = 7}), nil, "another area: none")
local e = K.classify(cfg, idx, "Armorcoil", T1)
check(e and e.tier == 1 and not e.boss and e.map == 1 and e.run == 1, "a tier I monster in a tier I map, no run: tier I")
eq(K.level(cfg, e), 1100, "level 1100")
e = K.classify(cfg, idx, "Armorcoil", T1, {[1] = 4})
eq(K.level(cfg, e), 1400, "a Tier IV run in that map: level 1400")
eq(K.classify(cfg, idx, "ARMORCOIL", T6), nil, "a tier I monster elsewhere (a rift, another tier's map): untouched")
eq(K.classify(cfg, idx, "Rat", T1), nil, "another monster in a tier map: untouched")
e = K.classify(cfg, idx, "Morgrath the Umbral Archmage", T5)
check(e and e.tier == 5 and e.boss and e.run == 11, "the base tier V boss, no run: tier XI")
eq(K.classify({enabled = false, maps = cfg.maps}, idx, "Armorcoil", T1), nil, "switched off")

local sc = K.scale(cfg, 500, 1000)
near(sc.health, (1 + 0.0074 * 1000) / (1 + 0.0074 * 500), 1e-12, "health: the engine's x(1 + 0.0074 L)")
near(sc.damage, (1 + 0.0015 * 1000) / (1 + 0.0015 * 500), 1e-12, "damage: the engine's x(1 + 0.0015 L)")
near(sc.experience, 2, 1e-12, "experience x L")
local mon = {tier = 6, boss = false, map = 11, run = 15}
near(K.damageMult(cfg, mon, 500), (1 + 0.0015 * 2500) / (1 + 0.0015 * 500), 1e-12, "a monster's damage at 2500")
local bossE = {tier = 6, boss = true, map = 11, run = 11}
near(K.damageMult(cfg, bossE), cfg.bossDamage[6], 1e-12, "a boss in its band's first tier: bossDamage")
bossE.run = 15
near(K.damageMult(cfg, bossE), cfg.bossDamage[6] * (1 + 0.0015 * 2500) / (1 + 0.0015 * 2100), 1e-12,
	"a boss in tier XV: x the level factor from 2100")
near(K.factors(cfg, bossE).health, (1 + 0.0074 * 2500) / (1 + 0.0074 * 2100), 1e-12, "its health")
eq(K.damageMult(cfg, nil, 500), 1, "nothing: x1")
eq(K.damageMult(cfg, mon, nil), 1, "a monster without a base level: x1")
eq(K.health(40000, 1.5), 60000, "health")
eq(K.health(2000000000, 5), 2147483647, "never above int32")
eq(K.health(0, 2), nil, "no health: none")
-- drops
eq(K.dropTier(cfg, nil, 50), 1, "outside the maps: Tier I")
eq(K.dropTier(cfg, 4, 1), 4, "in a run: its tier (60%)")
eq(K.dropTier(cfg, 4, 60), 4, "60 still its tier")
eq(K.dropTier(cfg, 4, 61), 5, "then the next (30%)")
eq(K.dropTier(cfg, 4, 91), 6, "then two up (10%)")
eq(K.dropTier(cfg, 25, 100), 25, "never above XXV")
eq(K.dropTier(cfg, 24, 95), 25, "capped")
eq(K.dropTier(cfg, 15, 100), 17, "a XV run drops up to XVII")
eq(K.bossDrop(cfg, 7), 8, "the boss adds the next tier")
eq(K.bossDrop(cfg, 15), 16, "the boss of XV adds XVI")
eq(K.bossDrop(cfg, 25), 25, "the last tier's boss: XXV")
eq(K.bossDrop(cfg, nil), nil, "no run: none")
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

local nextId = 100
local function monster(name, pos, hp)
	nextId = nextId + 1
	local m = {name = name, pos = pos, hp = hp or 40000, health = hp or 40000, events = {}, id = nextId}
	function m:getId() return self.id end
	function m:getHealth() return self.health end
	function m:setDisplayLevel(v) self.shown = v end
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

Position = function(x, y, z) return {x = x, y = y, z = z} end
dofile("data/scripts/chaos/waystone_tiers.lua")
local WT = ChaosWaystoneTiers

-- spawn: the run's level is passed to monster_levels.lua (Chaos.spawnLevel), the health waits for the first think
local m = monster("Plague Warbringer", {x = 0, y = 0, z = 0}, 120000)
callbacks.onSpawn(m, T5, false, false)
eq(Chaos.spawnLevel, 2100, "a high map before any run: tier XI, level 2100 shown after the name")
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
eq(Chaos.spawnLevel, 2100, "the boss shows its run's level")
Chaos.spawnLevel = nil

m.pos = T5
events.ChaosWaystoneTierInit.onThink(m, 100)
local want = math.floor(120000 * (1 + 0.0074 * 2100) / (1 + 0.0074 * 612) + 0.5)
eq(m.hp, want, "health at the run's level")
eq(m.health, want, "full health")
eq(m.shown, 2100, "shown level")
check(not m.events.ChaosWaystoneTierInit, "once")
check(m.events.ChaosWaystoneTierDeath, "forgotten at death")
events.ChaosWaystoneTierInit.onThink(m, 100)
eq(m.hp, want, "a second think changes nothing")
boss.pos = T5
events.ChaosWaystoneTierInit.onThink(boss, 100)
eq(boss.hp, 650000, "the boss in its band's first tier: its own health")

-- level for loot.lua / monster_damage.lua / pace.lua
eq(WT.levelOf(m, 612), 2100, "levelOf in its map")
eq(WT.levelOf(boss), 2100, "a boss: its run's level")
m.pos = {x = 32369, y = 32241, z = 7}
eq(WT.levelOf(m), nil, "out of the tier maps: its own level")
m.pos = T5
near(WT.damageMultOf(m), (1 + 0.0015 * 2100) / (1 + 0.0015 * 612), 1e-12, "damage of the monster")
near(WT.damageMultOf(boss), cfg.bossDamage[5], 1e-12, "damage of the base tier V boss")
eq(WT.damageMultOf(rat), 1, "anything else: x1")

-- experience
eq(callbacks.onGainExperience({}, m, 10000, 10000), math.floor(10000 * 2100 / 612 + 1e-9), "experience x L / N")
eq(callbacks.onGainExperience({}, boss, 10000, 10000), 10000, "the boss in its first tier: as before")
eq(callbacks.onGainExperience({}, nil, 10000, 10000), 10000, "no source")

-- the base device: the tier items VII-XV, the maps of a tier, a run
local tabs = WT.tablets()
eq(tabs[41951], 41951, "Tier VII keyed by its server id")
eq(tabs[29845], nil, "the base six keep the base keys")
local mapping = {[29849] = {{area = {fromPos = {x = 33351, y = 33170, z = 7}}}, {area = {fromPos = {x = 32930, y = 32960, z = 7}}}},
	[29850] = {{area = {fromPos = {x = 32890, y = 33257, z = 8}}}, {area = {fromPos = {x = 33124, y = 33376, z = 7}}}},
	[29845] = {{area = {fromPos = {x = 33314, y = 33066, z = 8}}}}}
local opts = WT.optionsFor(41959, mapping)
eq(opts and #opts, 4, "Tier XV: the four maps of base tiers V and VI")
opts = WT.optionsFor(29845, mapping)
eq(opts and #opts, 1, "Tier I: the low band's maps (the mapping's)")
eq(WT.optionsFor(2160, mapping), nil, "not a waystone: the base mapping")

Game = {getSpectators = function() return {m, boss, rat} end}
function rat:getHealth() return 1 end
local hpBefore = m.hp
m.health = math.floor(hpBefore / 2)
eq(WT.startRun({fromPos = {x = 33351, y = 33170, z = 7}}, 41959), 2, "a Tier XV run in the desert: monster and boss rescaled")
eq(WT.active[9], 15, "the map counts at tier XV")
eq(WT.levelOf(m), 2500, "level 2500")
eq(m.shown, 2500, "shown")
local wantHp = math.floor(hpBefore * (1 + 0.0074 * 2500) / (1 + 0.0074 * 2100) + 0.5)
eq(m.hp, wantHp, "health from 2100 to 2500")
eq(m.health, math.floor(math.floor(hpBefore / 2) * wantHp / hpBefore + 0.5), "the same share of health")
eq(boss.hp, math.floor(650000 * (1 + 0.0074 * 2500) / (1 + 0.0074 * 2100) + 0.5), "the boss too")
near(WT.damageMultOf(boss), cfg.bossDamage[5] * (1 + 0.0015 * 2500) / (1 + 0.0015 * 2100), 1e-12, "boss damage at XV")
eq(WT.startRun({fromPos = {x = 33351, y = 33170, z = 7}}, 41959), 0, "the same tier again: nothing to change")
eq(WT.startRun({fromPos = {x = 1, y = 1, z = 7}}, 41959), nil, "not a waystone map")
eq(WT.startRun({fromPos = {x = 33351, y = 33170, z = 7}}, 2160), nil, "not a waystone")
local m3 = monster("Plague Warbringer", T5, 120000)
callbacks.onSpawn(m3, T5, false, false)
eq(Chaos.spawnLevel, 2500, "a respawn during the run: the run's level")
Chaos.spawnLevel = nil
events.ChaosWaystoneTierInit.onThink(m3, 100)
eq(m3.hp, math.floor(120000 * (1 + 0.0074 * 2500) / (1 + 0.0074 * 612) + 0.5), "its health at 2500")
events.ChaosWaystoneTierDeath.onDeath(m3)
eq(WT.applied[m3.id], nil, "death: forgotten")

-- drops
local function corpse(list)
	local c = {items = {}}
	for _, id in ipairs(list) do
		c.items[#c.items + 1] = {id = id}
	end
	function c:getSize() return #self.items end
	function c:getItem(slot)
		local it = self.items[slot + 1]
		if not it then return nil end
		local cc = self
		return {getId = function() return it.id end, getCount = function() return 1 end,
			remove = function() for i, x in ipairs(cc.items) do if x == it then table.remove(cc.items, i) break end end end,
			isWaystoneItem = it.id >= 29845 and it.id <= 29850 or (it.id >= 41951 and it.id <= 41969)}
	end
	function c:addItem(id) self.items[#self.items + 1] = {id = id} return true end
	return c
end
local function isW(item) return item.isWaystoneItem end
local function ids(c)
	local out = {}
	for _, it in ipairs(c.items) do out[#out + 1] = it.id end
	table.sort(out)
	return table.concat(out, ",")
end
local realRandom = math.random
math.random = function() return 1 end -- luacheck: ignore
local c = corpse({2160, 29849})
eq(WT.retierDrops(c, m, isW), 1, "a waystone in a Tier XV run")
eq(ids(c), "2160,41959", "becomes a Tier XV (roll 1: its own tier)")
c = corpse({29846})
eq(WT.retierDrops(c, rat, isW), 1, "outside the maps")
eq(ids(c), "29845", "a Tier I")
c = corpse({2160})
eq(WT.retierDrops(c, boss, isW), 1, "the run's boss")
eq(ids(c), "2160,41960", "adds the next tier (XVI after XV)")
WT.active[9] = 11
c = corpse({})
WT.retierDrops(c, boss, isW)
eq(ids(c), "41956", "a Tier XI run's boss: a Tier XII")
math.random = realRandom -- luacheck: ignore

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

-- ================================================================== a map walked by a tester bot (O651)
-- the maps are the shared base map: a tester opens one only while nobody is in it, one run a map, and is sent out the moment a player steps in
do
	local tcfg = WT.config
	check(tcfg.tester and tcfg.tester.minLevel >= 1000 and tcfg.tester.maxSeconds > 0 and tcfg.tester.kills >= 1, "config: the tester rules")
	check(type(tcfg.arrivals) == "table", "config: the arrivals table")
	local realArrivals = tcfg.arrivals
	tcfg.arrivals = {} -- O657: the config holds all 12 arrival tiles now; this section plays with none and then one
	local creatures = {}
	local function inBox(c, centre, hx, hy)
		return c.pos.z == centre.z and math.abs(c.pos.x - centre.x) <= hx and math.abs(c.pos.y - centre.y) <= hy
	end
	Game = {getSpectators = function(centre, _, onlyPlayers, hx, _, hy)
		local out = {}
		for _, c in pairs(creatures) do
			if inBox(c, centre, hx, hy) and (not onlyPlayers or c:isPlayer()) then out[#out + 1] = c end
		end
		return out
	end}
	local temple = {x = 32369, y = 32241, z = 7}
	local nextP = 500
	local function person(name, level, isT)
		nextP = nextP + 1
		local p = {name = name, id = nextP, pos = {x = 32369, y = 32241, z = 7}, level = level, isT = isT, msgs = {}}
		function p:getName() return self.name end
		function p:getId() return self.id end
		function p:getGuid() return self.id end
		function p:getLevel() return self.level end
		function p:getPosition() return self.pos end
		function p:teleportTo(q) self.pos = {x = q.x, y = q.y, z = q.z} end
		function p:isPlayer() return true end
		function p:isMonster() return false end
		function p:getMaster() return nil end
		function p:getTown() return {getTemplePosition = function() return temple end} end
		function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
		creatures[p.id] = p
		return p
	end
	Chaos.isTester = function(p) return p.isT == true end
	local named = {}
	Player = function(name) return named[name] end
	local bot = person("Tester Wsm", 1500, true)
	named[bot.name] = bot
	local human = person("Real Walt", 1500, false)
	named[human.name] = human
	-- refusals (the cases below start from no arrival: tcfg.arrivals was emptied above)
	local got, why = WT.testerEnter(human, 11)
	check(got == nil and why == "not a tester", "a player never enters this way")
	bot.level = 900
	got, why = WT.testerEnter(bot, 11)
	check(got == nil and why:find("need level 1000", 1, true), "a bot below tester.minLevel: refused (" .. tostring(why) .. ")")
	bot.level = 1500
	got, why = WT.testerEnter(bot, 11)
	check(got == nil and why:find("no map of the band has an arrival", 1, true), "no arrival tile known: refused (" .. tostring(why) .. ")")
	local pr = WT.probe(bot)
	check(pr.inside == false and pr.arrivals == 0 and pr.free == false and pr.minLevel == tcfg.tester.minLevel, "the probe outside: no arrival, no free map")
	got, why = WT.testerEnter(bot, 99)
	check(got == nil and why == "no such tier", "no such tier")
	-- the desert map (9) has an arrival
	local arrival = {x = 33400, y = 33200, z = 7}
	tcfg.arrivals[9] = arrival
	pr = WT.probe(bot)
	check(pr.free == true and pr.arrivals == 1 and pr.freeTier == 11 and pr.freeTierLevel == 2100, "the probe outside: a map is free, at the band's first tier we have an arrival for")
	-- somebody in the map: not free
	local walker = person("Real Wanda", 1500, false)
	walker.pos = {x = 33420, y = 33210, z = 7}
	check(WT.playersIn(9) == 1, "playersIn counts a player in the rectangle")
	got, why = WT.testerEnter(bot, 11)
	check(got == nil and why == "somebody is in the map", "a player is in the map: the tester waits (" .. tostring(why) .. ")")
	walker.pos = {x = 1, y = 1, z = 7}
	check(WT.playersIn(9) == 0, "gone")
	-- the run
	local before = WT.active[9]
	got, why = WT.testerEnter(bot, 11)
	check(got and got.map == 9 and got.tier == 11 and got.tierLevel == 2100 and why == nil, "a free map: the tester is in (" .. tostring(why) .. ")")
	check(bot.pos.x == arrival.x and bot.pos.y == arrival.y and bot.pos.z == arrival.z, "...on the arrival tile")
	eq(WT.active[9], 11, "the map counts at the run's tier")
	got, why = WT.testerEnter(bot, 11)
	check(got == nil and why == "already inside a waystone map", "never twice")
	local bot2 = person("Tester Two", 1500, true)
	got, why = WT.testerEnter(bot2, 11)
	check(got == nil and why == "a tester run holds the map", "a second tester: one run a map (" .. tostring(why) .. ")")
	-- the probe inside: the tier, the level of the monsters, the nearest monster, the guide
	local mon = monster("Plague Warbringer", {x = 33410, y = 33200, z = 7}, 120000)
	creatures[mon.id] = mon
	WT.applied[mon.id] = 2100
	pr = WT.probe(bot)
	check(pr.inside and pr.run.map == 9 and pr.run.tier == 11 and pr.run.tierLevel == 2100 and pr.run.players == 0, "probe inside: the run")
	check(pr.run.monsters == 1 and pr.run.monsterLevel == 2100 and pr.run.nearestHp == 100, "probe inside: the monster and its level")
	check(pr.guide.mode == "walk" and pr.guide.goal.x == 33410 and pr.guide.reach[2] == 5, "the guide walks to the monster")
	bot.pos = {x = 33406, y = 33200, z = 7}
	eq(WT.probe(bot).guide.mode, "fight", "within 5 tiles: fight")
	creatures[mon.id] = nil
	pr = WT.probe(bot)
	check(pr.run.monsters == 0 and pr.guide.mode == "wait", "no monster: wait")
	creatures[mon.id] = mon
	-- players first: a player steps in, the tester is sent out, the map goes back
	walker.pos = {x = 33415, y = 33205, z = 7}
	WT.testerGuard()
	check(WT.testerRuns[9] == nil and bot.pos.x == temple.x, "a player came: the tester is at the temple")
	check(bot.msgs[#bot.msgs]:find("A player came", 1, true), "...and told why")
	eq(WT.active[9], before, "the map counts as before")
	walker.pos = {x = 1, y = 1, z = 7}
	-- the time limit, the bot's own close, a logout
	got = WT.testerEnter(bot, 11)
	check(got ~= nil, "the map is free again")
	clock = clock + tcfg.tester.maxSeconds + 1
	WT.testerGuard()
	check(WT.testerRuns[9] == nil and bot.pos.x == temple.x, "the time of the run is over: out")
	clock = clock + 5
	got = WT.testerEnter(bot, 11)
	check(got ~= nil and WT.testerRuns[9] ~= nil, "in again")
	eq(WT.testerClose(human), false, "a player has no tester run to close")
	eq(WT.testerClose(bot), true, "the bot's own close")
	check(WT.testerRuns[9] == nil and bot.pos.x == temple.x, "out at the temple")
	eq(WT.testerClose(bot), false, "no run: nothing to close")
	got = WT.testerEnter(bot, 11)
	bot.pos = {x = 5, y = 5, z = 7} -- left the map another way (a death)
	WT.testerGuard()
	check(WT.testerRuns[9] == nil, "a bot that is no longer in the map ends its run")
	tcfg.arrivals = realArrivals
end

print(string.format("waystone_tiers_test: %d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)
