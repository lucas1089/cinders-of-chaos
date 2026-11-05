-- The weekly class boards without engine calls (O409; weekly_class.lua, tests/weekly_class_test.lua).
-- Lua 5.1 / LuaJIT and Lua 5.3.
--
--   K.add(buf, guid, exp)                  experience gained, kept per character until the next flush
--   K.take(buf, guid)                      the kept amount (0 when none), cleared
--   K.classTop(ranked, groups, n, filter, minValue)   per class tab the first n of a ranked board (value >= minValue)
--   K.awards(cfg, tops)                    the token grants of the week's end
--   K.compact(n)                           "1.23M" / "45.6K" / "812" (the Discord post and the broadcast)
--   K.weekLabel(week)                      "2026-11-02" of a week key 20261102
--   K.discordSections(cfg, tops)           {{name = class, value = "1. A 1.23M\n2. ..."}} for the Discord post
--   K.broadcastText(tops, boardName, lang) the line naming the 1st of every class
--   K.schemaSql(tbl)                       CREATE TABLE IF NOT EXISTS (sql/chaos_weekly_class.sql)

ChaosWeeklyClassCore = ChaosWeeklyClassCore or {}
local K = ChaosWeeklyClassCore

local floor = math.floor

local function num(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return v
end

local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	return select("#", ...) > 0 and string.format(key, ...) or key
end

-- ---------------------------------------------------------------- the experience buffer
function K.add(buf, guid, exp)
	exp = num(exp)
	guid = num(guid)
	if not exp or exp <= 0 or not guid then
		return buf[guid or -1] or 0
	end
	buf[guid] = (buf[guid] or 0) + floor(exp)
	return buf[guid]
end

function K.take(buf, guid)
	local v = buf[guid] or 0
	buf[guid] = nil
	return v
end

-- ---------------------------------------------------------------- the week's end
-- ranked: a ranked board (leaderboard_core.lua LB.rank, entries with voc); groups: {{key, name, ids}} (LB.classGroups);
-- filter(ranked, ids): LB.filterClass. -> per group {key, name, rows = the first n with value >= minValue}
function K.classTop(ranked, groups, n, filter, minValue)
	local out = {}
	for _, g in ipairs(groups or {}) do
		local rows = {}
		for _, e in ipairs(filter(ranked or {}, g.ids)) do
			if #rows >= n then
				break
			end
			if (e.value or 0) >= (minValue or 1) then
				rows[#rows + 1] = {rank = #rows + 1, guid = e.guid, name = e.name, value = e.value}
			end
		end
		out[#out + 1] = {key = g.key, name = g.name, rows = rows}
	end
	return out
end

-- tops = K.classTop(...) -> {{group, groupName, rank, guid, name, value, tokens}}
function K.awards(cfg, tops)
	local out = {}
	for _, g in ipairs(tops or {}) do
		for i, r in ipairs(g.rows or {}) do
			local tokens = floor(num((cfg.tokens or {})[i]) or 0)
			if i <= (cfg.rewardTop or 3) then
				out[#out + 1] = {group = g.key, groupName = g.name, rank = i, guid = r.guid, name = r.name, value = r.value,
					tokens = math.max(0, tokens)}
			end
		end
	end
	return out
end

local function trim(s)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return s
end

function K.compact(n)
	n = num(n) or 0
	local a = math.abs(n)
	if a >= 1e9 then
		return trim(string.format("%.2f", n / 1e9)) .. "B"
	elseif a >= 1e6 then
		return trim(string.format("%.2f", n / 1e6)) .. "M"
	elseif a >= 1e4 then
		return trim(string.format("%.1f", n / 1e3)) .. "K"
	end
	return tostring(floor(n))
end

function K.weekLabel(week)
	week = floor(num(week) or 0)
	return string.format("%04d-%02d-%02d", floor(week / 10000), floor(week / 100) % 100, week % 100)
end

-- one Discord field per class with someone on the podium
function K.discordSections(cfg, tops)
	local out = {}
	for _, g in ipairs(tops or {}) do
		if #(g.rows or {}) > 0 then
			local lines = {}
			for i = 1, math.min(#g.rows, cfg.discordTop or 3) do
				local r = g.rows[i]
				lines[#lines + 1] = string.format("%d. %s %s", i, tostring(r.name), K.compact(r.value))
			end
			out[#out + 1] = {name = tostring(g.name), value = table.concat(lines, "\n")}
		end
	end
	return out
end

function K.broadcastText(tops, boardName, lang)
	local parts = {}
	for _, g in ipairs(tops or {}) do
		local r = (g.rows or {})[1]
		if r then
			parts[#parts + 1] = string.format("%s: %s", tostring(g.name), tostring(r.name))
		end
	end
	if #parts == 0 then
		return nil
	end
	return T(lang, "%s, the best of every class last week - %s.", T(lang, boardName or "Weekly Experience"),
		table.concat(parts, "; "))
end

-- ---------------------------------------------------------------- SQL
function K.schemaSql(tbl)
	return string.format("CREATE TABLE IF NOT EXISTS `%s` (`week` int unsigned NOT NULL, `board` varchar(16) NOT NULL, " ..
		"`class_base` smallint unsigned NOT NULL, `rank` tinyint unsigned NOT NULL, `player_id` int NOT NULL, " ..
		"`value` bigint unsigned NOT NULL DEFAULT 0, `tokens` smallint unsigned NOT NULL DEFAULT 0, " ..
		"`awarded_at` int unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`week`, `board`, `class_base`, `rank`), " ..
		"KEY `player` (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8", tbl)
end

return K
