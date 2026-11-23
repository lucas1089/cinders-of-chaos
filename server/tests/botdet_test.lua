-- Run from the server/ folder: luajit tests/botdet_test.lua [-v] (or lua5.3; CI runs both)
-- Bot detection events and scores (O722): the opcode and constants, the rings and the packed rows, each of the six
-- heuristics on small traces, synthetic human and bot traces (humans below 40, bots above 70), the policy switch for the
-- owner's route tool, the client's integrity chunks and tool codes. botdet.lua against a mocked engine: botdet_engine_test.lua.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
local verbose = arg and arg[1] == "-v"
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/botdet_config.lua")
dofile("data/scripts/chaos/botdet_core.lua")
local K = ChaosBotdetCore
local floor = math.floor

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, eps, label)
	check(math.abs(a - b) <= eps, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ---------------------------------------------------------------- opcode, tables, config
eq(ChaosOpcodes.botdet, 169, "opcode 169")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	check(not seen[v], "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 113, 144, 145, 146, 210, 212, 213, 230, 246}) do
	check(v ~= 169, "169 is not the reference opcode " .. v)
end
eq(Chaos.botdetTables.events, "chaos_botdet_events", "events table")
eq(Chaos.botdetTables.scores, "chaos_botdet_scores", "scores table")
eq(cfg.retention.eventDays, 7, "events kept 7 days")
eq(cfg.retention.scoreDays, 90, "scores kept 90 days")
eq(cfg.flagAt, 70, "flag above 70")
eq(cfg.weights.route, 30, "route weight")
eq(cfg.weights.regularity, 25, "regularity weight")
eq(cfg.weights.reaction, 20, "reaction weight")
eq(cfg.weights.heal, 15, "heal weight")
eq(cfg.weights.session, 10, "session weight")
eq(cfg.rumo.policy, "forbidden", "the route tool policy is forbidden (owner 2026-11-22: no cavebot, no external tool)")
eq(cfg.sampleMs, 1000, "positions every second")
eq(cfg.flushSeconds, 300, "writes every 5 minutes")

-- ---------------------------------------------------------------- helpers
local pk, pp = K.posKey, K.posParts
local x, y, z = pp(pk(33445, 31987, 7))
eq(x, 33445, "key x"); eq(y, 31987, "key y"); eq(z, 7, "key z")
eq(K.ramp(0.5, 0, 1), 0.5, "ramp up")
eq(K.ramp(0.05, 0.25, 0.08) > 0.99, true, "ramp down: low is 1")
eq(K.median({3, 1, 2}), 2, "median odd")
eq(K.median({1, 2, 3, 4}), 2.5, "median even")
local mean, std = K.meanStd({2, 4, 4, 4, 5, 5, 7, 9})
eq(mean, 5, "mean"); eq(std, 2, "std")
local r = K.ringNew(3)
for i = 1, 5 do
	K.ringPush(r, i, i * 10)
end
local l, lb = K.ringList(r)
eq(#l, 3, "ring keeps its cap"); eq(l[1], 3, "oldest kept"); eq(l[3], 5, "newest"); eq(lb[1], 30, "second array")

-- a tiny deterministic random source (the same numbers in LuaJIT and Lua 5.3)
local function rng(seed)
	local s = seed
	local f = {}
	function f.u()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
	function f.range(a, b)
		return a + (b - a) * f.u()
	end
	function f.exp(mean_)
		return -mean_ * math.log(1 - f.u() * 0.999999)
	end
	return f
end

local T0 = 1790000000

-- ---------------------------------------------------------------- the state, the pending rows
do
	local st = K.newState(cfg, 7, "Mira", T0)
	eq(K.onSample(st, cfg, 100, 200, 7, T0), true, "first sample is a change")
	eq(K.onSample(st, cfg, 100, 200, 7, T0 + 1), false, "standing still adds nothing")
	eq(K.onSample(st, cfg, 101, 200, 7, T0 + 2), true, "a step is a change")
	K.onCast(st, cfg, (T0 + 3) * 1000, T0 + 3, 12, false, 80, 60)
	K.onHeal(st, cfg, (T0 + 4) * 1000, T0 + 4, 55)
	K.onReact(st, cfg, 4001, 220, T0 + 5)
	K.onSignals(st, cfg, {keys = 3, paths = 1, pathSteps = 12, reactions = {{4002, 300}}}, T0 + 6)
	K.onLogin(st, cfg, T0)
	local rows = K.takeRows(st, cfg, T0 + 10)
	local byType = {}
	for _, row in ipairs(rows) do
		byType[row.type] = row
	end
	check(byType.pos and byType.walk and byType.spell and byType.heal and byType.react and byType.session, "one row per kind")
	eq(byType.pos.data.v, "0,100,200,7;2,101,200,7", "positions are delta coded")
	eq(byType.pos.data.t, T0, "positions start time")
	eq(byType.walk.data.k, 3, "key steps"); eq(byType.walk.data.p, 1, "path commands"); eq(byType.walk.data.s, 12, "path steps")
	eq(byType.spell.data.v, (T0 + 3) .. ",12,80,60,0", "a spell with hit point and mana %")
	eq(byType.heal.data.v, (T0 + 4) .. ",55", "a heal with hit point %")
	check(byType.react.data.v:find("4001,220", 1, true) and byType.react.data.v:find("4002,300", 1, true), "reactions")
	eq(#K.takeRows(st, cfg, T0 + 11), 0, "nothing left after a flush")
	-- the second flush holds only what is new
	K.onSample(st, cfg, 102, 200, 7, T0 + 12)
	rows = K.takeRows(st, cfg, T0 + 13)
	eq(#rows, 1, "one new row"); eq(rows[1].data.v, "0,102,200,7", "only the new position")
	-- a heal at the top is no threshold, a heal in the same moment as a cast is the spell's
	local s2 = K.newState(cfg, 8, "Tol", T0)
	K.onCast(s2, cfg, 100000, T0, 5, false, 90, 90)
	K.onHeal(s2, cfg, 100020, T0, 99)
	eq(K.ringList(s2.heals) ~= nil and #K.ringList(s2.heals), 0, "a top-up heal is not a threshold sample")
	check(s2.kinds.p == nil, "a heal inside a cast is not a potion")
	K.onHeal(s2, cfg, 105000, T0 + 5, 60)
	check(s2.kinds.p ~= nil, "a heal on its own is a potion kind")
	-- pending is bounded
	local s3 = K.newState(cfg, 9, "Cap", T0)
	for i = 1, cfg.rings.pending * 3 do
		K.onHeal(s3, cfg, i * 1000, T0 + i, 50)
	end
	check(#s3.pend.heal <= cfg.rings.pending, "pending rows are bounded")
	-- a position ring that wrapped between flushes writes what it still has
	local s4 = K.newState(cfg, 10, "Wrap", T0)
	for i = 1, cfg.rings.pos + 50 do
		K.onSample(s4, cfg, 100 + (i % 2000), 200, 7, T0 + i)
	end
	local wrows = K.takeRows(s4, cfg, T0)
	local cnt = 0
	for _ in wrows[1].data.v:gmatch("[^;]+") do
		cnt = cnt + 1
	end
	eq(cnt, cfg.rings.pos, "a wrapped ring writes its cap")
end

-- ---------------------------------------------------------------- one heuristic at a time
do
	-- reaction: needs samples, median
	local st = K.newState(cfg, 1, "R", T0)
	for i = 1, 19 do
		K.onReact(st, cfg, i, 80, T0 + i)
	end
	eq(K.analyze(st, cfg, T0 + 30).parts.reaction, nil, "reaction below minSamples has no score")
	for i = 20, 60 do
		K.onReact(st, cfg, i, 80, T0 + i)
	end
	local a = K.analyze(st, cfg, T0 + 70)
	check(a.parts.reaction and a.parts.reaction.score > 95, "median 80 ms is bot-like")
	local st2 = K.newState(cfg, 2, "R2", T0)
	for i = 1, 60 do
		K.onReact(st2, cfg, i, 400 + (i % 7) * 60, T0 + i)
	end
	eq(K.analyze(st2, cfg, T0 + 70).parts.reaction.score, 0, "median 580 ms is human")
	local st3 = K.newState(cfg, 3, "R3", T0)
	K.onReact(st3, cfg, 1, 9000, T0)
	eq(#K.ringList(st3.react), 0, "a first attack after 5 s is no reaction")

	-- heal threshold
	local h = K.newState(cfg, 4, "H", T0)
	local g = rng(5)
	for i = 1, 60 do
		K.onHeal(h, cfg, i * 3000, T0 + i * 3, 69 + g.range(-1, 1))
	end
	check(K.analyze(h, cfg, T0 + 400).parts.heal.score > 95, "heals at 69 to 71 percent are bot-like")
	local h2 = K.newState(cfg, 5, "H2", T0)
	for i = 1, 60 do
		K.onHeal(h2, cfg, i * 3000, T0 + i * 3, g.range(30, 85))
	end
	eq(K.analyze(h2, cfg, T0 + 400).parts.heal.score, 0, "heals anywhere from 30 to 85 percent are human")

	-- regularity: a fixed delay against a loose one; a held hotkey (bound) gives no samples
	local rg = K.newState(cfg, 6, "G", T0)
	for i = 1, 120 do
		K.onCast(rg, cfg, i * 2000 + g.range(-20, 20), T0 + i * 2, 9, false, 100, 100)
	end
	check(K.analyze(rg, cfg, T0 + 300).parts.regularity.score > 95, "a spell every 2000 ms plus or minus 20 is bot-like")
	local rh = K.newState(cfg, 7, "G2", T0)
	local ms = 0
	for i = 1, 120 do
		ms = ms + 1800 + g.exp(1500)
		K.onCast(rh, cfg, ms, T0 + floor(ms / 1000), 9, false, 100, 100)
	end
	eq(K.analyze(rh, cfg, T0 + 300).parts.regularity.score, 0, "a loose rhythm is human")
	local rb = K.newState(cfg, 8, "G3", T0)
	for i = 1, 120 do
		K.onCast(rb, cfg, i * 2000, T0 + i * 2, 9, true, 100, 100)
	end
	eq(K.analyze(rb, cfg, T0 + 300).parts.regularity, nil, "casts bound to the cooldown give no rhythm")
	-- few samples: partial credit
	local rf = K.newState(cfg, 9, "G4", T0)
	for i = 1, 41 do
		K.onCast(rf, cfg, i * 2000, T0 + i * 2, 9, false, 100, 100)
	end
	local part = K.analyze(rf, cfg, T0 + 300).parts.regularity.score
	check(part > 30 and part < 50, "40 perfect intervals count for 40 of 100 samples: " .. part)
	-- the kinds table is bounded
	local rk = K.newState(cfg, 10, "G5", T0)
	for id = 1, 30 do
		K.onCast(rk, cfg, id * 100, T0, id, false, 100, 100)
	end
	check(#rk.kindOrder <= cfg.rings.kinds, "kinds of action are bounded")

	-- session: a stretch without a pause, hours with an action in the day
	local se = K.newState(cfg, 11, "S", T0)
	for s = 0, 7 * 3600, 60 do
		K.touch(se, cfg, T0 + s)
	end
	local a2 = K.analyze(se, cfg, T0 + 7 * 3600)
	check(a2.parts.session.score > 60 and a2.parts.session.score < 80, "7 hours without a pause: " .. a2.parts.session.score)
	local sf = K.newState(cfg, 12, "S2", T0)
	for s = 0, 22 * 3600, 60 do
		-- an hour on, ten minutes off: the stretch never passes an hour, the day has 18.9 hours
		if s % 4200 < 3600 then
			K.touch(sf, cfg, T0 + s)
		end
	end
	local a3 = K.analyze(sf, cfg, T0 + 22 * 3600)
	check(a3.parts.session.score > 55, "nearly all day with ten minute pauses still shows in the day total: " .. a3.parts.session.score)
	local sh = K.newState(cfg, 13, "S3", T0)
	for s = 0, 2.5 * 3600, 60 do
		K.touch(sh, cfg, T0 + s)
	end
	eq(K.analyze(sh, cfg, T0 + 2.5 * 3600).parts.session.score, 0, "2.5 hours without a pause is nothing")
	local sn = K.newState(cfg, 14, "S4", T0)
	K.touch(sn, cfg, T0)
	eq(K.analyze(sn, cfg, T0 + 600).parts.session, nil, "ten minutes say nothing")
end

-- ---------------------------------------------------------------- route on small traces
do
	-- a rectangle loop of 120 tiles, walked 25 times in 2 hours (one lap = 288 s)
	local loop = {}
	for i = 0, 29 do loop[#loop + 1] = {1000 + i, 1000} end
	for i = 1, 29 do loop[#loop + 1] = {1029, 1000 + i} end
	for i = 1, 29 do loop[#loop + 1] = {1029 - i, 1029} end
	for i = 1, 28 do loop[#loop + 1] = {1000, 1029 - i} end
	local st = K.newState(cfg, 20, "Loop", T0)
	local t = T0
	for lap = 1, 25 do
		for i = 1, #loop do
			K.onSample(st, cfg, loop[i][1], loop[i][2], 7, t)
			t = t + 2
		end
	end
	local rr = K.analyze(st, cfg, t).parts.route
	check(rr and rr.score > 95, "the same rectangle 25 times is bot-like: " .. (rr and rr.score or "nil") .. " " .. (rr and rr.text or ""))
	-- the same rectangle only twice: not a pattern yet
	local s2 = K.newState(cfg, 21, "Loop2", T0)
	t = T0
	for lap = 1, 2 do
		for i = 1, #loop do
			K.onSample(s2, cfg, loop[i][1], loop[i][2], 7, t)
			t = t + 12
		end
	end
	local r2 = K.analyze(s2, cfg, t).parts.route
	check(r2 == nil or r2.score < 10, "two laps are no pattern")
	-- standing in one place walks no loop
	local s3 = K.newState(cfg, 22, "Stand", T0)
	t = T0
	for i = 1, 3000 do
		K.onSample(s3, cfg, 1000 + (i % 2), 1000, 7, t)
		t = t + 1
	end
	local r3 = K.analyze(s3, cfg, t).parts.route
	check(r3 == nil or r3.score == 0, "walking between two tiles is no loop")
end

-- ---------------------------------------------------------------- the path bonus
do
	local st = K.newState(cfg, 30, "P", T0)
	K.onSignals(st, cfg, {keys = 10, paths = 40, pathSteps = 640}, T0 + 100)
	local a = K.analyze(st, cfg, T0 + 200)
	check(a.path and a.path.score > 95, "long path commands and a few keys: " .. (a.path and a.path.score or "nil"))
	near(a.bonus, cfg.bonusMax, 0.6, "the bonus is at most bonusMax")
	check(a.total <= cfg.bonusMax + 0.01, "the bonus alone never flags: " .. a.total)
	local s2 = K.newState(cfg, 31, "P2", T0)
	K.onSignals(s2, cfg, {keys = 700, paths = 40, pathSteps = 200}, T0 + 100)
	eq(K.analyze(s2, cfg, T0 + 200).path.score, 0, "keys and short clicks are no bonus")
	local s3 = K.newState(cfg, 32, "P3", T0)
	K.onSignals(s3, cfg, {keys = 5, paths = 3, pathSteps = 30}, T0 + 100)
	eq(K.analyze(s3, cfg, T0 + 200).path, nil, "too few steps say nothing")
	-- the hour buckets forget after 4 hours
	local s4 = K.newState(cfg, 33, "P4", T0)
	K.onSignals(s4, cfg, {keys = 10, paths = 40, pathSteps = 640}, T0)
	eq(K.analyze(s4, cfg, T0 + 5 * 3600).path, nil, "old path counts are dropped")
end

-- ---------------------------------------------------------------- the synthetic players
-- one second at a time; returns the state after `hours` of play
local function simulate(kind, seed, hours)
	local g = rng(seed)
	local st = K.newState(cfg, seed, kind .. seed, T0)
	K.onLogin(st, cfg, T0)
	local total = floor(hours * 3600)
	-- ---- the walk
	local loop, li, lapStep = {}, 1, 0
	if kind == "bot" or kind == "smartbot" then
		-- a cave circuit of 36 waypoints joined by straight lines: about 200 tiles, 3.5 minutes a lap at one tile a second
		local wps = {}
		local cx, cy = 1500 + seed, 2000
		for i = 1, 36 do
			wps[i] = {cx + floor(16 * math.cos(i * 0.5) + (i % 5) * 2), cy + floor(12 * math.sin(i * 0.5) + (i % 3) * 3)}
		end
		local px, py = wps[1][1], wps[1][2]
		for i = 2, 37 do
			local w = wps[(i - 1) % 36 + 1]
			while px ~= w[1] or py ~= w[2] do
				px = px + (w[1] > px and 1 or (w[1] < px and -1 or 0))
				py = py + (w[2] > py and 1 or (w[2] < py and -1 or 0))
				loop[#loop + 1] = {px, py}
			end
		end
	end
	local areaX, areaY = 3000 + seed * 7, 3000
	local tx, ty = areaX, areaY
	local px, py = areaX, areaY
	local nextArea = 2400 + g.range(0, 1200)
	-- ---- the actions
	local nextSpell = T0 * 1000 + 1000
	local nextDmg = T0 * 1000 + 9000
	local nextMob = T0 * 1000 + 15000
	local pauseUntil = -1
	local nextBreak = 2400 + g.range(0, 1800)
	local breakUntil = -1
	for s = 0, total do
		local now = T0 + s
		local nowMs = now * 1000
		local active = true
		if kind == "human" or kind == "helper" then
			if s >= nextBreak and breakUntil < 0 then
				breakUntil = s + g.range(400, 900)
			end
			if breakUntil >= 0 then
				active = false
				if s >= breakUntil then
					breakUntil = -1
					nextBreak = s + g.range(2400, 4200)
				end
			end
		end
		if active then
			-- the walk
			if kind == "bot" or kind == "smartbot" then
				local p = loop[li]
				px, py = p[1], p[2]
				li = li % #loop + 1
				if kind == "smartbot" and g.u() < 0.02 then
					li = li + floor(g.range(0, 2)) -- a smarter bot skips or repeats a tile now and then
					if li > #loop then li = 1 end
				end
			else
				if s >= nextArea then
					areaX, areaY = 3000 + floor(g.range(-300, 300)), 3000 + floor(g.range(-300, 300))
					tx, ty = areaX, areaY
					nextArea = s + 2400 + g.range(0, 1800)
				end
				if s >= pauseUntil then
					if px == tx and py == ty then
						tx, ty = areaX + floor(g.range(-25, 25)), areaY + floor(g.range(-25, 25))
					end
					px = px + (tx > px and 1 or (tx < px and -1 or 0))
					py = py + (ty > py and 1 or (ty < py and -1 or 0))
					if g.u() < 0.05 then
						pauseUntil = s + g.range(2, 12)
					end
				end
			end
			K.onSample(st, cfg, px, py, 7, now)
			-- spells
			while nextSpell <= nowMs do
				if kind == "bot" then
					K.onCast(st, cfg, nextSpell, floor(nextSpell / 1000), 31, false, 100, 90)
					nextSpell = nextSpell + 2000 + g.range(-25, 25)
				elseif kind == "smartbot" then
					K.onCast(st, cfg, nextSpell, floor(nextSpell / 1000), 31, false, 100, 90)
					nextSpell = nextSpell + 2000 * g.range(0.85, 1.15)
				elseif kind == "helper" then
					-- the client's own helper: at the cooldown, so the cast comes the moment the spell is ready
					K.onCast(st, cfg, nextSpell, floor(nextSpell / 1000), 31, true, 100, 90)
					nextSpell = nextSpell + 2000
				else
					K.onCast(st, cfg, nextSpell, floor(nextSpell / 1000), 31, false, 100, 90)
					nextSpell = nextSpell + 1900 + g.exp(1700)
				end
			end
			-- damage and the heal that answers it
			while nextDmg <= nowMs do
				local hp
				if kind == "bot" then
					hp = 69 + g.range(-1, 1)
				elseif kind == "smartbot" then
					hp = 70 + g.range(-3.5, 3.5)
				elseif kind == "helper" then
					hp = 65 + g.range(-6, 4) -- the helper heals below a set value, the hit decides how far below
				else
					hp = g.range(32, 80)
				end
				K.onHeal(st, cfg, nextDmg + 300, floor(nextDmg / 1000), hp)
				nextDmg = nextDmg + g.range(7000, 25000)
			end
			-- a creature comes into view and is attacked
			while nextMob <= nowMs do
				local ms
				if kind == "bot" then
					ms = g.range(40, 110)
				elseif kind == "smartbot" then
					ms = g.range(100, 200)
				else
					ms = 230 + g.exp(350)
				end
				K.onReact(st, cfg, floor(nextMob / 1000) % 100000, ms, floor(nextMob / 1000))
				nextMob = nextMob + g.range(9000, 35000)
			end
			-- steps as the engine counts them
			if s % 5 == 0 then
				if kind == "bot" or kind == "smartbot" then
					K.onSignals(st, cfg, {keys = 0, paths = 1, pathSteps = 5}, now)
				elseif kind == "helper" then
					K.onSignals(st, cfg, {keys = 3, paths = 1, pathSteps = 2}, now)
				else
					K.onSignals(st, cfg, {keys = 4, paths = 0, pathSteps = 0}, now)
				end
			end
		else
			-- on a pause the creature table and the timers move on without the player
			while nextSpell <= nowMs do nextSpell = nextSpell + 2000 end
			while nextDmg <= nowMs do nextDmg = nextDmg + 10000 end
			while nextMob <= nowMs do nextMob = nextMob + 20000 end
		end
	end
	return st, T0 + total
end

local results = {}
local function run(kind, seed, hours)
	local st, now = simulate(kind, seed, hours)
	local a = K.analyze(st, cfg, now)
	results[#results + 1] = {kind = kind, seed = seed, a = a}
	if verbose then
		print(string.format("%-8s seed %2d total %5.1f flagged %s", kind, seed, a.total, tostring(a.flagged)))
		for _, line in ipairs(K.lines(a, cfg)) do
			print("    " .. line)
		end
	end
	return a
end

for seed = 1, 6 do
	local a = run("human", seed, 3)
	check(a.total < 40, "a human (seed " .. seed .. ") stays below 40: " .. a.total)
	check(not a.flagged, "a human is not flagged (seed " .. seed .. ")")
end
for seed = 1, 4 do
	local a = run("helper", 10 + seed, 3)
	check(a.total < 55 and not a.flagged, "a character using the client's helper is not flagged (seed " .. (10 + seed) .. "): " .. a.total)
end
for seed = 1, 4 do
	local a = run("bot", 20 + seed, 7)
	check(a.total > 70, "a cavebot (seed " .. (20 + seed) .. ") is above 70: " .. a.total)
	check(a.flagged, "a cavebot is flagged (seed " .. (20 + seed) .. ")")
	check(a.parts.route and a.parts.route.score > 90, "its route is the main sign: " .. tostring(a.parts.route and a.parts.route.score))
	check(a.parts.regularity and a.parts.regularity.score > 90, "its rhythm is a main sign")
end
for seed = 1, 3 do
	local a = run("smartbot", 30 + seed, 7)
	-- jitter on every signal: it must still stand well apart from a human (above 40) even if it slips under the flag
	check(a.total > 40, "a bot with jitter still stands out (seed " .. (30 + seed) .. "): " .. a.total)
end

-- ---------------------------------------------------------------- the score row and the lines
do
	local st, now = simulate("bot", 41, 7)
	local a = K.analyze(st, cfg, now)
	local row = K.scoreRow(a, cfg)
	eq(row.flagged, 1, "row flagged"); check(row.total > 70, "row total"); check(#row.notes > 50 and #row.notes <= 1000, "notes fit the column")
	local lines = K.lines(a, cfg)
	check(#lines >= 7, "a line for the total, five heuristics and the path")
	check(lines[1]:find("FLAGGED", 1, true) ~= nil, "the first line says flagged")
	check(lines[2]:find("route", 1, true) ~= nil and lines[2]:find("laps", 1, true) == nil and lines[2]:find("repeated", 1, true) ~= nil,
		"the route line has its numbers")
	local fresh = K.newState(cfg, 50, "New", T0)
	local a2 = K.analyze(fresh, cfg, T0 + 10)
	eq(a2.total, 0, "a character with no data scores 0"); eq(a2.flagged, false, "and is not flagged")
	check(K.lines(a2, cfg)[2]:find("not enough", 1, true) ~= nil, "no data is said")
	-- one heuristic alone cannot flag: only the route has data, the coverage cut keeps it under the flag
	local st3 = K.newState(cfg, 51, "One", T0)
	for i = 1, 60 do
		K.onReact(st3, cfg, i, 60, T0 + i)
	end
	local a3 = K.analyze(st3, cfg, T0 + 100)
	check(a3.total < cfg.flagAt, "the reaction alone (weight 20 of 60) stays under the flag: " .. a3.total)
end

-- ---------------------------------------------------------------- the policy switch for the owner's route tool
do
	local function with(policy, areas)
		local c = {}
		for k, v in pairs(cfg) do c[k] = v end
		c.rumo = {policy = policy, areas = areas or {}, moduleNames = cfg.rumo.moduleNames, toolCode = cfg.rumo.toolCode}
		return c
	end
	local st, now = simulate("bot", 60, 7)
	st.rumoSeen = true
	local flagC = with("flag")
	local a = K.analyze(st, flagC, now)
	check(a.flagged and a.rumo == "flag", "flag only: flagged and the tool is shown")
	a = K.analyze(st, with("forbidden"), now)
	check(a.flagged and a.rumo == "forbidden", "forbidden: flagged, labelled")
	a = K.analyze(st, with("allowed"), now)
	check(not a.flagged and a.rumo == "allowed", "allowed: not flagged")
	check(a.parts.route and a.total < 70, "allowed: the route, rhythm and session are left out of the total (" .. a.total .. ")")
	local x1, y1 = pp(st.lastKey)
	a = K.analyze(st, with("areas", {{x1 - 5, y1 - 5, x1 + 5, y1 + 5, 7}}), now)
	check(not a.flagged and a.rumo == "allowed in this area", "areas: inside is allowed")
	a = K.analyze(st, with("areas", {{0, 0, 10, 10, 7}}), now)
	check(a.flagged and a.rumo == "outside the allowed areas", "areas: outside is flagged")
	st.rumoSeen = nil
	a = K.analyze(st, with("allowed"), now)
	check(a.flagged and a.rumo == nil, "allowed means nothing for a character that does not run the tool")
end

-- ---------------------------------------------------------------- the client's integrity chunks and tool codes
do
	local official = {game_a = "aaaa", game_b = "bbbb", client_c = "cccc"}
	local st = K.newState(cfg, 70, "Int", T0)
	local read, ev = K.integrityChunk(st, cfg, {i = 1, n = 2, b = 7, m = {{"game_a", "aaaa"}, {"game_b", "xxxx"}}}, official)
	eq(read, 2, "entries read"); eq(ev, nil, "no event before the last chunk")
	read, ev = K.integrityChunk(st, cfg, {i = 2, n = 2, b = 7, m = {{"client_c", "cccc"}, {"zz_bot", "1234"}, {"game_rumolink", "99"}}}, official)
	check(ev ~= nil and ev.type == "integrity", "an event at the last chunk")
	eq(ev.data.changed[1], "game_b", "a changed module"); eq(#ev.data.extra, 2, "two extras")
	eq(ev.data.extra[1], "game_rumolink", "extras sorted")
	eq(st.rumoSeen, true, "the route tool's module is noticed")
	-- clean client: no event
	local s2 = K.newState(cfg, 71, "Int2", T0)
	read, ev = K.integrityChunk(s2, cfg, {i = 1, n = 1, b = 7, m = {{"game_a", "aaaa"}, {"game_b", "bbbb"}}}, official)
	eq(ev, nil, "no event for an official client")
	-- no official list: no event
	local s3 = K.newState(cfg, 72, "Int3", T0)
	read, ev = K.integrityChunk(s3, cfg, {i = 1, n = 1, b = 7, m = {{"zz_bot", "1"}}}, {})
	eq(ev, nil, "no list, nothing to compare")
	-- malformed
	read, ev = K.integrityChunk(s3, cfg, {i = 5, n = 2, m = {}}, official)
	eq(read, 0, "a chunk number out of range reads nothing")
	read = K.integrityChunk(s3, cfg, {i = 1, n = 1, m = {{1, 2}, {"x"}, "y", {("n"):rep(100), "d"}}}, official)
	eq(read, 0, "malformed entries are skipped")
	eq(K.integrityChunk(s3, cfg, "text", official), 0, "not a table")
	-- tool codes
	local c2 = {}
	for k, v in pairs(cfg) do c2[k] = v end
	c2.tools = {list = {{code = "cave1", hashes = {"0123456789abcdef"}}, {code = "rumo", hashes = {"fedcba9876543210", "short"}}}, maxCodes = 8}
	local s4 = K.newState(c2, 73, "Tool", T0)
	local ev2 = K.toolCodes(s4, c2, {c = {"cave1", "nothere", "bad code", "ab", "rumo"}})
	check(ev2 and ev2.type == "tool", "a tool event")
	eq(#ev2.data.c, 2, "only codes of the list"); eq(ev2.data.c[1], "cave1", "sorted"); eq(s4.rumoSeen, true, "the route tool code")
	eq(K.toolCodes(s4, c2, {c = {"zzzzz"}}), nil, "an unknown code is nothing")
	eq(K.toolCodes(s4, c2, {c = "text"}), nil, "malformed codes")
	local list = K.toolList(c2)
	eq(#list, 2, "two valid hashes are sent, the short one is not"); eq(list[1][1], "cave1", "code and hash")
	eq(K.toolList(cfg)[1], nil, "the empty list sends nothing")
end

-- ---------------------------------------------------------------- the engine files read the constants
local function read(path)
	local f = io.open(path, "r")
	if not f then
		return ""
	end
	local s = f:read("*a")
	f:close()
	return s
end
do
	local constants = read("data/scripts/chaos/chaos_constants.lua")
	local count169 = 0
	for _ in constants:gmatch("ChaosOpcodes%.[%w_]+%s*=%s*169%f[%D]") do
		count169 = count169 + 1
	end
	eq(count169, 1, "the constants name 169 once")
	local sql = read("sql/chaos_botdet.sql")
	check(sql:find("chaos_botdet_events", 1, true) and sql:find("chaos_botdet_scores", 1, true), "the sql file has both tables")
	check(sql:find("uniq_player_hour", 1, true) ~= nil, "one score row a character and hour")
end

if failures > 0 then
	print(string.format("botdet_test: %d of %d checks failed", failures, count))
	os.exit(1)
end
print(string.format("botdet_test: %d checks ok", count))
