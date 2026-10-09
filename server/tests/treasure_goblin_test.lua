-- Run from the server/ folder: luajit tests/treasure_goblin_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Pure Treasure Goblin logic (treasure_goblin_core.lua + treasure_goblin_config.lua): the spawn roll and its
-- exclusions, the area cooldown, area level and health, the escape / lifetime timers, blinks, loot scaling, the three
-- variants (weights, XMLs, loot tables) and the Treasure Goblin Chance modifier's roll and cap.
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
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
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

-- ------------------------------------------------------------------ variants
do
	local vs = G.variants(cfg)
	eq(#vs, 3, "three variants")
	eq(vs[1].key, "hoarder"); eq(vs[1].name, cfg.name, "the Hoarder keeps the old name (rifts, staff)")
	eq(G.variant(cfg, "gem").name, "Gem Goblin"); eq(G.variant(cfg, "SHARD GOBLIN").key, "shard")
	eq(G.variant(cfg, "nope"), nil, "unknown variant")
	ok(G.isGoblinName(cfg, "gem goblin") and G.isGoblinName(cfg, "Shard Goblin") and G.isGoblinName(cfg, "treasure goblin"),
		"every variant name is a goblin")
	ok(not G.isGoblinName(cfg, "goblin"), "the stock goblin is not")
	local res, why = G.eligible(cfg, spawnInfo({name = "Gem Goblin"}), {alive = 0, lastByCell = {}}, 0)
	ok(not res and why == "goblin", "a variant never turns into a goblin")
	-- weights 70 / 20 / 10
	eq(vs[1].weight + vs[2].weight + vs[3].weight, 100, "weights sum")
	eq(vs[1].weight, 70); eq(vs[2].weight, 20); eq(vs[3].weight, 10)
	local rand, n, seen = rng(11), 30000, {}
	for _ = 1, n do
		local v = G.pickVariant(cfg, rand)
		seen[v.key] = (seen[v.key] or 0) + 1
	end
	for _, v in ipairs(vs) do
		local share = seen[v.key] / n * 100
		ok(math.abs(share - v.weight) < 1.5, v.key .. " share " .. share)
	end
	-- exact boundaries of the weighted pick
	eq(G.pickVariant(cfg, function() return 70 end).key, "hoarder")
	eq(G.pickVariant(cfg, function() return 71 end).key, "gem")
	eq(G.pickVariant(cfg, function() return 90 end).key, "gem")
	eq(G.pickVariant(cfg, function() return 91 end).key, "shard")
	-- XMLs: one per variant, distinct names and stock looks (no new sprites), same flee setup
	local files = {hoarder = "treasure_goblin.xml", gem = "gem_goblin.xml", shard = "shard_goblin.xml"}
	local looks = {}
	for _, v in ipairs(vs) do
		local f = io.open("data/monster/monsters/chaos/" .. files[v.key])
		ok(f ~= nil, v.key .. " XML exists")
		local xml = f and f:read("*a") or ""
		if f then f:close() end
		eq(xml:match('<monster name="([^"]+)"'), v.name, v.key .. " XML name")
		local look = tonumber(xml:match('<look type="(%d+)"'))
		eq(look, v.look, v.key .. " look type")
		ok(look and look <= 2038 and not looks[look], v.key .. ": a distinct stock look type")
		looks[look or 0] = true
		eq(tonumber(xml:match('runonhealth="(%d+)"')), cfg.runThreshold, v.key .. " runonhealth")
		ok(xml:match('hostile="0"') and not xml:match("<attacks>"), v.key .. ": never hostile, no attacks")
		ok(xml:match('ChaosTreasureGoblinHit') and xml:match('ChaosTreasureGoblinDeath'), v.key .. ": events")
		ok((v.shader or 0) >= 1 and (v.shader or 0) <= 17, v.key .. ": a stock shader id")
	end
	ok(vs[1].shader ~= vs[2].shader and vs[2].shader ~= vs[3].shader and vs[1].shader ~= vs[3].shader, "distinct glows")
end

-- ------------------------------------------------------------------ Treasure Goblin Chance
do
	dofile("data/lib/chaos_item_mods.lua")
	local def = ChaosItemMods.byKey[cfg.spoor.modKey]
	ok(def ~= nil, "the modifier exists in chaos_item_mods.lua")
	eq(def.cap, cfg.spoor.cap, "same cap in both places")
	ok(def.kinds.helmet and def.kinds.jewel and not def.kinds.armor, "helmets and jewellery")
	local m, pct = G.spoorMult(cfg, {})
	eq(m, 1); eq(pct, 0, "nobody near: no bonus")
	m, pct = G.spoorMult(cfg, {20, 55, 30})
	eq(pct, 55, "the highest player counts, bonuses do not add up"); eq(m, 1.55)
	m, pct = G.spoorMult(cfg, {250})
	eq(pct, 100, "capped"); eq(m, 2)
	-- the lazy roll has the same odds as the plain roll x the bonus
	local function rate(bonus, n, seed)
		local rand, hits, asked = rng(seed), 0, 0
		for _ = 1, n do
			local hit, oneIn, p = G.rollWithSpoor(cfg, rand, 1, function()
				asked = asked + 1
				return G.spoorMult(cfg, {bonus})
			end)
			if hit then
				hits = hits + 1
				eq(p, bonus, "bonus reported")
				ok(math.abs(oneIn - cfg.spawn.oneIn / (1 + bonus / 100)) < 1e-6, "effective 1 in N")
			end
		end
		return hits, asked
	end
	local n = 1500000
	local h0, asked0 = rate(0, n, 21)
	local h100 = rate(100, n, 22)
	local h40 = rate(40, n, 23)
	local e0 = n / cfg.spawn.oneIn
	ok(math.abs(h0 - e0) < e0 * 0.15, "no bonus: 1 in 3000 (" .. h0 .. " of ~" .. e0 .. ")")
	ok(math.abs(h100 - 2 * e0) < 2 * e0 * 0.15, "+100%: 1 in 1500 (" .. h100 .. " of ~" .. 2 * e0 .. ")")
	ok(math.abs(h40 - 1.4 * e0) < 1.4 * e0 * 0.15, "+40%: 1 in ~2143 (" .. h40 .. " of ~" .. 1.4 * e0 .. ")")
	ok(asked0 < n / 1000, "players are only looked up on a first-stage hit (" .. asked0 .. " of " .. n .. ")")
	-- the event multiplier still applies on top
	local rand, hits = rng(24), 0
	for _ = 1, n do
		if G.rollWithSpoor(cfg, rand, 2, function() return 2, 100 end) then
			hits = hits + 1
		end
	end
	ok(math.abs(hits - 4 * e0) < 4 * e0 * 0.15, "event x2 and +100%: 1 in 750 (" .. hits .. ")")
	-- a tiny oneIn (test servers): the first roll is sure, the bonus still decides
	local saved2 = cfg.spawn.oneIn
	cfg.spawn.oneIn = 2
	local function smallRate(bonus, seed)
		local r, h = rng(seed), 0
		for _ = 1, 20000 do
			if G.rollWithSpoor(cfg, r, 1, function() return G.spoorMult(cfg, {bonus}) end) then
				h = h + 1
			end
		end
		return h / 20000
	end
	ok(math.abs(smallRate(0, 25) - 0.5) < 0.02, "oneIn 2, no bonus: 1 in 2")
	ok(math.abs(smallRate(50, 26) - 0.75) < 0.02, "oneIn 2, +50%: 3 in 4")
	eq(smallRate(100, 27), 1, "oneIn 2, +100%: always")
	cfg.spawn.oneIn = saved2
	-- disabled spawn stays disabled whatever the bonus
	local saved = cfg.spawn.oneIn
	cfg.spawn.oneIn = 0
	ok(not G.rollWithSpoor(cfg, rng(1), 5, function() return 2, 100 end), "oneIn 0: never")
	cfg.spawn.oneIn = saved
end

-- ------------------------------------------------------------------ variant loot tables
do
	dofile("data/lib/chaos_gems.lua")
	local salvage = dofile("data/scripts/chaos/salvage_config.lua")
	local hoarder, gem, shard = G.variant(cfg, "hoarder"), G.variant(cfg, "gem"), G.variant(cfg, "shard")
	local ch, cg, cs = G.forVariant(cfg, hoarder), G.forVariant(cfg, gem), G.forVariant(cfg, shard)
	ok(ch == cfg, "the Hoarder uses the shared table as is")
	eq(cg.loot.gold, cfg.loot.gold, "untouched keys come from the shared table")
	eq(cg.spawn, cfg.spawn, "the view reads the rest of the config")
	eq(cs.loot.shards.id, salvage.shard.id, "Rune Shards = the salvage shard item")
	eq(cg.loot.socketOrb ~= nil, true)
	eq(ch.loot.gems, nil, "the Hoarder has no gems"); eq(ch.loot.shards, nil, "nor shards")
	-- every orb key of the Shard Goblin exists in the salvage orb list (= ChaosCrafting orb keys)
	local known = {}
	for _, w in ipairs(salvage.orbWeights) do
		known[w[1]] = true
	end
	for _, w in ipairs(cs.loot.orbs.weights) do
		ok(known[w[1]], "orb key " .. w[1])
	end

	local function avg(fn, level, seed, n)
		local rand, sum = rng(seed), 0
		n = n or 20000
		for _ = 1, n do
			sum = sum + fn(level, rand)
		end
		return sum / n
	end
	local function hGold(l, r) return G.goldValue(ch, l, r) end
	local function gGold(l, r) return G.goldValue(cg, l, r) end
	local ratio = avg(gGold, 100, 31) / avg(hGold, 100, 31)
	ok(math.abs(ratio - 0.5) < 0.02, "Gem / Shard Goblins carry half the gold: " .. ratio)
	-- Hoarder: unchanged (3 Chaos Orbs at low level, 25% Divine)
	ok(math.abs(avg(function(l, r) return G.chaosOrbs(ch, l, r) end, 50, 32) - 3) < 0.05, "Hoarder chaos orbs")
	eq(G.gemCount(ch, 100, rng(1)), 0); eq(G.shardCount(ch, 100, rng(1)), 0); eq(G.socketOrbs(ch, rng(1)), 0)
	eq(#G.orbKeys(ch, rng(1)), 0)
	-- Gem Goblin: 2-3 gems (+1 per 250 levels, at most 5), 1.25 Orbs of Sockets, no Chaos / Divine Orbs
	local gems100 = avg(function(l, r) return G.gemCount(cg, l, r) end, 100, 33)
	local gems300 = avg(function(l, r) return G.gemCount(cg, l, r) end, 300, 34)
	ok(math.abs(gems100 - 2.5) < 0.05, "gems at level 100: " .. gems100)
	ok(math.abs(gems300 - 3.5) < 0.05, "gems at level 300: " .. gems300)
	eq(G.gemCount(cg, 5000, function(a, b) return b end), 5, "gems capped")
	local so = avg(function(l, r) return G.socketOrbs(cg, r) end, 0, 35)
	ok(math.abs(so - 1.25) < 0.02, "Orbs of Sockets: " .. so)
	eq(G.chaosOrbs(cg, 900, rng(1)), 0, "no Chaos Orbs"); ok(not G.divineOrb(cg, 3, rng(1)), "no Divine Orb")
	eq(G.itemCount(cg, rng(1)), 1, "one rolled gear item")
	-- gem ids from the gem system, tiers by level (no Perfect gem from a low-level goblin)
	local rand = rng(36)
	for _ = 1, 2000 do
		local id = ChaosGems.randomGem(ChaosGems.levelWeights(30), rand)
		local g = ChaosGems.gemOf(id)
		ok(g and g.tier <= 2, "low-level gem tier")
	end
	-- Shard Goblin: (10 + L/10) x 80-120% shards, at most 60; 1-2 Chaos Orbs; one crafting orb
	local s100 = avg(function(l, r) return G.shardCount(cs, l, r) end, 100, 37)
	local s300 = avg(function(l, r) return G.shardCount(cs, l, r) end, 300, 38)
	ok(math.abs(s100 - 20) < 0.5, "shards at level 100: " .. s100)
	ok(math.abs(s300 - 40) < 0.7, "shards at level 300: " .. s300)
	eq(G.shardCount(cs, 2000, function(a, b) return b end), 60, "shards capped")
	ok(G.shardCount(cs, 1, function(a) return a end) >= 8, "a few shards even at level 1")
	ok(math.abs(avg(function(l, r) return G.chaosOrbs(cs, l, r) end, 100, 39) - 1.5) < 0.05, "Shard Goblin chaos orbs")
	local orbSeen = {}
	rand = rng(40)
	for _ = 1, 5000 do
		local keys = G.orbKeys(cs, rand)
		eq(#keys, 1, "one crafting orb")
		orbSeen[keys[1]] = (orbSeen[keys[1]] or 0) + 1
	end
	ok(orbSeen.transmutation > orbSeen.chaos and orbSeen.chaos > orbSeen.exalted, "orb weights")
	-- economy: per goblin on average (70 / 20 / 10), level 100 and 300
	local perGoblinGems = 0.2 * gems100
	local perGoblinShards100, perGoblinShards300 = 0.1 * s100, 0.1 * s300
	ok(perGoblinGems > 0.4 and perGoblinGems < 0.6, "about 0.5 gems per goblin")
	ok(perGoblinShards100 > 1.8 and perGoblinShards100 < 2.2, "about 2 shards per goblin at level 100")
	ok(perGoblinShards300 > 3.8 and perGoblinShards300 < 4.2, "about 4 shards per goblin at level 300")
	-- the variants' orb value stays near the Hoarder's (Chaos Coins: Chaos 10, Divine 25, Sockets 25; 25 shards = 1
	-- Chaos Orb): Hoarder 3 x 10 + 0.25 x 25 = 36; Gem 1.25 x 25 = 31 + gems; Shard 1.5 x 10 + 20/25 x 10 + ~11 = 34
	local hoarderOrbs = 3 * 10 + cfg.loot.divineOrb.chance / 100 * 25
	local gemOrbs = so * 25
	local shardOrbs = 1.5 * 10 + s100 / 25 * 10 + 11
	ok(gemOrbs < hoarderOrbs and shardOrbs < hoarderOrbs * 1.1, "variants do not out-earn the Hoarder in orbs")
end

print(string.format("treasure_goblin_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
