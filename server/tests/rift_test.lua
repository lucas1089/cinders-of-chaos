-- Run from the server/ folder: luajit tests/rift_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Pure rift logic (rift_core.lua + rift_config.lua): modifier rolling, key format, reward scaling, key drop odds,
-- slot allocation and layout, the run timer / fail / boss bookkeeping and the experience cap.
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
	for _, def in ipairs(cfg.mods) do
		ok((seenMods[def.key] or 0) > 200, "every modifier rolls: " .. def.key)
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
	eq(swarm and swarm.value, 3, "decode clamps down to the range")
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

print(string.format("rift tests: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
