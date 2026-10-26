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
-- O258 funnel (server/README.md "Funnel metrics (O258)"):
--   M.dayNumber(t, offset) / M.dayString(day)  whole days since the epoch in server time / "YYYYMMDD"
--   M.returnCheck(stored, today, cfg)          -> list of "d1" / "d3" / "d7" newly due, new stored value, cohort day
--   M.returnStart(today)                       the stored value of a first login
--   M.firstUseMark(mask, key, cfg)             -> true and the new mask when the system's bit was not set; false, mask
--   M.playedBucket(minutes, cfg)               the played-minutes bucket label of a first use
--   M.stopSql(cfg, now, notTesterSql) / M.stopRows(sqlRows, spots, cfg)   where the gone characters stood, by area and band
--   M.setSqlChunks(rows, table, escape)        setSql in chunks of at most 200 rows
--   M.stableId(id)                             the number stored for a hunt place (hash of its id string, 1 .. 1073741789)
--   M.spotFor(pos, spots, cfg)                 the nearest hunt spot within cfg.areaRadius on the floor, or nil
--   M.huntMark(session, pos, now, spots, cfg)  -> the new stored hunt id when a kill changed it (throttled), else nil
-- Table: kind, k1, k2, n. Kinds: death_area (k1 area, k2 band), death_monster (k1 monster, k2 band),
-- session1 (k1 minute bucket), ttl (k1 milestone level, k2 minute bucket), churn (k1 band, k2 gone | active),
-- meta (k1 name, n value: churn_at, churn_days), cohort (k1 YYYYMMDD of a first login), return (k1 d1 | d3 | d7,
-- k2 YYYYMMDD of the cohort day), first (k1 system, k2 "band|played-minutes bucket"), stop (k1 area, k2 band: gone
-- characters, a snapshot).
-- Lua 5.1 / LuaJIT and 5.3 compatible.

ChaosMetrics = ChaosMetrics or {}
local M = ChaosMetrics
local floor = math.floor

M.KINDS = {"death_area", "death_monster", "session1", "ttl", "churn", "meta", "cohort", "return", "first", "stop"}

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
function M.spotFor(pos, spots, cfg)
	if type(pos) ~= "table" then
		return nil
	end
	local best, bestD
	for _, s in ipairs(spots or {}) do
		if s.z == pos.z then
			local d = math.max(math.abs(s.x - pos.x), math.abs(s.y - pos.y))
			if d <= cfg.areaRadius and (not bestD or d < bestD) then
				best, bestD = s, d
			end
		end
	end
	return best
end

function M.areaFor(pos, instanceLabel, spots, cfg)
	if type(instanceLabel) == "string" and instanceLabel ~= "" then
		return clean(instanceLabel, cfg.nameMax)
	end
	if type(pos) ~= "table" then
		return string.format(cfg.otherArea, 0)
	end
	local best = M.spotFor(pos, spots, cfg)
	if best then
		return clean(best.name, cfg.nameMax)
	end
	return string.format(cfg.otherArea, pos.z or 0)
end

-- O258 last hunt: a stable number for a hunt place. The index in the places file shifts when the installer places a
-- new plan (plans are ordered by level band), so the id string of the place is hashed instead: h = h * 33 + byte
-- modulo a prime below 2^30 (exact in doubles, the same in Lua 5.3 and LuaJIT, fits the int32 of a storage value).
function M.stableId(id)
	local h = 5381
	for i = 1, #tostring(id) do
		h = (h * 33 + tostring(id):byte(i)) % 1073741789
	end
	return h + 1
end

-- a kill at `pos`: the id to store when the character stands in a hunt and it differs from session.hunt (the cached
-- value); the check runs at most once per cfg.huntSeconds. Sets session.hunt and session.huntAt.
function M.huntMark(session, pos, now, spots, cfg)
	if type(session) ~= "table" or (session.huntAt and now - session.huntAt < cfg.huntSeconds) then
		return nil
	end
	session.huntAt = now
	local spot = M.spotFor(pos, spots, cfg)
	if not spot or not spot.sid or spot.sid == session.hunt then
		return nil
	end
	session.hunt = spot.sid
	return spot.sid
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

-- ---------------------------------------------------------------- O258: return
-- whole days since the epoch of unix time t, in the server's time (offset = seconds east of UTC)
function M.dayNumber(t, offset)
	return floor(((tonumber(t) or 0) + (tonumber(offset) or 0)) / 86400)
end

-- "YYYYMMDD" of a day number (proleptic Gregorian, civil-from-days)
function M.dayString(day)
	local z = floor(tonumber(day) or 0) + 719468
	local era = floor(z / 146097)
	local doe = z - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local mp = floor((5 * doy + 2) / 153)
	local d = doy - floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	if m <= 2 then
		y = y + 1
	end
	return string.format("%04d%02d%02d", y, m, d)
end

-- the value stored at a character's first login: day * 8, no flag set
function M.returnStart(today)
	return floor(today) * 8
end

-- stored = day * 8 + flags (bit i = cfg.returnDays[i] counted). A login on day >= first + N with the flag clear counts
-- "dN" once. Nothing stored (<= 0): a character from before the install, nothing counted.
function M.returnCheck(stored, today, cfg)
	stored = floor(tonumber(stored) or 0)
	if stored <= 0 then
		return {}, stored, nil
	end
	local cohort = floor(stored / 8)
	local flags = stored % 8
	local due = {}
	for i, n in ipairs(cfg.returnDays) do
		local bit = 2 ^ (i - 1)
		if floor(flags / bit) % 2 == 0 and today >= cohort + n then
			due[#due + 1] = "d" .. n
			flags = flags + bit
		end
	end
	return due, cohort * 8 + flags, cohort
end

-- ---------------------------------------------------------------- O258: first use of a system
function M.firstUseMark(mask, key, cfg)
	mask = floor(tonumber(mask) or 0)
	if mask < 0 then
		mask = 0
	end
	for i, k in ipairs(cfg.systems) do
		if k == key then
			local bit = 2 ^ (i - 1)
			if floor(mask / bit) % 2 == 1 then
				return false, mask
			end
			return true, mask + bit
		end
	end
	return false, mask
end

function M.playedBucket(minutes, cfg)
	return M.bucketLabel(minutes, cfg.timeBuckets)
end

-- ---------------------------------------------------------------- O258: where they stop
-- Gone characters (last login older than churnDays) grouped by level band and by a cell of cfg.stopCell tiles of the
-- last position, or by the last hunt the character was seen in (storage cfg.huntStorage). The answer is rows of (band, floor, cell, count): no row belongs to a character.
function M.stopSql(cfg, now, notTesterSql)
	local cutoff = floor(now - cfg.churnDays * 86400)
	local cell = floor(cfg.stopCell)
	-- sid: the last hunt (player storage cfg.huntStorage), 0 when the character has none; then the cell of the last
	-- position (pz / cx / cy are 0 for a character with a hunt, so the groups stay few)
	local has = string.format("`ps`.`value` > 0")
	return string.format(
		"SELECT %s AS `band`, IF(%s, `ps`.`value`, 0) AS `sid`, IF(%s, 0, `players`.`posz`) AS `pz`, " ..
		"IF(%s, 0, FLOOR(`players`.`posx` / %d)) AS `cx`, IF(%s, 0, FLOOR(`players`.`posy` / %d)) AS `cy`, " ..
		"COUNT(*) AS `gone` FROM `players` LEFT JOIN `player_storage` AS `ps` ON `ps`.`player_id` = `players`.`id` AND " ..
		"`ps`.`key` = %d WHERE `players`.`group_id` <= %d AND `players`.`lastlogin` > 0 AND " ..
		"`players`.`lastlogin` < %d AND %s GROUP BY `band`, `sid`, `pz`, `cx`, `cy`",
		M.bandCaseSql("`players`.`level`", cfg.bands), has, has, has, cell, has, cell, cfg.huntStorage,
		cfg.maxGroupId, cutoff, notTesterSql)
end

function M.stopRows(sqlRows, spots, cfg)
	local sum, order = {}, {}
	local cell = floor(cfg.stopCell)
	for _, r in ipairs(sqlRows or {}) do
		local n = floor(tonumber(r.gone) or 0)
		if n > 0 then
			local sid = floor(tonumber(r.sid) or 0)
			local area
			if sid > 0 then
				area = cfg.removedArea
				for _, sp in ipairs(spots or {}) do
					if sp.sid == sid then
						area = clean(sp.name, cfg.nameMax)
						break
					end
				end
			else
				local pos = {x = floor(tonumber(r.cx) or 0) * cell + floor(cell / 2),
					y = floor(tonumber(r.cy) or 0) * cell + floor(cell / 2), z = floor(tonumber(r.pz) or 0)}
				area = M.areaFor(pos, nil, spots, cfg)
			end
			local band = M.bandLabel(floor(tonumber(r.band) or 1), cfg.bands)
			local key = area .. SEP .. band
			if not sum[key] then
				sum[key] = {kind = "stop", k1 = area, k2 = band, n = 0}
				order[#order + 1] = key
			end
			sum[key].n = sum[key].n + n
		end
	end
	local out = {}
	for _, key in ipairs(order) do
		out[#out + 1] = sum[key]
	end
	table.sort(out, function(a, b)
		if a.k1 ~= b.k1 then return a.k1 < b.k1 end
		return a.k2 < b.k2
	end)
	return out
end

function M.setSqlChunks(rows, t, escape)
	local out = {}
	for i = 1, #rows, 200 do
		local chunk = {}
		for j = i, math.min(i + 199, #rows) do
			chunk[#chunk + 1] = rows[j]
		end
		out[#out + 1] = M.setSql(chunk, t, escape)
	end
	return out
end
