-- Run from the server/ folder: luajit tests/boss_mechanics_test.lua (or lua5.3; CI runs both)
-- Boss mechanics: boss_mechanics_core.lua (shapes, timing, fairness, the state machine, debuffs, soak, line of sight,
-- balance) with every profile of boss_mechanics_config.lua, a grid simulation of the fairness rules (a dodging bot
-- that walks by the player step rules of data/lib/chaos_speed.lua reaches a safe tile before every hit, alone and
-- with overlapping telegraphs, for sizes 1 to 4 and every difficulty), and boss_mechanics.lua against a mocked engine
-- (a telegraph hits the player left on it and not the one who walked off, an immune adds phase, a channel stopped by
-- killing its totem, a line-of-sight blast, the cast bar payload).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

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

dofile("data/lib/chaos_speed.lua")
dofile("data/scripts/chaos/boss_mechanics_core.lua")
local G = ChaosBossMechCore
local cfg = dofile("data/scripts/chaos/boss_mechanics_config.lua")

-- a seeded generator (the same in LuaJIT and 5.3)
local function rng(seed)
	local s = seed % 2147483646 + 1
	return function(a, b)
		s = (s * 16807) % 2147483647 -- exact in doubles (LuaJIT) and integers (5.3)
		return a + s % (b - a + 1)
	end
end

-- ================================================================== the config
local known = {}
for _, k in ipairs(G.SHAPES) do
	known[k] = true
end
local profiles = 0
for name, p in pairs(cfg.profiles) do
	profiles = profiles + 1
	check(p.label ~= nil, name .. ": label")
	check(p.size == 1 or p.size == 2 or p.size == 4, name .. ": size 1, 2 or 4")
	check((p.difficulty or 0) >= 0 and (p.difficulty or 0) <= 1, name .. ": difficulty 0..1")
	local mechs = #(p.telegraphs or {}) + #(p.adds or {}) + #(p.timed or {}) + (p.debuff and 1 or 0) + (p.softEnrage and 1 or 0)
	check(mechs >= 2 or (p.ownTelegraphs and mechs >= 1), name .. ": two mechanics or more (own telegraphs count)")
	for _, t in ipairs(p.telegraphs or {}) do
		check(known[t.kind], name .. ": shape " .. tostring(t.kind))
		check(t.share > 0 and t.share <= 0.6, name .. ": telegraph share in (0, 0.6]: " .. t.key)
		check(t.label and t.tip, name .. ": label and tip: " .. t.key)
	end
	for _, a in ipairs(p.adds or {}) do
		check(a.mode == "immune" or a.mode == "shield" or a.mode == "empower" or a.mode == "heal", name .. ": adds mode")
		check(a.at > 0 and a.at < 1 and a.type and a.name and a.text and a.tip, name .. ": adds fields")
	end
	for _, m in ipairs(p.timed or {}) do
		check(m.kind == "channel" or m.kind == "soak" or m.kind == "los", name .. ": timed kind " .. tostring(m.kind))
		check(m.text and m.tip and m.label, name .. ": timed text: " .. m.key)
		check(m.text:find("%%s") ~= nil, name .. ": the warning names the boss: " .. m.key)
	end
	-- solo content: nothing needs two players
	if p.ref and p.ref.solo then
		for _, m in ipairs(p.timed or {}) do
			if m.kind == "soak" then
				check((m.min or 1) <= 1 or m.groupOnly, name .. ": a solo soak counts one player")
				local each = G.soakShare(m, 1)
				check(each <= 0.6, name .. ": a lone soaker survives (" .. each .. ")")
			elseif m.kind == "channel" then
				local secs = G.totemHealth(m, 1) / p.ref.dps
				check(secs <= 0.6 * (m.channelMs / 1000), name .. ": one player kills the totem in time (" .. secs .. " s)")
			end
		end
		for _, a in ipairs(p.adds or {}) do
			local secs = G.addsHealth(a, 1) * G.addsCount(a, 1) / p.ref.dps
			check(secs <= 45, name .. ": the adds of a solo phase die within 45 s (" .. math.floor(secs) .. ")")
		end
	end
end
check(profiles >= 20, "at least 20 boss profiles (" .. profiles .. ")")
for _, k in ipairs({"kaelgor the infernal warlord", "skaldra the rime queen", "the rotmother", "nyxareth the void archon",
		"vharok the blood colossus", "sangrith the bloodmoon herald", "morvane the hollow crown",
		"thalcyra the stormbound seer", "ascended sangrith", "ascended morvane", "ascended thalcyra",
		"ysgrath the cinderheart", "rift_guardian", "vault keeper ossrim", "gorvath the banner-eater", "ormathulak",
		"talath", "gloomfire", "saga", "legendary warrior"}) do
	check(cfg.profiles[k] ~= nil, "a profile for " .. k)
end
-- the names match the monsters: world bosses, omens, ascended, guild boss
for _, f in ipairs({"world_bosses/kaelgor_the_infernal_warlord", "omens/morvane_the_hollow_crown",
		"ascended/ysgrath_the_cinderheart", "guildboss/gorvath_the_banner_eater", "raid/hex_effigy"}) do
	local h = io.open("data/monster/monsters/chaos/" .. f .. ".xml")
	check(h ~= nil, "monster file " .. f)
	if h then
		local name = h:read("*a"):match('<monster name="([^"]+)"')
		h:close()
		check(name and (cfg.profiles[name:lower()] or name == "Hex Effigy"), "profile key is the monster name: " .. tostring(name))
	end
end

-- ================================================================== timing
eq(G.warnMs(nil, 0), 3000, "difficulty 0: 3 s")
eq(G.warnMs(nil, 1), 1500, "difficulty 1: 1.5 s")
eq(G.warnMs(nil, 0.33), 2500, "difficulty 0.33: 2.5 s")
eq(G.warnMs(nil, 5), 1500, "never under 1.5 s")
eq(G.warnMs({warnMs = 900}, 0), 1500, "a spec's own time is held to 1.5 s")
eq(G.warnMs(nil, 0.9, nil, true), 1500, "enraged: still 1.5 s")
for d = 0, 10 do
	for _, en in ipairs({false, true}) do
		local w = G.warnMs(nil, d / 10, nil, en)
		check(w >= 1500 and w <= 3000, "warning in 1.5-3 s at difficulty " .. d / 10)
	end
end
for name, p in pairs(cfg.profiles) do
	local d = (p.difficulty or 0) + (p.tierDifficulty or 0) * 14
	local w = G.warnMs(nil, d, p.fair)
	check(w >= 2000, name .. ": the default warning is 2 s or more (" .. w .. ")")
	if not p.ownTelegraphs and (p.difficulty or 0) <= 0.33 then
		check(G.warnMs(nil, p.difficulty, p.fair) >= 2500, name .. ": default 2.5-3 s")
	end
end
local pl = G.pulses(2500, 600, 900)
eq(pl[1].at, 0, "pulses start at once")
eq(pl[1].kind, "zone", "the first pulse is the danger mark")
eq(pl[#pl].kind, "fill", "the last pulse fills")
for i = 2, #pl do
	check(pl[i].at > pl[i - 1].at and pl[i].at < 2500, "pulses in order before the hit")
end
check(#pl >= 4, "the mark pulses until the hit (" .. #pl .. ")")

-- ================================================================== shapes
local arena = G.boxGrid({x = 100, y = 100, z = 7}, 9)
local boss = {x = 100, y = 100, z = 7}
local function shape(spec, size, target, players, seed)
	return G.shape(G.scaleShape(spec, size), {grid = arena, boss = boss, size = size, target = target or {x = 100, y = 106},
		players = players or {{x = 103, y = 104}}, rand = rng(seed or 1)})
end
for _, k in ipairs(G.SHAPES) do
	local spec = {kind = k, radius = 2, length = 6, spread = 2, inner = 2, outer = 5, halfWidth = 1, count = 3, safe = 2}
	local t1 = shape(spec, 1)
	local t4 = shape(spec, 4)
	check(#t1 > 0 and #t1 < #arena.list, k .. ": marks some tiles, not all")
	if k ~= "marks" and k ~= "puddles" and k ~= "follow" and k ~= "lines" and k ~= "eye" and k ~= "half" then
		check(#t4 > #t1, k .. ": a 4x4 boss gets a wider shape (" .. #t1 .. " -> " .. #t4 .. ")")
	end
	for _, t in ipairs(t4) do
		check(arena.set[G.key(t.x, t.y)] ~= nil, k .. ": tiles on the grid only")
	end
end
local cone = shape({kind = "cone", length = 5, spread = 2}, 1)
local south = 0
for _, t in ipairs(cone) do
	if t.y > boss.y then
		south = south + 1
	end
end
eq(south, #cone, "the cone points at the target (south)")
local ring = G.tileSet(shape({kind = "ring", inner = 2, outer = 4}, 1))
check(not ring[G.key(100, 101)] and ring[G.key(100, 103)] and not ring[G.key(100, 106)], "the ring has a safe middle and outside")
local line = G.tileSet(shape({kind = "line", halfWidth = 0, length = 20}, 1, {x = 109, y = 101}))
check(line[G.key(109, 100)] and not line[G.key(100, 101)], "the line runs east to the wall")
local fol = shape({kind = "follow", radius = 1}, 1, {x = 95, y = 95})
check(G.tileSet(fol)[G.key(95, 95)], "follow sits on the target")
local pud, pinfo = shape({kind = "puddles", count = 4, onPlayers = 1, radius = 1}, 1, nil, {{x = 103, y = 104}})
check(G.tileSet(pud)[G.key(103, 104)] and #pinfo.centers == 4, "a puddle under the player and three more")
-- a 4x4 body: a circle of radius 1 reaches the tiles next to every side of the footprint
local body = G.tileSet(shape({kind = "circle", radius = 1, fixedSize = true}, 4))
check(body[G.key(96, 100)] and body[G.key(100, 101)] and body[G.key(97, 96)], "a 4x4 boss: shapes measured from its body")

-- a 4x4 boss's melee target stands on its body (north or west of the anchor): the cone and the line aimed at it still
-- reach it (live test 2026-10-14: Sangrith's Red Crescent marked 1 tile and missed the tank)
for _, tp in ipairs({{x = 100, y = 99}, {x = 99, y = 100}, {x = 97, y = 99}, {x = 100, y = 101}, {x = 101, y = 100}}) do
	local c4 = G.tileSet(shape({kind = "cone", length = 5, spread = 2}, 4, tp))
	local l4 = G.tileSet(shape({kind = "line", halfWidth = 1, length = 8}, 4, tp))
	check(c4[G.key(tp.x, tp.y)], "size 4 cone reaches its target at " .. tp.x .. "," .. tp.y)
	check(l4[G.key(tp.x, tp.y)], "size 4 line reaches its target at " .. tp.x .. "," .. tp.y)
	local n = 0
	for _ in pairs(c4) do n = n + 1 end
	check(n >= 10, "size 4 cone at " .. tp.x .. "," .. tp.y .. " is a real cone (" .. n .. " tiles)")
end
do -- a target outside the body: the same tiles as before (direction from the anchor, the whole body)
	local body4 = G.footprint(boss, 4)
	local dx, dy, from = G.aimFrom(body4, boss, {x = 100, y = 106})
	check(dx == 0 and dy == 1 and from == body4, "a target outside the body: anchor direction, whole body")
end

-- the same tiles as uber_core.lua's own shapes for a size 1 boss (uber_test.lua keeps those)
dofile("data/scripts/chaos/uber_core.lua")
local U = ChaosUberCore
local ucfg = dofile("data/scripts/chaos/uber_config.lua")
local L = U.layout(ucfg, 1)
for _, k in ipairs({"cone", "ring", "circle", "marks", "cross", "half", "lines", "eye"}) do
	local ctx = {L = L, boss = {x = L.center.x, y = L.center.y - 2}, target = {x = L.center.x + 3, y = L.center.y},
		players = {{x = L.center.x + 2, y = L.center.y + 3}}, rand = rng(7)}
	local a = U.pattern(k, ucfg, ctx)
	ctx.rand = rng(7)
	local spec = {kind = k}
	for kk, v in pairs(ucfg.patterns[k]) do
		spec[kk] = v
	end
	local b = G.shape(spec, {list = L.floorList, rect = L.rect, z = L.z, boss = ctx.boss, target = ctx.target,
		players = ctx.players, rand = ctx.rand})
	eq(#a, #b, "uber shape " .. k .. " is the core's")
end
check(U.markPlan == G.markPlan, "uber's mark plan is the core's")
local ut = U.telegraphTiming(ucfg, true)
check(ut.hitMs >= 1500, "Ascended enraged warning held to 1.5 s")

-- ================================================================== fairness: the grid simulation
local straight, diag = G.stepCosts({refLevel = 300})
eq(straight, ChaosSpeed.stepDuration(ChaosSpeed.clamp(ChaosSpeed.baseSpeed(220, 300))), "level 300 step from ChaosSpeed")
eq(diag, math.floor(straight * 7 / 5), "a diagonal is 7/5 of a straight step")
local s100 = G.stepCosts({refLevel = 100})
check(s100 > straight, "slower at level 100")

-- walks the cheapest path to the nearest safe tile; true when it arrives before the budget is spent
local function dodges(g, marked, from, budget, st, dg)
	local spot, cost = G.safeSpot(g, marked, from, budget, st, dg)
	return spot ~= nil and cost <= budget
end

-- where the bot stands after walking `ms` of its cheapest path to the nearest safe tile (a tile on that path)
local function walkFor(g, marked, from, budget, st, dg, ms)
	local spot, c1 = G.safeSpot(g, marked, from, budget, st, dg)
	if not spot then
		return from
	end
	local r0 = G.reach(g, from, budget, st, dg)
	local rs = G.reach(g, spot, budget, st, dg)
	local best, bestC = from, 0
	for k, c in pairs(r0) do
		if c <= ms and rs[k] and c + rs[k] == c1 and c > bestC then
			best, bestC = g.set[k], c
		end
	end
	return best
end

-- arenas: an open box, a room with pillars, a rift chamber (a circle), a narrow hall
local function arenas()
	local out = {}
	out[#out + 1] = {name = "box 19", g = G.boxGrid({x = 100, y = 100, z = 7}, 9)}
	local pill = {}
	for _, d in ipairs({{-7, -7}, {7, -7}, {-7, 7}, {7, 7}}) do
		pill[G.key(100 + d[1], 100 + d[2])] = true
	end
	out[#out + 1] = {name = "world boss 31", g = G.without(G.boxGrid({x = 100, y = 100, z = 7}, 15), pill)}
	out[#out + 1] = {name = "rift chamber", g = G.boxGrid({x = 100, y = 100, z = 7}, 9, function(x, y)
		return (x - 100) ^ 2 + (y - 100) ^ 2 <= 81
	end)}
	out[#out + 1] = {name = "hall 9x21", g = G.boxGrid({x = 100, y = 100, z = 7}, 10, function(x, y)
		return math.abs(y - 100) <= 4
	end)}
	return out
end

local sims, trapped, worst = 0, 0, 0
for _, ar in ipairs(arenas()) do
	local g = ar.g
	for pname, p in pairs(cfg.profiles) do
		local fair = {}
		for k, v in pairs(cfg.fair) do
			fair[k] = v
		end
		for k, v in pairs(p.fair or {}) do
			fair[k] = v
		end
		local st, dg = G.stepCosts(fair)
		for _, spec in ipairs(p.telegraphs or {}) do
			for _, size in ipairs({1, p.size}) do
				for seed = 1, 8 do
					local r = rng(seed * 31 + size)
					local fight = G.newFight({telegraphs = {spec}, fair = fair}, {now = 0, difficulty = (seed - 1) / 5, size = size})
					local bt = g.list[r(1, #g.list)]
					local players = {}
					for _ = 1, r(1, 8) do
						players[#players + 1] = g.list[r(1, #g.list)]
					end
					local warn = G.warnMs(spec, fight.difficulty, fair)
					if spec.kind == "follow" then
						warn = warn + (spec.followMs or 1500)
					end
					check(warn >= 1500, pname .. ": warning >= 1.5 s")
					local tel = G.planTelegraph(fight, spec, {grid = g, boss = bt, size = size, target = players[1],
						players = players, rand = r}, 0, warn)
					local lock = spec.kind == "follow" and warn - (spec.followMs or 1500) or warn
					check(lock >= 1500, pname .. ": the last warning (after a follow locks) is 1.5 s or more")
					local budget = G.budget(lock, fair)
					-- a second telegraph while the first is pending (the overlap rule): the bot has walked 300 ms of its
					-- dodge; both together still leave it a safe tile before the first hit
					local moved = {}
					for i, pp in ipairs(players) do
						moved[i] = walkFor(g, tel.set, pp, budget, st, dg, 300)
					end
					local spec2 = p.telegraphs[(seed % #p.telegraphs) + 1]
					local tel2 = G.planTelegraph(fight, spec2, {grid = g, boss = bt, size = size, target = moved[#moved],
						players = moved, rand = r}, 300, warn)
					local union = {}
					for k in pairs(tel.set) do
						union[k] = true
					end
					for k in pairs(tel2.set) do
						union[k] = true
					end
					for i, pp in ipairs(players) do
						sims = sims + 1
						local ok = dodges(g, tel.set, pp, budget, st, dg)
						local ok2 = dodges(g, union, moved[i], G.budget(lock - 300, fair), st, dg)
						if not (ok and ok2) then
							trapped = trapped + 1
							print(string.format("  trapped: %s %s size %d seed %d at %d,%d in %s (alone %s, overlap %s, warn %d)",
								pname, spec.key, size, seed, pp.x, pp.y, ar.name, tostring(ok), tostring(ok2), warn))
						end
						local _, c = G.safeSpot(g, tel.set, pp, budget, st, dg)
						worst = math.max(worst, c or 0)
					end
				end
			end
		end
	end
end
eq(trapped, 0, "the dodging bot always reaches a safe tile before the hit (" .. sims .. " cases)")
check(sims > 2000, "the simulation ran enough cases (" .. sims .. ")")
print(string.format("boss_mechanics_test: grid simulation %d dodges, worst walk %d ms", sims, worst))

-- the slowest content walker (level 300) on the biggest shape: a world boss cone towards a player in a corner
do
	local g = G.boxGrid({x = 100, y = 100, z = 7}, 15)
	local cone = {kind = "circle", radius = 14}
	local fight = G.newFight({telegraphs = {cone}, fair = {refLevel = 300}}, {now = 0, difficulty = 1})
	local tel = G.planTelegraph(fight, cone, {grid = g, boss = {x = 100, y = 100}, players = {{x = 100, y = 100}}, rand = rng(1)}, 0, 1500)
	check(#tel.cut > 0 and #tel.pockets == 1, "a shape with no safe tile in reach gets a pocket cut out")
	local st, dg = G.stepCosts({refLevel = 300})
	check(dodges(g, tel.set, {x = 100, y = 100}, G.budget(1500, {}), st, dg), "and the pocket is reachable")
	-- the pocket is not under the player: it has to move
	check(tel.set[G.key(100, 100)] == nil or G.safeSpot(g, tel.set, {x = 100, y = 100}, 1000, st, dg) ~= nil, "pocket in reach")
end

-- line of sight: from every tile of the world boss arena a hidden tile is in reach of the blast's warning
for pname, p in pairs(cfg.profiles) do
	for _, m in ipairs(p.timed or {}) do
		if m.kind == "los" then
			local g = G.boxGrid({x = 100, y = 100, z = 7}, 9)
			local pillars = G.pillarSpots(g, {x = 100, y = 100}, m.pillars)
			check(#pillars >= 3, pname .. ": three pillars or more")
			local cover = G.tileSet(pillars)
			local walk = G.without(g, cover)
			local blast = G.tileSet(G.blastTiles(walk, {x = 100, y = 100}, cover))
			local fair = {refLevel = p.fair and p.fair.refLevel or 300, reactionMs = 500}
			local st, dg = G.stepCosts(fair)
			local bad = 0
			for _, t in ipairs(walk.list) do
				if not dodges(walk, blast, t, G.budget(m.hideMs, fair), st, dg) then
					bad = bad + 1
				end
			end
			eq(bad, 0, pname .. ": " .. m.key .. ": a hidden tile is in reach from every tile")
			check(G.hidden({x = 100, y = 100}, {x = 100 + 2 * m.pillars[1][1], y = 100 + 2 * m.pillars[1][2]}, cover),
				pname .. ": behind a pillar is hidden")
		end
	end
end

-- ================================================================== the fight machine
local prof = {every = 6000, firstMs = 1000, telegraphs = {{key = "a", kind = "circle", radius = 2, share = 0.3}},
	adds = {{at = 0.5, mode = "immune", count = 2, health = 1000, type = "X", name = "W", text = "%s warded",
		doneText = "%s free"}},
	timed = {{key = "c", kind = "channel", channelMs = 8000, every = 30000, firstMs = 20000, below = 1, text = "%s channels"}},
	softEnrage = {at = 60, perMin = 0.5, maxMult = 2, text = "%s enrages"},
	debuff = {perStack = 0.05, max = 4, decayMs = 5000}}
local st = G.newFight(prof, {now = 0})
local acts = G.update(st, 500, 1.0, 0)
eq(#acts, 0, "nothing before the first telegraph")
acts = G.update(st, 1000, 1.0, 0)
eq(acts[1] and acts[1].kind, "telegraph", "the first telegraph")
check(acts[1].warnMs >= 1500, "its warning")
acts = G.update(st, 2000, 0.49, 0)
eq(acts[1] and acts[1].kind, "adds", "the adds phase at its threshold")
eq(acts[2] and acts[2].kind, "warn", "with its warning")
acts = G.update(st, 2500, 0.3, 2)
eq(#acts, 0, "each adds phase once")
eq(G.damageTakenMult(st, 2), 0, "immune while the adds live")
eq(G.damageTakenMult(st, 0), 1, "hurt again when they die")
acts = G.update(st, 4000, 0.3, 0)
eq(acts[1] and acts[1].text, "%s free", "the done warning")
acts = G.update(st, 20000, 0.3, 0)
local kinds = {}
for _, a in ipairs(acts) do
	kinds[a.kind] = true
end
check(kinds.channel and kinds.warn, "the channel starts on its cadence")
check(not kinds.telegraph, "no telegraph while the boss channels")
acts = G.update(st, 21000, 0.3, 0)
check(#acts == 0, "busy: no telegraph during the channel")
eq(G.damageDealtMult(st, 30000, 0), 1, "no soft enrage yet")
acts = G.update(st, 60000, 0.3, 0)
local se = false
for _, a in ipairs(acts) do
	se = se or a.kind == "softEnrage"
end
check(se, "the soft enrage starts")
check(math.abs(G.damageDealtMult(st, 120000, 0) - 1.5) < 1e-9, "+50% after a minute")
eq(G.damageDealtMult(st, 600000, 0), 2, "at most maxMult")
-- empower, heal, shield
local st2 = G.newFight({adds = {{at = 0.9, mode = "empower", perAdd = 0.2}, {at = 0.5, mode = "heal", perAdd = 0.01},
	{at = 0.2, mode = "shield", reduce = 0.75}}}, {now = 0})
G.update(st2, 0, 0.8, 0)
check(math.abs(G.damageDealtMult(st2, 0, 2) - 1.4) < 1e-9, "empower: +20% per add")
G.update(st2, 2000, 0.4, 2)
eq(G.addsHeal(st2, 3, 100000), 3000, "heal: 1% per add")
G.update(st2, 4000, 0.1, 2)
eq(G.damageTakenMult(st2, 2), 0.25, "shield: 75% less")
-- tiers: the rift guardian's light kit
local rg = cfg.profiles.rift_guardian
local low = G.newFight(rg, {now = 0, tier = 1})
local high = G.newFight(rg, {now = 0, tier = 15})
local seen = {}
for t = 1, 40 do
	for _, a in ipairs(G.update(low, t * 20000, 0.4, 0)) do
		seen[a.spec and a.spec.key or a.kind] = true
	end
end
check(not seen.rift_scatter and not seen.adds, "tier 1: no puddles, no shield phase")
seen = {}
for t = 1, 40 do
	for _, a in ipairs(G.update(high, t * 20000, 0.4, 0)) do
		seen[a.spec and a.spec.key or a.kind] = true
	end
end
check(seen.rift_scatter and seen.adds, "tier 15: puddles and the shield phase")
-- solo: a group-only soak is skipped
local nyx = G.newFight(cfg.profiles["nyxareth the void archon"], {now = 0, solo = true})
for t = 1, 30 do
	for _, a in ipairs(G.update(nyx, t * 10000, 0.5, 0)) do
		check(not (a.kind == "soak"), "a group-only soak never runs solo")
	end
end

-- debuffs
local d = {perStack = 0.05, max = 4, decayMs = 5000}
local e = G.stackAdd(nil, d, 0)
e = G.stackAdd(e, d, 1000)
e = G.stackAdd(e, d, 2000)
eq(e.stacks, 3, "three stacks")
eq(G.stackMult(d, e.stacks), 1.15, "+5% each")
for t = 3, 8 do
	e = G.stackAdd(e, d, t * 1000)
end
eq(e.stacks, 4, "capped at max")
eq(G.stackDecay(e, d, 8000 + 10000), 2, "two fall off in 10 s")
eq(G.stackDecay(e, d, 8000 + 60000), 0, "and all of them later")
-- soak
local each, miss = G.soakShare({total = 1.5, min = 3, missShare = 0.5}, 1)
eq(each, 0.5, "a lone soaker counts as min")
each = G.soakShare({total = 1.5, min = 3}, 5)
eq(each, 0.3, "five split it")
each, miss = G.soakShare({total = 1.5, min = 3, missShare = 0.5}, 0)
check(each == 0 and miss == 0.5, "nobody inside: everyone takes the miss share")

-- ================================================================== balance: the kill times stay
print("boss_mechanics_test: kill times (base -> with the mechanics, health x factor -> final)")
local names = {}
for name in pairs(cfg.profiles) do
	names[#names + 1] = name
end
table.sort(names)
for _, name in ipairs(names) do
	local p = cfg.profiles[name]
	if p.ref then
		local ref = {}
		for k, v in pairs(p.ref) do
			ref[k] = v
		end
		local b = G.balance(p, ref)
		local tol = ref.weakDps and 0.12 or 0.05
		check(b.final <= b.base * 1.05 and b.final >= b.base * (1 - tol), name .. ": the kill time stays (" .. G.clockText(b.base)
			.. " -> " .. G.clockText(b.final) .. ")")
		if ref.weakDps then
			-- the weakest class keeps its old time too (within 5%) and finishes inside the limit
			local w = {}
			for k, v in pairs(ref) do
				w[k] = v
			end
			w.dps, w.weakDps = ref.weakDps, nil
			local before = ref.health / (w.dps * ref.uptime - (ref.heal or 0))
			w.health = ref.health * b.hpMult
			local now = G.balance(setmetatable({compensate = false}, {__index = p}), w).with
			check(now <= before * 1.05, name .. ": the weakest class keeps its time (" .. G.clockText(before) .. " -> "
				.. G.clockText(now) .. ")")
			check(now < ref.limit, name .. ": the weakest class inside the limit (" .. G.clockText(now) .. ")")
			print(string.format("  %-30s weakest (%d): %s -> %s", name, ref.weakDps, G.clockText(before), G.clockText(now)))
		end
		check(b.hpMult >= 0.6 and b.hpMult <= 1, name .. ": health factor 0.6-1")
		if ref.limit then
			check(b.final < ref.limit, name .. ": inside the limit")
		end
		print(string.format("  %-30s %s -> %s, health x%.3f -> %s", name, G.clockText(b.base), G.clockText(b.with), b.hpMult,
			G.clockText(b.final)))
	end
end

-- ================================================================== the engine file against a mocked engine
local T = 0
local events = {}
function addEvent(fn, ms, ...)
	events[#events + 1] = {at = T + (ms or 0), fn = fn, args = {...}}
	return #events
end
local function runTo(t)
	while true do
		table.sort(events, function(a, b) return a.at < b.at end)
		local ev = events[1]
		if not ev or ev.at > t then
			break
		end
		table.remove(events, 1)
		T = ev.at
		local ok, err = pcall(ev.fn, (unpack or table.unpack)(ev.args))
		if not ok then
			check(false, "event error: " .. tostring(err))
		end
	end
	T = t
end
os.mtime = function() return T end

local Pos = {}
Pos.__index = Pos
function Position(x, y, z)
	if type(x) == "table" then
		x, y, z = x.x, x.y, x.z
	end
	return setmetatable({x = x, y = y, z = z}, Pos)
end
local effects = {}
function Pos:sendMagicEffect(id)
	effects[#effects + 1] = {x = self.x, y = self.y, id = id}
end
function Pos:getDistance(o)
	return math.max(math.abs(self.x - o.x), math.abs(self.y - o.y))
end

local creatures, nextId = {}, 1000
local Cr = {}
Cr.__index = Cr
function Cr:getId() return self.id end
function Cr:getName() return self.name end
function Cr:getPosition() return Position(self.pos) end
function Cr:getHealth() return self.hp end
function Cr:getMaxHealth() return self.maxHp end
function Cr:setMaxHealth(v) self.maxHp = v; self.hp = math.min(self.hp, v) end
function Cr:addHealth(v) self.hp = math.max(0, math.min(self.maxHp, self.hp + v)) end
function Cr:isPlayer() return self.player == true end
function Cr:isMonster() return not self.player end
function Cr:getMaster() return nil end
function Cr:getTarget() return self.target and creatures[self.target] end
function Cr:say(text) self.said = text end
function Cr:registerEvent(n) self.ev = self.ev or {}; self.ev[n] = true end
function Cr:unregisterEvent(n) if self.ev then self.ev[n] = nil end end
function Cr:remove() creatures[self.id] = nil end
function Cr:getGuid() return self.id end
function Cr:sendTextMessage(_, text) self.msgs = self.msgs or {}; self.msgs[#self.msgs + 1] = text end
function Cr:sendExtendedOpcode(op, buf) self.ops = self.ops or {}; self.ops[#self.ops + 1] = {op, buf} end
local function make(o)
	nextId = nextId + 1
	o.id = nextId
	o.hp = o.hp or 1000
	o.maxHp = o.maxHp or o.hp
	creatures[o.id] = setmetatable(o, Cr)
	return creatures[o.id]
end
function Monster(id) local c = creatures[type(id) == "table" and id.id or id]; return c and not c.player and c or nil end
function Player(id) local c = creatures[type(id) == "table" and id.id or id]; return c and c.player and c or nil end
function Creature(id) return creatures[id] end
local tileItems = {}
local Tl = {}
Tl.__index = Tl
function Tile(p)
	if math.abs(p.x - 200) > 9 or math.abs(p.y - 200) > 9 then
		return nil
	end
	return setmetatable({p = p}, Tl)
end
function Tl:getGround() return true end
function Tl:hasProperty() return tileItems[self.p.x .. "," .. self.p.y] ~= nil end
function Tl:getTopCreature()
	for _, c in pairs(creatures) do
		if c.pos.x == self.p.x and c.pos.y == self.p.y then
			return c
		end
	end
end
function Tl:getItemById(id)
	local it = tileItems[self.p.x .. "," .. self.p.y]
	if it then
		return {remove = function() tileItems[self.p.x .. "," .. self.p.y] = nil end}
	end
end
Game = {}
function Game.createMonster(name, pos)
	return make({name = name, pos = {x = pos.x, y = pos.y, z = pos.z}, hp = 5000})
end
function Game.createItem(id, cnt, pos)
	tileItems[pos.x .. "," .. pos.y] = id
	return {}
end
function Game.getSpectators(pos, _, onlyPlayers, rx)
	local out = {}
	for _, c in pairs(creatures) do
		if (not onlyPlayers or c.player) and math.abs(c.pos.x - pos.x) <= rx and math.abs(c.pos.y - pos.y) <= rx then
			out[#out + 1] = c
		end
	end
	return out
end
local hits = {}
function doTargetCombat(cid, target, ctype, mn)
	hits[#hits + 1] = {target = target.id, dmg = -mn}
	target.hp = target.hp + mn
end
json = {encode = function(t) return "{" .. tostring(t.action) .. ":" .. tostring(t.data and t.data.label) .. "}" end}
Chaos = {percentBase = function(p) return p.maxHp end}
function Chaos.send(p, op, action, data) p:sendExtendedOpcode(op, json.encode({action = action, data = data})); return true end
Chaos.createMonsterNamed = function(t, p, e, f, shown) local m = Game.createMonster(t, p); m.name = shown or t; return m end
ChaosOpcodes = {monsterbar = 125}
local registered = {}
function CreatureEvent(name)
	local ev = {}
	function ev.register() registered[name] = ev end
	return ev
end
EventCallback = setmetatable({}, {__index = function() return nil end})
function EventCallback.register() end
Vfx, ChaosVfx = nil, nil
ChaosBigFx = {live = function() return false end, telegraph = function() end, bossHit = function() end}
math.randomseed(5)

dofile("data/scripts/chaos/boss_mechanics.lua")
local M = ChaosBossMech
M.fights = {}
check(registered.ChaosBossMechHealth and registered.ChaosBossMechTaken and registered.ChaosBossMechAttach, "events registered")
-- a test profile: one circle, a wardstone phase at 50%, a channel and a blast behind pillars
cfg = ChaosBossMechConfig
cfg.profiles["test boss"] = {label = "Testor", size = 1, element = "fire", difficulty = 0, every = 9000, firstMs = 1000,
	compensate = false,
	telegraphs = {{key = "slam", label = "Slam", kind = "circle", radius = 2, share = 0.4, hit = "x", fallback = 1}},
	adds = {{at = 0.5, mode = "immune", type = "Hex Effigy", name = "Wardstone", count = 2, health = 100,
		text = "%s is warded!", doneText = "free"}},
	timed = {{key = "inferno", label = "Inferno", kind = "channel", channelMs = 8000, every = 60000, firstMs = 15000,
		below = 1, totemType = "Hex Effigy", totemName = "Ember Totem", totemHealth = 100, share = 0.5, text = "%s gathers flame!"},
		{key = "blast", label = "Blast", kind = "los", hideMs = 3000, every = 60000, firstMs = 40000, below = 1, share = 0.6,
			pillars = {{0, 3}}, text = "%s blasts!"}}}
local b = make({name = "Test Boss", pos = {x = 200, y = 200, z = 7}, hp = 100000})
local stay = make({name = "Stayer", player = true, pos = {x = 200, y = 201, z = 7}, hp = 10000})
local walker = make({name = "Walker", player = true, pos = {x = 200, y = 202, z = 7}, hp = 10000})
b.target = stay.id
local f = M.attach(b, nil, {center = {x = 200, y = 200, z = 7}, radius = 8})
check(f ~= nil, "attached")
eq(M.attach(b, nil, {}), f, "a second attach is the same fight")
runTo(1000)
local sent = false
for _, o in ipairs(stay.ops or {}) do
	sent = sent or (o[1] == 125 and o[2] == "{mech:Slam}")
end
check(sent, "the cast bar went out on opcode 125 (action mech)")
check(#effects > 0, "the danger marks are drawn")
walker.pos = {x = 200, y = 207, z = 7} -- walks off before the hit
runTo(1000 + 3100)
local hitStay, hitWalker = false, false
for _, h in ipairs(hits) do
	hitStay = hitStay or h.target == stay.id
	hitWalker = hitWalker or h.target == walker.id
end
check(hitStay, "the player left on the mark is hit")
check(not hitWalker, "the player who walked off is not")
eq(stay.hp, 6000, "40% of max health")
-- the wardstone phase
b.hp = 49000
runTo(T + 300)
local wards = 0
for id in pairs(f.adds) do
	wards = wards + 1
end
eq(wards, 2, "two wardstones")
check(b.said and b.said:find("Testor is warded") ~= nil, "the orange warning names the boss")
local reg = registered.ChaosBossMechHealth
local dmg = reg.onHealthChange(b, stay, -500, COMBAT_FIREDAMAGE, 0, 0)
eq(dmg, 0, "immune while the wardstones stand")
for id in pairs(f.adds) do
	creatures[id] = nil
end
runTo(T + 1500)
dmg = reg.onHealthChange(b, stay, -500, COMBAT_FIREDAMAGE, 0, 0)
eq(dmg, -500, "hurt again after the wardstones")
-- the channel: kill the totem, no hit
stay.hp, walker.hp = 10000, 10000
hits = {}
runTo(15300)
check(f.channel ~= nil and f.channel.totem ~= nil, "the channel raised a totem")
creatures[f.channel.totem] = nil
runTo(15300 + 9000)
local chHit = false
for _, h in ipairs(hits) do
	chHit = chHit or h.dmg == 5000
end
check(not chHit, "killing the totem stops the channel")
-- the blast: the player behind the pillar is spared
hits = {}
b.pos = {x = 200, y = 200, z = 7}
stay.pos = {x = 200, y = 205, z = 7} -- the pillar at 200,203 is between
walker.pos = {x = 205, y = 200, z = 7}
runTo(40500 + 3500)
local hid, open = false, false
for _, h in ipairs(hits) do
	hid = hid or h.target == stay.id
	open = open or h.target == walker.id
end
check(open, "the blast hits the player in view")
check(not hid, "the player behind the pillar is spared")
-- debuff stacks on the boss's own hits
cfg.profiles["test boss"].debuff = {label = "Brand", perStack = 0.1, max = 5, everyMs = 0, decayMs = 60000}
local taken = registered.ChaosBossMechTaken
local d1 = taken.onHealthChange(stay, b, -1000, COMBAT_PHYSICALDAMAGE, 0, 0)
local d2 = taken.onHealthChange(stay, b, -1000, COMBAT_PHYSICALDAMAGE, 0, 0)
check(d2 < d1, "the second hit is stronger with a stack (" .. d1 .. ", " .. d2 .. ")")
-- the boss dies: the fight is cleaned up
creatures[b.id] = nil
runTo(T + 500)
check(M.fights[b.id] == nil, "the fight ends with the boss")

print(string.format("boss_mechanics_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
