-- Leaderboards: pure logic (no engine calls), shared by leaderboard.lua and server/tests/leaderboard_test.lua.
--   ChaosLeaderboard.week(t, hour)          week key (YYYYMMDD of the Monday) of unix time t; the week starts Monday `hour`
--                                           (the bounty board's rule: ChaosBounty.week)
--   ChaosLeaderboard.weekStart(week, hour)  unix time the week starts; nextReset(t, hour); prevWeek(week, hour)
--   ChaosLeaderboard.merge(e, value, mode, now)   apply one record ("add" or "max") to a score entry
--   ChaosLeaderboard.rank(scores, staffGroup)     sorted list with ranks (value desc, then who got there first, then guid)
--   ChaosLeaderboard.awards(boards, ranked, cfg)  the titles and rewards of a weekly reset
--   ChaosLeaderboard.groupOf(vocId, baseOf, demotion)   base class of a vocation (class ladder)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosBounty or not ChaosBounty.week then
	dofile("data/scripts/chaos/bounty_core.lua")
end

ChaosLeaderboard = ChaosLeaderboard or {}
local LB = ChaosLeaderboard

-- ---------------------------------------------------------------- weeks
function LB.week(t, hour)
	return ChaosBounty.week(t, {rollHour = hour})
end

function LB.weekStart(week, hour)
	local y, m, d = math.floor(week / 10000), math.floor(week / 100) % 100, week % 100
	return os.time({year = y, month = m, day = d, hour = hour, min = 0, sec = 0})
end

function LB.nextReset(t, hour)
	local w = LB.week(t, hour)
	local y, m, d = math.floor(w / 10000), math.floor(w / 100) % 100, w % 100
	return os.time({year = y, month = m, day = d + 7, hour = hour, min = 0, sec = 0})
end

function LB.prevWeek(week, hour)
	return LB.week(LB.weekStart(week, hour) - 3600, hour)
end

-- ---------------------------------------------------------------- records
-- e = {value, count, at} or nil. Returns the entry (new or updated) and whether the value changed.
-- add: value grows by `value`; max: value becomes the best of both. `at` is when the value last changed, so on a tie
-- the player who reached it first ranks higher. count = how many records (kills, contracts, runs) this week.
function LB.merge(e, value, mode, now)
	value = math.floor(tonumber(value) or 0)
	e = e or {value = 0, count = 0, at = now}
	e.count = (e.count or 0) + 1
	local before = e.value or 0
	if mode == "min" then -- lower is better (a fastest kill in seconds); 0 = no value yet
		if value > 0 and (before <= 0 or value < before) then
			e.value = value
		end
	elseif mode == "max" then
		if value > before then
			e.value = value
		end
	else
		if value > 0 then
			e.value = before + value
		end
	end
	local changed = e.value ~= before
	if changed then
		e.at = now
	end
	return e, changed
end

-- ---------------------------------------------------------------- ranking
local function before(a, b)
	if a.value ~= b.value then
		return a.value > b.value
	end
	if (a.at or 0) ~= (b.at or 0) then
		return (a.at or 0) < (b.at or 0)
	end
	return a.guid < b.guid
end
LB.before = before

-- scores = {[guid] = {value, count, at, name, group, ...}} -> array of entries (value > 0, below staffGroup), each
-- with .guid and .rank 1..n. Equal values: the earlier `at` wins, then the lower guid (ranks are never shared).
-- ascending = true: the lowest value first (boards of mode "min", fastest times)
function LB.rank(scores, staffGroup, ascending)
	local list = {}
	for guid, e in pairs(scores) do
		if (e.value or 0) > 0 and (not staffGroup or (e.group or 1) < staffGroup) then
			e.guid = guid
			list[#list + 1] = e
		end
	end
	table.sort(list, ascending and function(a, b)
		if a.value ~= b.value then
			return a.value < b.value
		end
		return before(a, b)
	end or before)
	for i, e in ipairs(list) do
		e.rank = i
	end
	return list
end

-- the entries of a ranked list whose vocation is one of `ids` (a class tab), ranked again 1..n
function LB.filterClass(ranked, ids)
	local set, out = {}, {}
	for _, id in ipairs(ids or {}) do
		set[id] = true
	end
	for _, e in ipairs(ranked) do
		if set[e.voc or -1] then
			out[#out + 1] = {guid = e.guid, name = e.name, value = e.value, count = e.count, at = e.at, voc = e.voc,
				rank = #out + 1}
		end
	end
	return out
end

-- rank of guid in a ranked list, or nil
function LB.find(ranked, guid)
	for _, e in ipairs(ranked) do
		if e.guid == guid then
			return e
		end
	end
	return nil
end

-- ---------------------------------------------------------------- weekly reset
-- boards = cfg.boards; ranked = {[boardKey] = ranked list of the week that ended}
-- -> list of {board, boardName, title, rank, rankName, guid, name, value, items}, board order then rank
function LB.awards(boards, ranked, cfg)
	local out = {}
	for _, b in ipairs(boards) do
		local list = ranked[b.key] or {}
		for i = 1, math.min(cfg.top or 3, #list) do
			local e = list[i]
			local items = {}
			for _, it in ipairs(not b.noReward and (cfg.rewards or {})[i] or {}) do -- noReward: the title only
				items[#items + 1] = {id = it.id, count = it.count}
			end
			out[#out + 1] = {board = b.key, boardName = b.name, title = b.title, rank = i,
				rankName = (cfg.rankNames or {})[i] or ("#" .. i), guid = e.guid, name = e.name, value = e.value,
				items = items}
		end
	end
	return out
end

-- whether a reset is due: the week now is later than the last processed one (never when the clock went back)
function LB.resetDue(lastDone, current)
	return lastDone == nil or current > lastDone
end

-- titles held by one player: awards (of one week) -> {[guid] = {"Bossbane (1st)", ...}}
function LB.titleMap(awards)
	local map = {}
	for _, a in ipairs(awards) do
		map[a.guid] = map[a.guid] or {}
		local list = map[a.guid]
		list[#list + 1] = {title = a.title, rank = a.rank, rankName = a.rankName, board = a.board}
	end
	return map
end

-- look text line for a player's titles, or nil
function LB.lookText(titles, pronoun)
	if not titles or #titles == 0 then
		return nil
	end
	local parts = {}
	for _, t in ipairs(titles) do
		parts[#parts + 1] = string.format("%s (%s)", t.title, t.rankName)
	end
	return string.format("%s holds the title%s %s.", pronoun or "He", #parts > 1 and "s" or "", table.concat(parts, ", "))
end

-- broadcast text of a reset
function LB.broadcastText(boards, awards)
	local parts = {}
	for _, b in ipairs(boards) do
		local names = {}
		for _, a in ipairs(awards) do
			if a.board == b.key then
				names[#names + 1] = a.name
			end
		end
		if #names > 0 then
			parts[#parts + 1] = string.format("%s: %s", b.title, table.concat(names, ", "))
		end
	end
	if #parts == 0 then
		return "A new leaderboard week begins! Nobody placed on last week's boards."
	end
	return "A new leaderboard week begins! Last week's champions - " .. table.concat(parts, "; ") .. "."
end

-- ---------------------------------------------------------------- class ladder
-- base class of a vocation: baseOf[id] if listed, else follow demotion(id) (returns an id or nil/0) down to the base.
function LB.groupOf(vocId, baseOf, demotion)
	if baseOf and baseOf[vocId] then
		return baseOf[vocId]
	end
	local id, guard = vocId, 0
	while demotion and guard < 10 do
		local d = demotion(id)
		if not d or d == 0 or d == id then
			break
		end
		id = d
		guard = guard + 1
	end
	if baseOf and baseOf[id] then
		return baseOf[id]
	end
	return id
end

-- vocation ids (that exist) -> ordered groups {{base = id, ids = {...}}} (bases in id order)
function LB.groups(vocIds, baseOf, demotion)
	local byBase, order = {}, {}
	table.sort(vocIds)
	for _, id in ipairs(vocIds) do
		local base = LB.groupOf(id, baseOf, demotion)
		if not byBase[base] then
			byBase[base] = {base = base, ids = {}}
			order[#order + 1] = base
		end
		table.insert(byBase[base].ids, id)
	end
	table.sort(order)
	local out = {}
	for _, base in ipairs(order) do
		out[#out + 1] = byBase[base]
	end
	return out
end
