-- Run from the server/ folder: luajit tests/nameplate_test.lua (and lua5.3; CI runs both)
-- Name plates and titles: the pure logic (nameplate_core.lua: normalize, order, pick, find, frames, wire format,
-- client queries) and the title registry (titles.lua) with mocked players and mocked leaderboard / siege / season
-- tables.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/nameplate_core.lua")
dofile("data/scripts/chaos/titles.lua")
local N = ChaosNameplate
local T = ChaosTitles

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

eq(ChaosOpcodes.nameplate, 248, "opcode")

-- ---------------------------------------------------------------- clean / normalize
eq(N.clean("  Grim|Lord\n  of  ash "), "Grim Lord of ash", "separators and spaces")
eq(N.clean(nil), "", "nil")
eq(#N.clean(string.rep("x", 40), N.MAX_TITLE), 24, "cut")
eq(N.normalize({text = ""}, "staff"), nil, "empty text")
eq(N.normalize(5, "staff"), nil, "not a table")
local t = N.normalize("Bossbane", "leaderboard")
eq(t.key, "leaderboard:bossbane", "default key")
eq(t.color, "e8c15a", "leaderboard gold")
eq(t.frame, nil, "no frame of its own")
t = N.normalize({key = "staff", text = "Administrator"}, "staff")
eq(t.color, "e0402c", "staff red")
eq(t.frame, "gold", "staff gold frame")
eq(t.priority, 100, "staff first")
eq(N.normalize({text = "X"}, "champion").color, "f08a2c", "champion orange")
eq(N.normalize({text = "X"}, "champion").frame, "crimson", "champion crimson frame")
eq(N.normalize({text = "X", color = "#12AB34"}, "season").color, "12ab34", "own colour")
eq(N.normalize({text = "X", color = "red"}, "season").color, "b48cff", "bad colour -> source colour")
eq(N.normalize({text = "X"}, "brandnew").color, "d6c9ae", "unknown source colour")
eq(N.normalize({text = "X", frame = "golden"}, "brandnew").frame, nil, "unknown frame dropped")
eq(N.normalize({text = "X", frame = "violet"}, "brandnew").frame, "violet", "known frame kept")

-- ---------------------------------------------------------------- collect / order / pick
local errors = {}
local list = N.collect({
	{name = "leaderboard", fn = function() return {{text = "Bossbane", at = 100}, {text = "Riftwalker", at = 300}} end},
	{name = "broken", fn = function() error("boom") end},
	{name = "staff", fn = function() return {key = "staff", text = "Game Master"} end},
	{name = "season", fn = function() return {{text = "Firstborn", at = 200}, {text = "Bossbane", key = "leaderboard:bossbane"}} end},
	{name = "nothing", fn = function() return nil end}
}, nil, function(name) errors[#errors + 1] = name end)
eq(#list, 4, "four titles (duplicate key dropped)")
eq(errors[1], "broken", "a failing source is reported and skipped")
eq(list[1].text, "Game Master", "staff first")
eq(list[2].text, "Riftwalker", "then newest")
eq(list[3].text, "Firstborn", "then older")
eq(list[4].text, "Bossbane", "oldest last")
eq(N.pick(list, nil).text, "Game Master", "default = first")
eq(N.pick(list, "none"), nil, "hidden")
eq(N.pick(list, "season:firstborn").text, "Firstborn", "chosen")
eq(N.pick(list, "season:gone").text, "Game Master", "chosen title gone -> default")
eq(N.pick({}, nil), nil, "no titles")
eq(N.find(list, "riftwalker").key, "leaderboard:riftwalker", "find by text")
eq(N.find(list, "RIFT").key, "leaderboard:riftwalker", "find by prefix")
eq(N.find(list, "staff").text, "Game Master", "find by key")
eq(N.find(list, "dragon"), nil, "not held")
eq(N.find(list, ""), nil, "empty query")

-- ---------------------------------------------------------------- frames
eq(N.frameOf(nil, nil), "default", "no title, no cosmetic")
eq(N.frameOf(list[1], nil), "gold", "staff title frame")
eq(N.frameOf(list[1], "frost"), "frost", "cosmetic beats title")
eq(N.frameOf(list[2], "nope"), "default", "unknown cosmetic ignored")
-- O317: an active Chaos Pact brings its frame (pact_config.lua pact.frame) below the frames the player wears
eq(N.frameOf(nil, nil, "pactbound"), "pactbound", "the Pact's frame when nothing else")
eq(N.frameOf(list[2], nil, "pactbound"), "pactbound", "the Pact's frame under a title without a frame")
eq(N.frameOf(list[1], nil, "pactbound"), "gold", "a staff title frame beats the Pact's")
eq(N.frameOf(nil, "frost", "pactbound"), "frost", "a bought frame beats the Pact's")
eq(N.frameOf(nil, nil, "nope"), "default", "an unknown Pact frame is ignored")
eq(dofile("data/scripts/chaos/pact_config.lua").pact.frame, "pactbound", "the Pact's frame")
eq(N.FRAMES[dofile("data/scripts/chaos/pact_config.lua").pact.frame], true, "and the client has it")

-- ---------------------------------------------------------------- wire
eq(N.encode({cid = 268435461, title = "Administrator", color = "e0402c", guild = "Omar", frame = "gold"}),
	"268435461|Administrator|e0402c|Omar|gold", "all three lines")
eq(N.encode({cid = 5, title = "", color = "e0402c", guild = "Omar", frame = "default"}), "5|||Omar|", "no title, default frame")
eq(N.encode({cid = 5, title = "Riftwalker", color = "e8c15a", guild = "", frame = "default"}), "5|Riftwalker|e8c15a||",
	"no guild")
eq(N.encode({cid = 5, title = "A|B", color = "zz", guild = "G\nH"}), "5|A B||G H|", "sanitised")
local ids = N.decodeQuery("q|10,20,10,x,-3,1.5,30")
eq(#ids, 3, "unique valid ids")
eq(ids[3], 30, "order kept")
eq(#N.decodeQuery("x|1,2"), 0, "unknown message")
eq(#N.decodeQuery(nil), 0, "nil")
local many = {}
for i = 1, 100 do
	many[#many + 1] = tostring(i)
end
eq(#N.decodeQuery("q|" .. table.concat(many, ","), 40), 40, "capped")

-- ---------------------------------------------------------------- registry with mocked players and systems
local function mockPlayer(o)
	return {
		getGroup = function() return {getId = function() return o.group or 1 end} end,
		getGuid = function() return o.guid or 1 end,
		getAccountId = function() return o.account or 1 end,
		getGuild = function()
			return o.guildId and {getId = function() return o.guildId end, getName = function() return "Omar" end} or nil
		end
	}
end

eq(#T.of(mockPlayer({})), 0, "plain player, systems not loaded: no titles")
eq(T.of(mockPlayer({group = 6}))[1].text, "Administrator", "god group")
eq(T.of(mockPlayer({group = 4}))[1].text, "Game Master", "gamemaster group")
eq(T.of(mockPlayer({group = 3}))[1].text, "Senior Tutor", "senior tutor group")

local now = os.time()
ChaosLeaderboard = {held = {week = 20261005}, titlesOf = function(guid)
	if guid == 7 then
		return {{title = "Bossbane", rank = 1, rankName = "1st", board = "worldboss"}}
	end
end, weekStart = function() return now - 10 * 86400 end} -- held week started 10 days ago: earned 3 days ago
Chaos.leaderboardConfig = {resetHour = 6}
ChaosSiege = {champions = {[3] = {name = "Omar", untilAt = now + 6 * 86400}}, championOf = function(c, id, at)
	local x = id and c[id]
	return x and x.untilAt > at and x or nil
end}
Chaos.siegeConfig = {title = "Siege Champions", titleDays = 7}
ChaosSeason = {titlesOf = function(account) return account == 9 and {{title = "Firstborn", rankName = "Season 1"}} or {} end}

local p = mockPlayer({guid = 7, guildId = 3, group = 6, account = 9})
list = T.of(p)
eq(#list, 4, "staff + leaderboard + champion + season")
eq(list[1].key, "staff", "staff first")
eq(list[2].key, "champion:siege", "champion earned a day ago is newer than the weekly title")
eq(list[2].color, "f08a2c", "champion orange")
eq(list[3].key, "leaderboard:worldboss", "leaderboard title")
eq(list[3].color, "e8c15a", "leaderboard gold")
eq(list[4].text, "Firstborn", "season title (no time: last)")
eq(#T.of(mockPlayer({guid = 8, guildId = 4})), 0, "other guild, no titles")

-- registering again replaces; new sources are picked up
T.register("arena", function() return {text = "Unbroken", at = now} end)
T.register("arena", function() return {text = "Unbroken 30", at = now} end)
list = T.of(mockPlayer({guid = 8}))
eq(#list, 1, "replaced, not added")
eq(list[1].text, "Unbroken 30", "new source")
eq(list[1].color, "8fb6e8", "arena steel blue")
T.unregister("arena")
eq(#T.of(mockPlayer({guid = 8})), 0, "unregistered")

-- login-streak milestone titles (daily.lua tables)
ChaosDaily = {accounts = {[5] = {best = 40}}}
ChaosDailyCore = {titleFor = function(cfg, best)
	local title, days = nil, 0
	for _, m in ipairs(cfg.milestones) do
		if m.title and m.days <= best and m.days > days then
			title, days = m.title, m.days
		end
	end
	return title, days
end}
Chaos.dailyStreak = {milestones = {{days = 7, title = "the Devoted"}, {days = 30, title = "the Relentless"}}}
list = T.of(mockPlayer({guid = 8, account = 5}))
eq(#list, 1, "streak title")
eq(list[1].text, "the Relentless", "highest milestone reached")
eq(list[1].key, "streak:30", "streak key")
eq(list[1].color, "7cd17c", "streak green")
eq(#T.of(mockPlayer({guid = 8, account = 6})), 0, "no streak")

-- cosmetic frames
eq(T.frameOf(p), nil, "no cosmetic frame source")
T.registerFrame("store", function(pl) return pl:getGuid() == 7 and "violet" or nil end)
eq(T.frameOf(p), "violet", "cosmetic frame")
eq(T.frameOf(mockPlayer({guid = 2})), nil, "not owned")
eq(N.frameOf(N.pick(T.of(p)), T.frameOf(p)), "violet", "cosmetic beats the staff frame")

-- ---------------------------------------------------------------- memo (clean and colours are cached; same results)
for _ = 1, 3 do
	eq(N.clean("  Grim|Lord\n  of  ash "), "Grim Lord of ash", "memo: same text twice")
	eq(#N.clean(string.rep("y", 40), N.MAX_TITLE), 24, "memo: cut")
	eq(N.clean(string.rep("y", 40)), string.rep("y", 40), "memo: other max, own entry")
	eq(N.clean(12), "12", "memo: a number is not cached")
	eq(N.normalize({text = "X", color = "#ABCDEF"}, "season").color, "abcdef", "memo: colour")
	eq(N.normalize({text = "X", color = "zzz"}, "season").color, N.COLORS.season, "memo: bad colour")
	eq(N.normalize({text = "X", key = " k|1 "}, "season").key, "k 1", "memo: key cleaned once")
end
local max = N.MEMO_MAX
N.MEMO_MAX = 4
for i = 1, 20 do
	eq(N.clean(" t" .. i .. " "), "t" .. i, "memo: past the cap it starts over")
end
N.MEMO_MAX = max

-- O252: a plate query answers only for players the asker sees (no ghosts, other floors, far away)
do
	local function pl(x, y, z, sees)
		local pos = {x = x, y = y, z = z}
		pos.getDistance = function(a, b) return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) end
		return {getPosition = function() return pos end, canSeeCreature = function() return sees end}
	end
	eq(N.mayQuery(pl(100, 100, 7, true), pl(105, 100, 7, true)), true, "a visible neighbour")
	eq(N.mayQuery(pl(100, 100, 7, false), pl(105, 100, 7, true)), false, "a ghost")
	eq(N.mayQuery(pl(100, 100, 7, true), pl(105, 100, 8, true)), false, "another floor")
	eq(N.mayQuery(pl(100, 100, 7, true), pl(300, 100, 7, true)), false, "far away")
end

print("nameplate_test: OK")
