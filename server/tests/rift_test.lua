-- Run from the server/ folder: luajit tests/rift_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Pure rift logic (rift_core.lua + rift_config.lua): modifier rolling and tiers, key format, reward scaling, key drop odds,
-- slot allocation and layout, the run timer / fail / boss bookkeeping, lives, omens and the experience cap.
local cfg = dofile("data/scripts/chaos/rift_config.lua")
dofile("data/scripts/chaos/rift_core.lua")
local R = ChaosRiftCore
-- the packs of before (density off): the same config with density.enabled = false
local legacy = setmetatable({density = {enabled = false}}, {__index = cfg})

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

-- ------------------------------------------------------------------ modifiers
do
	local rand = rng(7)
	local seenMods, counts = {}, {0, 0, 0}
	for _ = 1, 3000 do
		local key = R.rollKey(cfg, 4, rand)
		local n = #key.mods
		ok(n >= 1 and n <= 3, "1-3 modifiers")
		counts[n] = counts[n] + 1
		local keys = {}
		local lastIndex = 0
		for _, m in ipairs(key.mods) do
			local def, i = R.modDef(cfg, m.key)
			ok(def ~= nil, "known modifier " .. tostring(m.key))
			ok(not keys[m.key], "no duplicate modifier")
			keys[m.key] = true
			ok(i > lastIndex, "modifiers in config order")
			lastIndex = i
			ok(m.value >= def.range[1] and m.value <= def.range[2], "value in range " .. m.key)
			ok((m.value - def.range[1]) % def.step == 0, "value on a step " .. m.key)
			seenMods[m.key] = (seenMods[m.key] or 0) + 1
		end
		eq(key.tier, 4, "tier kept")
	end
	-- every modifier a tier-4 key may roll shows up about in proportion to its weight; the gated ones never do
	local drawn, weights = 0, 0
	for _, v in pairs(seenMods) do
		drawn = drawn + v
	end
	for _, def in ipairs(cfg.mods) do
		if (def.minTier or 1) <= 4 then
			weights = weights + R.modWeight(def)
		end
	end
	for _, def in ipairs(cfg.mods) do
		if (def.minTier or 1) <= 4 then
			-- about its weight's share of every draw (groups and exclusions move it a little)
			local expect = drawn * R.modWeight(def) / weights
			ok((seenMods[def.key] or 0) > 0.6 * expect, "every modifier rolls: " .. def.key .. " " .. tostring(seenMods[def.key])
				.. " (expected ~" .. math.floor(expect) .. ")")
		else
			eq(seenMods[def.key], nil, "tier gating: " .. def.key)
		end
	end
	-- weights 50 / 35 / 15
	ok(math.abs(counts[1] / 3000 - 0.50) < 0.04, "one modifier ~50%")
	ok(math.abs(counts[3] / 3000 - 0.15) < 0.03, "three modifiers ~15%")
	local better = {0, 0, 0}
	for _ = 1, 3000 do
		local n = R.rollModCount(cfg, rand, true)
		better[n] = better[n] + 1
	end
	ok(better[3] > counts[3] * 1.5, "a better key has more modifiers")
end

-- ------------------------------------------------------------------ key format
do
	local key = {tier = 4, mods = {{key = "vitality", value = 40}, {key = "reflection", value = 10}}}
	local text = R.encodeMods(key.mods)
	eq(text, "vitality:40,reflection:10", "encode")
	local back = R.decodeMods(cfg, text)
	eq(#back, 2, "decode count")
	eq(back[1].key, "vitality", "decode key")
	eq(back[2].value, 10, "decode value")
	local dirty = R.decodeMods(cfg, "swarm:9,bogus:5,vitality:1,vitality:50,haste:60,elites:100")
	eq(#dirty, 3, "decode drops unknown / duplicates and keeps at most 3")
	eq(dirty[1].key, "vitality", "decode sorts by config order")
	eq(dirty[1].value, 20, "decode clamps up to the range")
	local swarm
	for _, m in ipairs(dirty) do
		if m.key == "swarm" then
			swarm = m
		end
	end
	eq(swarm and swarm.value, R.modDef(cfg, "swarm").range[2], "decode clamps down to the range")
	eq(#R.decodeMods(cfg, nil), 0, "decode nil")
	for _, m in ipairs(key.mods) do
		local u = R.unpackMod(cfg, R.packMod(cfg, m))
		eq(u.key .. u.value, m.key .. m.value, "pack / unpack " .. m.key)
	end
	eq(R.unpackMod(cfg, 0), nil, "unpack 0")
	eq(R.unpackMod(cfg, 99000), nil, "unpack unknown index")
	eq(R.keyName(cfg, 4), "Rift Key (Tier 4)", "key name")
	local d = R.describe(cfg, key)
	ok(d:find("Monsters have %+40%% health") ~= nil, "description lists modifier 1: " .. d)
	ok(d:find("reflect 10%%") ~= nil, "description lists modifier 2")
	ok(d:find("%+30%% item quantity") ~= nil, "description lists the quantity bonus")
	ok(d:find("level 300%+") ~= nil, "description names the level")
	eq(R.clampTier(cfg, 99), cfg.maxTier, "tier clamped")
	eq(R.clampTier(cfg, 0), 1, "tier at least 1")
end

-- ------------------------------------------------------------------ bonuses and effects
do
	local b = R.bonuses(cfg, {{key = "vitality", value = 40}, {key = "withering", value = 1}, {key = "swarm", value = 2}})
	eq(b.quantity, 20 + 15 + 16, "quantity bonus")
	eq(b.experience, 10 + 15 + 10, "experience bonus")
	eq(b.rarity, 0, "rarity bonus")
	local fx = R.effects(cfg, {{key = "vitality", value = 40}, {key = "brutality", value = 20}, {key = "haste", value = 50},
		{key = "elites", value = 100}, {key = "reflection", value = 10}, {key = "warding", value = 20},
		{key = "withering", value = 1}, {key = "swarm", value = 2}}, 4)
	ok(math.abs(fx.health - 1.4) < 1e-9, "health x1.4")
	ok(math.abs(fx.damage - 1.2) < 1e-9, "damage x1.2")
	eq(fx.speed, 50, "speed")
	ok(math.abs(fx.elite - 2.0) < 1e-9, "elite x2")
	ok(math.abs(fx.reflect - 0.1) < 1e-9, "reflect 10%")
	ok(math.abs(fx.resist - 0.2) < 1e-9, "resist 20%")
	eq(fx.noRegen, true, "withering")
	eq(fx.packBonus, 2, "swarm")
	local t12 = R.tierInfo(cfg, 12)
	eq(t12.minLevel, 950, "tier 12 level")
	ok(math.abs(t12.health - 1.3) < 1e-9, "tier 12 health")
	local fx12 = R.effects(cfg, {}, 12)
	ok(math.abs(fx12.damage - 1.3) < 1e-9, "tier 12 damage")
	eq(R.tierInfo(cfg, 4).minLevel, 300, "tier 4 level")
end

-- ------------------------------------------------------------------ plan
do
	local pool = {
		{name = "Low", level = 50, health = 500},
		{name = "A", level = 300, health = 5000},
		{name = "B", level = 350, health = 6000},
		{name = "C", level = 400, health = 7000},
		{name = "D", level = 410, health = 50}, -- too little health: left out
		{name = "E", level = 600, health = 9000}
	}
	local rand = rng(11)
	local types = R.pickTypes(cfg, pool, 4, rand) -- window 280-420
	eq(#types, 3, "three types")
	eq(types[3].name, "C", "types sorted by level, strongest last")
	local unknownC = R.pickTypes(cfg, pool, 4, rand, function(n) return n ~= "C" end)
	ok(#unknownC == 3, "window widened when a type is unknown")
	local fx = R.effects(cfg, {{key = "swarm", value = 2}}, 4)
	local plan = R.plan(legacy, 4, fx, 2, types, {"east", "north"}, rand)
	local count, sum = cfg.packs.base + math.floor(4 / cfg.packs.perTiers) + cfg.packs.perExtraPlayer, 0
	eq(#plan.packs, count, "pack count (tier, extra player)")
	eq(plan.packs[1].room, "hub", "first pack in the hub")
	for i, p in ipairs(plan.packs) do
		ok(p.count >= cfg.packs.size[1] + 2 and p.count <= cfg.packs.size[2] + 2, "pack size + swarm")
		eq(#p.elites, p.count, "one elite roll per monster")
		if i > 1 then
			ok(p.room == "east" or p.room == "north", "packs only in open rooms")
		end
		sum = sum + p.count
	end
	eq(plan.total, sum, "total")
	eq(plan.bossAt, math.ceil(sum * cfg.bossAt / 100), "boss threshold")
	eq(plan.boss, "C", "boss = strongest type")
	-- elites: the Elites modifier raises them
	local function eliteShare(f)
		local r, n, e = rng(5), 0, 0
		for _ = 1, 20000 do
			n = n + 1
			if R.eliteTier(cfg, f, 4, r) then
				e = e + 1
			end
		end
		return e / n
	end
	local base = eliteShare(R.effects(cfg, {}, 4))
	local more = eliteShare(R.effects(cfg, {{key = "elites", value = 100}}, 4))
	ok(math.abs(base - 0.136 * 1.2) < 0.015, "base elite share ~16%: " .. base)
	ok(more > base * 1.8, "Elites doubles them")
end

-- ------------------------------------------------------------------ rewards
do
	local rand = rng(3)
	local g2 = cfg.reward.goldPerTier2
	local r4 = R.reward(cfg, 4, {quantity = 0, rarity = 0}, rand)
	eq(r4.gold, g2 * 16, "tier 4 gold")
	eq(r4.lootTier, "rare", "tier 4 loot tier")
	local r4q = R.reward(cfg, 4, {quantity = 50, rarity = 40}, rand)
	eq(r4q.gold, math.floor(g2 * 16 * 1.5), "quantity bonus scales gold")
	ok(math.abs(r4q.rarityMult - 1.4) < 1e-9, "rarity bonus multiplier")
	eq(R.reward(cfg, 10, {quantity = 0}, rand).gold, g2 * 100, "tier 10 gold")
	eq(R.reward(cfg, 12, {quantity = 0}, rand).gold, math.floor(g2 * 144 * 1.2), "tier 12 gold with the beyond bonus")
	eq(R.lootTier(cfg, 2), "magic", "tier 2 loot tier")
	eq(R.lootTier(cfg, 10), "legendary", "tier 10 loot tier")
	eq(R.lootTier(cfg, 11), "boss", "tier 11 loot tier")
	-- expected orbs: (base + perTier x t) x quantity
	local rc, rd = cfg.reward.chaos, cfg.reward.divine
	local n, chaos, divine, rolls = 4000, 0, 0, 0
	for _ = 1, n do
		local r = R.reward(cfg, 6, {quantity = 20}, rand)
		chaos, divine, rolls = chaos + r.chaos, divine + r.divine, rolls + r.rolls
	end
	ok(math.abs(chaos / n - (rc.base + rc.perTier * 6) * 1.2) < 0.05, "mean Orbs of Upheaval tier 6: " .. chaos / n)
	ok(math.abs(divine / n - (rd.base + rd.perTier * 6) * 1.2) < 0.04, "mean Orbs of Fate tier 6: " .. divine / n)
	ok(math.abs(rolls / n - (2 + 0.5 * 6) * 1.2) < 0.1, "mean item rolls tier 6: " .. rolls / n)
	local last = 0
	for t = 1, cfg.maxTier do
		local g = R.reward(cfg, t, nil, rand).gold
		ok(g > last, "gold grows with the tier " .. t)
		last = g
	end
end

-- ------------------------------------------------------------------ key drops
do
	local o0, o1, o3 = R.keyOdds(cfg, 0), R.keyOdds(cfg, 1), R.keyOdds(cfg, 3)
	eq(o1.chance, 40, "1 modifier: 40%")
	eq(o3.chance, 60, "3 modifiers: 60%")
	eq(o0.chance, 30, "no modifier: 30%")
	eq(o1.nextTier, 60, "1 modifier: 60% of the keys are the next tier")
	eq(o3.nextTier, 80, "3 modifiers: 80% next tier")
	local rand = rng(99)
	local n, keys, up, same, mods = 20000, 0, 0, 0, 0
	for _ = 1, n do
		local k = R.rollKeyDrop(cfg, 5, 2, rand)
		if k then
			keys = keys + 1
			if k.tier == 6 then
				up = up + 1
				mods = mods + #k.mods
			elseif k.tier == 5 then
				same = same + 1
			else
				ok(false, "dropped tier must be 5 or 6")
			end
		end
	end
	ok(math.abs(keys / n - 0.50) < 0.015, "2 modifiers: ~50% key drop: " .. keys / n)
	ok(math.abs(up / keys - 0.70) < 0.02, "~70% of them next tier: " .. up / keys)
	ok(mods / up > 1.9, "next-tier keys roll more modifiers: " .. mods / up)
	for _ = 1, 500 do
		local k = R.rollKeyDrop(cfg, cfg.maxTier, 3, rand)
		ok(not k or k.tier == cfg.maxTier, "no key above the max tier")
	end
	-- tier-1 keys from normal kills
	eq(R.monsterKeyChance(cfg, 200, 99, "normal"), 0, "killer below level 100")
	eq(R.monsterKeyChance(cfg, 50, 120, "normal"), 0, "monster below level 60")
	eq(R.monsterKeyChance(cfg, 300, 1000, "normal"), 0, "monster far below the killer (level x 0.4)")
	eq(R.monsterKeyChance(cfg, 400, 1000, "normal"), 50, "level-appropriate kill")
	eq(R.monsterKeyChance(cfg, 400, 1000, "legendary"), 1000, "legendary x20")
	eq(R.monsterKeyChance(cfg, nil, 1000, "normal"), 0, "monster not in the pool")
end

-- ------------------------------------------------------------------ slots and layout
do
	local total = R.slotCount(cfg)
	eq(total, 16, "16 slots")
	eq(R.allocSlot(cfg, {}), 0, "first slot")
	eq(R.allocSlot(cfg, {[0] = true, [1] = true}), 2, "next free slot")
	eq(R.allocSlot(cfg, {[0] = true}, {[1] = true}), 2, "bad slots skipped")
	local busy = {}
	for s = 0, total - 1 do
		busy[s] = true
	end
	eq(R.allocSlot(cfg, busy), nil, "all busy")
	busy[9] = nil
	eq(R.allocSlot(cfg, busy), 9, "a freed slot is reused")
	local seen = {}
	for s = 0, total - 1 do
		local c = R.slotCenter(cfg, s)
		eq(R.slotOfPos(cfg, c), s, "slot of its centre " .. s)
		local k = c.x .. "," .. c.y
		ok(not seen[k], "distinct centres")
		seen[k] = true
	end
	local g = cfg.grid
	eq(g.origin.x, 20480, "grid at x/y 20480 (no map tile there)")
	eq(R.slotOfPos(cfg, {x = g.origin.x - 1, y = g.origin.y + 10, z = 7}), nil, "west of the grid")
	eq(R.slotOfPos(cfg, {x = g.origin.x + 10, y = g.origin.y + 10, z = 6}), nil, "the floor above")
	eq(R.slotOfPos(cfg, {x = g.origin.x + 10, y = g.origin.y + 10, z = 8}), 0, "the second floor belongs to the slot")
	eq(R.slotOfPos(cfg, {x = g.origin.x + 10, y = g.origin.y + 10, z = 9}), nil, "below the second floor")
	eq(R.slotOfPos(cfg, {x = g.origin.x + g.spacing * g.cols, y = g.origin.y, z = 7}), nil, "east of the grid")
	-- every layout band fits its slot with a margin (rift_layout_test.lua checks the generated tiles)
	for _, row in ipairs(cfg.layout.sizes) do
		ok(row[2] + 16 <= g.spacing, "band side " .. row[2] .. " fits the slot with 8 cells each side")
	end
	-- clear of every other runtime area (they use x/y 2000-15359)
	local ag = dofile("data/scripts/chaos/areagen_config.lua")
	for _, def in ipairs(ag.areas) do
		ok(def.origin.x + def.size[1] < g.origin.x and def.origin.y + def.size[2] < g.origin.y, "clear of " .. def.id)
	end
end

-- ------------------------------------------------------------------ run: timer, boss, success, fail
do
	local now = 1000
	local run = R.newRun(cfg, now, 10, 8)
	eq(run.deadline, now + cfg.timeLimit, "deadline")
	eq(R.timeLeft(run, now + 100), cfg.timeLimit - 100, "time left")
	eq(R.tick(run, now + cfg.timeLimit - 1), nil, "no fail before the deadline")
	for i = 1, 7 do
		eq(R.onKill(run), nil, "kill " .. i)
	end
	eq(R.onBossKilled(run, now + 10), nil, "no success while the boss has not appeared")
	eq(R.onKill(run), "boss", "boss after 8 kills")
	eq(R.onKill(run), nil, "boss only once")
	eq(run.boss, "alive", "boss alive")
	eq(R.onBossKilled(run, now + 300), "success", "success")
	eq(run.state, "success", "state success")
	eq(R.tick(run, now + cfg.timeLimit + 5), nil, "a sealed rift does not fail later")
	eq(R.onKill(run), nil, "kills after the end ignored")
	eq(R.timeLeft(run, now + 400), 0, "no time left after the end")

	local late = R.newRun(cfg, now, 4, 3)
	for _ = 1, 3 do
		R.onKill(late)
	end
	eq(R.tick(late, now + cfg.timeLimit), "fail", "fail at the deadline")
	eq(late.state, "failed", "state failed")
	eq(R.tick(late, now + cfg.timeLimit + 1), nil, "fail only once")
	eq(R.onBossKilled(late, now + cfg.timeLimit + 2), nil, "no success after failing")

	local slow = R.newRun(cfg, now, 2, 1)
	R.onKill(slow)
	eq(R.onBossKilled(slow, now + cfg.timeLimit + 1), "fail", "a boss killed after the deadline is a fail")
end

-- ------------------------------------------------------------------ experience cap
do
	eq(R.expForLevel(1), 0, "level 1 exp")
	eq(R.expForLevel(2), 100, "level 2 exp")
	eq(R.expForLevel(8), 4200, "level 8 exp")
	local r950 = R.expRatePerMinute(cfg, 950)
	local band = (R.expForLevel(1000) - R.expForLevel(900)) / (25.5 * 60)
	ok(math.abs(r950 - band) < 1, "rate at 950 = the 900-1000 band")
	ok(math.abs(R.expRatePerMinute(cfg, 1200) - band) < 1, "rate past the model = the last band")
	ok(R.expRatePerMinute(cfg, 200) < R.expRatePerMinute(cfg, 400), "rate grows with the level")
	-- 100 h to 1000: the model's hours
	local hours = 0
	for _, b in ipairs(cfg.exp.model) do
		hours = hours + b[3]
	end
	ok(math.abs(hours - 96) < 0.5, "the model sums to ~96 h")
	local st = {base = 0}
	local rate = R.expRatePerMinute(cfg, 950)
	eq(R.capFactor(cfg, st, 950, rate * 0.5, 0.5), 1, "under the cap: full experience")
	-- the first minute allows rate x 1.2
	local f = R.capFactor(cfg, st, 950, rate, 0.5)
	ok(f < 1 and f > cfg.exp.overCapMult, "partly over the cap: " .. f)
	eq(R.capFactor(cfg, st, 950, rate, 0.6), cfg.exp.overCapMult, "over the cap: overCapMult")
	eq(R.capFactor(cfg, st, 950, rate, 3), 1, "time in the rift refills the allowance")
	-- whole run: a group killing 10x faster than the model still gets about capFactor x the model
	local st2, credited = {base = 0}, 0
	for minute = 1, 10 do
		for _ = 1, 10 do
			local base = rate
			credited = credited + base * R.capFactor(cfg, st2, 950, base, minute)
		end
	end
	local expect = rate * 10 * cfg.exp.capFactor
	ok(credited < expect * 1.95 and credited > expect, "10x kill speed stays near the cap: " .. credited / (rate * 10))
	local st3, normal = {base = 0}, 0
	for minute = 1, 10 do
		normal = normal + rate * R.capFactor(cfg, st3, 950, rate, minute)
	end
	ok(math.abs(normal - rate * 10) < 1, "model-speed hunting is never cut")
end

-- ------------------------------------------------------------------ map modifiers (second set)
do
	local function def(k)
		return (R.modDef(cfg, k))
	end
	-- ten new modifiers with a weight, a description and (for the hard ones) a reward bonus
	local new = {"teeming", "gilded", "warband", "coffer", "twin", "echo", "cinder", "blight", "waning", "dread"}
	for _, k in ipairs(new) do
		local d = def(k)
		ok(d ~= nil, "new modifier " .. k)
		ok(d and d.weight and d.weight > 0, "weight " .. k)
		ok(d and (d.boon or d.reward ~= nil), "reward bonus or boon " .. k)
		ok(d and #R.modText(cfg, {key = k, value = d.range[2]}) > 10, "text " .. k)
		ok(d and not R.modText(cfg, {key = k, value = d.range[1]}):find("%%d"), "text formatted " .. k)
	end
	-- the first eight keep their storage index (crash refund marker)
	eq(select(2, R.modDef(cfg, "swarm")), 8, "swarm still index 8")
	-- tier gating
	local rand = rng(21)
	local seen1, seen15 = {}, {}
	for _ = 1, 4000 do
		for _, m in ipairs(R.rollKey(cfg, 1, rand).mods) do
			seen1[m.key] = true
		end
		for _, m in ipairs(R.rollKey(cfg, 15, rand).mods) do
			seen15[m.key] = true
		end
	end
	for _, d in ipairs(cfg.mods) do
		if (d.minTier or 1) > 1 then
			ok(not seen1[d.key], "tier 1 never rolls " .. d.key)
		else
			ok(seen1[d.key], "tier 1 rolls " .. d.key)
		end
		ok(seen15[d.key], "tier 15 rolls " .. d.key)
	end
	-- weights: Teeming (80) rolls about twice as often as Gilded Trail (40)
	local cnt = {}
	local r2 = rng(33)
	for _ = 1, 20000 do
		for _, m in ipairs(R.rollMods(cfg, 1, r2, 15)) do
			cnt[m.key] = (cnt[m.key] or 0) + 1
		end
	end
	local ratio = cnt.teeming / cnt.gilded
	ok(ratio > 1.7 and ratio < 2.3, "weights: teeming / gilded ~2: " .. ratio)
	-- addMods (orbs): respects the tier, no duplicates, config order
	local key = {tier = 1, mods = {{key = "waning", value = 20}}}
	local added = R.addMods(cfg, key, 2, rng(4))
	eq(#added, 2, "addMods adds two")
	eq(#key.mods, 3, "key has three")
	local last = 0
	for _, m in ipairs(key.mods) do
		ok((def(m.key).minTier or 1) <= 1, "addMods respects the tier: " .. m.key)
		local _, i = R.modDef(cfg, m.key)
		ok(i > last, "addMods keeps config order")
		last = i
	end
	-- packing a new modifier for the crash refund marker
	local u = R.unpackMod(cfg, R.packMod(cfg, {key = "dread", value = 125}))
	eq(u.key .. u.value, "dread125", "pack / unpack dread")

	-- bonuses and the cap
	local b = R.bonuses(cfg, {{key = "warband", value = 30}, {key = "blight", value = 50}, {key = "dread", value = 150}})
	eq(b.rarity, cfg.bonusCap.rarity, "rarity capped") -- 85 > 75 -> 75
end

do
	local b = R.bonuses(cfg, {{key = "warband", value = 30}, {key = "blight", value = 50}, {key = "dread", value = 150}})
	eq(b.quantity, 9 + 10 + 15, "quantity of warband + blight + dread")
	eq(b.experience, 15, "experience of blight")
	local q = R.bonuses(cfg, {{key = "vitality", value = 60}, {key = "waning", value = 30}, {key = "swarm", value = 3}})
	eq(q.quantity, cfg.bonusCap.quantity, "quantity capped (30 + 30 + 24 = 84 -> 80)")
	-- the old eight never reach a cap: the best three of each kind
	local best = {quantity = 0, rarity = 0, experience = 0}
	local old = {}
	for i = 1, 8 do
		old[i] = cfg.mods[i]
	end
	for a = 1, 8 do
		for bb = a + 1, 8 do
			for c = bb + 1, 8 do
				local mods = {}
				for _, i in ipairs({a, bb, c}) do
					-- the top of tier III = the old top of the range
					mods[#mods + 1] = {key = old[i].key, value = select(2, R.tierBounds(old[i], 3))}
				end
				local raw = R.bonuses({mods = cfg.mods, tiers = cfg.tiers, beyond = cfg.beyond, maxTier = cfg.maxTier}, mods)
				for k, v in pairs(raw) do
					best[k] = math.max(best[k], v)
				end
			end
		end
	end
	for k, v in pairs(best) do
		ok(v <= cfg.bonusCap[k], "old combinations stay under the " .. k .. " cap: " .. v)
	end

	-- effects
	local fx = R.effects(cfg, {{key = "teeming", value = 50}, {key = "gilded", value = 40}, {key = "warband", value = 20},
		{key = "coffer", value = 60}, {key = "twin", value = 60}, {key = "echo", value = 10}, {key = "cinder", value = 10},
		{key = "blight", value = 30}, {key = "waning", value = 20}, {key = "dread", value = 100}}, 5)
	ok(math.abs(fx.packMult - 1.5) < 1e-9, "teeming x1.5")
	eq(fx.gilded, 40, "gilded chance")
	eq(fx.warband, 20, "warband share")
	eq(fx.coffer, 60, "coffer chance")
	ok(math.abs(fx.twin - 0.6) < 1e-9, "twin share")
	eq(fx.echo, 10, "echo chance")
	ok(math.abs(fx.cinder - 0.1) < 1e-9, "cinder share")
	ok(math.abs(fx.healMult - 0.7) < 1e-9, "blight x0.7")
	ok(math.abs(fx.timeMult - 0.8) < 1e-9, "waning x0.8")
	ok(math.abs(fx.boss - 2) < 1e-9, "dread x2")
	local none = R.effects(cfg, {}, 5)
	eq(none.packMult .. none.healMult .. none.timeMult .. none.boss .. none.twin, "11110", "neutral effects")

	-- plan: Teeming packs, Warbands, the goblin threshold, the coffer room
	local types = {{name = "A", level = 300}, {name = "B", level = 320}, {name = "C", level = 350}}
	local base = R.plan(legacy, 4, none, 1, types, {"east"}, rng(8))
	local more = R.plan(legacy, 4, R.effects(cfg, {{key = "teeming", value = 50}}, 4), 1, types, {"east"}, rng(8))
	eq(#more.packs, math.floor(#base.packs * 1.5 + 0.5), "teeming: +50% packs")
	eq(base.gildedAt, nil, "no goblin without the modifier")
	eq(base.coffer, nil, "no coffer without the modifier")
	eq(base.guardians, 1, "one guardian")
	local wb, packs = 0, 0
	local r = rng(9)
	local fxw = R.effects(cfg, {{key = "warband", value = 30}}, 4)
	for _ = 1, 300 do
		for _, p in ipairs(R.plan(legacy, 4, fxw, 1, types, {"east"}, r).packs) do
			packs = packs + 1
			if p.warband then
				wb = wb + 1
				eq(p.elites[1], "legendary", "warband leader legendary")
				for k = 2, p.count do
					ok(p.elites[k] == "rare" or p.elites[k] == "legendary", "warband members rare+")
				end
			end
		end
	end
	ok(math.abs(wb / packs - 0.30) < 0.03, "warbands ~30% of packs: " .. wb / packs)
	local fxg = R.effects(cfg, {{key = "gilded", value = 100}, {key = "coffer", value = 100}, {key = "twin", value = 55}}, 4)
	for _ = 1, 200 do
		local p = R.plan(cfg, 4, fxg, 1, types, {"east", "west"}, r)
		ok(p.gildedAt and p.gildedAt >= math.ceil(p.total * 0.25) and p.gildedAt <= math.ceil(p.total * 0.60), "goblin at 25-60% kills")
		ok(p.coffer == "east" or p.coffer == "west", "coffer in an open room")
		eq(p.guardians, 2, "twin: two guardians")
	end
	local hub = R.plan(cfg, 4, fxg, 1, types, {}, r)
	eq(hub.coffer, "hub", "coffer in the hub when no side room is open")
	local gch, gn = 0, 2000
	local fxg40 = R.effects(cfg, {{key = "gilded", value = 40}}, 4)
	for _ = 1, gn do
		if R.plan(cfg, 4, fxg40, 1, types, {"east"}, r).gildedAt then
			gch = gch + 1
		end
	end
	ok(math.abs(gch / gn - 0.4) < 0.04, "goblin chance ~40%: " .. gch / gn)

	-- guardian health: twin share, dread, players
	local hm = R.guardianHealthMult(cfg, none, 1)
	ok(math.abs(hm - cfg.boss.healthMult) < 1e-9, "guardian x3")
	ok(math.abs(R.guardianHealthMult(cfg, R.effects(cfg, {{key = "twin", value = 60}}, 4), 1) - 1.8) < 1e-9, "twin 60% each")
	ok(math.abs(R.guardianHealthMult(cfg, R.effects(cfg, {{key = "dread", value = 100}}, 4), 2) - 12) < 1e-9, "dread x2, 2 players")

	-- run: Waning Veil shortens the limit, twin guardians need two kills
	local run = R.newRun(cfg, 1000, 10, 8, R.effects(cfg, {{key = "waning", value = 30}, {key = "twin", value = 60}}, 4))
	eq(run.limit, 420, "waning: 600 s -> 420 s")
	eq(run.deadline, 1420, "deadline")
	eq(run.guardians, 2, "two guardians")
	for _ = 1, 8 do
		R.onKill(run)
	end
	eq(run.boss, "alive", "guardians out")
	eq(R.onBossKilled(run, 1100), "twin", "first guardian: twin left")
	eq(run.state, "running", "still running")
	eq(R.onBossKilled(run, 1101), "success", "second guardian: sealed")
	local plain = R.newRun(cfg, 0, 5, 4)
	eq(plain.limit, cfg.timeLimit, "no fx: the full limit")
	eq(plain.guardians, 1, "no fx: one guardian")

	-- cinder damage: share of the health, capped by tier
	eq(R.cinderDamage(cfg, 2000, 0.1, 4), 200, "cinder 10% of 2000")
	eq(R.cinderDamage(cfg, 100000, 0.15, 4), cfg.cinder.capBase + 4 * cfg.cinder.capPerTier, "cinder cap tier 4")
	eq(R.cinderDamage(cfg, 2000, 0, 4), 0, "no cinder")

	-- coffer
	eq(R.cofferWaveSize(cfg, 1), cfg.coffer.wave.base, "wave solo")
	eq(R.cofferWaveSize(cfg, 3), cfg.coffer.wave.base + 2 * cfg.coffer.wave.perExtraPlayer, "wave 3 players")
	local cl = R.cofferLoot(cfg, 5, {quantity = 20, rarity = 10}, rng(2))
	eq(cl.gold, math.floor(cfg.coffer.goldPerTier2 * 25 * 1.2), "coffer gold tier 5 +20%")
	ok(cl.rolls >= 1 and cl.chaos >= 0, "coffer rolls / chaos")
	ok(cl.gold < R.reward(cfg, 5, {quantity = 20}, rng(2)).gold, "coffer below the chest")
	local coins = R.coins(1234567)
	local total = 0
	for _, c in ipairs(coins) do
		total = total + ({[2160] = 10000, [2152] = 100, [2148] = 1})[c[1]] * c[2]
		ok(c[2] <= 100 and c[2] > 0, "coin stack size")
	end
	eq(total, 1234567, "coins sum")
end


-- ------------------------------------------------------------------ modifier tiers
do
	-- tiers I-III are exactly the ranges of before the tiers (old keys keep their values and roll the same)
	local before = {vitality = {20, 60}, brutality = {15, 40}, haste = {40, 120}, elites = {50, 200}, reflection = {5, 15},
		warding = {10, 30}, swarm = {1, 3}, teeming = {20, 50}, gilded = {30, 70}, warband = {10, 30}, coffer = {40, 100},
		twin = {55, 75}, echo = {5, 15}, cinder = {5, 15}, blight = {20, 50}, waning = {15, 30}, dread = {50, 150}}
	for key, r in pairs(before) do
		local d = R.modDef(cfg, key)
		eq(R.tierBounds(d, 1), r[1], "tier I starts at the old bottom: " .. key)
		eq(select(2, R.tierBounds(d, 3)), r[2], "tier III ends at the old top: " .. key)
		-- every old value decodes unchanged and has a tier of I-III
		for v = r[1], r[2], d.step do
			local m = R.decodeMods(cfg, key .. ":" .. v)[1]
			eq(m and m.value, v, "old value decodes unchanged: " .. key .. v)
			local t = R.modTier(d, v)
			ok(t and t >= 1 and t <= 3, "old value is tier I-III: " .. key .. v)
		end
	end
	for _, d in ipairs(cfg.mods) do
		if d.tiers then
			-- tiers are contiguous on the step grid, increasing, and end at the top of the range
			eq(d.tiers[#d.tiers], d.range[2], "last tier ends the range: " .. d.key)
			for t = 1, #d.tiers do
				local lo, hi = R.tierBounds(d, t)
				ok(lo <= hi, "tier bounds ordered: " .. d.key .. t)
				eq((lo - d.range[1]) % d.step, 0, "tier start on a step: " .. d.key .. t)
				eq(R.modTier(d, lo), t, "tier of its bottom: " .. d.key .. t)
				eq(R.modTier(d, hi), t, "tier of its top: " .. d.key .. t)
			end
		else
			eq(R.modTier(d, d.range[1]), nil, "no tiers: " .. d.key)
		end
	end
	-- windows
	local a, b = R.modTierWindow(cfg, 1)
	eq(a .. b, "13", "tier 1 keys roll I-III")
	a, b = R.modTierWindow(cfg, 5)
	eq(a .. b, "13", "tier 5 keys roll I-III")
	a, b = R.modTierWindow(cfg, 8)
	eq(a .. b, "14", "tier 8 keys roll I-IV")
	a, b = R.modTierWindow(cfg, 15)
	eq(a .. b, "25", "tier 15 keys roll II-V")
	a, b = R.modTierWindow(cfg, nil)
	eq(a .. b, "13", "no tier: I-III")
	-- rolls per key tier
	local r = rng(77)
	local seen = {[1] = {}, [8] = {}, [15] = {}}
	for _, kt in ipairs({1, 8, 15}) do
		for _ = 1, 4000 do
			for _, m in ipairs(R.rollMods(cfg, 3, r, kt)) do
				local d = R.modDef(cfg, m.key)
				ok(m.value >= d.range[1] and m.value <= d.range[2], "tiered value in range")
				eq((m.value - d.range[1]) % d.step, 0, "tiered value on a step")
				local t = R.modTier(d, m.value)
				if t then
					seen[kt][t] = (seen[kt][t] or 0) + 1
				end
			end
		end
	end
	ok(seen[1][4] == nil and seen[1][5] == nil, "tier 1 keys never roll IV / V")
	ok((seen[8][4] or 0) > 500 and seen[8][5] == nil, "tier 8 keys roll IV, never V")
	ok((seen[15][5] or 0) > 500 and seen[15][1] == nil, "tier 15 keys roll V, never I")
	-- the coffer has three tiers: a tier 15 key rolls II-III there
	for _ = 1, 300 do
		local v = R.rollValue(R.modDef(cfg, "coffer"), r, 15, cfg)
		ok(v >= 60 and v <= 100, "coffer on a tier 15 key: II-III")
	end
	-- the old rolls: a key of tier 1-5 rolls the old range with the same single rand call
	local d = R.modDef(cfg, "vitality")
	local calls = 0
	local v = R.rollValue(d, function(x, y) calls = calls + 1; eq(x .. "-" .. y, "0-8", "one call over the old 9 steps"); return 8 end, 4, cfg)
	eq(v, 60, "old top")
	eq(calls, 1, "one rand call")
	eq(R.rollValue(d, function(x, y) return y end, nil, nil), 60, "no tier, no cfg: old range")
	eq(R.rollValue(d, function(x, y) return y end, 15, cfg), 90, "tier 15: top of V")
	eq(R.rollValue(d, function(x, y) return x end, 15, cfg), 35, "tier 15: bottom of II")
	-- labels and descriptions
	eq(R.modLabel(cfg, {key = "vitality", value = 85}), "Vitality V", "label V")
	eq(R.modLabel(cfg, {key = "withering", value = 1}), "Withering", "label without tier")
	local desc = R.describe(cfg, {tier = 12, mods = {{key = "vitality", value = 70}}})
	ok(desc:find("%+70%% health %(IV%)") ~= nil, "description names the tier: " .. desc)
	-- caps rise with tier IV / V modifiers
	local caps = R.bonusCaps(cfg, {{key = "vitality", value = 90}, {key = "swarm", value = 4}})
	eq(caps.quantity, cfg.bonusCap.quantity + 16 + 8, "cap + V + IV")
	local big = R.bonuses(cfg, {{key = "vitality", value = 90}, {key = "waning", value = 40}, {key = "swarm", value = 5}})
	eq(big.quantity, math.min(45 + 40 + 40, cfg.bonusCap.quantity + 48), "three tier V modifiers: raised cap")
	ok(big.quantity > cfg.bonusCap.quantity, "tier V beats the old cap")
	-- packing high values for the crash refund marker
	local u = R.unpackMod(cfg, R.packMod(cfg, {key = "elites", value = 300}))
	eq(u.key .. u.value, "elites300", "pack / unpack elites V")
	-- effects of the new top values
	local fx = R.effects(cfg, {{key = "vitality", value = 90}, {key = "swarm", value = 5}}, 15)
	ok(math.abs(fx.health - 1.9 * R.tierInfo(cfg, 15).health) < 1e-9, "vitality V x1.9")
	eq(fx.packBonus, 5, "swarm V +5")
end

-- ------------------------------------------------------------------ lives
do
	local none = R.effects(cfg, {}, 4)
	eq(R.startLives(cfg, 1, none), 3, "solo: 3 lives")
	eq(R.startLives(cfg, 2, none), 4, "two players: 4")
	eq(R.startLives(cfg, 4, none), 6, "four players: 6")
	local fr = R.effects(cfg, {{key = "fragile", value = 2}}, 6)
	eq(fr.fragile, 2, "fragile -2")
	eq(R.startLives(cfg, 1, fr), 1, "fragile solo: 1")
	eq(R.startLives(cfg, 1, R.effects(cfg, {{key = "fragile", value = 2}, {key = "fragile", value = 2}}, 6)), cfg.lives.min,
		"never below the minimum")
	eq(R.startLives(cfg, 3, fr), 3, "fragile with 3 players: 5 - 2")
	local fb = R.bonuses(cfg, {{key = "fragile", value = 2}})
	eq(fb.quantity .. "/" .. fb.rarity .. "/" .. fb.experience, "14/14/10", "fragile bonuses")
	eq(R.modDef(cfg, "fragile").minTier, 4, "fragile from tier 4")
	local run = R.newRun(cfg, 0, 10, 8)
	run.lives = 2
	eq(R.loseLife(run), 1, "one life lost")
	eq(run.deaths, 1, "deaths counted")
	eq(R.loseLife(run), 0, "last life")
	eq(R.loseLife(run), 0, "never negative")
	run.state = "success"
	eq(R.loseLife(run), nil, "after the seal a death costs nothing")
	eq(run.deaths, 3, "no death counted after the seal")
	-- the fragile modifier is appended: keys of before still decode, the refund marker index is new
	local _, idx = R.modDef(cfg, "fragile")
	eq(idx, 19, "fragile keeps its index (modifiers are only appended)")
	local u = R.unpackMod(cfg, R.packMod(cfg, {key = "fragile", value = 2}))
	eq(u.key .. u.value, "fragile2", "pack / unpack fragile")
end

-- ------------------------------------------------------------------ omens
do
	local o = cfg.omen
	eq(R.omenFragments(cfg, o.minTier - 1, nil, rng(1)), 0, "no fragments below the omen tier")
	eq(R.omenFragments(cfg, o.minTier, nil, rng(1)), o.chest.base, "fragments at the omen tier")
	eq(R.omenFragments(cfg, 10, nil, rng(1)), o.chest.base + 4 * o.chest.perTier, "fragments at tier 10")
	-- +50% quantity: 2 x 1.5 = 3 exactly; 3 x 1.5 = 4.5 -> 4 or 5
	eq(R.omenFragments(cfg, o.minTier, {quantity = 50}, rng(1)), 3, "fragments x quantity")
	local r, fives = rng(12), 0
	for _ = 1, 2000 do
		local n = R.omenFragments(cfg, o.minTier + 1, {quantity = 50}, r)
		ok(n == 4 or n == 5, "fragments 4.5 -> 4 or 5")
		if n == 5 then
			fives = fives + 1
		end
	end
	ok(math.abs(fives / 2000 - 0.5) < 0.04, "fraction is a chance")
	-- runs to a key: tier 6 ~30, tier 10 ~10, tier 15 ~6 (solo, no quantity bonus, chest only)
	ok(o.keyCost / R.omenFragments(cfg, 6, nil, rng(1)) <= 30, "tier 6: at most 30 rifts per key")
	ok(o.keyCost / R.omenFragments(cfg, 15, nil, rng(1)) <= 6, "tier 15: at most 6 rifts per key")
	-- kinds
	eq(#o.kinds, 3, "three omen kinds")
	local names = {}
	for i, k in ipairs(o.kinds) do
		local d, idx = R.omenKind(cfg, k.key)
		eq(d, k, "kind by key")
		eq(idx, i, "kind index")
		eq(R.omenKind(cfg, i), k, "kind by index")
		ok(cfg.themes[k.theme] ~= nil, "kind theme exists")
		ok(not names[k.boss], "one guardian per kind")
		names[k.boss] = true
		eq(R.markerOmen(cfg, R.markerTier(cfg, k.key)), k.key, "marker round trip " .. k.key)
		ok(R.markerTier(cfg, k.key) > cfg.maxTier, "an omen marker is no rift tier")
		-- the guardian's XML exists, with an outfit of the client pair and the same name
		local fn = "data/monster/monsters/chaos/omens/" .. k.boss:lower():gsub(" ", "_") .. ".xml"
		local f = io.open(fn, "r")
		ok(f ~= nil, "guardian XML " .. fn)
		if f then
			local t = f:read("*a")
			f:close()
			ok(t:find('<monster name="' .. k.boss .. '"', 1, true) ~= nil, "guardian name in " .. fn)
			local look = tonumber(t:match('<look type="(%d+)"'))
			ok(look and look <= 2125, "guardian look in the client pair (things_custom11: outfits up to 2125)")
			ok(look and look >= 2116 and look <= 2118, "omen guardian on its own rift-exclusive look (2116-2118)")
		end
	end
	eq(R.omenKind(cfg, "nope"), nil, "unknown kind")
	eq(R.markerOmen(cfg, 7), nil, "a rift tier is no omen")
	eq(R.markerOmen(cfg, 0), nil, "no marker")
	eq(R.omenKeyName(cfg, "hollow"), "Omen Key (Hollow)", "omen key name")
	ok(math.abs(R.omenHealthMult(cfg, 1) - 1) < 1e-9, "guardian solo x1")
	ok(math.abs(R.omenHealthMult(cfg, 4) - (1 + 3 * o.healthPerExtraPlayer)) < 1e-9, "guardian 4 players")
	local rw = R.omenReward(cfg)
	eq(rw.lootTier, "boss", "guardian chest at the boss loot tier")
	ok(rw.gold > R.reward(cfg, 15, nil, rng(1)).gold, "the guardian pays more than a tier 15 rift")
	ok(rw.uniqueRolls >= 1, "unique rolls")
	-- the items are new server ids, apart from each other and from the other Chaos items
	ok(o.fragment.id ~= o.key.id, "two item ids")
	for _, id in ipairs({o.fragment.id, o.key.id}) do
		ok(not (id >= 32001 and id <= 32035) and id ~= 32051 and not (id >= 32101 and id <= 32200)
			and not (id >= 30484 and id <= 30557), "omen id clear of the gem / salvage / support / dark tile ids: " .. id)
	end
end

-- ------------------------------------------------------------------ rift-exclusive looks
do
	local L = cfg.looks
	ok(L and L.enabled, "rift looks on")
	local all = {}
	for _, th in ipairs(cfg.themes) do
		local fam = L.families[th.name]
		ok(fam ~= nil, "a look family for the theme " .. th.name)
		for _, rank in ipairs({"minion", "brute", "elite", "guardian"}) do
			local v = fam and fam[rank]
			ok(type(v) == "number" and v >= 2100 and v <= 2125, th.name .. " " .. rank .. " look in 2100-2125")
			ok(v and not all[v], th.name .. " " .. rank .. ": a look of its own")
			if v then
				all[v] = th.name .. " " .. rank
			end
		end
	end
	local types = {{name = "Weak One", level = 100}, {name = "Middle", level = 150}, {name = "Strong", level = 200}}
	local plan = R.lookPlan(cfg, "Abyssal Rift", types)
	local fam = L.families["Abyssal Rift"]
	eq(R.lookOf(plan, "weak one", false), fam.minion, "weakest type: minion")
	eq(R.lookOf(plan, "MIDDLE", false), fam.brute, "middle type: brute (any case)")
	eq(R.lookOf(plan, "Strong", false), fam.elite, "strongest type: elite")
	eq(R.lookOf(plan, "Strong", true), fam.guardian, "guardian: the guardian look")
	eq(R.lookOf(plan, "Treasure Goblin", false), nil, "a monster of no rift type keeps its look")
	local two = R.lookPlan(cfg, "Ashen Crypt", {types[1], types[3]})
	eq(R.lookOf(two, "weak one", false), L.families["Ashen Crypt"].brute, "two types: brute")
	eq(R.lookOf(two, "strong", false), L.families["Ashen Crypt"].elite, "two types: elite")
	local one = R.lookPlan(cfg, "Obsidian Hall", {types[2]})
	eq(R.lookOf(one, "middle", false), L.families["Obsidian Hall"].elite, "one type: elite")
	eq(R.lookPlan(cfg, "No Such Theme", types), nil, "no family: no looks")
	eq(R.lookOf(nil, "x", true), nil, "no plan: own look")
	-- names: one per rank and theme, the family word first; credit stays with the type (only the shown name changes)
	local names = L.names["Abyssal Rift"]
	eq(R.nameOf(plan, "weak one", false), names.minion, "weakest type: the minion name")
	eq(R.nameOf(plan, "MIDDLE", false), names.brute, "middle type: the brute name (any case)")
	eq(R.nameOf(plan, "Strong", false), names.elite, "strongest type: the elite name")
	eq(R.nameOf(plan, "Strong", true), names.guardian, "guardian: the guardian name")
	eq(R.nameOf(plan, "Treasure Goblin", false), nil, "a monster of no rift type keeps its name")
	eq(R.nameOf(two, "weak one", false), L.names["Ashen Crypt"].brute, "two types: brute name")
	eq(R.nameOf(one, "middle", false), L.names["Obsidian Hall"].elite, "one type: elite name")
	eq(R.nameOf(nil, "x", true), nil, "no plan: own name")
	local shown = {}
	for _, th in ipairs(cfg.themes) do
		for _, rank in ipairs({"minion", "brute", "elite", "guardian"}) do
			local v = L.names[th.name] and L.names[th.name][rank]
			ok(type(v) == "string" and #v >= 3 and #v <= 30 and v:match("^[%a ]+$") ~= nil,
				th.name .. " " .. rank .. ": a name of letters and spaces")
			ok(v and not shown[v:lower()], th.name .. " " .. rank .. ": a name of its own")
			if v then
				shown[v:lower()] = true
			end
		end
	end
	-- rank variants (looks.variants): off until a client pair with looks 2200+ ships; each a look and a name of its own
	-- (the name check against the monster files below covers them too); pack ranks only
	eq(L.variantsOn, false, "rank variants off: looks 2200+ are not in the live client pair yet")
	ok(type(L.variantShare) == "number" and L.variantShare > 0 and L.variantShare < 1, "variant share in (0, 1)")
	local nVar = 0
	for theme, ranks in pairs(L.variants) do
		ok(L.families[theme] ~= nil, "variants of a theme with a family: " .. theme)
		for rank, list in pairs(ranks) do
			ok(rank == "minion" or rank == "brute" or rank == "elite", theme .. " " .. rank .. ": a pack rank")
			for _, e in ipairs(list) do
				nVar = nVar + 1
				ok(type(e.look) == "number" and e.look >= 2200 and e.look <= 2299, e.name .. ": look in 2200-2299")
				ok(not all[e.look], e.name .. ": a look of its own")
				all[e.look] = e.name
				ok(type(e.name) == "string" and #e.name <= 30 and e.name:match("^[%a ]+$") ~= nil,
					e.name .. ": a name of letters and spaces")
				local word = L.names[theme].minion:match("^(%a+)")
				ok(e.name:sub(1, #word + 1) == word .. " ", e.name .. ": the family word first")
				ok(not shown[e.name:lower()], e.name .. ": a name of its own")
				shown[e.name:lower()] = true
			end
		end
	end
	eq(nVar, 8, "eight rank variants")
	eq(plan.variants, nil, "variants off: the plan has none")
	eq(R.pickVariant(plan, "weak one", false, 0), nil, "variants off: the rank's own look")
	L.variantsOn = true
	local vp = R.lookPlan(cfg, "Abyssal Rift", types)
	local mv = L.variants["Abyssal Rift"].minion[1]
	eq(R.pickVariant(vp, "Weak One", false, 0), mv, "variants on, a low roll: the variant (any case)")
	eq(R.pickVariant(vp, "weak one", false, L.variantShare - 1e-9), mv, "just under the share: the variant")
	eq(R.pickVariant(vp, "weak one", false, L.variantShare), nil, "at the share: the rank's own look")
	eq(R.pickVariant(vp, "Strong", true, 0), nil, "a guardian: no variant")
	eq(R.pickVariant(vp, "Treasure Goblin", false, 0), nil, "no rift type: no variant")
	eq(R.pickVariant(nil, "weak one", false, 0), nil, "no plan: no variant")
	eq(R.lookOf(vp, "weak one", false), fam.minion, "the rank's look is kept for the other rolls")
	eq(R.nameOf(vp, "weak one", false), names.minion, "and its name")
	local op = R.lookPlan(cfg, "Obsidian Hall", types)
	eq(R.pickVariant(op, "weak one", false, 0), nil, "a rank without variants: none")
	eq((R.pickVariant(op, "strong", false, 0) or {}).look, 2204, "Obsidian Hall elite: the Ashmane")
	local one2 = R.lookPlan(cfg, "Forsaken Sanctum", {types[2]})
	eq((R.pickVariant(one2, "middle", false, 0) or {}).look, 2207, "one type is the elite: the elite's variant")
	-- two variants of a rank share the rolls evenly
	local list = L.variants["Abyssal Rift"].minion
	list[2] = {look = 2299, name = "Abyssal Test"}
	local tp = R.lookPlan(cfg, "Abyssal Rift", types)
	eq(R.pickVariant(tp, "weak one", false, 0.25 * L.variantShare).look, 2202, "two variants: the first")
	eq(R.pickVariant(tp, "weak one", false, 0.75 * L.variantShare).look, 2299, "two variants: the second")
	list[2] = nil
	-- the share over many spawns
	local rand, hits = rng(11), 0
	for _ = 1, 4000 do
		if R.pickVariant(vp, "weak one", false, (rand(1, 1000000) - 1) / 1000000) then
			hits = hits + 1
		end
	end
	ok(math.abs(hits / 4000 - L.variantShare) < 0.03, "about variantShare of the spawns wear a variant: " .. hits)
	L.variantsOn = false
	L.enabled = false
	eq(R.lookPlan(cfg, "Abyssal Rift", types), nil, "looks off")
	eq(R.nameOf(R.lookPlan(cfg, "Abyssal Rift", types), "Strong", true), nil, "looks off: own names")
	L.enabled = true
	-- a rift name is no monster type's name (so /m, the bestiary and the bounty board never confuse the two)
	local pn = io.popen("find data/monster -name '*.xml'")
	for fn in pn:lines() do
		local f = io.open(fn)
		local t = f:read("*a")
		f:close()
		local n = t:match('<monster%s+name="([^"]+)"')
		if n then
			eq(shown[n:lower()], nil, "rift name " .. n .. " is not a monster type (" .. fn .. ")")
		end
	end
	pn:close()
	-- exclusive: no monster definition uses a rift family look; each omen look only by its guardian
	local p = io.popen("find data/monster -name '*.xml' -o -name '*.lua'")
	local users = {}
	for fn in p:lines() do
		-- the Ascended Omens (uber.lua) are their omens ascended and wear the omen's look on purpose
		local f = not fn:find("/chaos/ascended/", 1, true) and io.open(fn) or nil
		local t = f and f:read("*a") or ""
		if f then
			f:close()
		end
		for v in t:gmatch('<look%s+type="(%d+)"') do
			users[tonumber(v)] = (users[tonumber(v)] or 0) + 1
		end
		for v in t:gmatch("lookType%s*=%s*(%d+)") do
			users[tonumber(v)] = (users[tonumber(v)] or 0) + 1
		end
	end
	p:close()
	for v, what in pairs(all) do
		eq(users[v], nil, what .. " look used by no monster file")
	end
	for _, v in ipairs({2116, 2117, 2118}) do
		eq(users[v], 1, "omen look " .. v .. " used once")
	end
end

-- ------------------------------------------------------------------ party scaling (cfg.party)
do
	local p = cfg.party
	local near = function(a, b) return math.abs(a - b) < 1e-9 end
	local solo = R.party(cfg, 1)
	ok(solo.health == 1 and solo.damage == 1 and solo.reward == 1 and solo.loot == 1, "solo: every party value 1")
	ok(R.party(cfg, nil).players == 1 and R.party(cfg, 0).players == 1, "no or zero players: solo")
	ok(R.party({}, 5).reward == 1, "no party block: neutral")
	ok(cfg.maxPlayers == 5, "rifts take a party of 5")
	-- the curve: health +1.0 or more per extra player, damage up, reward linear up to the cap
	ok(p.healthPerExtraPlayer >= 1.0, "health +100% or more per extra player")
	ok(p.damagePerExtraPlayer > 0, "parties take more damage")
	ok(cfg.boss.perExtraPlayer >= 1.0 and cfg.omen.healthPerExtraPlayer >= 1.0, "guardians +100% per extra player")
	local last = 1
	for n = 2, 8 do
		local ps = R.party(cfg, n)
		ok(near(ps.health, 1 + p.healthPerExtraPlayer * (n - 1)), "total health " .. n)
		ok(near(ps.damage, 1 + p.damagePerExtraPlayer * (n - 1)), "damage " .. n)
		ok(ps.reward >= last and ps.reward <= 1 + p.rewardCap / 100 + 1e-9, "reward grows to the cap " .. n)
		ok(ps.loot <= 1 + p.lootCap / 100 + 1e-9 and ps.loot > 1, "loot bonus bounded " .. n)
		last = ps.reward
	end
	ok(near(R.party(cfg, 2).reward, 1 + p.rewardPerExtraPlayer / 100), "two players: one step")
	local full = R.party(cfg, cfg.maxPlayers)
	ok(full.reward >= 1.4 and full.reward <= 1.5 + 1e-9, "a full party: +40-50% per finisher")
	ok(near(R.party(cfg, 9).reward, full.reward), "capped at a full party")
	-- the packs grow with the players; each monster gets the rest, so the total follows the curve
	for _, tier in ipairs({1, 6, 15}) do
		eq(R.partyMonsterHealth(cfg, tier, 1), 1, "solo monsters x1, tier " .. tier)
		for n = 2, 5 do
			local total = R.partyMonsterHealth(legacy, tier, n) * R.packCount(cfg, tier, n) / R.packCount(cfg, tier, 1)
			ok(math.abs(total - R.party(cfg, n).health) < 1e-9, string.format("packs of before: tier %d, %d players: total health x%.2f", tier, n, total))
			total = R.partyMonsterHealth(cfg, tier, n) * R.densityCount(cfg, tier, n) / R.densityCount(cfg, tier, 1)
			ok(math.abs(total - R.party(cfg, n).health) < 1e-9, string.format("tier %d, %d players: total health x%.2f", tier, n, total))
			ok(R.partyMonsterHealth(cfg, tier, n) >= 1, "a monster never gets weaker")
		end
	end
	-- R.plan uses the same pack count
	local plan = R.plan(legacy, 9, R.effects(cfg, {}, 9), 3, {{name = "a", level = 1}}, {"n"}, rng(4))
	eq(#plan.packs, R.packCount(cfg, 9, 3), "plan packs = R.packCount")
	eq(#R.plan(cfg, 9, R.effects(cfg, {}, 9), 3, {{name = "a", level = 1}}, {"n"}, rng(4)).packs, R.density(cfg, 9, 3).packs,
		"density: plan packs = R.density")
	-- R.applyParty: damage into fx, the monster share, Brutality kept
	local fx = R.applyParty(cfg, R.effects(cfg, {{key = "brutality", value = 20}}, 4), 3, 4)
	ok(near(fx.damage, 1.2 * (1 + 2 * p.damagePerExtraPlayer)), "damage: Brutality x party")
	ok(near(fx.partyHealth, R.partyMonsterHealth(cfg, 4, 3)), "monster share")
	eq(fx.party.players, 3, "party kept on fx")
	local fxs = R.applyParty(cfg, R.effects(cfg, {}, 4), 1, 4)
	ok(fxs.damage == 1 and fxs.partyHealth == 1, "solo fx unchanged")
	local fxo = R.applyParty(cfg, R.effects(cfg, {}, 1), 4, nil)
	ok(fxo.partyHealth == 1 and fxo.damage > 1, "an Omen arena: damage, no pack share")
	-- the guardian health is not scaled twice by the party
	ok(near(R.guardianHealthMult(cfg, fx, 3), cfg.boss.healthMult * (1 + 2 * cfg.boss.perExtraPlayer) * fx.health),
		"guardian health from boss.perExtraPlayer only")
	-- rewards: solo unchanged, a party more per finisher, every field scaled
	local base = R.reward(cfg, 12, {quantity = 40}, rng(5))
	local same = R.partyReward(cfg, R.reward(cfg, 12, {quantity = 40}, rng(5)), 1, rng(1))
	ok(same.gold == base.gold and same.chaos == base.chaos and same.rolls == base.rolls, "solo chest unchanged")
	local pr = R.partyReward(cfg, R.reward(cfg, 12, {quantity = 40}, rng(5)), 5, rng(1))
	eq(pr.gold, math.floor(base.gold * full.reward), "party gold")
	ok(pr.rolls >= math.floor(base.rolls * full.reward), "party item rolls")
	local sc, sp, n = 0, 0, 3000
	local r1, r2 = rng(21), rng(22)
	for _ = 1, n do
		sc = sc + R.reward(cfg, 15, {quantity = 100}, r1).chaos
		sp = sp + R.partyReward(cfg, R.reward(cfg, 15, {quantity = 100}, r2), 5, r2).chaos
	end
	ok(math.abs(sp / sc - full.reward) < 0.06, "party orbs x the bonus: " .. sp / sc)
	eq(R.partyCount(cfg, 20, 1, rng(1)), 20, "solo fragments unchanged")
	eq(R.partyCount(cfg, 20, 5, rng(1)), math.floor(20 * full.reward), "party fragments")
	eq(R.partyCount(cfg, 0, 5, rng(1)), 0, "no fragments stay none")
	-- coffer: one for the party, x the loot bonus
	local c1 = R.cofferLoot(cfg, 10, {quantity = 0}, rng(2), 1)
	local c5 = R.cofferLoot(cfg, 10, {quantity = 0}, rng(2), 5)
	eq(c1.gold, R.cofferLoot(cfg, 10, {quantity = 0}, rng(2)).gold, "coffer: no players = solo")
	eq(c5.gold, math.floor(c1.gold * full.loot), "coffer gold x the loot bonus")
	-- the chat line
	eq(R.partyNote(solo), nil, "no note solo")
	local note = R.partyNote(R.party(cfg, 3), 3)
	ok(note and note:find("Party of 3", 1, true) and note:find("x3", 1, true) and note:find("+20%", 1, true), "party note: " .. tostring(note))
end

-- ------------------------------------------------------------------ the income model (server/README.md "Rifts", Income)
-- hunting at level 1000 ("Respec" table and the audit): 9.5M gold, 2.5 Orbs of Upheaval, 1.3 Orbs of Fate an hour.
-- Rifting: four tier 15 chests an hour at +128% quantity (the highest sum with tier V modifiers).
do
	local hunt = {gold = 9519711, chaos = 2.5, divine = 1.3}
	local function hour(players, own, run)
		local g, c, d, n = 0, 0, 0, 4000
		local rand = rng(77)
		for _ = 1, n do
			local r = R.reward(cfg, 15, {quantity = 128}, rand)
			R.atlasReward(cfg, r, own, run, rand)
			R.partyReward(cfg, r, players, rand)
			g, c, d = g + r.gold, c + r.chaos, d + r.divine
		end
		return {gold = 4 * g / n, chaos = 4 * c / n, divine = 4 * d / n}
	end
	local solo, party = hour(1), hour(5)
	ok(solo.gold >= 1.5 * hunt.gold and solo.gold <= 2 * hunt.gold, string.format("solo gold %.1fM: 1.5-2x hunting", solo.gold / 1e6))
	ok(solo.chaos >= 5 * hunt.chaos and solo.chaos <= 15 * hunt.chaos, string.format("solo Upheaval %.1f: at most 15x hunting", solo.chaos))
	ok(solo.divine >= 5 * hunt.divine and solo.divine <= 15 * hunt.divine, string.format("solo Fate %.1f: at most 15x hunting", solo.divine))
	ok(party.chaos <= 15 * hunt.chaos and party.divine <= 15 * hunt.divine, "a full party's orbs per head: at most 15x hunting")
	local ratio = party.gold / solo.gold
	ok(ratio >= 1.3 and ratio <= 1.6, string.format("a full party per head: x%.2f solo", ratio))
	-- density: a typical player now clears tier 15 in the model's time (R.clearSeconds) instead of far past the limit;
	-- with 3 minutes around each run (open, chest, town) that is at most ~5.5 runs an hour, and the orbs of those
	-- chests stay inside the same bound (the kill loot per run is kept by the husks, see "density" above)
	local perHour = 3600 / (R.clearSeconds(cfg, 15, 1, 1) + 180)
	ok(perHour >= 4 and perHour <= 5.6, string.format("tier 15: %.1f runs an hour for a typical player", perHour))
	ok(solo.chaos / 4 * perHour <= 15 * hunt.chaos and solo.divine / 4 * perHour <= 15 * hunt.divine,
		string.format("orbs at that pace: %.1f Upheaval, %.1f Fate an hour", solo.chaos / 4 * perHour, solo.divine / 4 * perHour))
	-- the atlas multipliers raise gold, never the orbs
	local maxed = hour(1, {goldMult = 25}, {rewardMult = 60})
	ok(math.abs(maxed.gold / solo.gold - 1.25 * 1.6) < 0.01, "goldMult and Lone Ember on the gold")
	ok(math.abs(maxed.chaos / solo.chaos - 1) < 0.05 and math.abs(maxed.divine / solo.divine - 1) < 0.06,
		"goldMult and Lone Ember leave the orbs alone")
	-- the Omen guardian: gold by the finisher's level (at least the arena's level)
	local o = cfg.omen
	eq(R.omenReward(cfg, 1000).gold, o.reward.goldPerLevel * 1000, "Omen gold at level 1000")
	eq(R.omenReward(cfg, 1200).gold, o.reward.goldPerLevel * 1200, "Omen gold grows with the level")
	eq(R.omenReward(cfg, 10).gold, o.reward.goldPerLevel * o.minLevel, "Omen gold: at least the arena's level")
	eq(R.omenReward(cfg).gold, o.reward.goldPerLevel * o.minLevel, "Omen gold without a level")
	ok(R.omenReward(cfg, 1000).gold < hunt.gold / 2, "an Omen kill pays less gold than half an hour of hunting")
	ok(R.omenReward(cfg, 1000).chaos <= 6 and R.omenReward(cfg, 1000).divine <= 3, "Omen orbs cut to a third")
end

-- ------------------------------------------------------------------ density (cfg.density, server/README.md "Rifts", Density)
do
	local near = function(a, b, tol) return math.abs(a - b) <= tol end
	eq(R.density(legacy, 10, 1), nil, "density off: no density")
	ok(R.densityOn(cfg), "density on")
	-- the curve: solo 80 + 8 per tier (rounded to packs), a party of 5 twice that
	local last = 0
	for t = 1, cfg.maxTier do
		local d1, d5 = R.density(cfg, t, 1), R.density(cfg, t, 5)
		ok(d1.count > last, "more monsters every tier " .. t)
		last = d1.count
		ok(near(d1.count, R.densityCount(cfg, t, 1), 4), "solo count near the curve, tier " .. t .. ": " .. d1.count)
		ok(near(d5.count / d1.count, 2, 0.15), "party of 5: twice the monsters, tier " .. t)
		ok(d1.count >= 3 * d1.legacy, "at least three times the packs of before, tier " .. t)
		ok(d1.share > 0 and d1.share <= 1 and d1.normalShare > 0 and d1.normalShare <= 1, "shares in (0, 1], tier " .. t)
		-- the spoils of a run stay: elites per run and laden normal monsters per run as before
		local eliteNow = d1.count * R.eliteShare(cfg, t, d1.share)
		local eliteThen = d1.legacy * R.eliteShare(cfg, t, 1)
		ok(near(eliteNow, eliteThen, 1e-6), "elites per run as before, tier " .. t)
		local ladenNow = d1.count * (1 - R.eliteShare(cfg, t, d1.share)) * d1.normalShare
		ok(near(ladenNow, eliteThen / R.eliteShare(cfg, t, 1) * (1 - R.eliteShare(cfg, t, 1)), 1e-6),
			"laden normal monsters per run as before, tier " .. t)
		-- the budget on the big layouts: fighting as before (about 4.7 minutes for tiers 1-10) plus the walk of a typical
		-- layout of the tier's band, so tiers 1-10 take about 6 minutes, 11-15 up to about 9.5; a party of 5 (4.98x the
		-- damage, the Ascended model) about the same time
		local solo, party = R.clearSeconds(cfg, t, 1, 1), R.clearSeconds(cfg, t, 5, 4.98)
		local limit = R.timeLimit(cfg, t)
		if t <= 10 then
			ok(solo >= 300 and solo <= 400, string.format("tier %d solo clear %.0f s: about 6 minutes", t, solo))
		else
			ok(solo > R.clearSeconds(cfg, t - 1, 1, 1) and solo <= 600, string.format("tier %d solo clear %.0f s: under 10 minutes", t, solo))
		end
		ok(math.abs(party / solo - 1) < 0.1, string.format("tier %d party of 5 %.0f s within 10%% of solo", t, party))
		ok(solo < limit * 0.7, string.format("inside the band's limit with room, tier %d: %.0f of %d s", t, solo, limit))
		ok(R.walkSeconds(cfg, t) > 40 and R.walkSeconds(cfg, t) < 120, "walking 40-120 s, tier " .. t)
		-- a half-strength player still clears tiers 1-12 inside the limit
		if t <= 12 then
			ok(R.clearSeconds(cfg, t, 1, 0.5) <= limit, string.format("a weaker player still makes tier %d (%.0f s)", t,
				R.clearSeconds(cfg, t, 1, 0.5)))
		end
	end
	-- the health of a pack monster grows with the tier up to 10; the guardian's base too
	for t = 2, 10 do
		ok(R.packHealth(cfg, t) > R.packHealth(cfg, t - 1), "pack health grows, tier " .. t)
		ok(R.guardianBase(cfg, t) > R.guardianBase(cfg, t - 1), "guardian grows, tier " .. t)
	end
	-- live cap: 60 (+10 per extra player) + 0.5 per 100 walkable tiles; the worst case of all 16 slots (server/README.md
	-- "Instance limits", Load: the monsters away from every player are idle)
	eq(R.liveCap(cfg, 1, 0), 60, "60 alive solo without area")
	eq(R.liveCap(cfg, 5, 0), 100, "100 for 5 without area")
	eq(R.liveCap(cfg, 1, 20000), 160, "a layout of 20,000 walkable tiles: 160 solo")
	eq(R.liveCap(cfg, 1), 60 + math.floor(cfg.density.live.per100 * cfg.layout.typical[1].walkable / 100),
		"no area: the typical layout of tier 1's band")
	eq(R.liveCap(cfg, 5, 60000), cfg.density.live.max, "capped")
	ok(R.slotCount(cfg) * (cfg.density.live.max + cfg.density.extraSlack) <= 4500, "every slot full: at most 4,500 monsters")
	-- the plan grows with the layout's area: (walkable / ref) ^ exp
	eq(R.areaMult(cfg, cfg.density.area.ref), 1, "the old open floor: x1")
	ok(math.abs(R.areaMult(cfg, 20000) - (20000 / cfg.density.area.ref) ^ cfg.density.area.exp) < 1e-9, "x (area / ref) ^ exp")
	eq(R.areaMult(cfg, 1e9), cfg.density.area.maxMult, "at most maxMult")
	ok(R.densityCount(cfg, 10, 1, 20000) > R.densityCount(cfg, 10, 1, 8000), "a bigger layout plans more monsters")
	ok(R.packHealth(cfg, 10, 20000) < R.packHealth(cfg, 10, 8000), "and each one is weaker (the same health budget)")
	local typ15 = R.density(cfg, 15, 1)
	ok(typ15.count >= 350 and typ15.count <= 450, "tier 15 solo on a typical big layout: 350-450 monsters (" .. typ15.count .. ")")
	ok(R.density(cfg, 1, 1).count >= 120 and R.density(cfg, 1, 1).count <= 150, "tier 1 solo: 120-150 monsters")
	-- walking speed (engine patch 0018 table: 3.70 tiles/s at level 100, 5.88 at 300, 7.69 at 1000)
	ok(math.abs(R.tilesPerSecond(100) - 1000 / 270) < 1e-9, "level 100: 270 ms a step")
	ok(math.abs(R.tilesPerSecond(300) - 1000 / 170) < 1e-9, "level 300: 170 ms")
	ok(math.abs(R.tilesPerSecond(1000) - 1000 / 130) < 1e-9, "level 1000: 130 ms")
	-- the time limit of the band and a run's limit
	eq(R.timeLimit(cfg, 1), cfg.layout.sizes[1][3], "tier 1: band 1's limit")
	eq(R.timeLimit(cfg, 15), cfg.layout.sizes[3][3], "tier 15: band 3's limit")
	eq(R.newRun(cfg, 1000, 10, 8, {}, 900).limit, 900, "a run takes its base limit")
	eq(R.newRun(cfg, 1000, 10, 8, {timeMult = 0.8}, 900).limit, 720, "Waning Veil on the band's limit")
	eq(R.packDamage(cfg), cfg.density.damage, "pack damage")
	eq(R.packDamage(legacy), 1, "pack damage off")
	eq(R.effects(cfg, {}, 4).packDamage, cfg.density.damage, "effects carry the pack damage")
	-- the plan: packs, laden flags, elites always laden, Warbands, Single Brood
	local types = {{name = "A", level = 300}, {name = "B", level = 320}, {name = "C", level = 350}}
	local r = rng(41)
	local runs, normals, laden, elites, rares = 400, 0, 0, 0, 0
	local d = R.density(cfg, 6, 1, R.effects(cfg, {}, 6))
	for _ = 1, runs do
		local plan = R.plan(cfg, 6, R.effects(cfg, {}, 6), 1, types, {"east", "west"}, r)
		eq(#plan.packs, d.packs, "packs of the density")
		for _, p in ipairs(plan.packs) do
			ok(p.count >= cfg.density.size[1] and p.count <= cfg.density.size[2], "density pack size")
			for k = 1, p.count do
				if p.elites[k] then
					elites = elites + 1
					ok(p.laden[k] == true, "an elite always carries loot")
				else
					normals = normals + 1
					laden = laden + (p.laden[k] and 1 or 0)
				end
			end
		end
	end
	ok(near(laden / runs, d.legacy * (1 - R.eliteShare(cfg, 6, 1)), 1.0), "laden normals per run ~ before: " .. laden / runs)
	ok(near(elites / runs, d.legacy * R.eliteShare(cfg, 6, 1), 0.5), "elites per run ~ before: " .. elites / runs)
	local fxw = R.effects(cfg, {{key = "warband", value = 30}}, 4)
	local dw = R.density(cfg, 4, 1, fxw)
	local wbMonsters = 0
	for _ = 1, runs do
		for _, p in ipairs(R.plan(cfg, 4, fxw, 1, types, {"east"}, r).packs) do
			if p.warband then
				wbMonsters = wbMonsters + p.count
				for k = 1, p.count do
					ok(p.laden[k], "warband members carry loot")
				end
			end
		end
	end
	ok(near(wbMonsters / runs, 0.30 * dw.legacy, 1.5), "warband monsters per run ~ before: " .. wbMonsters / runs .. " vs " .. 0.3 * dw.legacy)
	local brood = R.plan(cfg, 6, R.effects(cfg, {{key = "brood", value = 1}}, 6), 1, types, {"east"}, r)
	for _, p in ipairs(brood.packs) do
		eq(p.name, "C", "single brood: the strongest kind")
	end
	-- Teeming and Swarm grow the density plan too
	local dt = R.density(cfg, 6, 1, R.effects(cfg, {{key = "teeming", value = 50}, {key = "swarm", value = 2}}, 6))
	ok(dt.count > d.count * 1.6, "teeming + swarm: more monsters")
	ok(dt.legacy > d.legacy, "and the share follows the packs of before")
	-- reinforcements: the farthest open room at least minDistance from every player
	local centres = {hub = {x = 0, y = -5}, east = {x = 22, y = 0}, west = {x = -22, y = 0}}
	eq(R.reinforceRoom(centres, {{x = 18, y = 0}}, 9), "west", "away from the player")
	eq(R.reinforceRoom(centres, {{x = 0, y = 0}}, 30), nil, "every room too close")
	eq(R.reinforceRoom(centres, {}, 9), "east", "no players: any (by name)")
	-- the big layouts spread the live cap: about 1 monster a 100 walkable tiles solo, the plan 1.5-2
	for b, typ in ipairs(cfg.layout.typical) do
		local tier = cfg.layout.sizes[b][1]
		local live = R.liveCap(cfg, 1, typ.walkable) / typ.walkable * 100
		ok(live >= 0.7 and live <= 1.3, string.format("band %d: %.2f alive a 100 tiles solo", b, live))
		local plan = R.density(cfg, tier, 1, nil, typ.walkable).count / typ.walkable * 100
		ok(plan >= 1.5 and plan <= 2.4, string.format("band %d: %.2f planned a 100 tiles solo", b, plan))
	end
end

-- ------------------------------------------------------------------ third set of modifiers
do
	local new = {"emberbrand", "frostbrand", "stormbrand", "keen", "ironhide", "festering", "spiteglass", "brood", "wrath",
		"breach", "searing", "flaying", "sapping", "parched", "scorched", "rimefloor", "veilstorm"}
	local first = select(2, R.modDef(cfg, "emberbrand"))
	eq(first, 20, "the third set comes after fragile")
	-- reward per point consistent with the old ones: the top of tier III (or the fixed bonus) sums to 15-50%
	local function sumAt(def)
		local v = def.tiers and select(2, R.tierBounds(def, 3)) or def.range[2]
		local b = R.bonuses({mods = cfg.mods, tiers = cfg.tiers, beyond = cfg.beyond, maxTier = cfg.maxTier}, {{key = def.key, value = v}})
		return b.quantity + b.rarity + b.experience
	end
	for i, k in ipairs(new) do
		local d, idx = R.modDef(cfg, k)
		ok(d ~= nil, "new modifier " .. k)
		eq(idx, first + i - 1, "appended in order: " .. k)
		ok(d.side == "prefix" or d.side == "suffix", "a side: " .. k)
		ok(d.weight and d.weight > 0, "a weight: " .. k)
		ok(d.reward ~= nil and not d.boon, "a reward bonus: " .. k)
		local s = sumAt(d)
		ok(s >= 15 and s <= 50, string.format("reward of %s at tier III: %d%%", k, s))
		ok(not R.modText(cfg, {key = k, value = d.range[2]}):find("%%d"), "text formatted " .. k)
		local u = R.unpackMod(cfg, R.packMod(cfg, {key = k, value = d.range[2]}))
		eq(u.key .. u.value, k .. d.range[2], "pack / unpack " .. k)
	end
	for _, d in ipairs(cfg.mods) do
		ok(d.boon or d.side == "prefix" or d.side == "suffix", "every modifier has a side or is a boon: " .. d.key)
	end
	-- groups and exclusions: never two of a group, never an excluded pair, from drops, orbs or a key's text
	local function conflictFree(mods, what)
		for a = 1, #mods do
			for b = a + 1, #mods do
				ok(not R.modConflict(R.modDef(cfg, mods[a].key), R.modDef(cfg, mods[b].key)), what .. ": " .. mods[a].key .. " + " .. mods[b].key)
			end
		end
	end
	ok(R.modConflict(R.modDef(cfg, "withering"), R.modDef(cfg, "parched")), "no two 'no regeneration'")
	ok(R.modConflict(R.modDef(cfg, "reflection"), R.modDef(cfg, "spiteglass")), "no two reflections")
	ok(R.modConflict(R.modDef(cfg, "searing"), R.modDef(cfg, "sapping")), "one hex")
	ok(R.modConflict(R.modDef(cfg, "scorched"), R.modDef(cfg, "rimefloor")), "one ground")
	ok(R.modConflict(R.modDef(cfg, "emberbrand"), R.modDef(cfg, "stormbrand")), "one brand")
	ok(R.modConflict(R.modDef(cfg, "twin"), R.modDef(cfg, "wrath")), "wrath excludes twin (both ways)")
	ok(not R.modConflict(R.modDef(cfg, "vitality"), R.modDef(cfg, "brutality")), "old pairs still meet")
	local r = rng(55)
	local pairsSeen = 0
	for _ = 1, 20000 do
		local key = R.rollKey(cfg, 15, r, true)
		conflictFree(key.mods, "drop")
		if #key.mods == 3 then
			pairsSeen = pairsSeen + 1
		end
	end
	ok(pairsSeen > 4000, "three-modifier keys still common")
	for _ = 1, 3000 do
		local key = {tier = 15, mods = {{key = "withering", value = 1}}}
		R.addMods(cfg, key, 2, r)
		conflictFree(key.mods, "orb")
		for _, m in ipairs(key.mods) do
			ok(m.key ~= "parched", "an orb never adds parched next to withering")
		end
	end
	local dec = R.decodeMods(cfg, "reflection:10,spiteglass:10,searing:20")
	eq(#dec, 2, "decode drops the second of a group")
	eq(dec[1].key .. dec[2].key, "reflectionsearing", "the first one stays")
	-- tier gating of the new ones: tier 1 rolls only keen
	for _ = 1, 3000 do
		for _, m in ipairs(R.rollKey(cfg, 1, r).mods) do
			local d = R.modDef(cfg, m.key)
			ok((d.minTier or 1) <= 1, "tier 1: " .. m.key)
		end
	end

	-- effects
	local fx = R.effects(cfg, {{key = "frostbrand", value = 30}, {key = "keen", value = 20}, {key = "ironhide", value = 25},
		{key = "festering", value = 40}, {key = "spiteglass", value = 10}, {key = "brood", value = 1}, {key = "wrath", value = 20},
		{key = "breach", value = 15}, {key = "flaying", value = 20}, {key = "parched", value = 1}, {key = "rimefloor", value = 3},
		{key = "veilstorm", value = 15}}, 8)
	eq(fx.brand.element, "ice", "frostbrand: ice")
	ok(math.abs(fx.brand.share - 0.3) < 1e-9 and math.abs(fx.crit - 0.2) < 1e-9 and math.abs(fx.physResist - 0.25) < 1e-9,
		"brand, crit, ironhide")
	ok(fx.fester == 40 and math.abs(fx.spite - 0.1) < 1e-9 and fx.brood and math.abs(fx.wrath - 0.2) < 1e-9 and fx.breach == 15,
		"fester, spite, brood, wrath, breach")
	ok(math.abs(fx.hexPhys - 0.2) < 1e-9 and fx.noMana and not fx.noRegen, "flaying, parched")
	ok(fx.ground.kind == "rimefloor" and fx.ground.element == "ice" and fx.ground.percent == 3, "rimefloor")
	ok(math.abs(fx.storm - 0.15) < 1e-9, "veilstorm")
	local none = R.effects(cfg, {}, 8)
	ok(not none.brand and none.crit == 0 and none.fester == 0 and none.sap == 0 and not none.ground and none.storm == 0,
		"neutral third set")

	-- a monster's hit
	local T = {physical = 1, none = 0, brand = {fire = 2, ice = 3, energy = 4}}
	local never = function(a, b) return b end -- chance() never fires (rand returns the top)
	local always = function(a, b) return a end
	local plain = R.effects(legacy, {}, 4)
	local p, pt, s, st = R.monsterHit(legacy, plain, {primary = -100, ptype = 1, secondary = 0, stype = 0}, T, never)
	eq(p .. "/" .. pt .. "/" .. s .. "/" .. st, "-100/1/0/0", "no modifiers: unchanged")
	local dens = R.effects(cfg, {}, 4)
	p = R.monsterHit(cfg, dens, {primary = -100, ptype = 1, secondary = 0, stype = 0}, T, never)
	eq(p, math.floor(-100 * cfg.density.damage), "density: pack monsters hit softer")
	p = R.monsterHit(cfg, dens, {primary = -100, ptype = 1, secondary = 0, stype = 0, boss = true}, T, never)
	eq(p, -100, "the guardian keeps its damage")
	local fb = R.effects(legacy, {{key = "emberbrand", value = 50}, {key = "searing", value = 20}}, 4)
	p, pt, s, st = R.monsterHit(legacy, fb, {primary = -100, ptype = 1, secondary = 0, stype = 0}, T, never)
	eq(p, -100, "brand: the physical part stays")
	eq(st, 2, "brand: fire in the free slot")
	eq(s, math.floor(-50 * 1.2), "brand 50% of the hit, then +20% elemental (searing)")
	p, pt, s, st = R.monsterHit(legacy, fb, {primary = -100, ptype = 3, secondary = -40, stype = 4}, T, never)
	eq(p, math.floor((-100 - 70) * 1.2), "no free slot: the brand joins the primary, then the hex")
	local crit = R.effects(legacy, {{key = "keen", value = 30}, {key = "flaying", value = 10}}, 4)
	local info
	p, pt, s, st, info = R.monsterHit(legacy, crit, {primary = -100, ptype = 1, secondary = 0, stype = 0}, T, always)
	eq(p, math.floor(math.floor(-100 * cfg.keen.critMult) * 1.1), "crit x1.5, then flaying +10%")
	ok(info.crit, "crit flagged")
	_, _, _, _, info = R.monsterHit(legacy, crit, {primary = -100, ptype = 1, secondary = 0, stype = 0}, T, never)
	ok(not info.crit, "no crit")
	local fest = R.effects(legacy, {{key = "festering", value = 50}}, 4)
	_, _, _, _, info = R.monsterHit(legacy, fest, {primary = -200, ptype = 1, secondary = 0, stype = 0}, T, always)
	eq(info.fester, 80, "festering: 40% of the hit")
	-- a player's hit on a rift monster
	local tk = R.effects(legacy, {{key = "ironhide", value = 40}, {key = "warding", value = 20}, {key = "sapping", value = 25}}, 4)
	local a, b, el = R.monsterTaken(tk, {primary = -1000, ptype = 1, secondary = -500, stype = 2, fromPlayer = true}, T)
	eq(a, math.floor(math.floor(-1000 * 0.6) * 0.75), "ironhide, then sapping")
	eq(b, math.floor(math.floor(-500 * 0.8) * 0.75), "warding, then sapping")
	eq(el, math.abs(b), "the elemental part for spiteglass")
	a = R.monsterTaken(tk, {primary = -1000, ptype = 1, secondary = 0, stype = 0, fromPlayer = false}, T)
	eq(a, -600, "sapping only on players' hits")
	-- hazards
	eq(R.percentHit(15000, 0.03), 450, "3% of 15,000")
	eq(R.percentHit(0, 0.03), 1, "at least 1")
	eq(#R.plus({x = 5, y = 5, z = 7}), 5, "a plus of five")
	local t = R.nearTile({x = 10, y = 10, z = 7}, 2, rng(3))
	ok(math.abs(t.x - 10) <= 2 and math.abs(t.y - 10) <= 2 and t.z == 7, "near tile")
end

print(string.format("rift tests: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
