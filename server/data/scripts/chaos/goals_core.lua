-- Next Goals: pure logic (no engine calls), shared by goals.lua, server/tests/goals_test.lua and the website wiki
-- generator (server/tools/gen_wiki_data.lua: K.oneIn, K.effortText). The data: goals_config.lua. Overview:
-- server/README.md "Next Goals".
--
--   K.validate(cfg)                 -> list of problem strings
--   K.lang(code)                    -> "en" | "pt"
--   K.text(t, lang)                 a {en, pt} pair (or a plain string) in that language
--   K.bandOf(cfg, level)            -> index, band
--   K.applies(item, systems)        false while the global an item `requires` is missing
--   K.value(ctx, stat)              the current value of a goal's stat
--   K.retro(cfg, ctx)               goals of the bands below the character's own that are done already (no reward)
--   K.evaluate(cfg, ctx)            -> goals done now (marks them in ctx.done)
--   K.reward(cfg, goal, level)      -> {xp, gold, tokens}
--   K.needXp(level)                 the experience from `level` to the next (the engine's formula)
--   K.view(cfg, ctx, lang, resolve) -> the panel's payload
--   K.tracker(cfg, ctx, lang, n)    -> the on-screen tracker's rows
--   K.huntsFor(cfg, level, slack)   the content hunts of a level
--   K.oneIn(p), K.effortText(p, what, lang)   "~1 in 400 legendary kills"
-- ctx = {level, stats = {stat = n}, done = {goalKey = at}, systems = {GlobalName = true}, season = name?, now}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosGoalsCore = ChaosGoalsCore or {}
local K = ChaosGoalsCore

local floor = math.floor

K.WHERE = {window = true, info = true, tasks = true, finder = true, npc = true, temple = true, hunts = true, plan = true,
	room = true}

local function validKey(s)
	return type(s) == "string" and #s > 0 and #s <= 32 and s:match("^[%w_]+$") ~= nil
end

local function pair(t)
	return type(t) == "table" and type(t.en) == "string" and t.en ~= "" and type(t.pt) == "string" and t.pt ~= ""
end

-- ---------------------------------------------------------------- config checks
function K.validate(cfg)
	local problems = {}
	local function bad(fmt, ...)
		problems[#problems + 1] = string.format(fmt, ...)
	end
	if type(cfg) ~= "table" or type(cfg.goals) ~= "table" or type(cfg.bands) ~= "table" then
		return {"config: goals and bands must be tables"}
	end
	local function checkWhere(w, where)
		if w == nil then
			return
		end
		if type(w) ~= "table" or not K.WHERE[w.k] then
			bad("%s: unknown where %s", where, tostring(type(w) == "table" and w.k or w))
		elseif w.k == "window" and not (type(w.m) == "string" and w.m:match("^game_") and type(w.f) == "string") then
			bad("%s: a window needs a game_ module and a function", where)
		elseif (w.k == "npc" and type(w.name) ~= "string") or (w.k == "plan" and type(w.id) ~= "string")
			or (w.k == "info" and type(w.page) ~= "string") or (w.k == "finder" and not tonumber(w.id)) then
			bad("%s: incomplete %s", where, w.k)
		end
	end
	local last = 0
	for i, b in ipairs(cfg.bands) do
		local where = "band " .. tostring(b.key or i)
		if not validKey(b.key) then
			bad("%s: bad key", where)
		end
		if type(b.from) ~= "number" or b.from <= last then
			bad("%s: from must rise", where)
		end
		last = tonumber(b.from) or last
		if not pair(b.name) or not pair(b.text) then
			bad("%s: name and text need en and pt", where)
		end
		if type(b.gear) ~= "table" or #b.gear == 0 then
			bad("%s: no gear path", where)
		end
		for j, g in ipairs(b.gear or {}) do
			if not pair(g.text) then
				bad("%s gear %d: text needs en and pt", where, j)
			end
			checkWhere(g.where, where .. " gear " .. j)
		end
	end
	if cfg.bands[1] and cfg.bands[1].from ~= 1 then
		bad("the first band starts at level 1")
	end
	local keys = {}
	for i, g in ipairs(cfg.goals) do
		local where = "goal " .. tostring(g.key or i)
		if not validKey(g.key) or keys[g.key] then
			bad("%s: key missing or duplicate", where)
		end
		keys[g.key or ""] = true
		if type(g.level) ~= "number" or g.level < 1 then
			bad("%s: level >= 1 needed", where)
		end
		if not validKey(g.stat) then
			bad("%s: bad stat", where)
		end
		if type(g.target) ~= "number" or g.target < 1 then
			bad("%s: target >= 1 needed", where)
		end
		for _, f in ipairs({"title", "why", "effort"}) do
			if not pair(g[f]) then
				bad("%s: %s needs en and pt", where, f)
			end
		end
		checkWhere(g.where, where)
		if g.reward ~= nil and type(g.reward) ~= "table" then
			bad("%s: reward must be a table", where)
		end
	end
	for _, h in ipairs(cfg.hunts or {}) do
		if type(h.id) ~= "string" or type(h.name) ~= "string" or type(h.level) ~= "table"
			or not (tonumber(h.level[1]) and tonumber(h.level[2]) and h.level[1] <= h.level[2]) then
			bad("hunt %s: id, name and level {lo, hi}", tostring(h.id))
		end
	end
	for k, mode in pairs(cfg.own or {}) do
		if not validKey(k) or (mode ~= "add" and mode ~= "max") then
			bad("own stat %s: add or max", tostring(k))
		end
	end
	return problems
end

-- ---------------------------------------------------------------- texts
function K.lang(code)
	if type(code) == "string" and code:lower():sub(1, 2) == "pt" then
		return "pt"
	end
	return "en"
end

function K.text(t, lang)
	if type(t) == "string" then
		return t
	end
	if type(t) ~= "table" then
		return ""
	end
	return t[lang] or t.en or ""
end

-- 1234567 -> "1,234,567"
function K.int(n)
	n = floor((tonumber(n) or 0) + 0.5)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (n < 0 and "-" or "") .. out
end

-- ---------------------------------------------------------------- bands
function K.bandOf(cfg, level)
	level = tonumber(level) or 1
	local idx = 1
	for i, b in ipairs(cfg.bands) do
		if level >= b.from then
			idx = i
		end
	end
	return idx, cfg.bands[idx]
end

-- the band's last level (nil for the last band)
function K.bandTo(cfg, i)
	local nextBand = cfg.bands[i + 1]
	return nextBand and nextBand.from - 1 or nil
end

-- ---------------------------------------------------------------- goals
function K.applies(item, systems)
	if item.requires == nil then
		return true
	end
	return systems ~= nil and systems[item.requires] == true
end

function K.value(ctx, stat)
	if stat == "level" then
		return tonumber(ctx.level) or 0
	end
	return tonumber(ctx.stats and ctx.stats[stat]) or 0
end

local function reached(ctx, g)
	return K.value(ctx, g.stat) >= g.target
end

-- the band index of a goal (its unlock level)
local function bandIndexOf(cfg, g)
	return (K.bandOf(cfg, g.level))
end

-- the first load of a character: the goals of the bands below its own that it has done already are marked done
-- without a reward (an old character is not paid for its whole past at once). Returns the keys.
function K.retro(cfg, ctx)
	ctx.done = ctx.done or {}
	local own = K.bandOf(cfg, ctx.level)
	local out = {}
	for _, g in ipairs(cfg.goals) do
		if not ctx.done[g.key] and K.applies(g, ctx.systems) and bandIndexOf(cfg, g) < own and reached(ctx, g) then
			ctx.done[g.key] = ctx.now or 0
			out[#out + 1] = g.key
		end
	end
	return out
end

-- the goals done now: unlocked (level), applies, at the target, not done before
function K.evaluate(cfg, ctx)
	ctx.done = ctx.done or {}
	local out = {}
	for _, g in ipairs(cfg.goals) do
		if not ctx.done[g.key] and (tonumber(ctx.level) or 0) >= g.level and K.applies(g, ctx.systems) and reached(ctx, g) then
			ctx.done[g.key] = ctx.now or 0
			out[#out + 1] = g
		end
	end
	return out
end

-- the experience from `level` to level + 1 (TFS: ((50 x L^3 - 150 x L^2 + 400 x L) / 3) at L - 1)
function K.needXp(level)
	local x = math.max(0, (tonumber(level) or 1) - 1)
	return 50 * x * x - 50 * x + 100
end

function K.reward(cfg, g, level)
	local r = cfg.reward or {}
	local o = g.reward or {}
	level = math.max(1, tonumber(level) or 1)
	local xpPct = tonumber(o.xpPct) or tonumber(r.xpPct) or 0
	local gold = tonumber(o.gold) or math.max(tonumber(r.goldMin) or 0, floor((tonumber(r.goldPerLevel) or 0) * level))
	local tokens = tonumber(o.tokens)
	if not tokens then
		tokens = tonumber((r.tokens or {})[bandIndexOf(cfg, g)]) or 0
	end
	return {xp = floor(K.needXp(level) * xpPct / 100), gold = floor(gold), tokens = floor(tokens)}
end

-- "4,000 XP, 2,500 gold, 3 tokens" (the panel's short line; goals.lua writes the long one)
function K.rewardShort(rw, lang, withTokens)
	local parts = {}
	if rw.xp > 0 then
		parts[#parts + 1] = K.int(rw.xp) .. " XP"
	end
	if rw.gold > 0 then
		parts[#parts + 1] = K.int(rw.gold) .. (lang == "pt" and " ouro" or " gold")
	end
	if withTokens and rw.tokens > 0 then
		parts[#parts + 1] = rw.tokens .. " tokens"
	end
	return table.concat(parts, ", ")
end

-- ---------------------------------------------------------------- hunts
-- the content hunts whose band holds `level` (or starts at most `slack` above it), lowest first
function K.huntsFor(cfg, level, slack)
	level = tonumber(level) or 1
	slack = tonumber(slack) or 0
	local out = {}
	for _, h in ipairs(cfg.hunts or {}) do
		if h.level[1] <= level + slack and h.level[2] >= level then
			out[#out + 1] = h
		end
	end
	table.sort(out, function(a, b)
		if a.level[1] ~= b.level[1] then
			return a.level[1] < b.level[1]
		end
		return a.id < b.id
	end)
	return out
end

-- ---------------------------------------------------------------- expected effort
-- 1 / p, rounded to a number a player reads at a glance (1-20 exact, then 5s, 10s, 50s, 100s)
function K.oneIn(p)
	p = tonumber(p) or 0
	if p <= 0 then
		return nil
	end
	local n = 1 / p
	if n < 1.5 then
		return 1
	end
	local step = n < 20 and 1 or n < 200 and 5 or n < 1000 and 10 or n < 10000 and 50 or 100
	return math.max(1, floor(n / step + 0.5) * step)
end

local WHAT = {
	en = {kill = "kills", legendary = "legendary kills", boss = "boss kills", run = "runs", chest = "chests"},
	pt = {kill = "abates", legendary = "abates lendários", boss = "chefes derrotados", run = "corridas", chest = "baús"}
}

-- "~1 in 400 legendary kills" / "~1 em 400 abates lendários"; what = kill | legendary | boss | run | chest
function K.effortText(p, what, lang)
	local n = K.oneIn(p)
	if not n then
		return nil
	end
	lang = lang == "pt" and "pt" or "en"
	local w = WHAT[lang][what or "kill"] or WHAT[lang].kill
	return string.format(lang == "pt" and "~1 em %s %s" or "~1 in %s %s", K.int(n), w)
end

-- ---------------------------------------------------------------- the panel
local function wireWhere(w, lang, resolve)
	if type(w) ~= "table" then
		return nil
	end
	local out = {k = w.k, m = w.m, f = w.f, page = w.page, q = w.q, id = w.id}
	if resolve then
		local pos, label = resolve(w)
		if type(pos) == "table" then
			out.pos = {x = pos.x, y = pos.y, z = pos.z}
		end
		out.label = label
	end
	return out
end

local function goalRow(cfg, g, ctx, lang, resolve, state)
	local value = math.min(g.target, K.value(ctx, g.stat))
	local target = g.target
	if g.flag then
		target = 1
		value = value >= g.target and 1 or 0
	end
	if state == "done" then
		value = target
	end
	local rw = K.reward(cfg, g, ctx.level)
	return {key = g.key, level = g.level, state = state, title = K.text(g.title, lang), why = K.text(g.why, lang),
		effort = K.text(g.effort, lang), where = state ~= "locked" and wireWhere(g.where, lang, resolve) or nil,
		progress = value, target = target,
		reward = K.rewardShort(rw, lang, ctx.systems and ctx.systems.ChaosConquest)}
end

-- the payload of the panel:
--   header {level, band = {key, name, text, from, to, index, count}, done, total, next = level of the next band,
--           nextName, season, more = open goals of lower bands not listed}
--   goals    [row]  the open goals of the band, the band's goals done, then the open goals of the bands below
--   upcoming [row]  the next locked goals
--   gear     [{text, where}]  the gear path of the band
--   hunts    [{id, name, lo, hi, where}]  the content hunts of the level
-- row = {key, level, state = open|done|locked, title, why, effort, where, progress, target, reward}
function K.view(cfg, ctx, lang, resolve)
	lang = K.lang(lang)
	ctx.done = ctx.done or {}
	local bi, band = K.bandOf(cfg, ctx.level)
	local level = tonumber(ctx.level) or 1
	local current, below, upcoming, doneHere = {}, {}, {}, {}
	local done, total = 0, 0
	for _, g in ipairs(cfg.goals) do
		if K.applies(g, ctx.systems) then
			local gi = bandIndexOf(cfg, g)
			local isDone = ctx.done[g.key] ~= nil
			if level >= g.level then
				total = total + 1
				if isDone then
					done = done + 1
				end
			end
			if level < g.level then
				upcoming[#upcoming + 1] = g
			elseif gi == bi then
				if isDone then
					doneHere[#doneHere + 1] = g
				else
					current[#current + 1] = g
				end
			elseif not isDone and gi < bi then
				below[#below + 1] = g
			end
		end
	end
	local rows = {}
	for _, g in ipairs(current) do
		rows[#rows + 1] = goalRow(cfg, g, ctx, lang, resolve, "open")
	end
	-- catch-up: the nearest bands first (config order within a band)
	local order = {}
	for i, g in ipairs(below) do
		order[g.key] = i
	end
	table.sort(below, function(x, y)
		local bx, by = bandIndexOf(cfg, x), bandIndexOf(cfg, y)
		if bx ~= by then
			return bx > by
		end
		return order[x.key] < order[y.key]
	end)
	local catchUp = tonumber(cfg.catchUp) or 6
	for i = 1, math.min(#below, catchUp) do
		rows[#rows + 1] = goalRow(cfg, below[i], ctx, lang, resolve, "open")
	end
	for _, g in ipairs(doneHere) do
		rows[#rows + 1] = goalRow(cfg, g, ctx, lang, nil, "done")
	end
	table.sort(upcoming, function(a, b)
		return a.level < b.level
	end)
	local up = {}
	for i = 1, math.min(#upcoming, tonumber(cfg.upcoming) or 3) do
		up[i] = goalRow(cfg, upcoming[i], ctx, lang, nil, "locked")
	end
	local gear = {}
	for _, g in ipairs(band.gear or {}) do
		if K.applies(g, ctx.systems) then
			gear[#gear + 1] = {text = K.text(g.text, lang), where = wireWhere(g.where, lang, resolve)}
		end
	end
	local hunts = {}
	for _, h in ipairs(K.huntsFor(cfg, level, 50)) do
		hunts[#hunts + 1] = {id = h.id, name = h.name, lo = h.level[1], hi = h.level[2],
			where = wireWhere({k = "plan", id = h.id}, lang, resolve)}
	end
	local nextBand = cfg.bands[bi + 1]
	return {
		header = {level = level, done = done, total = total, season = ctx.season,
			band = {key = band.key, name = K.text(band.name, lang), text = K.text(band.text, lang), from = band.from,
				to = K.bandTo(cfg, bi), index = bi, count = #cfg.bands},
			next = nextBand and nextBand.from or nil, nextName = nextBand and K.text(nextBand.name, lang) or nil,
			more = math.max(0, #below - catchUp)},
		goals = rows, upcoming = up, gear = gear, hunts = hunts,
		hereWhere = (#hunts == 0) and wireWhere({k = "hunts"}, lang, resolve) or nil
	}
end

-- the tracker: the first n open goals (the current band first, then the lower bands), {key, title, progress, target}
function K.tracker(cfg, ctx, lang, n)
	local v = K.view(cfg, ctx, lang, nil)
	local out = {}
	for _, r in ipairs(v.goals) do
		if r.state == "open" and #out < (n or 3) then
			out[#out + 1] = {key = r.key, title = r.title, progress = r.progress, target = r.target}
		end
	end
	return out
end

-- ---------------------------------------------------------------- storage rows
-- rows of chaos_goals {entry, value, at} -> done (goal key -> at), stats (own stat -> value)
function K.rowsToState(rows)
	local done, stats = {}, {}
	for _, r in ipairs(rows or {}) do
		local kind, key = tostring(r.entry):match("^([gs]):(.+)$")
		if kind == "g" then
			done[key] = tonumber(r.at) or 0
		elseif kind == "s" then
			stats[key] = tonumber(r.value) or 0
		end
	end
	return done, stats
end

function K.merge(stats, mode, stat, value)
	value = floor(tonumber(value) or 0)
	local old = tonumber(stats[stat]) or 0
	local new
	if mode == "max" then
		new = math.max(old, value)
	else
		if value <= 0 then
			return false
		end
		new = old + value
	end
	if new == old then
		return false
	end
	stats[stat] = new
	return true
end

-- the band a level just entered (oldLevel < band.from <= newLevel): its index, else nil
function K.bandEntered(cfg, oldLevel, newLevel)
	local hit
	for i, b in ipairs(cfg.bands) do
		if i > 1 and (tonumber(oldLevel) or 0) < b.from and (tonumber(newLevel) or 0) >= b.from then
			hit = i
		end
	end
	return hit
end

return K
