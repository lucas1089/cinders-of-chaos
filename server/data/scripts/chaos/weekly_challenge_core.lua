-- The Weekly Challenge (O390), pure logic (no engine calls); tests/weekly_challenge_test.lua. Config:
-- weekly_challenge_config.lua; the engine side: weekly_challenge.lua. Overview: server/README.md "The Weekly Challenge
-- (O390)". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--   W.isoWeek(year, month, day)        -> ISO year, ISO week of a date (ISO 8601: weeks start Monday, week 1 holds
--                                         the year's first Thursday)
--   W.weekOf(weekKey)                  -> ISO year, week of a leaderboard week key (YYYYMMDD of its Monday)
--   W.label(isoYear, isoWeek)          -> "2026-W45"
--   W.seed(cfg, isoYear, isoWeek, try) -> the area seed of a week (try 0, 1, ...: the next seeds)
--   W.theme(cfg, seed)                 -> the week's theme entry {key, name}
--   W.areaDef(cfg, base, week)         -> the areagen area of a week: a copy of the base area with the week's seed,
--                                         theme, place, dungeon and boss
--   W.layoutProblems(cfg, model)      -> what makes a valid layout unfit (too few monsters, no boss room)
--   W.boardOf(cfg, size)               -> the board key of a clear by party size
--   W.seconds(ms)                      -> whole seconds of a clear (at least 1)
--   W.entryProblem(built, current)     -> nil, or a reason text: no layout built, or built for another week
--   W.classTop(ranked, groups, n, filter) -> {{key, name, rows = {{rank, guid, name, value}}}} per class group
--   W.awards(cfg, tops)                -> token grants {board, group, groupName, rank, guid, name, value, tokens}
--   W.clock(secs)                      -> "m:ss" / "h:mm:ss"
--   W.discordSections(cfg, tops)       -> {{name = class, value = "Solo: ...\nParty: ..."}} for the Discord post

ChaosWeeklyChallengeCore = ChaosWeeklyChallengeCore or {}
local W = ChaosWeeklyChallengeCore

local floor = math.floor
local MOD = 2147483647

local function int(v)
	local n = tonumber(v)
	if not n or n ~= n then
		return nil
	end
	return floor(n)
end

-- ---------------------------------------------------------------- weeks
-- days from 1970-01-01 of a date (proleptic Gregorian; no os.time, so no time zone and no DST)
local function daysOf(y, m, d)
	y = m <= 2 and y - 1 or y
	local era = floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end
W.daysOf = daysOf

-- the date of a day number (the inverse of daysOf)
local function dateOf(z)
	z = z + 719468
	local era = floor(z / 146097)
	local doe = z - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local mp = floor((5 * doy + 2) / 153)
	local d = doy - floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	return m <= 2 and y + 1 or y, m, d
end

-- ISO 8601 week of a date: the Thursday of its week decides the year
function W.isoWeek(year, month, day)
	local n = daysOf(year, month, day)
	local wday = (n + 3) % 7 + 1 -- 1970-01-01 was a Thursday: Monday = 1 .. Sunday = 7
	local thursday = n + 4 - wday
	local ty = dateOf(thursday)
	local jan1 = daysOf(ty, 1, 1)
	return ty, floor((thursday - jan1) / 7) + 1
end

function W.weekOf(weekKey)
	weekKey = int(weekKey) or 0
	return W.isoWeek(floor(weekKey / 10000), floor(weekKey / 100) % 100, weekKey % 100)
end

function W.label(isoYear, isoWeek)
	return string.format("%d-W%02d", isoYear, isoWeek)
end

-- ---------------------------------------------------------------- seed and area
-- a week's seed: seedBase and the week mixed (an integer hash, the same in every interpreter), in 1 .. MOD - 1
function W.seed(cfg, isoYear, isoWeek, try)
	local h = (int(cfg.seedBase) or 1) % MOD
	for _, v in ipairs({int(isoYear) or 0, int(isoWeek) or 0, int(try) or 0}) do
		h = (h * 31 + v + 7) % MOD
		h = (h * 48271) % MOD
	end
	if h <= 0 then
		h = 1
	end
	return h
end

function W.theme(cfg, seed)
	local list = cfg.themes or {}
	if #list == 0 then
		return nil
	end
	return list[(int(seed) or 0) % #list + 1]
end

local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = copy(x)
	end
	return out
end
W.copy = copy

-- week = {isoYear, isoWeek, try}; base = the areagen area named by cfg.base. -> the area definition (a copy)
function W.areaDef(cfg, base, week)
	if type(base) ~= "table" or type(base.dungeon) ~= "table" then
		return nil
	end
	local def = copy(base)
	def.id = cfg.area.id
	def.origin = copy(cfg.area.origin)
	def.seed = W.seed(cfg, week.isoYear, week.isoWeek, week.try)
	local theme = W.theme(cfg, def.seed)
	if theme then
		def.theme = theme.key
	end
	def.weekly = {label = W.label(week.isoYear, week.isoWeek), theme = theme and theme.name or def.theme,
		seed = def.seed, try = int(week.try) or 0}
	def.name = cfg.area.name
	def.enabled = true
	def.entrance, def.back = nil, nil
	local d = def.dungeon
	d.id = cfg.dungeon.id
	d.party = cfg.dungeon.party
	d.fixedDifficulty = cfg.dungeon.difficulty
	d.title = cfg.dungeon.title
	d.chest = nil
	if def.boss and cfg.boss and cfg.boss.name then
		def.boss.name = cfg.boss.name
	end
	return def
end

-- the problems of a generated layout beyond areagen's own checks (A.validate): too few monsters
function W.layoutProblems(cfg, model)
	local out = {}
	local n = model and model.stats and model.stats.monsters or 0
	if n < (cfg.minMonsters or 0) then
		out[#out + 1] = string.format("%d monsters, fewer than %d", n, cfg.minMonsters)
	end
	if not (model and model.boss) then
		out[#out + 1] = "no boss room"
	end
	return out
end

function W.boardOf(cfg, size)
	if (int(size) or 1) <= 1 then
		return cfg.boards.solo
	end
	return cfg.boards.party
end

function W.seconds(ms)
	local s = math.ceil((tonumber(ms) or 0) / 1000)
	return s < 1 and 1 or s
end

-- built = the leaderboard week key the layout was built for (nil: not built), current = the week key now
function W.entryProblem(built, current)
	if not built then
		return "The Weekly Challenge is closed: its dungeon was not built at this start."
	end
	if built ~= current then
		return "This week's Weekly Challenge opens at the next server save (the dungeon still has last week's layout)."
	end
	return nil
end

-- ---------------------------------------------------------------- the week's end
-- ranked: a ranked board (leaderboard_core.lua LB.rank, entries with voc); groups: {{key, name, ids}} (the class tabs,
-- LB.classGroups); filter(ranked, ids): LB.filterClass. -> per group the first n
function W.classTop(ranked, groups, n, filter)
	local out = {}
	for _, g in ipairs(groups or {}) do
		local rows = {}
		for _, e in ipairs(filter(ranked or {}, g.ids)) do
			if #rows >= n then
				break
			end
			rows[#rows + 1] = {rank = e.rank, guid = e.guid, name = e.name, value = e.value}
		end
		out[#out + 1] = {key = g.key, name = g.name, rows = rows}
	end
	return out
end

-- tops = {{board = key, groups = W.classTop(...)}} in board order -> the token grants
function W.awards(cfg, tops)
	local out = {}
	for _, t in ipairs(tops or {}) do
		for _, g in ipairs(t.groups or {}) do
			for i, r in ipairs(g.rows) do
				local tokens = int((cfg.tokens or {})[i]) or 0
				if i <= (cfg.rewardTop or 3) and tokens > 0 then
					out[#out + 1] = {board = t.board, group = g.key, groupName = g.name, rank = i, guid = r.guid,
						name = r.name, value = r.value, tokens = tokens}
				end
			end
		end
	end
	return out
end

function W.clock(secs)
	secs = floor(tonumber(secs) or 0)
	if secs >= 3600 then
		return string.format("%d:%02d:%02d", floor(secs / 3600), floor(secs % 3600 / 60), secs % 60)
	end
	return string.format("%d:%02d", floor(secs / 60), secs % 60)
end

-- the Discord fields: one per class with a time on any board; tops as for W.awards; names = {[board] = "Solo"}
function W.discordSections(cfg, tops, names)
	local byGroup, order = {}, {}
	for _, t in ipairs(tops or {}) do
		for _, g in ipairs(t.groups or {}) do
			if #g.rows > 0 then
				if not byGroup[g.key] then
					byGroup[g.key] = {name = g.name, lines = {}}
					order[#order + 1] = g.key
				end
				local parts = {}
				for i = 1, math.min(#g.rows, cfg.discordTop or 3) do
					local r = g.rows[i]
					parts[#parts + 1] = string.format("%d. %s %s", i, tostring(r.name), W.clock(r.value))
				end
				local lines = byGroup[g.key].lines
				lines[#lines + 1] = string.format("%s: %s", (names or {})[t.board] or t.board, table.concat(parts, ", "))
			end
		end
	end
	local out = {}
	for _, key in ipairs(order) do
		out[#out + 1] = {name = byGroup[key].name, value = table.concat(byGroup[key].lines, "\n")}
	end
	return out
end

return W
