-- Run from the server/ folder: luajit tests/weekly_class_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The weekly class boards (O409): weekly_class_core.lua (the experience buffer, the class tops, token grants, the number
-- text, the Discord fields, the broadcast), the board in leaderboard_config.lua (class tabs, no overall title), the class
-- tabs of every weekly board (LB.hasClassTabs) and LB.awards skipping a classAwards board, the Discord kind on both ends
-- (discord_core.lua, discord_lib.php), the table's SQL file against the core, and weekly_class.lua against a mocked
-- engine (experience from monsters only, the flush, the week's end: tokens, podium rows, broadcast, Discord, no second
-- payment of the same week).
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function read(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/scripts/chaos/weekly_class_core.lua")
dofile("data/scripts/chaos/leaderboard_core.lua")
local K = ChaosWeeklyClassCore
local LB = ChaosLeaderboard
local cfg = dofile("data/scripts/chaos/weekly_class_config.lua")
local lbc = dofile("data/scripts/chaos/leaderboard_config.lua")

-- ====================================================================== the board
local board
for _, b in ipairs(lbc.boards) do
	if b.key == cfg.board then
		board = b
	end
end
ok(board ~= nil, "the board is in leaderboard_config.lua")
eq(board.mode, "add", "experience adds up")
eq(board.classAwards, true, "ranked per class at the reset")
eq(board.noReward, true, "no overall orbs")
ok(#board.key <= 16, "the key fits chaos_leaderboard.board")
eq(LB.hasClassTabs(lbc, board), true, "class tabs")
-- every weekly board has class tabs, but the guild and gathering ones
local tabs, none = 0, {}
for _, b in ipairs(lbc.boards) do
	if LB.hasClassTabs(lbc, b) then
		tabs = tabs + 1
	else
		none[#none + 1] = b.key
	end
end
table.sort(none)
eq(table.concat(none, ","), "factions,professions,siege", "boards without class tabs")
eq(tabs, #lbc.boards - 3, "the other boards have them")
eq(LB.hasClassTabs({}, {key = "x"}), false, "no classTabs switch: only byClass boards")
eq(LB.hasClassTabs({}, {key = "x", byClass = true}), true, "byClass always")
-- LB.awards gives a classAwards board nothing (no overall title, no orbs)
do
	local scores = {[1] = {value = 500, at = 1, name = "A", group = 1, voc = 4}}
	local awards = LB.awards({board}, {[board.key] = LB.rank(scores, 4)}, lbc)
	eq(#awards, 0, "no overall award")
end

-- ====================================================================== the buffer
local buf = {}
eq(K.add(buf, 10, 150.7), 150, "kept, whole numbers")
eq(K.add(buf, 10, 50), 200, "adds up")
eq(K.add(buf, 10, -5), 200, "a loss is not counted")
eq(K.add(buf, 10, 0 / 0), 200, "nan ignored")
eq(K.add(buf, 11, 1 / 0), 0, "inf ignored")
eq(K.take(buf, 10), 200, "taken")
eq(K.take(buf, 10), 0, "cleared")
eq(next(buf), nil, "empty")

-- ====================================================================== class tops and awards
local groups = {{key = 4, name = "Warrior", ids = {4, 8, 14}}, {key = 3, name = "Ranger", ids = {3, 7, 15}},
	{key = 1, name = "Mystic", ids = {1, 5, 10}}}
local scores = {
	[1] = {value = 9000000, at = 5, name = "Ana", group = 1, voc = 8},
	[2] = {value = 8000000, at = 5, name = "Bo", group = 1, voc = 4},
	[3] = {value = 7000000, at = 5, name = "Cy", group = 1, voc = 14},
	[4] = {value = 6000000, at = 5, name = "Di", group = 1, voc = 4},
	[5] = {value = 400, at = 5, name = "Ed", group = 1, voc = 3}, -- below minValue
	[6] = {value = 3500000, at = 5, name = "Fy", group = 1, voc = 7},
	[7] = {value = 99999999, at = 5, name = "GM", group = 5, voc = 4} -- staff
}
local ranked = LB.rank(scores, 4)
local tops = K.classTop(ranked, groups, 3, LB.filterClass, cfg.minValue)
eq(#tops, 3, "a top per class")
eq(#tops[1].rows, 3, "warrior: 3")
eq(tops[1].rows[1].name, "Ana", "warrior 1st")
eq(tops[1].rows[3].name, "Cy", "warrior 3rd")
eq(#tops[2].rows, 1, "ranger: one above the minimum")
eq(tops[2].rows[1].name, "Fy", "ranger 1st")
eq(#tops[3].rows, 0, "mystic: none")
local awards = K.awards(cfg, tops)
eq(#awards, 4, "4 rewarded")
eq(awards[1].tokens, cfg.tokens[1], "1st tokens")
eq(awards[3].tokens, cfg.tokens[3], "3rd tokens")
eq(awards[4].group, 3, "ranger's group key")
eq(awards[4].rank, 1, "ranger's rank")
eq(awards[4].tokens, cfg.tokens[1], "the 1st of a small class gets the 1st's tokens: fair per class")
-- the economy: at most 60 tokens a week for one character, the same as the Weekly Challenge's class rewards
local sum = 0
for i = 1, cfg.rewardTop do
	sum = sum + (cfg.tokens[i] or 0)
end
ok(cfg.tokens[1] <= 60 and sum <= 60, "token amounts stay small")

-- ====================================================================== texts
eq(K.compact(812), "812", "small number")
eq(K.compact(45600), "45.6K", "thousands")
eq(K.compact(1230000), "1.23M", "millions")
eq(K.compact(2000000), "2M", "trailing zeros dropped")
eq(K.compact(3450000000), "3.45B", "billions")
eq(K.weekLabel(20261102), "2026-11-02", "week label")
local sections = K.discordSections(cfg, tops)
eq(#sections, 2, "a field per class with a podium")
eq(sections[1].name, "Warrior", "field name")
eq(sections[1].value, "1. Ana 9M\n2. Bo 8M\n3. Cy 7M", "field text")
local line = K.broadcastText(tops, "Weekly Experience", "en")
eq(line, "Weekly Experience, the best of every class last week - Warrior: Ana; Ranger: Fy.", "broadcast")
eq(K.broadcastText(K.classTop({}, groups, 3, LB.filterClass), "X", "en"), nil, "nobody: no broadcast")

-- ====================================================================== Discord
dofile("data/scripts/chaos/discord_config.lua")
dofile("data/scripts/chaos/discord_core.lua")
local D, dc = ChaosDiscordCore, ChaosDiscordConfig
eq(dc.events.weekly_class, true, "the Discord event is on")
eq(dc.channels.weekly_class, "records", "its channel")
local ev = D.weeklyClass(dc, "2026-11-02", "Weekly Experience", sections)
eq(ev.kind, "weekly_class", "kind")
eq(#ev.fields, 2, "fields")
ok(ev.title:find("2026-11-02", 1, true) ~= nil, "title names the week")
ok(D.weeklyClass(dc, "2026-11-02", "X", {}).text:find("Nobody", 1, true) ~= nil, "an empty week")
local php = read("../website/overlay/plugins/chaos/discord_lib.php")
ok(php:find("'weekly_class'", 1, true) ~= nil and php:find("'weekly_class' => 0x", 1, true) ~= nil,
	"the worker knows the kind and its colour")

-- ====================================================================== SQL
local sql = read("sql/chaos_weekly_class.sql")
ok(sql:find(K.schemaSql(cfg.table) .. ";", 1, true) ~= nil, "sql/chaos_weekly_class.sql = schemaSql")
ok(cfg.table:match("^chaos_weekly_class_") ~= nil, "the reserved table prefix")

-- ====================================================================== weekly_class.lua, mocked engine
do
	local function stub()
		return setmetatable({}, {__index = function() return function() end end})
	end
	local events = {}
	local function named(kind)
		return function(name)
			local o = setmetatable({}, {__index = function() return function() end end})
			events[name or kind] = o
			return o
		end
	end
	TalkAction = function() return stub() end
	GlobalEvent = named("global")
	CreatureEvent = named("creature")
	local cb
	EventCallback = setmetatable({}, {__index = function() return function() end end})
	MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR = 1, 2
	local queries, broadcasts, granted, queued, records = {}, {}, {}, {}, {}
	local paidRows = 0
	db = {query = function(q)
		queries[#queries + 1] = q
		if q:find("INSERT IGNORE", 1, true) then
			paidRows = paidRows + 1
		end
		return true
	end, asyncQuery = function(q) queries[#queries + 1] = q end, escapeString = function(s) return "'" .. s .. "'" end,
		storeQuery = function(q) return q:find("COUNT", 1, true) and 1 or nil end}
	result = {getNumber = function() return paidRows end, free = function() end}
	Chaos = {leaderboardConfig = lbc, staffCommand = function() return true end,
		t = function(_, s, ...) return select("#", ...) > 0 and string.format(s, ...) or s end,
		broadcast = function(_, fn) broadcasts[#broadcasts + 1] = fn("en") end}
	LB.classGroups = function() return groups end
	local hooks = {}
	LB.onReset = function(fn) hooks[#hooks + 1] = fn end
	LB.record = function(boardKey, who, value, mode)
		records[#records + 1] = {board = boardKey, value = value, mode = mode}
		return {value = value}
	end
	ChaosConquest = {grantGuid = function(guid, n, src)
		granted[#granted + 1] = {guid = guid, n = n, src = src}
		return n
	end}
	ChaosDiscord = {queue = function(e) queued[#queued + 1] = e return true end}
	local players = {}
	Game = {getPlayers = function() return players end}
	local printed = print
	print = function() end
	dofile("data/scripts/chaos/weekly_class.lua")
	print = printed
	local WK = ChaosWeeklyClass
	cb = EventCallback
	ok(cb ~= nil and cb.onGainExperience ~= nil, "the experience callback")
	ok(#hooks >= 1, "the reset hook is registered")
	local player = {getGuid = function() return 42 end}
	local monster = {isMonster = function() return true end}
	local quest = nil
	eq(cb.onGainExperience(player, monster, 1000, 500), 1000, "experience unchanged")
	cb.onGainExperience(player, quest, 99999, 99999)
	cb.onGainExperience(player, {isMonster = function() return false end}, 99999, 99999)
	cb.onGainExperience(player, monster, 250, 100)
	eq(WK.buf[42], 1250, "only monster kills count")
	players[1] = player
	events.ChaosWeeklyClassFlush.onThink(60000)
	eq(#records, 1, "flushed once")
	eq(records[1].board, "weekly_xp", "to the board")
	eq(records[1].value, 1250, "the amount")
	eq(records[1].mode, "add", "added")
	events.ChaosWeeklyClassFlush.onThink(60000)
	eq(#records, 1, "nothing new: no record")
	cb.onGainExperience(player, monster, 70, 70)
	events.ChaosWeeklyClassLogout.onLogout(player)
	eq(#records, 2, "logout flushes")
	eq(records[2].value, 70, "the rest")
	-- the week's end
	print = function() end
	hooks[#hooks](20261026, {weekly_xp = ranked})
	print = printed
	eq(#granted, 4, "tokens to the class tops")
	eq(granted[1].src, "weekly_class", "token source")
	eq(granted[1].guid, 1, "the warrior 1st")
	eq(paidRows, 4, "podium rows")
	eq(#broadcasts, 1, "one broadcast")
	ok(broadcasts[1]:find("Warrior: Ana", 1, true) ~= nil, "broadcast names the class winners")
	eq(#queued, 1, "one Discord row")
	eq(queued[1].kind, "weekly_class", "Discord kind")
	ok(queued[1].title:find("2026-10-26", 1, true) ~= nil, "Discord title names the week")
	-- a second reset of the same week (a /leaderboard reset): rows exist, nothing paid again
	print = function() end
	hooks[#hooks](20261026, {weekly_xp = ranked})
	print = printed
	eq(#granted, 4, "no second payment")
	eq(#queued, 1, "no second post")
end

print(string.format("weekly_class: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
