-- Greater Rift ladder: the pure part (no engine calls), shared by greater_ladder.lua and tests/greater_rift_test.lua.
-- O668, server/README.md "Greater Rift (O668)". Numbers: rift_config.lua `greater` (ladder, rewards).
--   K.modeOf(players)               "solo" (1 player) or "party" (2-5)
--   K.seasonOf(cfg, tower, now)     season number, its start, its end: the tower's windows (tower.seasonEpoch) of greater.ladder.seasonDays
--   K.merge(row, tier, secs)        the character's row of a (season, mode) after a sealed run: {best_tier, best_time, runs}, improved
--   K.baseline(rows)                the best shown tier of a character in a season over every mode (the personal best reward's start)
--   K.groupOf(groups, voc)          the class group key of a vocation id (groups: [{key, name, ids}])
--   K.rank(rows, staffGroup)        rows {guid, name, voc, tier, time, group} -> sorted list with places (equal tier AND time share one)
--   K.board(rows, groups, mode, key, staffGroup, limit)   the ranked list of one class board (key nil: every class)
--   K.bracketFor(cfg, place, tier)  the season-end bracket row of a place (nil: none)
--   K.awards(cfg, rows, groups)     {guid, mode, place, tier, time, group, bracket} for every character of the season rows
--   K.timeText(secs)                m:ss
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosTowerCore then
	-- next to this file: the season windows are the Infinity Tower's (K.seasonOf)
	local src = debug and debug.getinfo and debug.getinfo(1, "S").source or ""
	local dir = src:sub(1, 1) == "@" and src:sub(2):match("^(.*[/\\])") or "data/scripts/chaos/"
	dofile(dir .. "infinitytower_core.lua")
end

ChaosGreaterCore = ChaosGreaterCore or {}
local K = ChaosGreaterCore

K.MODES = {solo = 0, party = 1}
K.MODE_NAMES = {[0] = "solo", [1] = "party"}

function K.modeOf(players)
	return (tonumber(players) or 1) > 1 and "party" or "solo"
end

function K.seasonOf(cfg, tower, now)
	local TC = ChaosTowerCore
	if not TC then
		return 1, nil, nil
	end
	return TC.seasonOf({seasonEpoch = tower and tower.seasonEpoch, seasonLengthDays = cfg.greater.ladder.seasonDays}, now)
end

-- a result beats another: the higher tier, then the shorter time (nil / 0 tier: nothing yet)
function K.beats(tier, secs, bestTier, bestTime)
	if (bestTier or 0) <= 0 then
		return tier > 0
	end
	if tier ~= bestTier then
		return tier > bestTier
	end
	return secs < (bestTime or 0)
end

function K.merge(row, tier, secs)
	row = row or {best_tier = 0, best_time = 0, runs = 0}
	local out = {best_tier = row.best_tier or 0, best_time = row.best_time or 0, runs = (row.runs or 0) + 1}
	local improved = false
	if K.beats(tier, secs, out.best_tier, out.best_time) then
		out.best_tier, out.best_time = tier, secs
		improved = true
	end
	return out, improved
end

function K.baseline(rows)
	local best = 0
	for _, r in ipairs(rows or {}) do
		if (r.best_tier or 0) > best then
			best = r.best_tier
		end
	end
	return best
end

function K.groupOf(groups, voc)
	for _, g in ipairs(groups or {}) do
		for _, id in ipairs(g.ids or {}) do
			if id == voc then
				return g.key
			end
		end
	end
	return nil
end

local function better(a, b)
	if a.tier ~= b.tier then
		return a.tier > b.tier
	end
	if a.time ~= b.time then
		return a.time < b.time
	end
	return a.guid < b.guid -- equal results share the place; the order among them is only for a stable list
end

function K.rank(rows, staffGroup)
	local list = {}
	for _, r in ipairs(rows or {}) do
		if (r.tier or 0) > 0 and (r.group or 1) < (staffGroup or 4) then
			list[#list + 1] = {guid = r.guid, name = r.name, voc = r.voc, tier = r.tier, time = r.time or 0, group = r.group}
		end
	end
	table.sort(list, better)
	for i, r in ipairs(list) do
		local prev = list[i - 1]
		if prev and prev.tier == r.tier and prev.time == r.time then
			r.place = prev.place
		else
			r.place = i
		end
	end
	return list
end

-- rows of ONE mode; key = a class group key, nil = every class
function K.board(rows, groups, key, staffGroup, limit)
	local pick = {}
	for _, r in ipairs(rows or {}) do
		if not key or K.groupOf(groups, r.voc) == key then
			pick[#pick + 1] = r
		end
	end
	local list = K.rank(pick, staffGroup)
	if limit and #list > limit then
		for i = #list, limit + 1, -1 do
			list[i] = nil
		end
	end
	return list
end

function K.bracketFor(cfg, place, tier)
	for _, b in ipairs(cfg.greater.rewards.brackets) do
		if b.upTo and place <= b.upTo then
			return b
		end
		if b.minTier and (tier or 0) >= b.minTier then
			return b
		end
	end
	return nil
end

-- rows: {guid, name, voc, mode ("solo"/"party"), tier, time, group}; one award per character and mode, from the place on
-- the board of its own class and mode
function K.awards(cfg, rows, groups)
	local staff = cfg.greater.ladder.staffGroup
	local out = {}
	for _, mode in ipairs({"solo", "party"}) do
		local ofMode = {}
		for _, r in ipairs(rows or {}) do
			if r.mode == mode then
				ofMode[#ofMode + 1] = r
			end
		end
		local keys, seen = {}, {}
		for _, r in ipairs(ofMode) do
			local k = K.groupOf(groups, r.voc) or "?"
			if not seen[k] then
				seen[k] = true
				keys[#keys + 1] = k
			end
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local subset = {}
			for _, r in ipairs(ofMode) do
				if (K.groupOf(groups, r.voc) or "?") == k then
					subset[#subset + 1] = r
				end
			end
			for _, r in ipairs(K.rank(subset, staff)) do
				local b = K.bracketFor(cfg, r.place, r.tier)
				if b then
					out[#out + 1] = {guid = r.guid, name = r.name, mode = mode, place = r.place, tier = r.tier, time = r.time,
						group = k, bracket = b}
				end
			end
		end
	end
	return out
end

function K.timeText(secs)
	secs = math.max(0, math.floor(tonumber(secs) or 0))
	return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

return K
