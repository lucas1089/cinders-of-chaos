-- Run from the server/ folder: luajit tests/rift_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Pure rift logic (rift_core.lua + rift_config.lua): modifier rolling and tiers, key format, reward scaling, key drop odds,
-- slot allocation and layout, the run timer / fail / boss bookkeeping, lives, omens and the experience cap.
local cfg = dofile("data/scripts/chaos/rift_config.lua")
dofile("data/scripts/chaos/rift_core.lua")
local R = ChaosRiftCore

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
	for _, def in ipairs(cfg.mods) do
		if (def.minTier or 1) <= 4 then
			ok((seenMods[def.key] or 0) > 2.5 * R.modWeight(def), "every modifier rolls: " .. def.key .. " " .. tostring(seenMods[def.key]))
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
	local plan = R.plan(cfg, 4, fx, 2, types, {"east", "north"}, rand)
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
	local r4 = R.reward(cfg, 4, {quantity = 0, rarity = 0}, rand)
	eq(r4.gold, 160000, "tier 4 gold")
	eq(r4.lootTier, "rare", "tier 4 loot tier")
	local r4q = R.reward(cfg, 4, {quantity = 50, rarity = 40}, rand)
	eq(r4q.gold, 240000, "quantity bonus scales gold")
	ok(math.abs(r4q.rarityMult - 1.4) < 1e-9, "rarity bonus multiplier")
	eq(R.reward(cfg, 10, {quantity = 0}, rand).gold, 1000000, "tier 10 gold")
	eq(R.reward(cfg, 12, {quantity = 0}, rand).gold, math.floor(10000 * 144 * 1.2), "tier 12 gold with the beyond bonus")
	eq(R.lootTier(cfg, 2), "magic", "tier 2 loot tier")
	eq(R.lootTier(cfg, 10), "legendary", "tier 10 loot tier")
	eq(R.lootTier(cfg, 11), "boss", "tier 11 loot tier")
	-- expected orbs: (1 + 0.5 t) chaos, 0.25 t divine, x quantity
	local n, chaos, divine, rolls = 4000, 0, 0, 0
	for _ = 1, n do
		local r = R.reward(cfg, 6, {quantity = 20}, rand)
		chaos, divine, rolls = chaos + r.chaos, divine + r.divine, rolls + r.rolls
	end
	ok(math.abs(chaos / n - 4 * 1.2) < 0.08, "mean Chaos Orbs tier 6: " .. chaos / n)
	ok(math.abs(divine / n - 1.5 * 1.2) < 0.06, "mean Divine Orbs tier 6: " .. divine / n)
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
	eq(R.slotOfPos(cfg, {x = 8191, y = 8200, z = 7}), nil, "west of the grid")
	eq(R.slotOfPos(cfg, {x = 8200, y = 8200, z = 6}), nil, "other floor")
	eq(R.slotOfPos(cfg, {x = 8192 + 64 * 4, y = 8200, z = 7}), nil, "east of the grid")
	for _, s in ipairs({0, 5, 15}) do
		local L = R.layout(cfg, s)
		for _, list in ipairs({L.floorList, L.wallList}) do
			for _, p in ipairs(list) do
				if R.slotOfPos(cfg, p) ~= s then
					ok(false, "layout tile outside its slot " .. s)
					break
				end
			end
		end
		for k in pairs(L.walls) do
			ok(not L.floor[k], "wall and floor never overlap")
		end
		ok(L.floor[L.start.x .. "," .. L.start.y] ~= nil, "start on the floor")
		ok(L.floor[L.bossSpawn.x .. "," .. L.bossSpawn.y] ~= nil, "boss spawn on the floor")
		-- everything is reachable from the start
		local reach, queue = {[L.start.x .. "," .. L.start.y] = true}, {L.start}
		while #queue > 0 do
			local p = table.remove(queue)
			for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
				local k = (p.x + d[1]) .. "," .. (p.y + d[2])
				if L.floor[k] and not reach[k] then
					reach[k] = true
					queue[#queue + 1] = L.floor[k]
				end
			end
		end
		local n = 0
		for _ in pairs(reach) do
			n = n + 1
		end
		eq(n, #L.floorList, "all floor connected, slot " .. s)
		for _, d in ipairs(R.DIRS) do
			eq(#L.doors[d.name], 3, "doorway width " .. d.name)
			for _, p in ipairs(L.doors[d.name]) do
				ok(L.floor[p.x .. "," .. p.y] ~= nil, "doorway is floor")
			end
			local rc = L.rooms[d.name].rect
			eq(rc.x2 - rc.x1 + 1, 2 * cfg.room.sideHalf - 1, "side room width")
		end
		eq(L.hub.x2 - L.hub.x1 + 1, 2 * cfg.room.hubHalf - 1, "hub width")
	end
	local rand = rng(1)
	for _ = 1, 200 do
		local open = R.pickRooms(cfg, rand)
		ok(#open >= 2 and #open <= 4, "2-4 rooms open")
		local s = {}
		for _, n in ipairs(open) do
			ok(not s[n], "rooms unique")
			s[n] = true
		end
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
	local base = R.plan(cfg, 4, none, 1, types, {"east"}, rng(8))
	local more = R.plan(cfg, 4, R.effects(cfg, {{key = "teeming", value = 50}}, 4), 1, types, {"east"}, rng(8))
	eq(#more.packs, math.floor(#base.packs * 1.5 + 0.5), "teeming: +50% packs")
	eq(base.gildedAt, nil, "no goblin without the modifier")
	eq(base.coffer, nil, "no coffer without the modifier")
	eq(base.guardians, 1, "one guardian")
	local wb, packs = 0, 0
	local r = rng(9)
	local fxw = R.effects(cfg, {{key = "warband", value = 30}}, 4)
	for _ = 1, 300 do
		for _, p in ipairs(R.plan(cfg, 4, fxw, 1, types, {"east"}, r).packs) do
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
	eq(cl.gold, math.floor(4000 * 25 * 1.2), "coffer gold tier 5 +20%")
	ok(cl.rolls >= 1 and cl.chaos >= 2, "coffer rolls / chaos")
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
	eq(idx, #cfg.mods, "fragile is the last modifier")
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
			ok(look and look <= 2038, "guardian look in the client pair")
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

print(string.format("rift tests: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
