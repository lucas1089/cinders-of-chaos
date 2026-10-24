-- Run from the server/ folder: luajit tests/monster_damage_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Late-game monster damage boost: monster_damage_core.lua (percent by level, rounding, which damage parts) and
-- data/scripts/chaos/monster_damage.lua against a mocked engine: physical vs elemental, origins, monster vs player only,
-- the level bands, a player's summons excluded, a monster's summons at their master's level, invaders at the area
-- level, PvP unaffected, the mana shield path (no double scaling), the login registration order and the config switch.

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, what)
	ok(math.abs(a - b) < 1e-9, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ---------------------------------------------------------------- engine mock
COMBAT_NONE, COMBAT_PHYSICALDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_FIREDAMAGE = 0, 1, 2, 4, 8
COMBAT_UNDEFINEDDAMAGE, COMBAT_LIFEDRAIN, COMBAT_MANADRAIN, COMBAT_HEALING = 16, 32, 64, 128
COMBAT_ICEDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_DEATHDAMAGE = 512, 1024, 2048
ORIGIN_NONE, ORIGIN_CONDITION, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED, ORIGIN_WAND = 0, 1, 2, 3, 4, 5

local events = {}
function CreatureEvent(name)
	local e = {name = name}
	function e:register()
		events[name] = self
	end
	return e
end

local clock = 1000
os.mtime = function() return clock end

Chaos = Chaos or {}
local poolLevels = {} -- name -> level (as the bounty pool / ChaosLoot.monsterLevel would give)
ChaosLoot = {
	monsterLevel = function(monster)
		if monster.mlevel and monster.mlevel > 0 then
			return monster.mlevel
		end
		return poolLevels[monster.name] or 0
	end
}

local nextId = 0x40000000
local function creature(kind, opts)
	nextId = nextId + 1
	local c = {id = nextId, kind = kind, name = opts.name or kind, mlevel = opts.level, master = opts.master,
		mana = opts.mana or 0, registered = {}}
	function c:getId() return self.id end
	function c:isPlayer() return self.kind == "player" end
	function c:isMonster() return self.kind == "monster" end
	function c:getMaster() return self.master end
	function c:getName() return self.name end
	function c:getMana() return self.mana end
	function c:getMonsterLevel() return self.mlevel or 0 end
	function c:registerEvent(n) self.registered[#self.registered + 1] = n return true end
	return c
end
local function monster(level, opts)
	opts = opts or {}
	opts.level = level
	return creature("monster", opts)
end
local function player(opts) return creature("player", opts or {}) end

dofile("data/scripts/chaos/monster_damage.lua")
local MD, C = ChaosMonsterDamage, ChaosMonsterDamageCore
local cfg = Chaos.monsterDamage
ok(MD and C and cfg, "modules loaded")

local function hit(target, attacker, p, pt, s, st, origin)
	local a, b, c2, d = events.ChaosMonsterDamageHealth.onHealthChange(target, attacker, p, pt, s or 0, st or COMBAT_NONE,
		origin or ORIGIN_MELEE)
	return a, c2, b, d
end
local function manaHit(target, attacker, p, pt, s, st, origin)
	local a, b, c2, d = events.ChaosMonsterDamageMana.onManaChange(target, attacker, p, pt, s or 0, st or COMBAT_NONE,
		origin or ORIGIN_MELEE)
	return a, c2, b, d
end

-- ---------------------------------------------------------------- config and the percent by level
eq(cfg.enabled, true, "enabled by default")
eq(cfg.elemental, false, "physical only by default")
ok(#cfg.points >= 2, "points")
for i = 2, #cfg.points do
	ok(cfg.points[i].level > cfg.points[i - 1].level, "points sorted by level " .. i)
	ok(cfg.points[i].percent >= cfg.points[i - 1].percent, "percent does not fall " .. i)
end
eq(cfg.points[1].percent, 0, "the first point is 0%")
ok(cfg.points[1].level >= 130, "the level 100 band (hunting level 80-130) is not boosted")

local pts = {enabled = true, points = {{level = 150, percent = 0}, {level = 300, percent = 14}, {level = 650, percent = 30}}}
eq(C.percentFor(pts, 0), 0, "unknown level")
eq(C.percentFor(pts, nil), 0, "nil level")
eq(C.percentFor(pts, 50), 0, "level 50")
eq(C.percentFor(pts, 100), 0, "level 100")
eq(C.percentFor(pts, 150), 0, "level 150")
near(C.percentFor(pts, 225), 7, "level 225 halfway")
eq(C.percentFor(pts, 300), 14, "level 300")
near(C.percentFor(pts, 475), 22, "level 475 halfway")
eq(C.percentFor(pts, 650), 30, "level 650")
eq(C.percentFor(pts, 1000), 30, "level 1000 flat")
eq(C.percentFor(pts, 5000), 30, "level 5000 flat")
eq(C.percentFor({points = {}}, 500), 0, "no points")
near(C.multiplierFor(pts, 650), 1.3, "multiplier")
eq(C.multiplierFor({enabled = false, points = pts.points}, 650), 1, "disabled")

-- rounding to the nearest point, sign kept
eq(C.scale(100, 1.3), 130, "scale 100")
eq(C.scale(101, 1.14), 115, "scale 101 x 1.14 = 115.14")
eq(C.scale(-100, 1.3), -130, "scale negative")
eq(C.scale(0, 1.3), 0, "scale 0")
eq(C.scale(7, 1), 7, "mult 1")

-- which parts are boosted
local K = MD.K
eq(C.isBoosted(pts, K, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), true, "physical melee")
eq(C.isBoosted(pts, K, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED), true, "physical ranged")
eq(C.isBoosted(pts, K, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL), false, "physical scripted (reflection, boss scripts)")
eq(C.isBoosted(pts, K, COMBAT_PHYSICALDAMAGE, ORIGIN_CONDITION), false, "bleeding")
eq(C.isBoosted(pts, K, COMBAT_FIREDAMAGE, ORIGIN_RANGED), false, "fire")
eq(C.isBoosted(pts, K, COMBAT_DEATHDAMAGE, ORIGIN_MELEE), false, "death")
eq(C.isBoosted(pts, K, COMBAT_LIFEDRAIN, ORIGIN_RANGED), false, "life drain")
eq(C.isBoosted(pts, K, COMBAT_HEALING, ORIGIN_SPELL), false, "healing")
eq(C.isBoosted(pts, K, COMBAT_UNDEFINEDDAMAGE, ORIGIN_MELEE), false, "undefined")
local withElem = {enabled = true, elemental = true, points = pts.points}
eq(C.isBoosted(withElem, K, COMBAT_FIREDAMAGE, ORIGIN_SPELL), true, "elemental option: fire spell")
eq(C.isBoosted(withElem, K, COMBAT_ICEDAMAGE, ORIGIN_RANGED), true, "elemental option: ice")
eq(C.isBoosted(withElem, K, COMBAT_FIREDAMAGE, ORIGIN_CONDITION), false, "elemental option: burning condition")
eq(C.isBoosted(withElem, K, COMBAT_HEALING, ORIGIN_SPELL), false, "elemental option: healing")
eq(C.isBoosted(withElem, K, COMBAT_MANADRAIN, ORIGIN_SPELL), false, "elemental option: mana drain")

-- ---------------------------------------------------------------- the event: monster -> player
local pct300 = C.percentFor(cfg, 300)
local pct1000 = C.percentFor(cfg, 1000)
local pct650 = C.percentFor(cfg, 650)
ok(pct300 >= 8 and pct300 <= 20, "level 300 boost in range: " .. pct300)
ok(pct1000 >= pct300, "level 1000 boost at least the level 300 one")

local pl = player()
local m50, m300, m1000 = monster(50), monster(300), monster(1000)
local p, s, pt, st = hit(pl, m300, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, math.floor(1000 * (1 + pct300 / 100) + 0.5), "level 300 melee boosted")
eq(pt, COMBAT_PHYSICALDAMAGE, "type kept")
p = hit(pl, m1000, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED)
eq(p, math.floor(1000 * (1 + pct1000 / 100) + 0.5), "level 1000 ranged physical boosted")
p = hit(pl, m50, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, 1000, "level 50 monster unchanged")
p = hit(pl, monster(120), 1000, COMBAT_PHYSICALDAMAGE)
eq(p, 1000, "level 120 monster unchanged")

-- elemental unchanged, mixed hit: only the physical part
p = hit(pl, m1000, 800, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(p, 800, "fire spell unchanged")
p, s = hit(pl, m1000, 1000, COMBAT_PHYSICALDAMAGE, 500, COMBAT_ENERGYDAMAGE)
eq(p, math.floor(1000 * (1 + pct1000 / 100) + 0.5), "mixed hit: physical part boosted")
eq(s, 500, "mixed hit: energy part unchanged")
p, s = hit(pl, m1000, 600, COMBAT_EARTHDAMAGE, 400, COMBAT_PHYSICALDAMAGE)
eq(p, 600, "earth primary unchanged")
eq(s, math.floor(400 * (1 + pct1000 / 100) + 0.5), "physical secondary boosted")
p = hit(pl, m1000, 300, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(p, 300, "scripted physical (reflection) unchanged")
p = hit(pl, m1000, 300, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_CONDITION)
eq(p, 300, "bleeding unchanged")
p = hit(pl, m1000, 300, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(p, 300, "healing unchanged")

-- level from the hunting level (no engine level) and from the engine level
poolLevels["Juggernaut"] = 300
p = hit(pl, monster(0, {name = "Juggernaut"}), 1000, COMBAT_PHYSICALDAMAGE)
eq(p, math.floor(1000 * (1 + pct300 / 100) + 0.5), "hunting level 300 (bounty pool)")
poolLevels["Dragon"] = 42
p = hit(pl, monster(0, {name = "Dragon"}), 1000, COMBAT_PHYSICALDAMAGE)
eq(p, 1000, "hunting level 42 unchanged")
p = hit(pl, monster(0, {name = "Unknown Thing"}), 1000, COMBAT_PHYSICALDAMAGE)
eq(p, 1000, "unknown level unchanged")

-- not a player target: monster -> monster (e.g. a player's summon is hit), no attacker (fields)
local mTarget = monster(100)
p = hit(mTarget, m1000, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, 1000, "monster target unchanged")
p = hit(pl, nil, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, 1000, "no attacker unchanged")

-- PvP unaffected
local other = player()
p = hit(pl, other, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, 1000, "PvP melee unchanged")
p = hit(pl, other, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED)
eq(p, 1000, "PvP ranged unchanged")

-- summons: a player's summon is never boosted (whatever its level); a monster's summon counts at its master's level
local playerSummon = monster(1000, {master = other})
p = hit(pl, playerSummon, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, 1000, "a player's summon (level 1000) unchanged")
local minion = monster(0, {name = "Weak Minion", master = m1000})
p = hit(pl, minion, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, math.floor(1000 * (1 + pct1000 / 100) + 0.5), "a level 1000 boss's summon at the boss's level")
local lowMaster = monster(0, {name = "Weak Master"})
p = hit(pl, monster(1000, {master = lowMaster}), 1000, COMBAT_PHYSICALDAMAGE)
eq(p, math.floor(1000 * (1 + pct1000 / 100) + 0.5), "a strong summon of a weak monster keeps its own level")

-- invaders: at least the invasion area's level
ChaosInvasion = {invaders = {}}
local invader = monster(0, {name = "Dragon"})
ChaosInvasion.invaders[invader:getId()] = {areaLevel = 300}
p = hit(pl, invader, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, math.floor(1000 * (1 + pct300 / 100) + 0.5), "a Dragon invader in a level 300 area counts at 300")
local lowArea = monster(1000)
ChaosInvasion.invaders[lowArea:getId()] = {areaLevel = 100}
p = hit(pl, lowArea, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, math.floor(1000 * (1 + pct1000 / 100) + 0.5), "an invader keeps its own higher level")
ChaosInvasion = nil

-- Infinity Tower (O168): a tower monster counts at least at the level of its floor, a higher own level stays
local towerLevels = {}
ChaosTowerRun = {levelOf = function(mon) return towerLevels[mon:getId()] end}
local towerTroll = monster(20, {name = "Troll"})
towerLevels[towerTroll:getId()] = 650
p = hit(pl, towerTroll, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, math.floor(1000 * (1 + pct650 / 100) + 0.5), "a level 20 troll on a level 650 tower floor counts at 650")
local towerHigh = monster(1000)
towerLevels[towerHigh:getId()] = 300
p = hit(pl, towerHigh, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, math.floor(1000 * (1 + pct1000 / 100) + 0.5), "a tower monster keeps its own higher level")
ChaosTowerRun = nil

-- ---------------------------------------------------------------- mana shield
local mp = player({mana = 5000})
local boosted = math.floor(1000 * (1 + pct1000 / 100) + 0.5)
p = manaHit(mp, m1000, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, boosted, "mana shield: the mana event scales the hit")
-- the mana took all of it: the next (different) hit is scaled normally
clock = clock + 1
p = hit(mp, m1000, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, boosted, "after a hit the mana took whole, the next health hit is scaled")
-- the mana cannot take it all: the rest of the same hit is not scaled twice
local low = player({mana = 200})
clock = clock + 1
p = manaHit(low, m1000, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, boosted, "mana shield (200 mana): scaled once")
p = hit(low, m1000, boosted - 200, COMBAT_PHYSICALDAMAGE)
eq(p, boosted - 200, "the rest of the same hit is not scaled again")
p = hit(low, m1000, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, boosted, "the next hit is scaled again")
-- a stale mark (another millisecond) does not skip a later hit
clock = clock + 1
manaHit(low, m1000, 1000, COMBAT_PHYSICALDAMAGE)
clock = clock + 5
p = hit(low, m1000, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, boosted, "a stale mana mark does not skip a later hit")
-- mana drain and PvP through the mana event: unchanged
p = manaHit(mp, m1000, 500, COMBAT_MANADRAIN, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(p, 500, "mana drain unchanged")
p = manaHit(mp, other, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, 1000, "PvP on the mana shield unchanged")
cfg.manaShield = false
p = manaHit(mp, m1000, 1000, COMBAT_PHYSICALDAMAGE)
eq(p, 1000, "manaShield = false: the mana event does nothing")
cfg.manaShield = true

-- ---------------------------------------------------------------- switches
cfg.enabled = false
p = hit(pl, monster(1000), 1000, COMBAT_PHYSICALDAMAGE)
eq(p, 1000, "disabled: unchanged")
cfg.enabled = true
cfg.elemental = true
p = hit(pl, monster(1000), 800, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(p, math.floor(800 * (1 + pct1000 / 100) + 0.5), "elemental = true: fire spell boosted")
cfg.elemental = false

-- ---------------------------------------------------------------- pack combat (pace.lua): the damage curve on top
do
	local pm = monster(300)
	local pacedSet = {[pm] = 0.65}
	ChaosPace = {damageMultOf = function(a) return pacedSet[a] or 1 end}
	local pct300 = C.percentFor(cfg, 300)
	p = hit(pl, pm, 1000, COMBAT_PHYSICALDAMAGE)
	eq(p, math.floor(math.floor(1000 * (1 + pct300 / 100) + 0.5) * 0.65 + 0.5), "pace: physical boost, then x0.65")
	p, s = hit(pl, pm, 800, COMBAT_FIREDAMAGE, 200, COMBAT_EARTHDAMAGE, ORIGIN_SPELL)
	eq(p, 520, "pace: a fire spell x0.65")
	eq(s, 130, "pace: the earth part x0.65")
	p = hit(pl, pm, 300, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_CONDITION or 0)
	eq(p, 195, "pace: a burning tick x0.65")
	p = hit(pl, pm, 500, COMBAT_HEALING)
	eq(p, 500, "pace: healing untouched")
	local unp = monster(300)
	p = hit(pl, unp, 800, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
	eq(p, 800, "pace: an unpaced monster's spell untouched")
	p = manaHit(pl, pm, 1000, COMBAT_ICEDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
	eq(p, 650, "pace: a mana shield hit x0.65")
	ChaosPace = nil
end

-- ---------------------------------------------------------------- registration and order
ok(events.Chaos0MonsterDamageLogin ~= nil, "login event")
local lp = player()
eq(events.Chaos0MonsterDamageLogin.onLogin(lp), true, "login returns true")
eq(lp.registered[1], "ChaosMonsterDamageHealth", "health event registered")
eq(lp.registered[2], "ChaosMonsterDamageMana", "mana event registered")
-- the engine runs login events in name order: this one must sort before every other Chaos login event
local names = {}
for _, dir in ipairs({"data/scripts/chaos/"}) do
	local listing = io.popen('ls "' .. dir .. '"')
	if listing then
		for fn in listing:lines() do
			if fn:match("%.lua$") then
				local f = io.open(dir .. fn)
				if f then
					local text = f:read("*a")
					f:close()
					for n in text:gmatch('CreatureEvent%("([^"]+)"%)') do
						names[#names + 1] = n
					end
				end
			end
		end
		listing:close()
	end
end
ok(#names > 50, "creature events found: " .. #names)
for _, n in ipairs(names) do
	if n ~= "Chaos0MonsterDamageLogin" and n:match("^Chaos") then
		ok("Chaos0MonsterDamageLogin" < n, "login event sorts before " .. n)
	end
end

-- ---------------------------------------------------------------- level cache (pace: ~100k monsters alive)
do
	-- 12000 monsters that keep hitting: every level is looked up once, the second round comes from the cache
	local calls = 0
	local realLevel = ChaosLoot.monsterLevel
	ChaosLoot.monsterLevel = function(m) calls = calls + 1 return realLevel(m) end
	local herd = {}
	for i = 1, 12000 do
		herd[i] = monster(200 + i % 400)
	end
	for _, m in ipairs(herd) do
		MD.levelOf(m)
	end
	eq(calls, 12000, "first round: each level computed once")
	calls = 0
	local wrong = 0
	for _, m in ipairs(herd) do
		if MD.levelOf(m) ~= m.mlevel then
			wrong = wrong + 1
		end
	end
	eq(wrong, 0, "cached levels")
	eq(calls, 0, "second round: no recompute (the cache does not clear under 12000 live monsters)")
	ChaosLoot.monsterLevel = realLevel
	ok((cfg.levelCacheSize or 0) >= 20000, "level cache holds 20000+ monsters per generation")

	-- the core cache: bounded, and an entry in use survives the turnover
	local cache = C.newCache(100)
	for i = 1, 100 do
		cache.put(i, i)
	end
	cache.put(101, 101) -- turnover: 1..100 become the old generation
	eq(cache.get(5), 5, "old generation still found")
	for i = 102, 300 do
		cache.put(i, i)
	end
	eq(cache.get(1), nil, "two turnovers later: dropped")
	ok(cache.size() <= 200, "at most 2 x cap entries: " .. cache.size())
	local hot, lost = C.newCache(50), 0
	hot.put(7, 7)
	for i = 1, 10000 do
		hot.put(1000000 + i, i) -- a stream of new monsters
		if hot.get(7) ~= 7 then
			lost = lost + 1
		end
	end
	eq(lost, 0, "a monster that keeps fighting stays cached")
	ok(hot.size() <= 100, "bounded under a stream of new monsters")
end

print(string.format("monster_damage_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
