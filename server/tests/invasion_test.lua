-- Run from the server/ folder: luajit tests/invasion_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Pure invasion and world event logic (invasion_core.lua + invasion_config.lua): schedule and the random daily
-- invasion, wave planning and scaling, the boss, spawn edges, the breach meter, the outcome, contribution shares and
-- rewards, the occupation timer, the Victory buff, the world event rotation and the HUD message.
local cfg = dofile("data/scripts/chaos/invasion_config.lua")
dofile("data/scripts/chaos/invasion_core.lua")
local I = ChaosInvasionCore

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
local function near(a, b, eps, what)
	ok(math.abs(a - b) <= (eps or 1e-9), what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local function T(y, mo, d, h, mi)
	return os.time({year = y, month = mo, day = d, hour = h or 0, min = mi or 0, sec = 0})
end

-- ------------------------------------------------------------------ config sanity
do
	local keys = {}
	for _, a in ipairs(cfg.areas) do
		ok(not keys[a.key], "unique area key " .. a.key)
		keys[a.key] = true
		ok(a.from.x <= a.to.x and a.from.y <= a.to.y, a.key .. " rectangle")
		ok(I.inArea({x = a.target.x, y = a.target.y, z = a.target.z or a.z}, a), a.key .. " target inside the area")
		ok(a.level > 0, a.key .. " level")
	end
	for key, f in pairs(cfg.factions) do
		ok(#f.monsters >= 3, key .. " has monsters")
		ok(#f.bosses >= 1, key .. " has a boss")
	end
	ok(#I.invasionAreas(cfg) >= 3, "at least 3 invasion areas enabled")
end

-- ------------------------------------------------------------------ lcg
do
	local a, b = I.lcg(42), I.lcg(42)
	for _ = 1, 20 do
		eq(a(1, 1000), b(1, 1000), "lcg deterministic")
	end
	local r = I.lcg(7)
	for _ = 1, 200 do
		local v = r(3, 5)
		ok(v >= 3 and v <= 5, "lcg range")
	end
	local f = r()
	ok(f >= 0 and f < 1, "lcg fraction")
end

-- ------------------------------------------------------------------ schedule
do
	local c = {areas = cfg.areas, factions = cfg.factions, random = {chance = 0},
		schedule = {{weekdays = {4}, hour = 19, minute = 30, area = "cinderhold", faction = "orcs"}}}
	-- 2026-10-07 is a Wednesday (wday 4)
	local wed = T(2026, 10, 7, 12)
	eq(os.date("*t", wed).wday, 4, "test day is a Wednesday")
	local s = I.scheduledStarts(c, wed, wed + 7 * 86400)
	eq(#s, 1, "one start a week")
	eq(s[1].at, T(2026, 10, 7, 19, 30), "Wednesday 19:30")
	eq(#I.scheduledStarts(c, T(2026, 10, 7, 19, 31), T(2026, 10, 13, 0)), 0, "none until next Wednesday")
	-- every day when weekdays is nil
	c.schedule = {{hour = 8, minute = 0}}
	eq(#I.scheduledStarts(c, T(2026, 10, 1, 0), T(2026, 10, 8, 0)), 7, "daily entry: 7 in a week")
	-- one-off entry
	c.schedule = {{at = wed + 600, area = "thornmere"}}
	local once = I.scheduledStarts(c, wed, wed + 3600)
	eq(#once, 1, "one-off start")
	eq(once[1].source, "once", "one-off source")
	-- resolve: fixed keys and deterministic random picks
	local ak, fk = I.resolve(cfg, wed, "cinderhold", "undead")
	eq(ak, "cinderhold", "resolve fixed area")
	eq(fk, "undead", "resolve fixed faction")
	local a1, f1 = I.resolve(cfg, wed + 999, "random", "random")
	local a2, f2 = I.resolve(cfg, wed + 999, "random", "random")
	eq(a1, a2, "random area deterministic")
	eq(f1, f2, "random faction deterministic")
	ok(I.areaByKey(cfg, a1).enabled ~= false, "random area is an enabled one")
	local seen = {}
	for k = 1, 200 do
		local a = I.resolve(cfg, wed + k * 3600, "random")
		seen[a] = true
		ok(a ~= "mirewake", "disabled area never picked")
	end
	local n = 0
	for _ in pairs(seen) do
		n = n + 1
	end
	ok(n >= 3, "random picks spread over the areas")
	-- an area's own faction list is respected
	local c2 = {areas = {{key = "x", name = "X", level = 50, from = {x = 0, y = 0}, to = {x = 10, y = 10}, z = 7,
		target = {x = 5, y = 5}, factions = {"orcs"}}}, factions = cfg.factions}
	for k = 1, 30 do
		local _, f = I.resolve(c2, k * 77, "x", "random")
		eq(f, "orcs", "area faction list")
	end
	eq(I.resolve(c2, 1, "nope"), "x", "unknown area falls back to a random one")
end

do -- random daily invasion
	local c = {areas = cfg.areas, factions = cfg.factions, schedule = {},
		random = {chance = 100, fromHour = 12, toHour = 23, minGapMinutes = 90, salt = 5}}
	local day = T(2026, 10, 8, 9)
	local r1, r2 = I.randomStart(c, day), I.randomStart(c, day + 3 * 3600)
	ok(r1 ~= nil, "chance 100: an invasion every day")
	eq(r1.at, r2.at, "same day -> same time (a restart does not re-roll)")
	local h = os.date("*t", r1.at).hour
	ok(h >= 12 and h < 23, "between fromHour and toHour")
	c.random.chance = 0
	eq(I.randomStart(c, day), nil, "chance 0: none")
	c.random.chance = 35
	local count = 0
	for d = 0, 199 do
		if I.randomStart(c, T(2026, 1, 1, 12) + d * 86400) then
			count = count + 1
		end
	end
	ok(count > 40 and count < 110, "about 35% of the days: " .. count)
	-- kept away from a scheduled start
	c.random.chance = 100
	c.schedule = {{hour = 17, minute = 0}}
	for d = 0, 30 do
		local r = I.randomStart(c, T(2026, 3, 1, 12) + d * 86400)
		if r then
			local hm = os.date("*t", r.at)
			local minutes = math.abs((hm.hour * 60 + hm.min) - 17 * 60)
			ok(minutes >= 90, "random start 90 minutes from the scheduled one")
		end
	end
	-- avoidHours
	c.schedule = {}
	c.random.avoidHours = {15, 21}
	for d = 0, 60 do
		local r = I.randomStart(c, T(2026, 5, 1, 12) + d * 86400)
		if r then
			local hm = os.date("*t", r.at).hour
			ok(hm ~= 15 and hm ~= 21, "avoid the world boss hours")
		end
	end
	-- upcoming: sorted, resolved, random ones marked secret
	c.schedule = {{weekdays = {1, 2, 3, 4, 5, 6, 7}, hour = 10, minute = 0, area = "cinderhold", faction = "demons"}}
	local up = I.upcoming(c, T(2026, 10, 8, 0), 3 * 86400)
	ok(#up >= 3, "upcoming lists the scheduled ones")
	for k = 2, #up do
		ok(up[k - 1].at <= up[k].at, "upcoming sorted")
	end
	local secret, plain = 0, 0
	for _, s in ipairs(up) do
		ok(s.areaKey ~= nil and s.factionKey ~= nil, "upcoming resolved")
		if s.secret then
			secret = secret + 1
		else
			plain = plain + 1
		end
	end
	ok(secret >= 1 and plain >= 3, "random ones are secret")
end

-- ------------------------------------------------------------------ roster and scaling
do
	local orcs = cfg.factions.orcs
	local r = I.roster(orcs, 20, cfg.scaling)
	for _, m in ipairs(r) do
		ok(m.level >= 7 and m.level <= 25, "roster in [0.35, 1.25] x 20: " .. m.name)
	end
	for k = 2, #r do
		ok(r[k - 1].level <= r[k].level, "roster sorted by level")
	end
	-- area far above the faction: the closest ones
	local high = I.roster(orcs, 900, cfg.scaling)
	eq(#high, 3, "minTypes when nothing fits")
	eq(high[#high].name, "Orc Warlord", "the strongest is kept")
	local s = I.scale(50, 100, cfg.scaling)
	near(s.hp, 2, 1e-9, "hp x2 at double level")
	near(s.dmg, 2 ^ 0.4, 1e-9, "damage x 2^0.4")
	near(s.xp, 2 ^ 0.8, 1e-9, "experience x2^0.8")
	local cap = I.scale(10, 1000, cfg.scaling)
	eq(cap.hp, cfg.scaling.maxHp, "hp clamped")
	eq(cap.dmg, cfg.scaling.maxDmg, "damage clamped")
	local low = I.scale(100, 10, cfg.scaling)
	eq(low.hp, cfg.scaling.minMult, "weaker area: at least minMult")
	eq(I.playerFactor(1, cfg.players), 1, "1 player x1")
	near(I.playerFactor(5, cfg.players), 1.6, 1e-9, "5 players x1.6")
	eq(I.playerFactor(100, cfg.players), cfg.players.maxFactor, "player factor capped")
	eq(I.playerFactor(0, cfg.players), 1, "0 players counts as 1")
	local t1, t5 = I.tierChances(1, cfg.tiers), I.tierChances(5, cfg.tiers)
	eq(t1.magic, 10, "wave 1 magic 10%")
	eq(t5.magic, 26, "wave 5 magic 26%")
	eq(t5.rare, 10, "wave 5 rare 10%")
	eq(t5.legendary, 4, "wave 5 legendary 4%")
	local rng = I.lcg(3)
	local tiers = {normal = 0, magic = 0, rare = 0, legendary = 0}
	for _ = 1, 10000 do
		local tt = I.rollTier(t5, rng)
		tiers[tt] = tiers[tt] + 1
	end
	ok(tiers.legendary > 300 and tiers.legendary < 500, "legendary about 4%: " .. tiers.legendary)
	ok(tiers.magic > 2300 and tiers.magic < 2900, "magic about 26%: " .. tiers.magic)
end

-- ------------------------------------------------------------------ waves and the boss
do
	local area = I.areaByKey(cfg, "cinderhold")
	local faction = cfg.factions.undead
	local rng = I.lcg(11)
	local total = 0
	local firstLevels, lastLevels = 0, 0
	for i = 1, cfg.waves.count do
		local w = I.planWave(cfg, area, faction, i, 1, rng)
		eq(w.count, cfg.waves.base + cfg.waves.perWave * (i - 1), "wave " .. i .. " size (1 player)")
		local inPacks = 0
		for _, p in ipairs(w.packs) do
			ok(#p.monsters >= 1 and #p.monsters <= cfg.waves.packSize[2], "pack size")
			inPacks = inPacks + #p.monsters
			for _, m in ipairs(p.monsters) do
				ok(m.scale and m.scale.hp > 0, "monster scaled")
				if i == 1 then
					firstLevels = firstLevels + m.level
				elseif i == cfg.waves.count then
					lastLevels = lastLevels + m.level
				end
			end
		end
		eq(inPacks, w.count, "every monster in a pack")
		total = total + w.count
	end
	eq(total, 10 + 14 + 18 + 22 + 26, "90 invaders over 5 waves")
	ok(lastLevels / 26 > firstLevels / 10, "later waves are stronger")
	local big = I.planWave(cfg, area, faction, 1, 5, rng)
	eq(big.count, 16, "5 players: x1.6")
	local boss = I.planBoss(cfg, area, faction, 1)
	eq(boss.name, "Sanguidrake", "boss below the area level")
	eq(boss.rename, "Sanguidrake the Unburied", "boss renamed")
	eq(boss.health, cfg.boss.hpPerLevel * area.level, "boss health = hpPerLevel x level")
	ok(boss.dmg >= cfg.boss.minMult and boss.dmg <= cfg.boss.maxDmg, "boss damage scaled")
	local high = I.planBoss(cfg, {level = 400}, faction, 3)
	eq(high.name, "The Ashen Count", "higher area -> stronger boss")
	eq(high.health, math.floor(2500 * 400 * 1.3), "boss health x player factor")
	local low = I.planBoss(cfg, {level = 5}, cfg.factions.minotaurs, 1)
	eq(low.name, "Ironbrow", "no boss low enough -> the lowest")
	eq(low.health, cfg.boss.minHealth, "boss health at least minHealth")
	eq(I.planBoss(cfg, area, {bosses = {}}, 1), nil, "faction without boss")
end

-- ------------------------------------------------------------------ spawn edges and areas
do
	local area = {from = {x = 100, y = 200}, to = {x = 120, y = 230}, z = 7, target = {x = 110, y = 215}}
	local pts = I.edgePoints(area, I.lcg(5), 2)
	ok(#pts > 0, "edge points")
	local seen = {}
	for _, p in ipairs(pts) do
		local onBorder = p.x <= 101 or p.x >= 119 or p.y <= 201 or p.y >= 229
		ok(onBorder, "edge point on the border " .. p.x .. "," .. p.y)
		ok(I.inArea(p, area), "edge point inside")
		local k = p.x .. ":" .. p.y
		ok(not seen[k], "no duplicate edge point")
		seen[k] = true
	end
	-- perimeter 2 rows deep: outer ring 21x31 -> 100, inner ring 19x29 -> 92
	eq(#pts, 192, "edge point count")
	local north = I.edgePoints(area, I.lcg(5), 1, {"north"})
	eq(#north, 21, "north edge only")
	for _, p in ipairs(north) do
		eq(p.y, 200, "north row")
	end
	ok(I.inArea({x = 100, y = 200, z = 7}, area), "corner inside")
	ok(not I.inArea({x = 99, y = 200, z = 7}, area), "outside")
	ok(not I.inArea({x = 110, y = 210, z = 6}, area), "other floor")
	ok(I.inArea({x = 95, y = 200, z = 7}, area, 5), "margin")
	area.exclude = {{105, 205, 110, 210}}
	ok(I.excluded({x = 107, y = 207}, area), "excluded rectangle")
	ok(not I.excluded({x = 111, y = 207}, area), "outside excluded rectangle")
end

-- ------------------------------------------------------------------ wave pacing, breach, outcome
do
	local w = cfg.waves
	local st = {wave = 0, waves = 5, startedAt = 1000, firstWaveAt = 1030}
	ok(not I.nextWaveDue(st, 1029, w), "first wave waits")
	ok(I.nextWaveDue(st, 1030, w), "first wave due")
	st.wave, st.waveSize, st.waveAlive, st.waveAt = 1, 10, 5, 1030
	ok(not I.nextWaveDue(st, 1100, w), "half the wave alive: wait")
	st.waveAlive = 2
	ok(I.nextWaveDue(st, 1100, w), "25% left: next wave")
	st.waveAlive = 8
	ok(I.nextWaveDue(st, 1030 + w.maxWaveSeconds, w), "maxWaveSeconds: next wave")
	st.wave = 5
	ok(not I.nextWaveDue(st, 99999, w), "no wave after the last")

	local b = cfg.breach
	near(I.breachStep(0, 1, false, 1, b), 0.25, 1e-9, "one invader +0.25/s")
	near(I.breachStep(0, 3, false, 1, b), 0.75, 1e-9, "three invaders +0.75/s")
	near(I.breachStep(0, 20, false, 1, b), 1.5, 1e-9, "capped at 1.5/s")
	near(I.breachStep(0, 0, true, 1, b), 1.0, 1e-9, "the boss counts 4")
	near(I.breachStep(10, 0, false, 1, b), 9.75, 1e-9, "decay")
	eq(I.breachStep(0.1, 0, false, 1, b), 0, "not below 0")
	eq(I.breachStep(99.5, 20, false, 1, b), 100, "not above 100")
	-- 5 invaders at the gate: 1.25 per second -> 80 s to fall
	local m, s = 0, 0
	while m < 100 do
		m = I.breachStep(m, 5, false, 1, b)
		s = s + 1
	end
	eq(s, 80, "5 invaders breach in 80 s")

	local run = {breach = 10, wave = 3, waves = 5, alive = 4, endsAt = 2000, bossSpawned = false}
	eq(I.outcome(run, 1500), nil, "running")
	run.breach = 100
	eq(I.outcome(run, 1500), "breach", "breach")
	run.breach = 10
	eq(I.outcome(run, 2000), "time", "time up")
	run.wave, run.alive, run.bossSpawned, run.bossAlive = 5, 0, true, false
	eq(I.outcome(run, 1500), "win", "all slain: win")
	run.bossAlive = true
	eq(I.outcome(run, 1500), nil, "boss alive: not yet")
	run.bossAlive, run.alive = false, 1
	eq(I.outcome(run, 1500), nil, "an invader left: not yet")
end

-- ------------------------------------------------------------------ contribution, shares, rewards
do
	local c = {}
	I.credit(c, 1, "Alice", "damage", 9000)
	I.credit(c, 2, "Bob", "damage", 3000)
	I.credit(c, 2, "Bob", "kills", 4)
	I.credit(c, 3, "Cleric", "healing", 5000)
	I.credit(c, 4, "Afk", "damage", 10)
	eq(I.credit(c, 5, "X", "damage", 0), nil, "no credit for 0")
	eq(c[2].kills, 4, "kills counted")
	local w = cfg.contribution
	local unit = 1000 -- average invader health: a kill = 250 points
	eq(I.score(c[2], w, unit), 3000 + 4 * 250, "score: damage + kills x 0.25 x unit")
	eq(I.score(c[3], w, unit), 3000, "healing x 0.6")
	local list, total = I.shares(c, w, unit, 100)
	eq(#list, 3, "below minPoints left out")
	eq(total, 9000 + 4000 + 3000, "total of the eligible")
	eq(list[1].name, "Alice", "rank 1")
	eq(list[2].name, "Bob", "rank 2")
	eq(list[3].name, "Cleric", "the healer is rewarded")
	near(list[1].share, 9000 / 16000, 1e-9, "share")
	local ex = I.shares(c, w, unit, 100, {[1] = true})
	eq(#ex, 2, "excluded (multi-client)")
	eq(ex[1].name, "Bob", "excluded removed from the ranking")

	local r = cfg.rewards
	local rewards = I.rewards(list, r, 100, 1, function() return 1 end) -- rng 1: every unique roll hits
	local a = rewards[1]
	eq(a.bank, math.floor(100 * (r.goldBase + r.goldPool * list[1].share)), "gold by level and share")
	local items = {}
	for _, it in ipairs(a.items) do
		items[it.id] = it.count
	end
	eq(items[29856], 1 + math.floor(r.pool[1].count * list[1].share), "Orbs of Upheaval: base + share of the pool")
	eq(items[29857], math.floor(r.pool[2].count * list[1].share) + 3, "Orbs of Fate: share + top 1 extra")
	eq(items[29855], 1, "rank 1 Orb of Grafting")
	ok(a.unique, "unique roll")
	eq(a.points, 10 + math.floor(100 * list[1].share + 0.5), "defender points")
	local none = I.rewards(list, r, 100, 1, function() return 10000 end)
	ok(not none[1].unique, "unique roll misses")
	local lib = I.rewards(list, r, 100, 0.25, function() return 1 end)
	eq(lib[1].bank, math.floor(100 * (r.goldBase + r.goldPool * list[1].share) * 0.25), "liberation pays a quarter")
	ok(not lib[1].unique, "no unique for a liberation")
	eq(I.defenderPoints(0, r.defender), 10, "defender points base")
	eq(I.defenderPoints(1, r.defender), 110, "defender points all")
end

-- ------------------------------------------------------------------ occupation and the Victory buff
do
	local occ = {endsAt = 5000}
	eq(I.occupationOver(occ, 4000, 3), nil, "occupation lasts")
	eq(I.occupationOver(occ, 4000, 0), "liberated", "all occupiers slain")
	eq(I.occupationOver(occ, 5000, 2), "withdrawn", "time up")
	eq(I.occupationOver(nil, 1, 1), nil, "no occupation")
	ok(I.buffActive({endsAt = 100}, 99), "buff active")
	ok(not I.buffActive({endsAt = 100}, 100), "buff over")
	ok(not I.buffActive(nil, 1), "no buff")
end

-- ------------------------------------------------------------------ world events
do
	local we = cfg.worldEvents
	local rng = I.lcg(9)
	local counts = {storm = 0, merchant = 0, golden = 0}
	local last
	for _ = 1, 3000 do
		local k = I.pickWorldEvent(we, last, rng)
		ok(k ~= last, "never the same kind twice")
		counts[k] = counts[k] + 1
		last = k
	end
	ok(counts.storm > 0 and counts.merchant > 0 and counts.golden > 0, "every kind happens")
	local only = {storm = {weight = 1}, merchant = {weight = 0}, golden = {weight = 0}}
	eq(I.pickWorldEvent(only, "storm", rng), "storm", "a single kind may repeat")
	eq(I.pickWorldEvent({storm = {weight = 0}, merchant = {weight = 0}, golden = {weight = 0}}, nil, rng), nil, "none enabled")
	local towns = I.worldEventAreas({areas = cfg.areas, worldEvents = {merchant = {areas = {"cinderhold", "thornmere"}}}}, "merchant")
	eq(#towns, 2, "a kind's own area list")
	for _, a in ipairs(I.worldEventAreas(cfg, "storm")) do
		ok(a.enabled ~= false, "disabled areas never host an event")
	end
	for _ = 1, 50 do
		local at = I.nextWorldEventAt(we, 10000, rng, {})
		ok(at >= 10000 + 120 * 60 and at <= 10000 + 240 * 60, "gap of 2-4 hours")
	end
	local inv = 10000 + 150 * 60
	for _ = 1, 50 do
		local at = I.nextWorldEventAt({intervalMinutes = {140, 160}, quietMinutes = 45}, 10000, rng, {{at = inv}})
		ok(at >= inv + 45 * 60 or at <= inv - 45 * 60, "not near an invasion")
	end
end

-- ------------------------------------------------------------------ HUD
do
	eq(I.clock(725), "12:05", "clock")
	eq(I.clock(-5), "0:00", "clock negative")
	local st = {phase = "running", areaName = "Cinderhold", factionName = "Orc Warband", targetName = "the temple steps",
		wave = 3, waves = 5, alive = 14, breach = 33.6, endsAt = 1600, slain = 30, planned = 60,
		bossAlive = false}
	local list = {{guid = 1, name = "A", share = 0.5, rank = 1, kills = 3}, {guid = 2, name = "B", share = 0.3, rank = 2},
		{guid = 3, name = "C", share = 0.15, rank = 3}, {guid = 4, name = "D", share = 0.05, rank = 4}}
	local d = I.hud(st, 1000, list, list[4], cfg)
	eq(d.wave, 3, "hud wave")
	eq(d.waves, 5, "hud waves")
	eq(d.left, 14, "hud left")
	eq(d.breach, 34, "hud breach rounded")
	eq(d.time, 600, "hud time")
	eq(d.progress, 50, "hud progress")
	eq(#d.top, 3, "hud top 3")
	eq(d.top[1].share, 50, "hud top share")
	eq(d.you.rank, 4, "hud own rank")
	eq(d.you.share, 5, "hud own share")
	eq(d.boss, nil, "no boss yet")
	st.bossAlive, st.bossName, st.bossHp = true, "Warchief Grashnak", 63
	d = I.hud(st, 1000, {}, nil, cfg)
	eq(d.boss, "Warchief Grashnak", "hud boss")
	eq(d.bossHp, 63, "hud boss health")
	eq(d.you, nil, "no own entry")
	st.phase, st.occupation = "occupied", {endsAt = 2800, alive = 7}
	d = I.hud(st, 1000, {}, nil, cfg)
	eq(d.time, 1800, "occupation time")
	eq(d.left, 7, "occupiers left")
	local warm = I.hud({phase = "running", wave = 0, waves = 5, firstWaveAt = 1030, endsAt = 2200}, 1000, {}, nil, cfg)
	eq(warm.next, 30, "first wave countdown")
end

-- ------------------------------------------------------------------ engine: the boss unique by the boss's type
-- invasion.lua against a mocked engine: a renamed boss ("Warchief Grashnak", an Orc Warlord) rolls the unique drop
-- lists by its type name, which is what chaos_unique_items.lua lists, not by the name it is shown under.
do
	local n = 0
	setmetatable(_G, {__index = function(t, k)
		if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
	end})
	loadstring = loadstring or load
	local function obj()
		return setmetatable({}, {__index = function() return function() return true end end})
	end
	EventCallback = setmetatable({}, {__newindex = function() end,
		__index = function(t, k) if k == "register" then return function() end end end})
	CreatureEvent, GlobalEvent, TalkAction = obj, obj, obj
	db = {query = function() return true end, storeQuery = function() return false end,
		escapeString = function(v) return "'" .. v .. "'" end}
	addEvent = function() return 1 end
	Game = {getStorageValue = function() return -1 end, getPlayers = function() return {} end}
	json = json or {encode = function() return "{}" end}
	dofile("data/scripts/chaos/invasion.lua")
	local asked = {}
	ChaosLoot = {rollUniques = function(tier, name) asked[#asked + 1] = name return {} end,
		uniqueList = function() return {} end}
	local pos = {sendMagicEffect = function() end}
	local player = {getBankBalance = function() return 0 end, setBankBalance = function() end,
		sendTextMessage = function() end, sendExtendedOpcode = function() end, getPosition = function() return pos end,
		getName = function() return "Ash" end, getGuid = function() return 1 end, getLanguage = function() return "en" end}
	ChaosInvasion.deliver(player, {items = {}, unique = true, rank = 1, share = 0.5, bank = 0, areaLevel = 41,
		areaName = "Cinderhold", bossName = "Warchief Grashnak", bossType = "Orc Warlord"})
	eq(asked[1], "Orc Warlord", "a renamed invasion boss: uniques by its type")
	asked = {}
	ChaosInvasion.deliver(player, {items = {}, unique = true, rank = 1, share = 0.5, bank = 0, areaLevel = 41,
		areaName = "Cinderhold", bossName = "Orc Leader"})
	eq(asked[1], "Orc Leader", "no type recorded (an older reward): the boss name")
	ChaosLoot = nil
	setmetatable(_G, nil)
end

print(string.format("invasion tests: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
