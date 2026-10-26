-- Progress metrics, pure logic (metrics.lua, server/README.md "Progress metrics (O253)"; tests/metrics_test.lua).
-- Aggregate counters only: nothing here holds a name, account id, IP or chat of a player.
--   M.eligible(groupId, isTester, cfg)       staff and tester bots are left out of every counter
--   M.bandIndex(level, edges) / M.bandLabel(i, edges) / M.bandOf(level, edges)    "1-5", "6-10", ..., "901+"
--   M.bandCaseSql(column, edges)              SQL CASE expression that gives the band index of a level column
--   M.bucketLabel(value, edges)               the smallest upper limit >= value as a string, or "inf"
--   M.add(state, kind, k1, k2, n, cfg)        in-memory counter (key = kind, k1, k2 joined by a control character); false when dropped (maxKeys)
--   M.flushSql(state, table, escape)          the INSERT ... ON DUPLICATE KEY UPDATE n = n + VALUES(n) and clears state
--   M.setSql(rows, table, escape)             rows written as they are (churn snapshot): n = VALUES(n)
--   M.churnSql(cfg, now, notTesterSql)        one GROUP BY on `players`: band, gone, active (aggregated in SQL)
--   M.churnRows(sqlRows, cfg)                 -> counter rows for the snapshot, every band present
--   M.killerName(kind, name, cfg)             the monster's name, or the label of a player / summon / environment
--   M.areaFor(pos, instanceLabel, spots, cfg) death area label
--   M.milestonesCrossed(old, new, mask, cfg)  -> list of milestones newly reached, new mask
--   M.suppress(n, cfg)                        n, or the text "<5" for 1 to minShown - 1 (the report tool does the same; 0 stays 0)
--   M.sessionMinutes(seconds)                 whole minutes, a session of 0 s counts as 0
-- Table: kind, k1, k2, n. Kinds: death_area (k1 area, k2 band), death_monster (k1 monster, k2 band),
-- session1 (k1 minute bucket), ttl (k1 milestone level, k2 minute bucket), churn (k1 band, k2 gone | active),
-- meta (k1 name, n value: churn_at, churn_days).
-- Lua 5.1 / LuaJIT and 5.3 compatible.

ChaosMetrics = ChaosMetrics or {}
local M = ChaosMetrics
local floor = math.floor

M.KINDS = {"death_area", "death_monster", "session1", "ttl", "churn", "meta"}

function M.createSql(t)
	return "CREATE TABLE IF NOT EXISTS `" .. t .. "` (" ..
		"`kind` varchar(16) NOT NULL, `k1` varchar(64) NOT NULL, `k2` varchar(64) NOT NULL DEFAULT ''," ..
		"`n` bigint(20) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`kind`, `k1`, `k2`)" ..
		") ENGINE=InnoDB DEFAULT CHARSET=utf8"
end

-- ---------------------------------------------------------------- who counts
function M.eligible(groupId, isTester, cfg)
	if isTester then
		return false
	end
	return (tonumber(groupId) or 0) <= ((cfg and cfg.maxGroupId) or 1)
end

-- ---------------------------------------------------------------- bands
function M.bandIndex(level, edges)
	level = floor(tonumber(level) or 1)
	if level < 1 then
		level = 1
	end
	for i, hi in ipairs(edges) do
		if level <= hi then
			return i
		end
	end
	return #edges + 1
end

function M.bandLabel(i, edges)
	if i > #edges then
		return string.format("%d+", edges[#edges] + 1)
	end
	local lo = i == 1 and 1 or edges[i - 1] + 1
	return string.format("%d-%d", lo, edges[i])
end

function M.bandOf(level, edges)
	return M.bandLabel(M.bandIndex(level, edges), edges)
end

-- CASE WHEN `level` <= 5 THEN 1 WHEN ... ELSE n END (numbers from the config only, never from a player)
function M.bandCaseSql(column, edges)
	local parts = {"CASE"}
	for i, hi in ipairs(edges) do
		parts[#parts + 1] = string.format("WHEN %s <= %d THEN %d", column, floor(hi), i)
	end
	parts[#parts + 1] = string.format("ELSE %d END", #edges + 1)
	return table.concat(parts, " ")
end

function M.bucketLabel(value, edges)
	value = tonumber(value) or 0
	for _, hi in ipairs(edges) do
		if value <= hi then
			return tostring(hi)
		end
	end
	return "inf"
end

function M.sessionMinutes(seconds)
	seconds = tonumber(seconds) or 0
	if seconds < 0 then
		return 0
	end
	return floor(seconds / 60)
end

-- small-number suppression: a count behind which fewer than cfg.minShown players could stand is never shown exactly
function M.suppress(n, cfg)
	n = floor(tonumber(n) or 0)
	local min = (cfg and cfg.minShown) or 5
	if n > 0 and n < min then
		return "<" .. min
	end
	return n
end

-- ---------------------------------------------------------------- names
local function clean(s, max)
	s = tostring(s or "")
	s = s:gsub("[%c]", " ")
	if #s > max then
		s = s:sub(1, max)
	end
	return s
end
M.clean = clean

function M.killerName(kind, name, cfg)
	if kind == "player" then
		return cfg.killerPlayer
	elseif kind == "summon" then
		return cfg.killerSummon
	elseif kind == "monster" and type(name) == "string" and name ~= "" then
		return clean(name, cfg.nameMax)
	end
	return cfg.killerOther
end

-- the nearest spot {name, x, y, z} on the same floor within cfg.areaRadius
function M.areaFor(pos, instanceLabel, spots, cfg)
	if type(instanceLabel) == "string" and instanceLabel ~= "" then
		return clean(instanceLabel, cfg.nameMax)
	end
	if type(pos) ~= "table" then
		return string.format(cfg.otherArea, 0)
	end
	local best, bestD
	for _, s in ipairs(spots or {}) do
		if s.z == pos.z then
			local d = math.max(math.abs(s.x - pos.x), math.abs(s.y - pos.y))
			if d <= cfg.areaRadius and (not bestD or d < bestD) then
				best, bestD = s.name, d
			end
		end
	end
	if best then
		return clean(best, cfg.nameMax)
	end
	return string.format(cfg.otherArea, pos.z or 0)
end

-- ---------------------------------------------------------------- counters
local SEP = "\1" -- control characters are cut from every name, so no key holds it

function M.newState()
	return {counts = {}, keys = 0}
end

function M.add(state, kind, k1, k2, n, cfg)
	local key = kind .. SEP .. tostring(k1) .. SEP .. tostring(k2 or "")
	local c = state.counts[key]
	if c then
		state.counts[key] = c + (n or 1)
		return true
	end
	if state.keys >= (cfg and cfg.maxKeys or 4000) then
		return false
	end
	state.counts[key] = n or 1
	state.keys = state.keys + 1
	return true
end

local function split(key)
	local kind, k1, k2 = key:match("^([^\1]*)\1([^\1]*)\1?(.*)$")
	return kind, k1, k2
end

-- sorted rows {kind, k1, k2, n} of a state
function M.rows(state)
	local out = {}
	for key, n in pairs(state.counts) do
		local kind, k1, k2 = split(key)
		out[#out + 1] = {kind = kind, k1 = k1, k2 = k2, n = n}
	end
	table.sort(out, function(a, b)
		if a.kind ~= b.kind then return a.kind < b.kind end
		if a.k1 ~= b.k1 then return a.k1 < b.k1 end
		return a.k2 < b.k2
	end)
	return out
end

local function values(rows, escape)
	local v = {}
	for _, r in ipairs(rows) do
		v[#v + 1] = string.format("(%s, %s, %s, %d)", escape(r.kind), escape(r.k1), escape(r.k2 or ""), floor(r.n))
	end
	return table.concat(v, ", ")
end

-- the add statements (chunks of at most 200 rows); the state is cleared
function M.flushSql(state, t, escape)
	local rows = M.rows(state)
	state.counts, state.keys = {}, 0
	local out = {}
	for i = 1, #rows, 200 do
		local chunk = {}
		for j = i, math.min(i + 199, #rows) do
			chunk[#chunk + 1] = rows[j]
		end
		out[#out + 1] = string.format("INSERT INTO `%s` (`kind`, `k1`, `k2`, `n`) VALUES %s ON DUPLICATE KEY UPDATE `n` = `n` + VALUES(`n`)",
			t, values(chunk, escape))
	end
	return out
end

function M.setSql(rows, t, escape)
	if #rows == 0 then
		return nil
	end
	return string.format("INSERT INTO `%s` (`kind`, `k1`, `k2`, `n`) VALUES %s ON DUPLICATE KEY UPDATE `n` = VALUES(`n`)",
		t, values(rows, escape))
end

-- ---------------------------------------------------------------- churn
-- Gone: last login older than churnDays. Characters that never logged in, staff and testers are left out. The result
-- has one row per band; nothing per player leaves the database.
function M.churnSql(cfg, now, notTesterSql)
	local cutoff = floor(now - cfg.churnDays * 86400)
	return string.format(
		"SELECT %s AS `band`, SUM(`players`.`lastlogin` < %d) AS `gone`, SUM(`players`.`lastlogin` >= %d) AS `active` " ..
		"FROM `players` WHERE `players`.`group_id` <= %d AND `players`.`lastlogin` > 0 AND %s GROUP BY `band`",
		M.bandCaseSql("`players`.`level`", cfg.bands), cutoff, cutoff, cfg.maxGroupId, notTesterSql)
end

function M.churnRows(sqlRows, cfg, now)
	local by = {}
	for _, r in ipairs(sqlRows or {}) do
		by[floor(tonumber(r.band) or 0)] = r
	end
	local out = {}
	for i = 1, #cfg.bands + 1 do
		local label = M.bandLabel(i, cfg.bands)
		local r = by[i] or {}
		out[#out + 1] = {kind = "churn", k1 = label, k2 = "gone", n = floor(tonumber(r.gone) or 0)}
		out[#out + 1] = {kind = "churn", k1 = label, k2 = "active", n = floor(tonumber(r.active) or 0)}
	end
	out[#out + 1] = {kind = "meta", k1 = "churn_at", k2 = "", n = floor(now or 0)}
	out[#out + 1] = {kind = "meta", k1 = "churn_days", k2 = "", n = cfg.churnDays}
	return out
end

-- ---------------------------------------------------------------- time to level
-- mask: bit i set = milestone i of cfg.milestones recorded. Returns the milestones passed by old -> new that were not
-- recorded, and the new mask.
function M.milestonesCrossed(oldLevel, newLevel, mask, cfg)
	mask = floor(tonumber(mask) or 0)
	if mask < 0 then
		mask = 0
	end
	local out = {}
	for i, m in ipairs(cfg.milestones) do
		local bit = 2 ^ (i - 1)
		local set = floor(mask / bit) % 2 == 1
		if not set and (tonumber(newLevel) or 0) >= m then
			if (tonumber(oldLevel) or 0) < m then
				out[#out + 1] = m
			end
			mask = mask + bit
		end
	end
	return out, mask
end

-- at login: every milestone the character is already past counts as recorded (nothing is counted for it)
function M.maskAtLogin(level, mask, cfg)
	local _, m = M.milestonesCrossed(level, level, mask, cfg)
	return m
end
