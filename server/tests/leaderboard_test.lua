-- Run from the server/ folder: luajit tests/leaderboard_test.lua (and lua5.3; CI runs both)
-- Pure logic of the leaderboards (leaderboard_core.lua): the week key and reset time, record add/max, ranking and
-- ties, the titles and rewards of a weekly reset, the look text and the class grouping. Uses the real
-- leaderboard_config.lua.
dofile("data/scripts/chaos/leaderboard_core.lua")
local LB = ChaosLeaderboard
local cfg = dofile("data/scripts/chaos/leaderboard_config.lua")
local H = cfg.resetHour

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function t(y, mo, d, hh, mi)
	return os.time({year = y, month = mo, day = d, hour = hh, min = mi or 0, sec = 0})
end

-- ---------------------------------------------------------------- week key (2026-10-05 is a Monday)
eq(H, 6, "the reset hour is the bounty board's roll hour")
eq(LB.week(t(2026, 10, 8, 12), H), 20261005, "Thursday -> Monday")
eq(LB.week(t(2026, 10, 5, 6, 0), H), 20261005, "Monday 06:00 starts the week")
eq(LB.week(t(2026, 10, 5, 5, 59), H), 20260928, "Monday 05:59 is still last week")
eq(LB.week(t(2026, 10, 12, 5, 59), H), 20261005, "next Monday 05:59: still this week")
eq(LB.week(t(2026, 10, 12, 6, 0), H), 20261012, "next Monday 06:00: new week")
eq(LB.week(t(2027, 1, 2, 12), H), 20261228, "over the year end")
eq(LB.week(t(2026, 10, 8, 12), H), ChaosBounty.week(t(2026, 10, 8, 12), {rollHour = 6}), "same rule as the bounty chest")
eq(LB.weekStart(20261005, H), t(2026, 10, 5, 6), "week start")
eq(LB.nextReset(t(2026, 10, 8, 12), H), t(2026, 10, 12, 6), "next reset")
eq(LB.nextReset(t(2026, 10, 5, 5, 0), H), t(2026, 10, 5, 6), "next reset an hour away")
eq(LB.nextReset(t(2026, 12, 30, 12), H), t(2027, 1, 4, 6), "next reset over the year end")
eq(LB.prevWeek(20261005, H), 20260928, "previous week")
eq(LB.prevWeek(20260105, H), 20251229, "previous week over the year end")
eq(LB.resetDue(nil, 20261005), true, "first run")
eq(LB.resetDue(20260928, 20261005), true, "new week")
eq(LB.resetDue(20261005, 20261005), false, "already done")
eq(LB.resetDue(20261012, 20261005), false, "clock went back: no reset")

-- ---------------------------------------------------------------- record add / max
local e = LB.merge(nil, 1000, "add", 100)
eq(e.value, 1000, "add new")
eq(e.count, 1, "count new")
eq(e.at, 100, "at new")
local changed
e, changed = LB.merge(e, 500, "add", 200)
eq(e.value, 1500, "add sums")
eq(e.count, 2, "add counts")
eq(e.at, 200, "add moves at")
eq(changed, true, "changed")
e, changed = LB.merge(e, 0, "add", 300)
eq(e.value, 1500, "add 0")
eq(e.count, 3, "add 0 still counts")
eq(e.at, 200, "add 0 keeps at")
eq(changed, false, "unchanged")

local m = LB.merge(nil, 5, "max", 100)
eq(m.value, 5, "max new")
m = LB.merge(m, 3, "max", 200)
eq(m.value, 5, "max keeps the best")
eq(m.at, 100, "max keeps at when not improved")
eq(m.count, 2, "max counts runs")
m = LB.merge(m, 9, "max", 300)
eq(m.value, 9, "max improves")
eq(m.at, 300, "max moves at when improved")
eq(LB.merge(nil, 7.9, "max", 1).value, 7, "integers")

-- ---------------------------------------------------------------- ranking and ties
local scores = {
	[10] = {value = 500, at = 50, name = "Ana", group = 1},
	[11] = {value = 900, at = 90, name = "Bo", group = 1},
	[12] = {value = 500, at = 40, name = "Cy", group = 1}, -- same value as Ana, reached it first
	[13] = {value = 500, at = 40, name = "Di", group = 1}, -- same value and time as Cy: higher guid
	[14] = {value = 0, at = 10, name = "Ed", group = 1}, -- no score: not listed
	[15] = {value = 9999, at = 1, name = "GM", group = 4} -- staff: not listed
}
local ranked = LB.rank(scores, cfg.staffGroup)
eq(#ranked, 4, "listed")
eq(ranked[1].name, "Bo", "1st")
eq(ranked[2].name, "Cy", "tie: reached first")
eq(ranked[3].name, "Di", "tie: lower guid")
eq(ranked[4].name, "Ana", "tie: reached last")
for i, r in ipairs(ranked) do
	eq(r.rank, i, "distinct ranks")
end
eq(LB.find(ranked, 10).rank, 4, "own rank")
eq(LB.find(ranked, 14), nil, "own rank without score")
eq(#LB.rank(scores, nil), 5, "no staff filter")

-- ---------------------------------------------------------------- titles at the reset
local rankedBoards = {
	worldboss = ranked,
	bounty = LB.rank({[20] = {value = 3, at = 5, name = "Hunter", group = 1}}, cfg.staffGroup),
	rift = {}
}
local awards = LB.awards(cfg.boards, rankedBoards, cfg)
eq(#awards, 4, "3 world boss + 1 bounty + 0 rift")
eq(awards[1].board, "worldboss", "board order")
eq(awards[1].name, "Bo", "world boss 1st")
eq(awards[1].title, "Bossbane", "world boss title")
eq(awards[1].rankName, "1st", "rank name")
eq(awards[3].name, "Di", "world boss 3rd")
eq(awards[4].board, "bounty", "bounty")
eq(awards[4].title, "Warden of the Hunt", "bounty title")
eq(awards[4].rank, 1, "bounty 1st")
eq(awards[1].items[1].id, cfg.rewards[1][1].id, "1st reward")
eq(awards[1].items[1].count, cfg.rewards[1][1].count, "1st reward count")
eq(awards[3].items[1].count, cfg.rewards[3][1].count, "3rd reward count")
awards[1].items[1].count = 0
eq(cfg.rewards[1][1].count > 0, true, "awards copy the reward items")
for _, a in ipairs(awards) do
	eq(a.name ~= "Ana", true, "4th gets nothing")
end
eq(#LB.awards(cfg.boards, {}, cfg), 0, "empty week: no titles")

local map = LB.titleMap(awards)
eq(#map[11], 1, "title map")
map[11][#map[11] + 1] = {title = "Riftwalker", rankName = "2nd"}
eq(LB.lookText(map[11], "She"), "She holds the titles Bossbane (1st), Riftwalker (2nd).", "look text, two titles")
eq(LB.lookText(map[20], "He"), "He holds the title Warden of the Hunt (1st).", "look text")
eq(LB.lookText(nil, "He"), nil, "no title")
local text = LB.broadcastText(cfg.boards, awards)
assert(text:find("Bossbane: Bo, Cy, Di", 1, true), text)
assert(text:find("Warden of the Hunt: Hunter", 1, true), text)
assert(not text:find("Riftwalker", 1, true), "no rift winners")

-- ---------------------------------------------------------------- class ladder groups
local baseOf = {[1] = 1, [5] = 1, [10] = 1, [4] = 4, [8] = 4, [14] = 4, [11] = 11, [12] = 11, [13] = 11}
local demotions = {[20] = 11, [21] = 20} -- vocations the mapping does not know: grouped by their demotion chain
local function demotion(id)
	return demotions[id]
end
eq(LB.groupOf(14, baseOf, demotion), 4, "mapped")
eq(LB.groupOf(21, baseOf, demotion), 11, "demotion chain into a mapped base")
eq(LB.groupOf(30, baseOf, demotion), 30, "unknown: its own group")
eq(LB.groupOf(8, nil, function(id) return id == 8 and 4 or 0 end), 4, "no mapping: demotion only")
local groups = LB.groups({13, 1, 4, 8, 5, 10, 11, 12, 14, 30}, baseOf, demotion)
eq(#groups, 4, "groups")
eq(groups[1].base, 1, "group order")
eq(table.concat(groups[1].ids, ","), "1,5,10", "group ids")
eq(table.concat(groups[3].ids, ","), "11,12,13", "thief line")
eq(groups[4].base, 30, "unmapped vocation")

print("leaderboard_test: OK")
