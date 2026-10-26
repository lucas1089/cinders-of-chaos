-- Leveling journey model: minutes per level from level 1 to 2200, hunts per level, spikes and walls (computed from the
-- repo's own data; not measured in game). server/README.md "Progression smoothness (O135)".
--     cd server && luajit tools/progression_model.lua [--check]      (also lua5.3)
-- Inputs: experienceStages (tools/late_game.py), the hunt pool (bounty_pool.lua) with the pace curves (pace_config.lua),
-- kills per hour (spawn_tuning.json model.paceKillsPerHour), the engine's experience formula, the hall's hunt bands
-- (tools/hall_hunts.csv and tools/areaplan/plans/*.json) and progression_config.lua (the limits --check enforces).
local M = {}

local function readAll(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- experienceStages of tools/late_game.py: {{lo, hi, mult}, ...}
function M.stagesFromText(text)
	local out = {}
	if not text:find("SMOOTH_STAGES", 1, true) then
		-- the table before O135: BASE_STAGES + the late list inside STAGES
		for lo, hi, mult in (text:match("BASE_STAGES = %[(.-)\n[A-Z]") or ""):gmatch("%((%d+), ([%w_]+), (%d+)%)") do
			out[#out + 1] = {tonumber(lo), hi == "OPEN_END" and 999999 or tonumber(hi), tonumber(mult)}
		end
		for lo, hi, mult in (text:match("\nSTAGES = BASE_STAGES %+ %[(.-)%]\n") or ""):gmatch("%((%d+), ([%w_]+), (%d+)%)") do
			out[#out + 1] = {tonumber(lo), hi == "OPEN_END" and 999999 or tonumber(hi), tonumber(mult)}
		end
		return out
	end
	for _, name in ipairs({"SMOOTH_STAGES", "LATE_STAGES"}) do
		local body = text:match(name .. " = %[(.-)%]\n") or ""
		for lo, hi, mult in body:gmatch("%((%d+), ([%w_]+), (%d+)%)") do
			out[#out + 1] = {tonumber(lo), hi == "OPEN_END" and 999999 or tonumber(hi), tonumber(mult)}
		end
	end
	return out
end

function M.stage(stages, level)
	for _, s in ipairs(stages) do
		if level >= s[1] and level <= s[2] then
			return s[3]
		end
	end
	return stages[#stages][3]
end

-- experience from level L to L + 1 (the engine: Player::getExpForLevel)
function M.expToNext(L)
	return 50 * L * L - 150 * L + 200
end

local function lin(points, x)
	if x <= points[1][1] then return points[1][2] end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if x <= b[1] then
			return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
		end
	end
	return points[#points][2]
end
M.lin = lin

-- hunts: {level, xp} per pool entry, the experience of a kill after the pace curve, before the stage
function M.hunts(P, cfg, pool, kph)
	local out = {}
	for _, e in ipairs(pool.hunt) do
		local lvl, sc = P.entryLevel(cfg, e)
		local f = P.factors(cfg, lvl, sc)
		local xpL = sc and math.max(1, lvl * 0.03) or 1
		local k = lin(sc and kph.scaled or kph.base, lvl)
		out[#out + 1] = {name = e.name, level = lvl, xp = e.exp * xpL * f.xp, kph = k, xph = e.exp * xpL * f.xp * k}
	end
	table.sort(out, function(a, b) return a.level < b.level end)
	return out
end

-- the experience per hour (before the stage) a player of level L gets: the median of the hunts whose level is within
-- [lo L, hi L]; the window widens until `minHunts` are in it
function M.xpPerHour(hunts, L, win)
	local lo, hi = win.lo, win.hi
	local picked
	for _ = 1, 30 do
		picked = {}
		for _, h in ipairs(hunts) do
			if h.level >= lo * L and h.level <= hi * L then
				picked[#picked + 1] = h.xph
			end
		end
		if #picked >= win.minHunts then break end
		lo, hi = lo - 0.05, hi + 0.05
	end
	if #picked == 0 then return 0, 0 end
	table.sort(picked)
	return picked[math.ceil(#picked / 2)], #picked
end

-- minutes per level at each level 1..maxLevel: {min, hunts}
function M.curve(env, maxLevel)
	local out = {}
	for L = 1, maxLevel do
		local xph, n = M.xpPerHour(env.hunts, L, env.cfg.window)
		xph = xph * env.cfg.multikill * M.stage(env.stages, L)
		out[L] = {min = xph > 0 and M.expToNext(L) / xph * 60 or math.huge, hunts = n}
	end
	return out
end

-- hours from level a to level b
function M.hours(curve, a, b)
	local m = 0
	for L = a, b - 1 do m = m + curve[L].min end
	return m / 60
end

-- the hall's hunts: {band lo, band hi, name, level} (level: a base hunt's weighted median, a plan's middle)
function M.hallBands(csvText, planFiles)
	local out = {}
	for line in csvText:gmatch("[^\r\n]+") do
		if line:sub(1, 1) ~= "#" and not line:find("^id,") then
			local f = {}
			for v in (line .. ","):gmatch("([^,]*),") do f[#f + 1] = v end
			if f[8] == "hunt" and tonumber(f[11]) and tonumber(f[12]) then
				out[#out + 1] = {tonumber(f[11]), tonumber(f[12]), f[9], tonumber(f[10])}
			end
		end
	end
	for name, text in pairs(planFiles) do
		local a, b = text:match('"level"%s*:%s*%[%s*(%d+)%s*,%s*(%d+)')
		if a then out[#out + 1] = {tonumber(a), tonumber(b), name, (tonumber(a) + tonumber(b)) / 2} end
	end
	return out
end

-- hall hunts within reach of a character of level L: their level inside [lo L, hi L]
function M.hallCount(bands, L, win)
	win = win or {lo = 0.7, hi = 1.3}
	local n = 0
	for _, b in ipairs(bands) do
		if b[4] >= win.lo * L and b[4] <= win.hi * L then n = n + 1 end
	end
	return n
end

-- runs of levels where `fn(L)` is true: {{from, to}, ...}
function M.runs(fromLevel, toLevel, fn)
	local out, start = {}, nil
	for L = fromLevel, toLevel + 1 do
		local bad = L <= toLevel and fn(L)
		if bad and not start then start = L end
		if not bad and start then out[#out + 1] = {start, L - 1}; start = nil end
	end
	return out
end

-- mean of curve[L].min over `n` levels from L
function M.blockMean(curve, L, n)
	local m = 0
	for i = L, L + n - 1 do m = m + curve[i].min end
	return m / n
end

-- the problems --check reports (a list of strings; empty = smooth)
function M.problems(env)
	local lim = env.cfg.limits
	local out = {}
	-- 1. the stage table: contiguous from level 1, steps of at most stageStep
	local st = env.stages
	if #st == 0 or st[1][1] ~= 1 then out[#out + 1] = "stages: the table does not start at level 1" end
	for i = 2, #st do
		if st[i][1] ~= st[i - 1][2] + 1 then
			out[#out + 1] = string.format("stages: hole or overlap between %d and %d", st[i - 1][2], st[i][1])
		end
		local r = st[i][3] / st[i - 1][3]
		if r > lim.stageStep or r < 1 / lim.stageStep then
			out[#out + 1] = string.format("stages: x%d from level %d is a step of %.0f%% after x%d", st[i][3], st[i][1],
				(r - 1) * 100, st[i - 1][3])
		end
	end
	-- 2. minutes per level: no cliff, no spike
	local curve = M.curve(env, lim.toLevel + lim.long * 2)
	for _, w in ipairs({{lim.short, lim.shortRatio}, {lim.long, lim.longRatio}}) do
		local n, lo, hi = w[1], w[2][1], w[2][2]
		local L = lim.fromLevel
		local prev = M.blockMean(curve, L, n)
		L = L + n
		while L + n - 1 <= lim.toLevel + 1 do
			local m = M.blockMean(curve, L, n)
			local r = m / prev
			if r < lo or r > hi then
				out[#out + 1] = string.format("time per level: levels %d-%d take %.2f min a level, x%.2f of the %d before (limit %.2f-%.2f)",
					L, L + n - 1, m, r, n, lo, hi)
			end
			prev = m
			L = L + n
		end
	end
	-- 3. hunts of the pool and of the hall in reach
	for _, r in ipairs(M.runs(lim.fromLevel, lim.toLevel, function(L) return curve[L].hunts < lim.minPoolHunts end)) do
		out[#out + 1] = string.format("pool: levels %d-%d have fewer than %d hunts in reach", r[1], r[2], lim.minPoolHunts)
	end
	local hall = env.cfg.hall
	for _, r in ipairs(M.runs(lim.fromLevel, lim.toLevel, function(L) return M.hallCount(env.bands, L, hall) < hall.minHunts end)) do
		out[#out + 1] = string.format("hall: levels %d-%d have fewer than %d hall hunts within %.1fx-%.1fx", r[1], r[2],
			hall.minHunts, hall.lo, hall.hi)
	end
	-- the narrow window (O139): in the listed level ranges every level has `minHunts` hall hunts within lo-hi x L
	local tight = hall.tight
	if tight then
		local inside = function(L)
			for _, rg in ipairs(tight.ranges) do
				if L >= rg[1] and L <= rg[2] then return true end
			end
			return false
		end
		for _, r in ipairs(M.runs(lim.fromLevel, lim.toLevel, function(L)
			return inside(L) and M.hallCount(env.bands, L, tight) < tight.minHunts
		end)) do
			out[#out + 1] = string.format("hall: levels %d-%d have fewer than %d hall hunts within %.1fx-%.1fx", r[1], r[2],
				tight.minHunts, tight.lo, tight.hi)
		end
	end
	return out, curve
end

-- the attack and utility spell unlock levels of every vocation (data/spells): {voc = {level, ...}}
function M.unlockLevels()
	local spells = {}
	local function add(voc, name, level)
		spells[voc] = spells[voc] or {}
		spells[voc][name] = level
	end
	local xml = readAll("data/spells/chaos/spells_chaos.xml"):gsub("<!%-%-.-%-%->", "")
	for block in xml:gmatch("<instant.-</instant>") do
		local head = block:match("<instant([^>]*)>")
		local name, level = head:match('name="([^"]+)"'), tonumber(head:match('level="(%d+)"'))
		for voc in block:gmatch('<vocation name="([^"]+)"') do add(voc, name, level) end
	end
	local first = true
	for line in io.lines("data/spells/stock_spells.csv") do
		if first then first = false else
			local f = {}
			for col in (line .. ","):gmatch("([^,]*),") do f[#f + 1] = col end
			for voc in f[#f]:gmatch("[^;]+") do add(voc, f[2], tonumber(f[5])) end
		end
	end
	local out = {}
	for voc, list in pairs(spells) do
		local lv = {}
		for _, l in pairs(list) do lv[#lv + 1] = l end
		table.sort(lv)
		out[voc] = lv
	end
	return out
end

-- the longest stretch below `upTo` without a new spell: {gap, from, to}
function M.longestSpellGap(levels, upTo)
	local best = {0, 0, 0}
	for i = 2, #levels do
		if levels[i] - levels[i - 1] > best[1] and levels[i - 1] < upTo then
			best = {levels[i] - levels[i - 1], levels[i - 1], levels[i]}
		end
	end
	return best
end

-- the longest stretch between two unlocks that starts in [from, to] (the first hour, O241): {gap, from, to}
function M.earlyGap(levels, from, to)
	local best = {0, 0, 0}
	for i = 2, #levels do
		local a, b = levels[i - 1], levels[i]
		if a >= from and a <= to and b - a > best[1] then
			best = {b - a, a, b}
		end
	end
	return best
end

function M.load(opts)
	opts = opts or {}
	ChaosPaceCore = nil
	local P = dofile("data/scripts/chaos/pace_core.lua") or ChaosPaceCore
	local env = {P = P}
	env.pace = dofile("data/scripts/chaos/pace_config.lua")
	env.pool = dofile("data/scripts/chaos/bounty_pool.lua")
	env.cfg = dofile("data/scripts/chaos/progression_config.lua")
	env.stages = M.stagesFromText(readAll(opts.stagesFile or "tools/late_game.py"))
	-- paceKillsPerHour out of tools/spawn_tuning.json (two arrays of {level, kills})
	local js = readAll("tools/spawn_tuning.json")
	local blk = js:match('"paceKillsPerHour"%s*:%s*(%b{})')
	local kph = {}
	for _, key in ipairs({"base", "scaled"}) do
		local arr = blk:match('"' .. key .. '"%s*:%s*(%b[])')
		kph[key] = {}
		for a, b in arr:gmatch("%[%s*(%d+)%s*,%s*(%d+)%s*%]") do
			kph[key][#kph[key] + 1] = {tonumber(a), tonumber(b)}
		end
	end
	env.kph = kph
	env.hunts = M.hunts(P, env.pace, env.pool, kph)
	local plans = {}
	local p = io.popen("ls tools/areaplan/plans/*.json")
	for path in p:lines() do plans[path:match("([^/]+)%.json$")] = readAll(path) end
	p:close()
	env.bands = M.hallBands(readAll("tools/hall_hunts.csv"), plans)
	return env
end

if ChaosProgressionLib then
	return M
end

-- ---------------------------------------------------------------- command line
local mode = arg and arg[1]
local env = M.load()
local problems, curve = M.problems(env)
if mode == "--spells" then
	local names = {}
	local lv = M.unlockLevels()
	for voc in pairs(lv) do names[#names + 1] = voc end
	table.sort(names)
	print("| Class | Spells | Last unlock | Longest stretch without a new spell in levels 8-35 | Longest stretch without a new spell below level 300 | After the last unlock |")
	print("|---|---|---|---|---|---|")
	for _, voc in ipairs(names) do
		local g = M.longestSpellGap(lv[voc], 300)
		local last = lv[voc][#lv[voc]]
		local e = M.earlyGap(lv[voc], 8, 35)
		print(string.format("| %s | %d | %d | %d levels (%d to %d) | %d levels (%d to %d) | %d levels to 2200 |", voc, #lv[voc], last,
			e[1], e[2], e[3], g[1], g[2], g[3], 2200 - last))
	end
	return
end
if mode == "--check" then
	for _, p in ipairs(problems) do print("progression: " .. p) end
	if #problems > 0 then
		os.exit(1)
	end
	print(string.format("progression: smooth (%d stage rows, levels %d-%d, %d hall hunts, %d pool hunts)", #env.stages,
		env.cfg.limits.fromLevel, env.cfg.limits.toLevel, #env.bands, #env.hunts))
	return
end
-- the table
local lim = env.cfg.limits
print("| Levels | Stage | Minutes a level (start - end) | Hours | Pool hunts in reach | Hall hunts in reach |")
print("|---|---|---|---|---|---|")
local cuts = {8, 20, 50, 100, 150, 200, 300, 400, 500, 600, 700, 800, 1000, 1300, 1600, 2000, 2200}
for i = 1, #cuts - 1 do
	local a, b = cuts[i], cuts[i + 1]
	local hmin = math.huge
	for L = a, b - 1 do hmin = math.min(hmin, M.hallCount(env.bands, L, env.cfg.hall)) end
	print(string.format("| %d-%d | x%d to x%d | %.2f - %.2f | %.1f | %d | %d (fewest) |", a, b, M.stage(env.stages, a),
		M.stage(env.stages, b - 1), M.blockMean(curve, a, 5), M.blockMean(curve, b - 5, 5), M.hours(curve, a, b),
		curve[math.floor((a + b) / 2)].hunts, hmin))
end
print(string.format("levels %d to 1000: %.1f hours; to %d: %.1f hours", lim.fromLevel, M.hours(curve, lim.fromLevel, 1000),
	lim.toLevel, M.hours(curve, lim.fromLevel, lim.toLevel)))
for _, p in ipairs(problems) do print("progression: " .. p) end
