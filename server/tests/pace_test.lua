-- Run from the server/ folder: luajit tests/pace_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers pack combat (data/scripts/chaos/pace_core.lua, pace_config.lua, pace.lua): the curves at their points and
-- between them, the switch, the level of a monster (scaled, generated point, pool x2), the pool / bestiary entries, kill
-- goals, random rounding (expected values), experience and health scaling, loot thinning, the per-kill chances, the
-- multikill chain (steps, window, the step-up on earlier kills, tiers) and the kill credit; then pace.lua against a
-- mocked engine: what gets paced at the first think, bosses, summons, script-made monsters, the marks, the experience
-- callback with the chain, the damage multiplier and the loot factor.
dofile("data/scripts/chaos/pace_core.lua")
local P = ChaosPaceCore
local cfg = dofile("data/scripts/chaos/pace_config.lua")

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function near(a, b, eps, what)
	ok(math.abs(a - b) <= (eps or 1e-9), what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- the shipped calibration (pace_config.lua `scale`, from the live check) sits in a sane range; the curve checks below
-- test the pack model itself, so they run with the calibration at 1
local shippedScale = cfg.scale or {}
ok((shippedScale.xp or 1) >= 1 and (shippedScale.xp or 1) <= 1.6, "shipped xp calibration in 1-1.6")
ok((shippedScale.loot or 1) >= 1 and (shippedScale.loot or 1) <= 1.6, "shipped loot calibration in 1-1.6")
cfg.scale = {xp = 1, loot = 1}
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- a seeded generator in [0, 1) so the expected-value checks are stable under both interpreters
local seed = 12345
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

-- ------------------------------------------------------------------ config
ok(cfg.enabled == true, "on by default")
eq(cfg.baseLevelMult, 2, "hunting level = 2 x the pool estimate")
for _, set in ipairs({"base", "scaled"}) do
	for _, k in ipairs({"health", "xp", "loot", "goal"}) do
		local pts = cfg[set][k]
		ok(type(pts) == "table" and #pts >= 2, set .. "." .. k .. " has points")
		for i = 2, #pts do
			ok(pts[i][1] > pts[i - 1][1], set .. "." .. k .. " sorted by level")
		end
		for _, p in ipairs(pts) do
			if k == "goal" then
				ok(p[2] >= 1, set .. ".goal never lowers a goal")
			else
				ok(p[2] > 0 and p[2] <= 1, set .. "." .. k .. " in (0, 1]")
			end
		end
	end
end
for i = 2, #cfg.damage do
	ok(cfg.damage[i][2] <= cfg.damage[i - 1][2], "damage curve falls with the level")
end
-- the base curves start at 1 (levels 1-20 untouched: new players)
eq(cfg.base.health[1][1], 20, "health curve starts at 20")
for _, k in ipairs({"health", "xp", "loot", "goal"}) do
	eq(cfg.base[k][1][2], 1, "base " .. k .. " is 1 at level 20")
end
eq(cfg.damage[1][2], 1, "damage 1 at level 20")
-- experience per health point stays about the same (xp follows kills): xp / health within 0.6-1.0 from level 35
for _, L in ipairs({35, 60, 100, 175, 250, 450, 800, 1000, 1500}) do
	local f = P.factors(cfg, L, false)
	ok(f.xp / f.health >= 0.6 and f.xp / f.health <= 1.0, "base xp per health at " .. L)
	-- gold per kill a little above xp per kill (the multikill bonus is experience only)
	ok(f.loot >= f.xp, "loot >= xp at " .. L)
end
for _, L in ipairs({650, 800, 1000, 1300, 1600, 2000}) do
	local f = P.factors(cfg, L, true)
	ok(f.xp / f.health >= 0.35 and f.xp / f.health <= 0.5, "scaled xp per health at " .. L)
	ok(f.loot >= f.xp, "scaled loot >= xp at " .. L)
end
-- multikill steps
local last = 0
for _, s in ipairs(cfg.multikill.steps) do
	ok(s.kills > last, "steps sorted")
	last = s.kills
end
eq(cfg.multikill.windowMs, 3000, "3 s window")

-- ------------------------------------------------------------------ lin
local pts = {{10, 1}, {20, 3}, {40, 4}}
eq(P.lin(pts, 0), 1, "flat below")
eq(P.lin(pts, 10), 1, "first point")
eq(P.lin(pts, 15), 2, "between")
eq(P.lin(pts, 30), 3.5, "between 2")
eq(P.lin(pts, 40), 4, "last point")
eq(P.lin(pts, 99), 4, "flat above")
eq(P.lin({}, 5, 7), 7, "empty -> default")
eq(P.lin(nil, 5, 7), 7, "nil -> default")
eq(P.lin(pts, "x"), 1, "a bad level counts as 0")

-- ------------------------------------------------------------------ factors at the design points
local f = P.factors(cfg, 20, false)
eq(f.health, 1, "level 20 health")
eq(f.xp, 1, "level 20 xp")
f = P.factors(cfg, 5, false)
eq(f.health, 1, "level 5 untouched")
eq(f.goal, 1, "level 5 goal 1")
f = P.factors(cfg, 300, false)
near(f.health, 0.21, 1e-9, "300 health")
near(f.xp, 0.17, 1e-9, "300 xp")
near(f.loot, 0.20, 1e-9, "300 loot")
near(f.goal, 5, 1e-9, "300 goal")
near(f.damage, 0.65, 1e-9, "300 damage")
f = P.factors(cfg, 100, false)
near(f.health, 0.36, 1e-9, "100 health")
near(f.damage, 0.85 + (0.75 - 0.85) * 50 / 100, 1e-9, "100 damage between 50 and 150")
f = P.factors(cfg, 3000, false)
near(f.health, 0.21, 1e-9, "flat health past 250")
near(f.xp, 0.17, 1e-9, "flat xp past 1000")
near(f.damage, 0.40, 1e-9, "flat damage past 1000")
f = P.factors(cfg, 1000, true)
near(f.health, 0.066, 1e-9, "scaled 1000 health")
near(f.xp, 0.030, 1e-9, "scaled 1000 xp")
near(f.goal, 28, 1e-9, "scaled 1000 goal")
near(f.damage, 0.40, 1e-9, "scaled monsters share the damage curve")
f = P.factors(cfg, 400, true)
near(f.health, 0.095, 1e-9, "scaled flat below 650")
-- switch
local off = {enabled = false, base = cfg.base, scaled = cfg.scaled, damage = cfg.damage}
f = P.factors(off, 300, false)
ok(f.health == 1 and f.xp == 1 and f.loot == 1 and f.goal == 1 and f.damage == 1, "off: all 1")
f = P.factors(nil, 300, false)
eq(f.health, 1, "no config: 1")

-- calibration knob
do
	local c2 = {enabled = true, base = cfg.base, scaled = cfg.scaled, damage = cfg.damage, scale = {xp = 1.3, loot = 2}}
	local f2 = P.factors(c2, 300, false)
	near(f2.xp, 0.17 * 1.3, 1e-9, "scale.xp")
	near(f2.loot, 0.40, 1e-9, "scale.loot")
	near(f2.health, 0.21, 1e-9, "scale leaves health")
	eq(P.factors(c2, 10, false).xp, 1, "scale never above 1 per kill")
	eq(cfg.scale.xp, 1.0, "shipped: xp scale 1")
	eq(cfg.scale.loot, 1.0, "shipped: loot scale 1")
end

-- ------------------------------------------------------------------ the level of a monster
local L, s = P.levelOf(cfg, {native = 980, pool = 980})
ok(L == 980 and s == true, "level-scaled monster: its own level, scaled curve")
L, s = P.levelOf(cfg, {point = 1100, native = 0, pool = 60})
ok(L == 1100 and s == true, "generated point: the point's level, scaled curve")
L, s = P.levelOf(cfg, {point = 1100, native = 830})
eq(L, 1100, "the point wins over the native level")
L, s = P.levelOf(cfg, {native = 0, pool = 125})
ok(L == 250 and s == false, "base monster: 2 x the pool estimate")
L, s = P.levelOf(cfg, {})
ok(L == 0 and s == false, "unknown: 0")
L = P.levelOf({baseLevelMult = 3}, {pool = 10})
eq(L, 30, "baseLevelMult")

-- ------------------------------------------------------------------ entries (bounty pool, bestiary)
eq(P.estimateLevel(6000, 6000), 124, "estimate: 1.6 sqrt(exp)")
eq(P.estimateLevel(0, 0), 2, "estimate floor (sqrt of 1)")
L, s = P.entryLevel(cfg, {level = 124, exp = 6000, health = 6000})
ok(L == 248 and s == false, "pool entry that is its estimate: base, x2")
L, s = P.entryLevel(cfg, {level = 980, exp = 13900, health = 22000})
ok(L == 980 and s == true, "pool entry of a level-scaled monster (the range middle)")
L, s = P.entryLevel(cfg, {minLevel = 900, maxLevel = 1000, exp = 1, health = 1})
ok(L == 950 and s == true, "bestiary entry with a level range")
L, s = P.entryLevel(cfg, {exp = 6000, health = 6000})
ok(L == 248 and s == false, "bestiary entry without a level")
near(P.goalOfEntry(cfg, {level = 124, exp = 6000, health = 6000}), 5, 0.05, "goal of a level-248 base monster")
near(P.goalOfEntry(cfg, {level = 980, exp = 13900, health = 22000}), P.lin(cfg.scaled.goal, 980), 1e-9,
	"goal of a scaled monster")
eq(P.goalOfEntry(off, {level = 980, exp = 13900, health = 22000}), 1, "off: goal 1")

-- ------------------------------------------------------------------ goals
eq(P.scaleGoal(120, 5, 10), 600, "120 x 5")
eq(P.scaleGoal(120, 2.7, 10), 320, "120 x 2.7 = 324 -> 320")
eq(P.scaleGoal(60, 1.04, 10), 60, "never below n")
eq(P.scaleGoal(3, 1.5, 10), 10, "at least one step")
eq(P.scaleGoal(100, 1, 10), 100, "x1 unchanged")
eq(P.scaleGoal(100, 0.5, 10), 100, "never lowered")
eq(P.scaleGoal(25, 2.7, 1), 68, "step 1")

-- ------------------------------------------------------------------ random rounding (expected value)
local sum = 0
for _ = 1, 20000 do
	sum = sum + P.roundRandom(2.3, rnd)
end
near(sum / 20000, 2.3, 0.02, "roundRandom expected value")
eq(P.roundRandom(4, rnd), 4, "whole numbers stay")
sum = 0
for _ = 1, 20000 do
	sum = sum + P.scaleExp(1000, 0.17, rnd)
end
eq(P.scaleExp(1000, 0.17, function() return 0.99 end), 170, "exp x 0.17")
near(sum / 20000, 170, 0.01, "scaleExp mean")
eq(P.scaleExp(3, 0.17, function() return 0.99 end), 1, "a kill worth 1+ gives at least 1")
eq(P.scaleExp(0, 0.17, rnd), 0, "0 stays 0")
eq(P.scaleExp(-5, 0.17, rnd), -5, "negative untouched")
eq(P.scaleExp(77, 1, rnd), 77, "x1 untouched")
sum = 0
for _ = 1, 20000 do
	sum = sum + P.scaleExp(10, 0.17, rnd)
end
near(sum / 20000, 1.7, 0.03, "small kills keep their mean")
eq(P.scaleHealth(1000, 0.21), 210, "health")
eq(P.scaleHealth(3, 0.1), 1, "health at least 1")
eq(P.scaleHealth(2005, 0.5), 1003, "health rounds to nearest")

-- ------------------------------------------------------------------ loot thinning
local items = {{count = 100, stackable = true}, {count = 1, stackable = false}, {count = 7, stackable = true}}
local plan = P.thinPlan(items, 1, rnd)
ok(plan[1] == 100 and plan[2] == 1 and plan[3] == 7, "f = 1 keeps all")
local coins, kept, small = 0, 0, 0
for _ = 1, 20000 do
	plan = P.thinPlan(items, 0.2, rnd)
	coins = coins + plan[1]
	kept = kept + plan[2]
	small = small + plan[3]
	ok(plan[2] == 0 or plan[2] == 1, "an item is kept whole or removed")
end
near(coins / 20000, 20, 0.05, "stack x 0.2 on average")
near(kept / 20000, 0.2, 0.01, "item kept 20% of the time")
near(small / 20000, 1.4, 0.03, "small stack x 0.2 on average")
eq(#P.thinPlan({}, 0.2, rnd), 0, "empty corpse")
eq(P.scaleChance(400, 0.2), 80, "ambush chance x loot factor")
eq(P.scaleChance(400, 1), 400, "x1 unchanged")
eq(P.scaleChance(400, 3), 400, "never raised")

-- ------------------------------------------------------------------ multikill
eq(P.multikillPercent(cfg, 1), 0, "1 kill: 0")
eq(P.multikillPercent(cfg, 3), 0, "3 kills: 0")
eq(P.multikillPercent(cfg, 4), 10, "4: 10")
eq(P.multikillPercent(cfg, 5), 10, "5: 10")
eq(P.multikillPercent(cfg, 6), 20, "6: 20")
eq(P.multikillPercent(cfg, 7), 20, "7: 20")
eq(P.multikillPercent(cfg, 8), 30, "8: 30")
eq(P.multikillPercent(cfg, 9), 40, "9: 40")
eq(P.multikillPercent(cfg, 30), 40, "30: 40")
eq(P.multikillPercent(off, 9), 0, "off: 0")

-- a chain of n kills of 100 each, 1 s apart: the total is n x 100 x (1 + percent(n))
for _, n in ipairs({1, 3, 4, 6, 8, 9, 12}) do
	local st, total = {}, 0
	for i = 1, n do
		local e = P.multikill(cfg, st, 10000 + i * 1000, 100, 1)
		total = total + e
	end
	near(total, n * 100 * (1 + P.multikillPercent(cfg, n) / 100), 1e-6, "chain of " .. n)
end
-- the window: a gap over 3 s starts a new chain
do
	local st = {}
	for i = 1, 5 do
		P.multikill(cfg, st, i * 1000, 100, 1)
	end
	local e, n, pct = P.multikill(cfg, st, 5000 + 3001, 100, 1)
	ok(e == 100 and n == 1 and pct == 0, "a gap of 3.001 s resets")
	e, n = P.multikill(cfg, st, 8001 + 3000, 100, 1)
	eq(n, 2, "exactly 3 s still chains")
	e, n = P.multikill(cfg, st, 5, 100, 1)
	eq(n, 1, "a clock going back resets")
end
-- tiers: the kill that steps up is a rare (x4, applied by the tier callback after this one)
do
	local st, total = {}, 0
	for i = 1, 3 do
		total = total + P.multikill(cfg, st, i * 100, 100, 1)
	end
	local e = P.multikill(cfg, st, 400, 100, 4)
	total = total + e * 4 -- the tier callback multiplies this kill by 4
	-- the kills were worth 100, 100, 100, 400: all four at +10%
	near(total, 700 * 1.10, 1e-6, "a tiered step-up kill pays the others at their own value")
	-- the next normal kill at step 5 (still 10%) pays its own 10% only
	e = P.multikill(cfg, st, 500, 100, 1)
	near(e, 110, 1e-9, "no step: own bonus only")
end
-- mixed values: a chain of 100, 50, 200, 80, 120, 300 (6 kills, 20%)
do
	local st, total, vals = {}, 0, {100, 50, 200, 80, 120, 300}
	for i, v in ipairs(vals) do
		total = total + P.multikill(cfg, st, i * 500, v, 1)
	end
	near(total, 850 * 1.2, 1e-6, "mixed chain")
end
do
	local st = {}
	local e, n = P.multikill(off, st, 1, 100, 1)
	ok(e == 100 and n == 0, "off: no chain")
	e = P.multikill(cfg, st, 1, 0, 1)
	eq(e, 0, "0 exp untouched")
	local nomk = {enabled = true, multikill = {enabled = false}}
	e = P.multikill(nomk, st, 1, 100, 1)
	eq(e, 100, "multikill switched off alone")
end

-- ------------------------------------------------------------------ kill credit
do
	local acc, total = {}, 0
	for _ = 1, 50 do
		total = total + P.killCredit(acc, 5)
	end
	eq(total, 10, "50 kills at goal x5 = 10 credits")
	acc, total = {}, 0
	for _ = 1, 280 do
		total = total + P.killCredit(acc, 28)
	end
	eq(total, 10, "280 kills at x28 = 10")
	eq(P.killCredit({}, 1), 1, "x1: every kill")
	eq(P.killCredit({}, 0.5), 1, "below 1: every kill")
	acc, total = {}, 0
	for _ = 1, 27 do
		total = total + P.killCredit(acc, 2.7)
	end
	eq(total, 10, "x2.7: 27 kills = 10")
end

-- ------------------------------------------------------------------ pack cleave
do
	-- owner decision 2026-10-15 (data/spells/README.md "Pack farming for every class"): the Elementalist, the strongest
	-- pack class, has none; every other class cleaves 4 monsters, its share growing from level 300 to 1000
	ok(P.cleaveOf(cfg, 5) == nil, "Elementalist: no cleave")
	local c = P.cleaveOf(cfg, 7)
	ok(c and c.percent == 28 and c.high == 21 and c.targets == 4, "Deadeye: 28% at 300, 21% at 1000, to 4")
	ok(P.cleaveOf(cfg, nil) == nil, "no vocation: none")
	ok(P.cleaveOf(off, 7) == nil, "layer off: no cleave")
	ok(P.cleaveOf({enabled = true, cleave = {enabled = false, byVocation = {[7] = {percent = 1, targets = 1}}}}, 7) == nil,
		"cleave off")
	for _, v in ipairs({4, 8, 14, 3, 7, 15, 1, 10, 11, 12, 13, 20, 21, 22, 17, 18, 19, 23, 24, 25}) do
		local e = P.cleaveOf(cfg, v)
		ok(e and e.percent >= 0 and e.percent <= 70 and (e.high or e.percent) <= 70 and e.targets == 4,
			"cleave of " .. v .. " sane")
	end
	-- the share by level: percent up to fromLevel, linear to high at toLevel, high above
	local cc = cfg.cleave
	eq(cc.fromLevel, 300, "from level 300"); eq(cc.toLevel, 1000, "to level 1000")
	local t = cc.byVocation[23]
	eq(P.cleavePercent(t, 100, cc), t.percent, "below 300: the level 300 share")
	eq(P.cleavePercent(t, 300, cc), t.percent, "at 300")
	eq(P.cleavePercent(t, 650, cc), (t.percent + t.high) / 2, "half way")
	eq(P.cleavePercent(t, 1000, cc), t.high, "at 1000")
	eq(P.cleavePercent(t, 2000, cc), t.high, "above 1000")
	eq(P.cleavePercent({percent = 20}, 1000, cc), 20, "no high: one share")
	eq(P.cleavePercent(t, nil, cc), t.percent, "no level: the level 300 share")
	ok(P.cleaveOf({enabled = true, cleave = {byVocation = {[1] = {percent = 0, high = 3, targets = 4}}}}, 1) ~= nil,
		"a share only at high levels still counts")
	eq(P.cleaveDamage(1000, 20), 200, "20% of 1000")
	eq(P.cleaveDamage(-999, 25), 249, "negative values (the engine's sign) and rounding down")
	eq(P.cleaveDamage(3, 20), 0, "too small: 0")
	local cands = {{id = 5, x = 11, y = 10}, {id = 3, x = 9, y = 9}, {id = 4, x = 10, y = 12}, {id = 2, x = 10, y = 11},
		{id = 1, x = 11, y = 11}}
	local t = P.cleaveTargets(cands, 10, 10, 1, 2)
	ok(#t == 2 and t[1].id == 1 and t[2].id == 2, "nearest first, ties by id")
	t = P.cleaveTargets(cands, 10, 10, 1, 9)
	eq(#t, 4, "only within the radius")
	eq(#P.cleaveTargets({}, 0, 0, 1, 3), 0, "nobody around")
end

-- ================================================================== pace.lua against a mocked engine
do
	local events, callbacks, now = {}, {}, 100000
	local registered = {}
	_G.os.mtime = function() return now end
	_G.CreatureEvent = function(name)
		local ev = {name = name}
		function ev:register() events[name] = ev end
		return ev
	end
	local cbList = {}
	_G.EventCallback = setmetatable({}, {
		__newindex = function(t, k, v) rawset(t, "_pending", {k, v}) end,
		__index = function(t, k)
			if k == "register" then
				return function(self, index)
					local pend = rawget(self, "_pending")
					cbList[#cbList + 1] = {kind = pend[1], fn = pend[2], index = index or 0}
					rawset(self, "_pending", nil)
				end
			end
		end
	})
	_G.addEvent = function(fn, ms, ...) local a = {...} fn(unpack and unpack(a) or table.unpack(a)) end
	_G.MESSAGE_STATUS_DEFAULT = 1
	_G.Chaos = {}
	_G.ChaosLoot = {monsterLevel = function(m) return m._pool or 0 end}
	_G.ChaosTierConfig = {bosses = {["the boss"] = true}}
	_G.ChaosTierOf = function(m) return m._tier or "normal" end
	_G.ChaosTiers = {normal = nil, magic = {xp = 2}, rare = {xp = 4}}
	_G.ChaosAreaGen = {pointOf = {}}

	local nextId = 1000
	local function monster(o)
		o = o or {}
		nextId = nextId + 1
		local m = {_id = nextId, _max = o.max or 1000, _hp = o.max or 1000, _pool = o.pool or 150, _native = o.native or 0,
			_boss = o.boss, _master = o.master, _name = o.name or "Troll", _events = {}, _tier = o.tier}
		function m:getId() return self._id end
		function m:isMonster() return true end
		function m:isPlayer() return false end
		function m:getMaxHealth() return self._max end
		function m:getHealth() return self._hp end
		function m:setMaxHealth(v) self._max = v end
		function m:setHealth(v) self._hp = v end
		function m:getMonsterLevel() return self._native end
		function m:getMaster() return self._master end
		function m:getName() return self._name end
		function m:getType()
			local boss = self._boss
			return {isBoss = function() return boss end, isRewardBoss = function() return false end}
		end
		function m:registerEvent(n) self._events[n] = true end
		function m:unregisterEvent(n) self._events[n] = nil end
		return m
	end
	_G.Monster = function(id) return nil end

	_G.ORIGIN_NONE, _G.ORIGIN_CONDITION, _G.ORIGIN_SPELL, _G.ORIGIN_MELEE, _G.ORIGIN_RANGED = 0, 1, 2, 3, 4
	_G.COMBAT_PHYSICALDAMAGE, _G.COMBAT_HEALING, _G.CONST_ME_NONE = 1, 2, 0
	local spectators, combats = {}, {}
	_G.Game = {getSpectators = function() return spectators end}
	_G.doTargetCombatHealth = function(att, target, ctype, mn, mx, eff, origin)
		combats[#combats + 1] = {target = target, dmg = mn, origin = origin}
		-- the engine runs the target's healthchange events inside the call: a nested hit must not cleave again
		if events.ChaosPaceCleave then
			events.ChaosPaceCleave.onHealthChange(target, att, -mn, ctype, 0, 0, origin)
		end
		return true
	end
	dofile("data/scripts/chaos/pace.lua")
	local PC = ChaosPace
	ok(PC ~= nil, "pace.lua loads")
	ok(events.ChaosPaceInit ~= nil, "first-think event registered")

	local function spawnCb()
		for _, c in ipairs(cbList) do
			if c.kind == "onSpawn" then
				return c.fn
			end
		end
	end
	local function xpCb()
		for _, c in ipairs(cbList) do
			if c.kind == "onGainExperience" then
				return c.fn, c.index
			end
		end
	end
	local onSpawn = spawnCb()
	ok(onSpawn ~= nil, "onSpawn callback")
	local onXp, xpIndex = xpCb()
	ok(onXp ~= nil, "onGainExperience callback")
	eq(xpIndex, -10, "experience callback at index -10")

	local function think(m)
		if m._events.ChaosPaceInit then
			events.ChaosPaceInit.onThink(m, 1000)
		end
	end

	-- a natural map spawn: paced at its first think
	local m = monster({max = 1000, pool = 150})
	onSpawn(m, {}, false, false)
	ok(m._events.ChaosPaceInit, "a map spawn gets the first-think event")
	eq(m._max, 1000, "nothing changes before the first think")
	think(m)
	eq(m._max, 210, "level 300 monster: x0.21 at the first think")
	eq(m._hp, 210, "full health")
	ok(not m._events.ChaosPaceInit, "the event removes itself")
	ok(PC.isPaced(m), "marked as paced")
	think(m)
	eq(m._max, 210, "never twice")
	near(PC.lootMultOf(m), 0.20 * (shippedScale.loot or 1), 1e-9, "loot factor (x the shipped calibration)")
	near(PC.damageMultOf(m), 0.65, 1e-9, "damage factor")
	near(PC.goalMultOf(m), 5, 1e-9, "goal factor")

	-- a script-made monster (artificial) is not paced
	local a = monster({})
	onSpawn(a, {}, false, true)
	ok(not a._events.ChaosPaceInit, "artificial spawn not paced")
	eq(PC.lootMultOf(a), 1, "unpaced: loot 1")
	eq(PC.damageMultOf(a), 1, "unpaced: damage 1")
	-- unless marked (a base dungeon, an ambush copy)
	PC.mark(a)
	think(a)
	eq(a._max, 210, "marked artificial monster paced")
	-- bosses and summons never
	local b = monster({boss = true})
	onSpawn(b, {}, false, false)
	think(b)
	eq(b._max, 1000, "boss flag: not paced")
	local b2 = monster({name = "The Boss"})
	onSpawn(b2, {}, false, false)
	think(b2)
	eq(b2._max, 1000, "tier boss list: not paced")
	local sm = monster({master = m})
	onSpawn(sm, {}, false, false)
	think(sm)
	eq(sm._max, 1000, "summon: not paced")
	-- a level-scaled monster
	local sc = monster({max = 100000, native = 1000})
	onSpawn(sc, {}, false, false)
	think(sc)
	eq(sc._max, 6600, "scaled 1000: x0.066")
	-- a generated area point
	local g = monster({max = 50000})
	ChaosAreaGen.pointOf[g._id] = {level = 1300}
	PC.mark(g)
	think(g)
	eq(g._max, P.scaleHealth(50000, 0.062), "generated point: scaled curve at the point level")
	local gb = monster({max = 50000})
	ChaosAreaGen.pointOf[gb._id] = {level = 1300, boss = true}
	PC.mark(gb)
	think(gb)
	eq(gb._max, 50000, "generated boss: not paced")
	-- low level: untouched
	local low = monster({max = 50, pool = 5})
	onSpawn(low, {}, false, false)
	think(low)
	eq(low._max, 50, "level 10 untouched")
	-- the skip list
	ChaosPaceConfig.skip["skipme"] = true
	local sk = monster({name = "SkipMe"})
	onSpawn(sk, {}, false, false)
	think(sk)
	eq(sk._max, 1000, "skip list")
	-- the switch: off at the think
	ChaosPaceConfig.enabled = false
	local o2 = monster({})
	onSpawn(o2, {}, false, false)
	think(o2)
	eq(o2._max, 1000, "off: no health change")
	ChaosPaceConfig.enabled = true

	-- experience: x the curve, then the chain
	local player = {_id = 5}
	function player:getId() return self._id end
	function player:sendTextMessage() end
	function player:isMonster() return false end
	local e = onXp(player, m, 1000, 1000)
	local first = math.floor(1000 * 0.17 * (shippedScale.xp or 1) + 0.5)
	ok(math.abs(e - first) <= 1, "first kill: x0.17 x calibration (" .. tostring(e) .. ")")
	local total = e
	for i = 2, 6 do
		now = now + 500
		total = total + onXp(player, m, 1000, 1000)
	end
	near(total, 6 * first * 1.2, 3, "6 kills in a chain: +20% on all")
	eq(onXp(player, player, 1000, 1000), 1000, "a non-monster source untouched")
	eq(onXp(player, nil, 1000, 1000), 1000, "no source untouched")
	local un = monster({})
	eq(onXp(player, un, 1000, 1000), 1000, "an unpaced monster untouched")
	ChaosPaceConfig.enabled = false
	eq(onXp(player, m, 1000, 1000), 1000, "off: untouched")
	ChaosPaceConfig.enabled = true

	-- pack cleave: a Thief's hit on a paced monster also hits its two nearest neighbours (25% to up to 3)
	ok(m._events.ChaosPaceCleave, "a paced monster gets the cleave event")
	local function at(mon, x, y)
		mon._pos = {x = x, y = y, z = 7}
		function mon:getPosition() return self._pos end
		return mon
	end
	at(m, 100, 100)
	local n1, n2, n3, far = at(monster({}), 101, 100), at(monster({}), 99, 99), at(monster({}), 100, 101),
		at(monster({}), 103, 100)
	local bossN = at(monster({boss = true}), 101, 101)
	local pet = at(monster({master = player}), 99, 100)
	player._isPlayer = true
	function player:isPlayer() return true end
	function player:getVocation() local v = self._voc return {getId = function() return v end} end
	player._voc = 11
	player._level = 300
	function player:getLevel() return self._level end
	local thief = ChaosPaceConfig.cleave.byVocation[11]
	spectators = {m, n1, n2, n3, far, bossN, pet}
	combats = {}
	local p1 = events.ChaosPaceCleave.onHealthChange(m, player, 1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE)
	eq(p1, 1000, "the hit itself is unchanged")
	eq(#combats, 3, "Thief: the 3 monsters around, no nested cleave")
	local hitIds = {}
	for _, cbt in ipairs(combats) do
		hitIds[cbt.target] = true
		eq(cbt.dmg, -math.floor(1000 * thief.percent / 100), "the level 300 share of the hit")
		eq(cbt.origin, ORIGIN_NONE, "the cleave hit has no spell origin")
	end
	ok(hitIds[n1] and hitIds[n2] and hitIds[n3], "the three within 1 sqm")
	ok(not hitIds[far] and not hitIds[bossN] and not hitIds[pet], "not the far one, a boss or a player's summon")
	combats = {}
	player._level = 1000
	events.ChaosPaceCleave.onHealthChange(m, player, 1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE)
	eq(combats[1] and combats[1].dmg, -math.floor(1000 * thief.high / 100), "level 1000: the high share")
	combats = {}
	events.ChaosPaceCleave.onHealthChange(m, player, 1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_CONDITION)
	eq(#combats, 0, "damage over time: no cleave")
	player._voc = 5
	events.ChaosPaceCleave.onHealthChange(m, player, 1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_SPELL)
	eq(#combats, 0, "the Elementalist: no cleave")
	player._voc = 7
	events.ChaosPaceCleave.onHealthChange(m, player, 1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_SPELL)
	eq(#combats, 3, "Deadeye: up to 4, the 3 around")
	combats = {}
	player._voc = 23
	player._level = 650
	local tp = ChaosPaceConfig.cleave.byVocation[23]
	events.ChaosPaceCleave.onHealthChange(m, player, 1000, COMBAT_HOLYDAMAGE or COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_SPELL)
	eq(combats[1] and combats[1].dmg, -math.floor(1000 * (tp.percent + tp.high) / 2 / 100), "Templar 650: half way")
	-- a summon's hit cleaves by its master's class and level (the Necromancer's minions)
	combats = {}
	player._voc = 20
	player._level = 300
	local nec = ChaosPaceConfig.cleave.byVocation[20]
	events.ChaosPaceCleave.onHealthChange(m, pet, 1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE)
	eq(#combats, 3, "a minion's hit cleaves the 3 around (never the pet itself)")
	eq(combats[1] and combats[1].dmg, -math.floor(1000 * nec.percent / 100), "by the master's class")
	combats = {}
	player._voc = 5
	events.ChaosPaceCleave.onHealthChange(m, pet, 1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE)
	eq(#combats, 0, "an Elementalist's summon: no cleave")
	player._voc = 20
	combats = {}
	events.ChaosPaceCleave.onHealthChange(m, n1, 1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE)
	eq(#combats, 0, "a monster attacker: no cleave")
	ChaosPaceConfig.enabled = false
	events.ChaosPaceCleave.onHealthChange(m, player, 1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_SPELL)
	eq(#combats, 0, "off: no cleave")
	ChaosPaceConfig.enabled = true
	player._isPlayer = nil
	function player:isPlayer() return false end

	-- death cleanup
	ok(events.ChaosPaceDeath ~= nil, "death event")
	events.ChaosPaceDeath.onDeath(m)
	ok(not PC.isPaced(m), "forgotten after death (the loot callback ran first)")
end

print(string.format("pace_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
