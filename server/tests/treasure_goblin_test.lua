-- Run from the server/ folder: luajit tests/treasure_goblin_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Pure Treasure Goblin logic (treasure_goblin_core.lua + treasure_goblin_config.lua): the spawn roll and its
-- exclusions, the area cooldown, area level and health, the escape / lifetime timers, blinks, and loot scaling.
local cfg = dofile("data/scripts/chaos/treasure_goblin_config.lua")
dofile("data/scripts/chaos/treasure_goblin_core.lua")
local G = ChaosTreasureGoblinCore

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

-- deterministic generator (same in LuaJIT and Lua 5.3)
local function rng(seed)
	local s = seed
	return function(a, b)
		s = (s * 16807) % 2147483647
		return a + s % (b - a + 1)
	end
end

local function spawnInfo(over)
	local info = {name = "Dragon", pos = {x = 1000, y = 1000, z = 7}, natural = true, startup = false, summon = false,
		boss = false, hostile = true, maxHealth = 1000}
	for k, v in pairs(over or {}) do
		info[k] = v
	end
	return info
end

-- ------------------------------------------------------------------ eligibility and exclusions
do
	local st = {alive = 0, lastByCell = {}}
	local now = 100000
	ok(G.eligible(cfg, spawnInfo(), st, now), "plain natural respawn is eligible")
	local cases = {
		{{natural = false}, "artificial"}, -- rifts, arenas, tower, world boss adds, ambush copies
		{{startup = true}, "startup"},
		{{name = "Treasure Goblin"}, "goblin"},
		{{summon = true}, "summon"},
		{{boss = true}, "boss"},
		{{hostile = false}, "critter"},
		{{maxHealth = 10}, "weak"},
		{{excluded = true}, "area"}
	}
	for _, c in ipairs(cases) do
		local res, why = G.eligible(cfg, spawnInfo(c[1]), st, now)
		ok(not res, "excluded: " .. c[2])
		eq(why, c[2], "reason")
	end
	-- configured rectangles (quest rooms)
	local saved = cfg.spawn.excludedAreas
	cfg.spawn.excludedAreas = {{990, 990, 1010, 1010, 7}, {0, 0, 50, 50}}
	local r1 = G.eligible(cfg, spawnInfo(), st, now)
	ok(not r1, "inside an excluded rectangle")
	ok(G.eligible(cfg, spawnInfo({pos = {x = 1000, y = 1000, z = 6}}), st, now), "rectangle with z only covers its floor")
	ok(not G.eligible(cfg, spawnInfo({pos = {x = 20, y = 20, z = 3}}), st, now), "rectangle without z covers every floor")
	cfg.spawn.excludedAreas = saved
	-- skip names
	cfg.spawn.skipNames["dragon"] = true
	ok(not G.eligible(cfg, spawnInfo(), st, now), "skipped name")
	cfg.spawn.skipNames["dragon"] = nil
	-- max alive
	st.alive = cfg.spawn.maxAlive
	local r2, why2 = G.eligible(cfg, spawnInfo(), st, now)
	ok(not r2 and why2 == "max alive", "max alive")
	st.alive = 0
	-- per area cooldown: same cell blocked, other cell fine, free again after the cooldown
	G.markSpawn(cfg, st, {x = 1000, y = 1000, z = 7}, now)
	local r3, why3 = G.eligible(cfg, spawnInfo({pos = {x = 1010, y = 1020, z = 7}}), st, now + 60)
	ok(not r3 and why3 == "cooldown", "same cell on cooldown")
	ok(G.eligible(cfg, spawnInfo({pos = {x = 1000, y = 1000, z = 8}}), st, now + 60), "other floor not on cooldown")
	ok(G.eligible(cfg, spawnInfo({pos = {x = 1200, y = 1000, z = 7}}), st, now + 60), "other cell not on cooldown")
	ok(G.eligible(cfg, spawnInfo(), st, now + cfg.spawn.areaCooldown), "cooldown over")
	-- disabled
	local savedOne = cfg.spawn.oneIn
	cfg.spawn.oneIn = 0
	ok(not G.eligible(cfg, spawnInfo(), st, now + 99999), "oneIn 0 disables")
	ok(not G.rollSpawn(cfg, rng(1)), "oneIn 0 never rolls")
	cfg.spawn.oneIn = savedOne
end

-- ------------------------------------------------------------------ the dice
do
	local rand = rng(11)
	local hits, n = 0, 600000
	for _ = 1, n do
		if G.rollSpawn(cfg, rand) then
			hits = hits + 1
		end
	end
	local expect = n / cfg.spawn.oneIn
	ok(math.abs(hits - expect) < expect * 0.2, "1 in oneIn: " .. hits .. " of ~" .. expect)
	local boosted = 0
	for _ = 1, n do
		if G.rollSpawn(cfg, rand, 2) then
			boosted = boosted + 1
		end
	end
	ok(boosted > hits * 1.6, "event multiplier doubles the odds")
	local saved = cfg.spawn.oneIn
	cfg.spawn.oneIn = 1
	ok(G.rollSpawn(cfg, rand), "oneIn 1 always (test setting)")
	cfg.spawn.oneIn = saved
end

-- ------------------------------------------------------------------ area level and health
do
	eq(G.areaLevel(cfg, 230, {10, 20}, 5000), 230, "monster level wins")
	eq(G.areaLevel(cfg, 0, {100, 200, 300}, 5000), 200, "else the players' average")
	eq(G.areaLevel(cfg, 0, {}, 1000), 1000 / cfg.level.healthPerLevel, "else max health / healthPerLevel")
	eq(G.areaLevel(cfg, 0, nil, 0), cfg.level.min, "clamped to min")
	eq(G.areaLevel(cfg, 99999, nil, 0), cfg.level.max, "clamped to max")
	local h50 = G.realHealth(cfg, 50, 100)
	eq(h50, cfg.health.base + cfg.health.perLevel * 50, "health from level")
	eq(G.realHealth(cfg, 50, 10000), 10000 * cfg.health.monsterMult, "at least monsterMult x the replaced monster")
	ok(G.realHealth(cfg, 500, 100) > G.realHealth(cfg, 100, 100), "health grows with the level")
	local dormant = G.dormantHealth(cfg, h50)
	ok(dormant > cfg.runThreshold, "dormant health above runonhealth (no flee before the hit)")
	ok(h50 <= cfg.runThreshold, "real health at or below runonhealth (flees after the hit)")
	-- XML and config agree on the threshold
	local xml = io.open("data/monster/monsters/chaos/treasure_goblin.xml"):read("*a")
	eq(tonumber(xml:match('runonhealth="(%d+)"')), cfg.runThreshold, "XML runonhealth == runThreshold")
	ok(xml:match('hostile="0"') ~= nil, "XML: never hostile")
	ok(xml:match("<attacks>") == nil, "XML: no attacks")
	eq(xml:match('<monster name="([^"]+)"'), cfg.name, "XML name")
end

-- ------------------------------------------------------------------ escape timer, lifetime, blinks, taunts
do
	local b = cfg.behaviour
	local st = {bornAt = 0}
	eq(G.due(cfg, st, 60000), nil, "idle goblin stays")
	eq(G.due(cfg, st, b.lifetimeSeconds * 1000), "expire", "never hit: expires after the lifetime")
	st = {bornAt = 0}
	ok(G.onHit(cfg, st, 5000), "first hit")
	ok(not G.onHit(cfg, st, 6000), "second hit is not first")
	eq(st.escapeAt, 5000 + b.escapeSeconds * 1000, "escape scheduled from the first hit")
	ok(b.escapeSeconds >= 15 and b.escapeSeconds <= 20, "escape window 15-20 s")
	eq(G.due(cfg, st, 5000 + b.escapeSeconds * 1000 - 1), nil, "not yet")
	eq(G.due(cfg, st, 5000 + b.escapeSeconds * 1000), "escape", "escapes on time")
	eq(G.due(cfg, st, b.lifetimeSeconds * 1000 + 1), "escape", "a hit goblin escapes, it does not expire")
	-- blinks only while fleeing, spaced by blinkEveryMs
	local rand = rng(5)
	local idle = {bornAt = 0}
	ok(not G.blinkDue(cfg, idle, 100000, rand), "no blink before the first hit")
	local fl = {bornAt = 0}
	G.onHit(cfg, fl, 0)
	local blinks, t, last = 0, 0, nil
	while t < b.escapeSeconds * 1000 do
		if G.blinkDue(cfg, fl, t, rand) then
			blinks = blinks + 1
			if last then
				ok(t - last >= b.blinkEveryMs[1], "blinks spaced")
			end
			last = t
		end
		t = t + b.tickMs
	end
	ok(blinks >= 2 and blinks <= 8, "a few blinks per escape window: " .. blinks)
	-- taunt cooldown
	local tt = {}
	local sure = function(a) return a end -- rand(1, 100) -> 1: always within the chance
	ok(G.tauntDue(cfg, tt, 1000, sure), "taunt")
	ok(not G.tauntDue(cfg, tt, 1000 + b.tauntCooldownMs - 1, sure), "taunt on cooldown")
	ok(G.tauntDue(cfg, tt, 1000 + b.tauntCooldownMs, sure), "taunt after cooldown")
	-- speed
	eq(G.fleeSpeedDelta(cfg, 220, 400), math.floor(400 * b.fleeSpeedMult) - 220, "faster than the attacker")
	eq(G.fleeSpeedDelta(cfg, 220, 0), b.minBoost, "at least minBoost")
	eq(G.fleeSpeedDelta(cfg, 220, 5000), b.maxSpeed - 220, "capped")
	-- blink destination: away from the attackers
	local best = G.bestBlink({{x = 10, y = 10}, {x = 0, y = 15}, {x = 20, y = 15}}, {{x = 18, y = 14}, {x = 19, y = 16}})
	eq(best.x, 0, "blinks away from the attackers")
	eq(G.bestBlink({}, {{x = 1, y = 1}}), nil, "no candidate, no blink")
end

-- ------------------------------------------------------------------ loot scaling
do
	local rand = rng(3)
	local function avgGold(level)
		local sum = 0
		for _ = 1, 2000 do
			sum = sum + G.goldValue(cfg, level, rand)
		end
		return sum / 2000
	end
	local g10, g100, g500 = avgGold(10), avgGold(100), avgGold(500)
	ok(g100 > g10 * 3 and g500 > g100 * 3, "gold scales with the level")
	local g = cfg.loot.gold
	local mid = (g.base + g.perLevel * 100) * (g.minMult + g.maxMult) / 200
	ok(math.abs(g100 - mid) < mid * 0.05, "gold average at level 100")
	-- coins: value kept, stacks <= 100
	for _, v in ipairs({0, 99, 12345, 3456789}) do
		local total = 0
		for _, c in ipairs(G.coins(v)) do
			ok(c.count >= 1 and c.count <= 100, "stack size")
			total = total + c.count * ({[2160] = 10000, [2152] = 100, [2148] = 1})[c.id]
		end
		eq(total, v, "coins keep the value " .. v)
	end
	-- orbs
	local o = cfg.loot.chaosOrb
	for _ = 1, 200 do
		local n1 = G.chaosOrbs(cfg, 1, rand)
		ok(n1 >= o.min and n1 <= o.max, "chaos orbs at level 1")
		ok(G.chaosOrbs(cfg, 100000, rand) == o.cap, "chaos orbs capped")
	end
	ok(G.chaosOrbs(cfg, 600, function(a) return a end) > o.min, "more chaos orbs at a high level")
	local div, div3 = 0, 0
	for _ = 1, 20000 do
		if G.divineOrb(cfg, 1, rand) then div = div + 1 end
		if G.divineOrb(cfg, 2, rand) then div3 = div3 + 1 end
	end
	ok(math.abs(div / 20000 * 100 - cfg.loot.divineOrb.chance) < 2, "divine orb chance " .. div / 200)
	ok(div3 > div * 1.6, "item find raises the divine orb chance")
	-- gear rolls: 2-4, tiers by weight, gear from the replaced monster first
	local counts, tiers = {}, {}
	for _ = 1, 6000 do
		local n = G.itemCount(cfg, rand)
		counts[n] = (counts[n] or 0) + 1
		local t = G.pickItemTier(cfg, rand)
		tiers[t.tier] = (tiers[t.tier] or 0) + 1
	end
	ok(counts[2] and counts[3] and counts[4] and not counts[1] and not counts[5], "2-4 guaranteed items")
	ok(tiers.magic > tiers.rare and tiers.rare > tiers.legendary and tiers.legendary > 600, "tier weights")
	for _, t in ipairs(cfg.loot.itemTiers) do
		ok(t.floor >= 1, "every gear roll has a rarity floor: " .. t.tier)
	end
	local own = G.pickGear(cfg, 80, {111, 222}, 4, rand)
	eq(#own, 4, "picked count")
	for _, id in ipairs(own) do
		ok(id == 111 or id == 222, "gear from the replaced monster")
	end
	local low, high = G.poolFor(cfg, 5), G.poolFor(cfg, 400)
	ok(low ~= high and #low > 0 and #high > 0, "fallback pool by level band")
	for _, id in ipairs(G.pickGear(cfg, 400, {}, 3, rand)) do
		local found = false
		for _, x in ipairs(high) do
			if x == id then found = true end
		end
		ok(found, "fallback gear from the level band")
	end
	-- experience: modest and capped
	eq(G.experience(cfg, 0, 50), cfg.experience.min, "minimum experience")
	eq(G.experience(cfg, 700, 100), 700 * cfg.experience.mult, "replaced experience x mult")
	eq(G.experience(cfg, 1000000, 10), 10 * cfg.experience.capPerLevel, "capped by area level")
	-- hoard uniques: never boss-only, level filtered
	local list = {{name = "A", id = 1, level = 50}, {name = "B", id = 2, level = 500}, {name = "C", id = 3, level = 10, bossOnly = true}}
	local hc = G.hoardCandidates(cfg, list, 60)
	eq(#hc, 1, "hoard candidates")
	eq(hc[1].name, "A", "hoard candidate by level")
end

print(string.format("treasure_goblin_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
