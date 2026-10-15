-- telemetry_core.lua: the balance telemetry without engine calls (telemetry.lua; tests: server/tests/telemetry_test.lua).
-- Lua 5.1 / LuaJIT and Lua 5.3.
--
-- An hour's numbers are summed in memory (an "acc") and written as one row per bucket when the hour ends. The only
-- per-character data is the guid sets that count distinct characters per bucket and the last hunt counters of each
-- character (the sample deltas); both stay in memory and are dropped at the flush. No row holds an id or a name.
--
--   ChaosTelemetryCore.bandOf(level, bands)              "300-499", "1000+", nil below the first band
--   ChaosTelemetryCore.hourOf(t) / dayOf(t)              start of the UTC hour / day
--   ChaosTelemetryCore.newAcc(hour)                      an empty hour
--   ChaosTelemetryCore.huntDelta(last, cur, maxSecs)     the gain between two samples of the hunt tracker's counters
--   ChaosTelemetryCore.addHunt / addOnline / addBoss / addDeath / addCast / addEconomy   sum into the acc
--   ChaosTelemetryCore.areaOf(pos, instanceLabel, marks, cfg)    the death area's name
--   ChaosTelemetryCore.killerOf(info)                    the killer's label (a monster type; players never named)
--   ChaosTelemetryCore.flushSql(acc, tables, esc)        the INSERT statements of an hour (span 'h')
--   ChaosTelemetryCore.rollupSql(tables, hourlyBefore, dailyBefore)   hourly -> daily rows, the deletes, in a transaction
--   ChaosTelemetryCore.schemaSql(tables)                 CREATE TABLE IF NOT EXISTS of every table (sql/chaos_telemetry.sql)

ChaosTelemetryCore = ChaosTelemetryCore or {}
local K = ChaosTelemetryCore

local floor = math.floor

-- ---------------------------------------------------------------- bands, clocks
function K.bandLabel(b)
	return b[2] and (b[1] .. "-" .. b[2]) or (b[1] .. "+")
end

function K.bandOf(level, bands)
	level = tonumber(level) or 0
	for _, b in ipairs(bands or {}) do
		if level >= b[1] and (not b[2] or level <= b[2]) then
			return K.bandLabel(b)
		end
	end
	return nil
end

function K.hourOf(t)
	t = floor(tonumber(t) or 0)
	return t - t % 3600
end

function K.dayOf(t)
	t = floor(tonumber(t) or 0)
	return t - t % 86400
end

-- ---------------------------------------------------------------- the hour in memory
function K.newAcc(hour)
	return {hour = hour, hunt = {}, online = {}, onlineSamples = 0, boss = {}, deaths = {}, casts = {}, economy = {}}
end

local function bucket(map, key, make)
	local b = map[key]
	if not b then
		b = make()
		map[key] = b
	end
	return b
end

local function count(set)
	local n = 0
	for _ in pairs(set) do
		n = n + 1
	end
	return n
end
K.count = count

-- last / cur: {exp, loot, sup, kills, elapsed} of the hunt tracker's session. A counter that went down was reset by the
-- player (or the session is new): its whole current value is the gain. Hunting seconds: the session clock's advance,
-- at most maxSecs, and only when experience or kills came in.
function K.huntDelta(last, cur, maxSecs)
	local d = {}
	for _, k in ipairs({"exp", "loot", "sup", "kills"}) do
		local c = math.max(0, floor(tonumber(cur[k]) or 0))
		local l = last and floor(tonumber(last[k]) or 0) or nil
		if l == nil then
			d[k] = 0 -- the first sample of a character only sets the base
		elseif c >= l then
			d[k] = c - l
		else
			d[k] = c
		end
	end
	local secs = 0
	if last and (d.exp > 0 or d.kills > 0) then
		local ce, le = tonumber(cur.elapsed) or 0, tonumber(last.elapsed) or 0
		secs = ce >= le and (ce - le) or ce
		secs = math.max(0, math.min(floor(secs), maxSecs or secs))
	end
	d.secs = secs
	return d
end

function K.addHunt(acc, band, voc, guid, d)
	local b = bucket(acc.hunt, band .. "|" .. voc, function()
		return {band = band, voc = voc, players = {}, secs = 0, exp = 0, loot = 0, sup = 0, kills = 0}
	end)
	if d.secs > 0 or d.exp > 0 or d.loot > 0 or d.sup > 0 or d.kills > 0 then
		b.players[guid] = true
	end
	b.secs = b.secs + d.secs
	b.exp = b.exp + d.exp
	b.loot = b.loot + d.loot
	b.sup = b.sup + d.sup
	b.kills = b.kills + d.kills
end

-- list: {{band, voc}} of every counted online character in one sample. Rows per band and class, and band "all" voc 0.
function K.addOnline(acc, list)
	acc.onlineSamples = acc.onlineSamples + 1
	local n = {}
	n["all|0"] = 0
	for _, e in ipairs(list) do
		local key = e.band .. "|" .. e.voc
		n[key] = (n[key] or 0) + 1
		n["all|0"] = n["all|0"] + 1
	end
	for key, c in pairs(n) do
		local band, voc = key:match("^(.-)|(%d+)$")
		local b = bucket(acc.online, key, function()
			return {band = band, voc = tonumber(voc), sum = 0, max = 0}
		end)
		b.sum = b.sum + c
		if c > b.max then
			b.max = c
		end
	end
end

function K.partyOf(n, maxParty)
	n = math.max(1, floor(tonumber(n) or 1))
	return math.min(n, maxParty or n)
end

-- secs nil: a kill without a time
function K.addBoss(acc, boss, party, secs)
	local b = bucket(acc.boss, boss .. "|" .. party, function()
		return {boss = boss, party = party, kills = 0, timed = 0, total = 0, min = 0, max = 0}
	end)
	b.kills = b.kills + 1
	secs = tonumber(secs)
	if secs and secs > 0 then
		secs = floor(secs)
		b.timed = b.timed + 1
		b.total = b.total + secs
		if b.min == 0 or secs < b.min then
			b.min = secs
		end
		if secs > b.max then
			b.max = secs
		end
	end
end

function K.addDeath(acc, band, area, killer)
	local b = bucket(acc.deaths, band .. "|" .. area .. "|" .. killer, function()
		return {band = band, area = area, killer = killer, deaths = 0}
	end)
	b.deaths = b.deaths + 1
end

function K.addCast(acc, voc, spell, guid)
	local b = bucket(acc.casts, voc .. "|" .. spell, function()
		return {voc = voc, spell = spell, casts = 0, players = {}}
	end)
	b.casts = b.casts + 1
	b.players[guid] = true
end

-- flow: "sink" | "faucet"
function K.addEconomy(acc, flow, source, band, gold)
	gold = floor(tonumber(gold) or 0)
	if gold <= 0 then
		return false
	end
	local b = bucket(acc.economy, flow .. "|" .. source .. "|" .. band, function()
		return {flow = flow, source = source, band = band, gold = 0, events = 0}
	end)
	b.gold = b.gold + gold
	b.events = b.events + 1
	return true
end

-- ---------------------------------------------------------------- labels
local function clip(s, n)
	s = tostring(s or "")
	return #s > n and s:sub(1, n) or s
end
K.clip = clip

-- marks: {{k, x, y, z, n}} (data/chaos_poi.lua). The instance label first, then the nearest hunting place in range, then
-- the nearest temple.
function K.areaOf(pos, instanceLabel, marks, cfg)
	if instanceLabel and instanceLabel ~= "" then
		return clip(instanceLabel, 64)
	end
	if not pos then
		return "unknown"
	end
	local range, floors = cfg and cfg.poiRange or 60, cfg and cfg.poiFloors or 3
	local bestHunt, bestHuntD, bestTemple, bestTempleD
	for _, m in ipairs(marks or {}) do
		local dx, dy = math.abs(m.x - pos.x), math.abs(m.y - pos.y)
		local d = math.max(dx, dy)
		if m.k == "hunt" and d <= range and math.abs(m.z - pos.z) <= floors and (not bestHuntD or d < bestHuntD) then
			bestHunt, bestHuntD = m, d
		elseif m.k == "temple" and (not bestTempleD or d < bestTempleD) then
			bestTemple, bestTempleD = m, d
		end
	end
	if bestHunt then
		return clip(bestHunt.n, 64)
	end
	if bestTemple then
		return clip("near " .. tostring(bestTemple.n):gsub("^Temple of ", ""), 64)
	end
	return "wild"
end

-- info: {player = true} for a player or a player's summon, {monster = type name} otherwise, nil for none
function K.killerOf(info)
	if not info then
		return "environment"
	end
	if info.player then
		return "a player"
	end
	return clip(info.monster or "unknown", 64)
end

-- ---------------------------------------------------------------- SQL
-- per table: key columns (name, SQL type), summed columns, and the min / max columns. players: distinct characters of
-- the hour (a daily row holds the sum of its hours: character-hours).
K.SCHEMA = {
	hunt = {keys = {{"band", "varchar(12)"}, {"voc", "smallint"}},
		sums = {"players", "hunt_seconds", "exp", "loot", "supplies", "kills"}},
	online = {keys = {{"band", "varchar(12)"}, {"voc", "smallint"}}, sums = {"samples", "online_sum"}, max = {"online_max"}},
	boss = {keys = {{"boss", "varchar(64)"}, {"party", "tinyint"}}, sums = {"kills", "timed", "secs_total"},
		min = {"secs_min"}, max = {"secs_max"}},
	deaths = {keys = {{"band", "varchar(12)"}, {"area", "varchar(64)"}, {"killer", "varchar(64)"}}, sums = {"deaths"}},
	casts = {keys = {{"voc", "smallint"}, {"spell", "varchar(64)"}}, sums = {"casts", "players"}},
	economy = {keys = {{"flow", "varchar(8)"}, {"source", "varchar(32)"}, {"band", "varchar(12)"}},
		sums = {"gold", "events"}}
}
K.ORDER = {"hunt", "online", "boss", "deaths", "casts", "economy"}

local function cols(s)
	local out = {}
	for _, k in ipairs(s.keys) do
		out[#out + 1] = k[1]
	end
	for _, list in ipairs({s.sums, s.min or {}, s.max or {}}) do
		for _, c in ipairs(list) do
			out[#out + 1] = c
		end
	end
	return out
end

function K.schemaSql(tables)
	local out = {}
	for _, name in ipairs(K.ORDER) do
		local s = K.SCHEMA[name]
		local defs, keyNames = {"`span` char(1) NOT NULL", "`at` int unsigned NOT NULL"}, {"`span`", "`at`"}
		for _, k in ipairs(s.keys) do
			local default = k[2]:find("char", 1, true) and "''" or "0"
			defs[#defs + 1] = string.format("`%s` %s NOT NULL DEFAULT %s", k[1], k[2], default)
			keyNames[#keyNames + 1] = "`" .. k[1] .. "`"
		end
		for _, list in ipairs({s.sums, s.min or {}, s.max or {}}) do
			for _, c in ipairs(list) do
				defs[#defs + 1] = string.format("`%s` bigint NOT NULL DEFAULT 0", c)
			end
		end
		out[#out + 1] = string.format("CREATE TABLE IF NOT EXISTS `%s` (%s, PRIMARY KEY (%s), KEY `at` (`at`)) " ..
			"ENGINE=InnoDB DEFAULT CHARSET=utf8mb4", tables[name], table.concat(defs, ", "), table.concat(keyNames, ", "))
	end
	return out
end

-- ON DUPLICATE KEY UPDATE: min / max first (they compare with the old `timed`), then the sums
local function updateClause(s)
	local parts = {}
	for _, c in ipairs(s.min or {}) do
		parts[#parts + 1] = string.format("`%s` = IF(VALUES(`%s`) = 0, `%s`, IF(`%s` = 0, VALUES(`%s`), LEAST(`%s`, VALUES(`%s`))))",
			c, c, c, c, c, c, c)
	end
	for _, c in ipairs(s.max or {}) do
		parts[#parts + 1] = string.format("`%s` = GREATEST(`%s`, VALUES(`%s`))", c, c, c)
	end
	for _, c in ipairs(s.sums) do
		parts[#parts + 1] = string.format("`%s` = `%s` + VALUES(`%s`)", c, c, c)
	end
	return table.concat(parts, ", ")
end

local function rowsOf(name, acc)
	local rows = {}
	if name == "hunt" then
		for _, b in pairs(acc.hunt) do
			if b.secs > 0 or b.exp > 0 or b.loot > 0 or b.sup > 0 or b.kills > 0 then
				rows[#rows + 1] = {b.band, b.voc, count(b.players), b.secs, b.exp, b.loot, b.sup, b.kills}
			end
		end
	elseif name == "online" then
		for _, b in pairs(acc.online) do
			rows[#rows + 1] = {b.band, b.voc, acc.onlineSamples, b.sum, b.max}
		end
	elseif name == "boss" then
		for _, b in pairs(acc.boss) do
			rows[#rows + 1] = {b.boss, b.party, b.kills, b.timed, b.total, b.min, b.max}
		end
	elseif name == "deaths" then
		for _, b in pairs(acc.deaths) do
			rows[#rows + 1] = {b.band, b.area, b.killer, b.deaths}
		end
	elseif name == "casts" then
		for _, b in pairs(acc.casts) do
			rows[#rows + 1] = {b.voc, b.spell, b.casts, count(b.players)}
		end
	elseif name == "economy" then
		for _, b in pairs(acc.economy) do
			rows[#rows + 1] = {b.flow, b.source, b.band, b.gold, b.events}
		end
	end
	-- a stable order (tests, and the same statement for the same hour)
	table.sort(rows, function(a, b)
		for i = 1, #a do
			if a[i] ~= b[i] then
				if type(a[i]) ~= type(b[i]) then
					return tostring(a[i]) < tostring(b[i])
				end
				return a[i] < b[i]
			end
		end
		return false
	end)
	return rows
end
K.rowsOf = rowsOf

-- one INSERT per table with rows (span 'h', at = acc.hour); esc(s) quotes a string for SQL
function K.flushSql(acc, tables, esc, maxRows)
	local out = {}
	maxRows = maxRows or 200
	for _, name in ipairs(K.ORDER) do
		local s = K.SCHEMA[name]
		local rows = rowsOf(name, acc)
		local names = {"`span`", "`at`"}
		for _, c in ipairs(cols(s)) do
			names[#names + 1] = "`" .. c .. "`"
		end
		for first = 1, #rows, maxRows do
			local values = {}
			for i = first, math.min(#rows, first + maxRows - 1) do
				local v = {"'h'", tostring(floor(acc.hour))}
				for _, x in ipairs(rows[i]) do
					v[#v + 1] = type(x) == "number" and string.format("%d", x) or esc(x)
				end
				values[#values + 1] = "(" .. table.concat(v, ", ") .. ")"
			end
			out[#out + 1] = string.format("INSERT INTO `%s` (%s) VALUES %s ON DUPLICATE KEY UPDATE %s", tables[name],
				table.concat(names, ", "), table.concat(values, ", "), updateClause(s))
		end
	end
	return out
end

-- hourly rows before hourlyBefore (a day start) -> one daily row per day and bucket; daily rows before dailyBefore are
-- deleted. One transaction: a crash between the copy and the delete cannot count a day twice.
function K.rollupSql(tables, hourlyBefore, dailyBefore)
	local out = {"START TRANSACTION"}
	hourlyBefore, dailyBefore = floor(hourlyBefore), floor(dailyBefore)
	for _, name in ipairs(K.ORDER) do
		local s = K.SCHEMA[name]
		local t = tables[name]
		local keys, sel, names = {}, {}, {"`span`", "`at`"}
		for _, k in ipairs(s.keys) do
			keys[#keys + 1] = "`" .. k[1] .. "`"
			sel[#sel + 1] = "`" .. k[1] .. "`"
			names[#names + 1] = "`" .. k[1] .. "`"
		end
		for _, c in ipairs(s.sums) do
			sel[#sel + 1] = string.format("SUM(`%s`)", c)
			names[#names + 1] = "`" .. c .. "`"
		end
		for _, c in ipairs(s.min or {}) do
			sel[#sel + 1] = string.format("COALESCE(MIN(NULLIF(`%s`, 0)), 0)", c)
			names[#names + 1] = "`" .. c .. "`"
		end
		for _, c in ipairs(s.max or {}) do
			sel[#sel + 1] = string.format("MAX(`%s`)", c)
			names[#names + 1] = "`" .. c .. "`"
		end
		out[#out + 1] = string.format("INSERT INTO `%s` (%s) SELECT 'd', `at` - `at` %% 86400 AS `day`, %s FROM `%s` " ..
			"WHERE `span` = 'h' AND `at` < %d GROUP BY `day`, %s ON DUPLICATE KEY UPDATE %s", t, table.concat(names, ", "),
			table.concat(sel, ", "), t, hourlyBefore, table.concat(keys, ", "), updateClause(s))
		out[#out + 1] = string.format("DELETE FROM `%s` WHERE `span` = 'h' AND `at` < %d", t, hourlyBefore)
		out[#out + 1] = string.format("DELETE FROM `%s` WHERE `span` = 'd' AND `at` < %d", t, dailyBefore)
	end
	out[#out + 1] = "COMMIT"
	return out
end

return K
