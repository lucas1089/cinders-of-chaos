-- Run from the server/ folder: luajit tests/weekly_challenge_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The Weekly Challenge (O390): weekly_challenge_core.lua (ISO weeks, the seed, the week's area, boards, class tops,
-- token grants, the Discord text), the generated area over many weeks (valid, in the dungeon block, apart from every
-- other area, the Vault's run numbers), the boards in leaderboard_config.lua, the Discord kind, and
-- weekly_challenge.lua against a mocked engine (the area, the entry check, a clear on the right board, the week's end:
-- tokens and the Discord row).
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

dofile("data/scripts/chaos/weekly_challenge_core.lua")
local W = ChaosWeeklyChallengeCore
local cfg = dofile("data/scripts/chaos/weekly_challenge_config.lua")

-- ====================================================================== ISO weeks (checked against Python's isocalendar)
local vectors = {
	{2026, 11, 2, 2026, 45}, {2026, 11, 8, 2026, 45}, {2021, 1, 3, 2020, 53}, {2020, 12, 31, 2020, 53},
	{2019, 12, 30, 2020, 1}, {2024, 12, 30, 2025, 1}, {2026, 1, 1, 2026, 1}, {2027, 1, 1, 2026, 53},
	{2027, 1, 4, 2027, 1}, {2000, 2, 29, 2000, 9}, {2038, 6, 15, 2038, 24}
}
for _, v in ipairs(vectors) do
	local y, w = W.isoWeek(v[1], v[2], v[3])
	eq(string.format("%d-%d", y, w), string.format("%d-%d", v[4], v[5]), string.format("ISO week of %d-%02d-%02d", v[1], v[2], v[3]))
end
-- every day of 2015-2035: the week advances by one each Monday, never on another day, and the Monday's own week key
-- gives the same week (weekOf)
do
	local n0 = W.daysOf(2015, 1, 5) -- a Monday
	local py, pw = W.isoWeek(2015, 1, 5)
	local bad = 0
	for n = n0 + 1, W.daysOf(2035, 12, 31) do
		local t = os.date("!*t", n * 86400)
		local y, w = W.isoWeek(t.year, t.month, t.day)
		local monday = (n + 3) % 7 == 0
		if monday then
			local nextOk = (y == py and w == pw + 1) or (y == py + 1 and w == 1 and (pw == 52 or pw == 53))
			if not nextOk then
				bad = bad + 1
			end
			local wy, ww = W.weekOf(t.year * 10000 + t.month * 100 + t.day)
			if wy ~= y or ww ~= w then
				bad = bad + 1
			end
		elseif y ~= py or w ~= pw then
			bad = bad + 1
		end
		py, pw = y, w
	end
	eq(bad, 0, "ISO weeks over 2015-2035")
end
eq(W.label(2026, 5), "2026-W05", "label")
eq(select(2, W.weekOf(20261102)), 45, "week key 20261102 -> week 45")

-- ====================================================================== seed and theme
local seen, themes = {}, {}
for w = 1, 52 do
	local s = W.seed(cfg, 2026, w, 0)
	ok(s >= 1 and s < 2147483647 and s == math.floor(s), "seed in range " .. w)
	ok(not seen[s], "a new seed each week " .. w)
	seen[s] = true
	eq(W.seed(cfg, 2026, w, 0), s, "the same seed for the same week")
	ok(W.seed(cfg, 2026, w, 1) ~= s, "the next try has another seed")
	themes[W.theme(cfg, s).key] = true
end
ok(W.seed(cfg, 2027, 1, 0) ~= W.seed(cfg, 2026, 1, 0), "week 1 of another year: another seed")
local nThemes = 0
for _ in pairs(themes) do
	nThemes = nThemes + 1
end
eq(nThemes, #cfg.themes, "every theme comes up within a year")

-- ====================================================================== the week's area
dofile("data/scripts/chaos/areagen_core.lua")
dofile("data/lib/chaos_dark_tiles.lua")
local A = ChaosAreaGenCore
local ag = dofile("data/scripts/chaos/areagen_config.lua")
local base
for _, def in ipairs(ag.areas) do
	if def.id == cfg.base then
		base = def
	end
end
ok(base and base.dungeon, "the base area is a dungeon of areagen_config.lua")
for _, t in ipairs(cfg.themes) do
	ok(ag.themes[t.key] ~= nil, "theme " .. t.key .. " exists")
end
local baseSeed, baseTheme = base.seed, base.theme
local def = W.areaDef(cfg, base, {isoYear = 2026, isoWeek = 45, try = 0})
eq(base.seed, baseSeed, "the base is not changed")
eq(base.theme, baseTheme, "the base theme is not changed")
eq(base.dungeon.id, 5, "the base dungeon id is not changed")
eq(def.id, "challenge", "area id")
eq(def.dungeon.id, cfg.dungeon.id, "dungeon id")
eq(def.dungeon.party, 4, "party of up to 4")
eq(def.dungeon.fixedDifficulty, 1, "one difficulty")
eq(def.dungeon.chest, nil, "no boss chest")
eq(def.boss.name, "The Proving Warden", "boss name of its own")
ok(def.boss.name ~= base.boss.name, "the boss name differs from the Vault's (the kill is matched by name)")
eq(def.weekly.label, "2026-W45", "weekly label")
eq(def.seed, W.seed(cfg, 2026, 45, 0), "the week's seed")
eq(def.entrance, nil, "no entrance portal (the queue)")
ok(def.dungeon.id > 9, "a dungeon id after the generated 5-9")
for _, other in ipairs(ag.areas) do
	ok(not other.dungeon or other.dungeon.id ~= def.dungeon.id, "dungeon id not used by " .. other.id)
	ok(other.id ~= def.id, "area id not used by " .. other.id)
	local apart = def.origin.x > other.origin.x + other.size[1] - 1 or def.origin.x + def.size[1] - 1 < other.origin.x
		or def.origin.y > other.origin.y + other.size[2] - 1 or def.origin.y + def.size[2] - 1 < other.origin.y
		or def.origin.z > other.origin.z + (other.floors or 1) - 1 or def.origin.z + (def.floors or 1) - 1 < other.origin.z
	ok(apart, "the challenge does not overlap " .. other.id)
end
ok(def.origin.x >= 24576 and def.origin.y >= 24576 and def.origin.x + def.size[1] <= 25600
	and def.origin.y + def.size[2] <= 25600, "inside the empty dungeon block 24576-25599")

-- many weeks: a valid layout within the tries (light and dark tiles), different layouts, the same one again
do
	local DARK = {dark = true, darkIds = ChaosDarkTiles.ids}
	local sums, failed, retried = {}, 0, 0
	for w = 40, 52 do
		for _, opts in ipairs({{}, DARK}) do
			local found
			for try = 0, cfg.seedTries - 1 do
				local d = W.areaDef(cfg, base, {isoYear = 2026, isoWeek = w, try = try})
				local m = A.generate(ag, d, opts)
				if #A.validate(ag, m, opts) == 0 and #W.layoutProblems(cfg, m) == 0 then
					found = m
					retried = retried + (try > 0 and 1 or 0)
					if not opts.dark then
						sums[A.checksum(m)] = true
						eq(A.checksum(A.generate(ag, d, opts)), A.checksum(m), "week " .. w .. ": one seed, one layout")
						ok(m.stats.monsters >= 100, string.format("week %d: at least 100 monsters (%d)", w, m.stats.monsters))
						ok(m.boss ~= nil, "week " .. w .. ": a boss room")
					end
					break
				end
			end
			if not found then
				failed = failed + 1
			end
		end
	end
	eq(failed, 0, "every week has a valid layout within " .. cfg.seedTries .. " seeds")
	local n = 0
	for _ in pairs(sums) do
		n = n + 1
	end
	eq(n, 13, "13 weeks, 13 layouts")
	ok(retried <= 14, "most weeks take their first seed (" .. retried .. " of 26 did not)")
	eq(#W.layoutProblems(cfg, {stats = {monsters = 99}, boss = {}}), 1, "99 monsters: unfit")
	eq(#W.layoutProblems(cfg, {stats = {monsters = 100}, boss = {}}), 0, "100 monsters with a boss: fit")
end

-- ====================================================================== boards, times, entry
eq(W.boardOf(cfg, 1), "challenge_solo", "1 player: solo")
eq(W.boardOf(cfg, nil), "challenge_solo", "no size: solo")
eq(W.boardOf(cfg, 3), "challenge_party", "3: party")
eq(W.seconds(61200), 62, "61.2 s -> 62")
eq(W.seconds(0), 1, "at least 1 s")
eq(W.clock(754), "12:34", "clock")
eq(W.clock(3725), "1:02:05", "clock hours")
ok(W.entryProblem(nil, 20261102) ~= nil, "not built: closed")
ok(W.entryProblem(20261026, 20261102) ~= nil, "last week's layout: closed")
eq(W.entryProblem(20261102, 20261102), nil, "this week's layout: open")

local lbc = dofile("data/scripts/chaos/leaderboard_config.lua")
for _, key in ipairs({cfg.boards.solo, cfg.boards.party}) do
	local b
	for _, x in ipairs(lbc.boards) do
		if x.key == key then
			b = x
		end
	end
	ok(b ~= nil, key .. ": a leaderboard board")
	ok(b and b.mode == "min" and b.format == "time" and b.byClass and b.noReward and b.title, key .. ": min, time, class tabs, title only")
end

-- ====================================================================== the week's end
dofile("data/scripts/chaos/leaderboard_core.lua")
local LB = ChaosLeaderboard
local groups = {{key = 4, name = "Warrior", ids = {4, 8, 14}}, {key = 3, name = "Ranger", ids = {3, 7, 15}},
	{key = 1, name = "Mystic", ids = {1, 5, 10}}}
local scores = {
	[11] = {value = 300, at = 1, name = "Ana", voc = 8}, [12] = {value = 280, at = 2, name = "Bo", voc = 4},
	[13] = {value = 400, at = 3, name = "Cy", voc = 14}, [14] = {value = 500, at = 4, name = "Di", voc = 8},
	[15] = {value = 350, at = 5, name = "Ed", voc = 7}, [16] = {value = 0, at = 6, name = "Zero", voc = 3},
	[17] = {value = 200, at = 7, name = "Gm", voc = 4, group = 5}
}
local ranked = LB.rank(scores, 4, true)
local tops = {{board = "challenge_solo", groups = W.classTop(ranked, groups, 3, LB.filterClass)},
	{board = "challenge_party", groups = W.classTop({}, groups, 3, LB.filterClass)}}
local warrior = tops[1].groups[1]
eq(#warrior.rows, 3, "warrior: top 3 of 4")
eq(warrior.rows[1].name, "Bo", "warrior 1st: the fastest (staff left out)")
eq(warrior.rows[3].name, "Cy", "warrior 3rd")
eq(#tops[1].groups[2].rows, 1, "ranger: one time (0 is no time)")
eq(#tops[1].groups[3].rows, 0, "mystic: none")
local grants = W.awards(cfg, tops)
eq(#grants, 4, "4 grants")
eq(grants[1].tokens, cfg.tokens[1], "1st tokens")
eq(grants[3].tokens, cfg.tokens[3], "3rd tokens")
eq(grants[4].name, "Ed", "ranger 1st")
local total = 0
for _, g in ipairs(grants) do
	total = total + g.tokens
end
eq(total, 30 + 20 + 10 + 30, "token total")
-- economy bound (weekly_challenge_config.lua): one character at most 2 boards x the 1st's tokens a week, under one
-- day's cap of the dungeon clear source of conquest_config.lua
local cq = dofile("data/scripts/chaos/conquest_config.lua")
ok(2 * cfg.tokens[1] <= cq.sources.dungeon_clear.cap, "a week's tokens of one character stay under one day's dungeon clear cap")
local sections = W.discordSections(cfg, tops, {challenge_solo = "Solo", challenge_party = "Party"})
eq(#sections, 2, "two classes with times")
eq(sections[1].name, "Warrior", "first section")
eq(sections[1].value, "Solo: 1. Bo 4:40, 2. Ana 5:00, 3. Cy 6:40", "warrior line")

dofile("data/scripts/chaos/discord_core.lua")
dofile("data/scripts/chaos/discord_config.lua")
local D = ChaosDiscordCore
local ev = D.weeklyChallenge(ChaosDiscordConfig, "2026-W45", "Marrow Crypts", sections)
eq(ev.kind, "weekly_challenge", "discord kind")
eq(ev.channel, "records", "discord channel")
eq(#ev.fields, 2, "a field per class")
ok(D.enabled(ChaosDiscordConfig, "weekly_challenge"), "the kind is on")
ok(D.weeklyChallenge(ChaosDiscordConfig, "2026-W45", "X", {}).text:find("Nobody", 1, true), "an empty week says so")
do
	local f = io.open("../website/overlay/plugins/chaos/discord_lib.php", "r")
	local php = f and f:read("*a") or ""
	if f then
		f:close()
	end
	ok(php:find("'weekly_challenge'", 1, true) ~= nil, "the website worker knows the kind")
end

-- ====================================================================== weekly_challenge.lua, mocked engine
do
	Chaos = {t = function(_, s, ...) return select("#", ...) > 0 and string.format(s, ...) or s end,
		leaderboardConfig = {resetHour = 6, staffGroup = 4}, staffCommand = function() return true end}
	ChaosI18n = nil
	local function stub()
		return setmetatable({}, {__index = function() return function() end end})
	end
	TalkAction = function() return stub() end
	GlobalEvent = function() return stub() end
	MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR = 1, 2
	local nowT = os.time({year = 2026, month = 11, day = 4, hour = 12})
	local records, hooks, queued, granted = {}, {}, {}, {}
	LB.now = function() return nowT end
	LB.record = function(board, who, value)
		records[#records + 1] = {board = board, value = value}
		return {value = value}
	end
	LB.onReset = function(fn) hooks[#hooks + 1] = fn end
	LB.classGroups = function() return groups end
	ChaosConquest = {grantGuid = function(guid, n, source)
		granted[#granted + 1] = {guid = guid, n = n, source = source}
		return n
	end}
	ChaosDiscord = {queue = function(e) queued[#queued + 1] = e return true end}
	local printed = print
	print = function() end
	dofile("data/scripts/chaos/weekly_challenge.lua")
	local WC = ChaosWeeklyChallenge
	eq(#hooks, 1, "the reset hook is registered")
	local wk = WC.weekNow()
	eq(wk, 20261102, "the week now")
	local d = WC.areaFor(ag, A, {})
	print = printed
	ok(d and d.weekly.week == wk and d.weekly.label == "2026-W45", "the area of this week")
	ok(WC.entryProblem({}) ~= nil, "closed before the build")
	WC.onBuilt({def = d})
	eq(WC.entryProblem({}), nil, "open with this week's layout")
	local msgs = {}
	local player = {sendTextMessage = function(_, _, text) msgs[#msgs + 1] = text end}
	WC.onClear(player, {ms = 312400, size = 1})
	WC.onClear(player, {ms = 290000, size = 3})
	eq(#records, 2, "two clears recorded")
	eq(records[1].board, "challenge_solo", "solo board")
	eq(records[1].value, 313, "seconds")
	eq(records[2].board, "challenge_party", "party board")
	ok(msgs[1]:find("5:13", 1, true) ~= nil, "the time told")
	local info = WC.info(player)
	ok(info.current and info.label == "2026-W45" and info.resetIn > 0, "window info")
	-- the week turns without a restart: last week's layout records nothing and refuses entry
	nowT = nowT + 7 * 86400
	ok(WC.entryProblem({}) ~= nil, "stale layout: closed")
	WC.onClear(player, {ms = 1000, size = 1})
	eq(#records, 2, "a clear on a stale layout is not recorded")
	eq(WC.info(player).current, false, "window: stale")
	print = function() end
	hooks[1](20261102, {challenge_solo = ranked, challenge_party = {}}, {})
	print = printed
	eq(#granted, 4, "tokens to the class tops")
	eq(granted[1].source, "weekly_challenge", "token source")
	eq(#queued, 1, "one Discord row")
	eq(queued[1].kind, "weekly_challenge", "Discord kind")
	ok(queued[1].title:find("2026-W45", 1, true) ~= nil, "Discord title names the week")
	ok(queued[1].text:find(d.weekly.theme, 1, true) ~= nil, "Discord text names the theme")
end

print(string.format("weekly_challenge: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
