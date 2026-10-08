-- Run from the server/ folder: luajit tests/season_test.lua (and lua5.3; CI runs both)
-- Pure logic of the seasons (season_core.lua) with the real season_config.lua: the date math, join eligibility,
-- the trade / move / party / mail isolation decisions, milestone detection and the reward track, the end-of-season
-- migration decisions and the season unique rule.
dofile("data/scripts/chaos/season_core.lua")
local S = ChaosSeason
local cfg = dofile("data/scripts/chaos/season_config.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function t(y, mo, d, hh, mi)
	return os.time({year = y, month = mo, day = d, hour = hh or 0, min = mi or 0, sec = 0})
end

-- a test season list, independent of the shipped dates
local seasons = {
	{id = 1, name = "Season of Ash", tag = "[S1]", start = 20261101, finish = 20270131, hour = 12,
		modifier = {name = "Ashfall", expMult = 1.1}},
	{id = 2, name = "Season of Frost", tag = "[S2]", start = 20270301, finish = 20270531, hour = 12}
}
local C = {seasons = seasons, join = cfg.join, track = cfg.track}

-- ---------------------------------------------------------------- shipped config sanity
eq(type(cfg.seasons), "table", "config seasons")
for _, s in ipairs(cfg.seasons) do
	local a, b = S.times(s)
	eq(a ~= nil and b ~= nil and b > a, true, "shipped season " .. s.id .. " has valid dates")
end
local keys = {}
for _, m in ipairs(cfg.track) do
	eq(keys[m.key], nil, "track keys unique: " .. m.key)
	keys[m.key] = true
	eq(m.stat == "level" or cfg.stats[m.stat] ~= nil, true, "track stat known: " .. m.key)
	local r = m.reward
	eq(r.kind == "title" or r.kind == "outfit" or r.kind == "addon" or r.kind == "mount", true, "reward kind " .. m.key)
	if r.kind == "outfit" or r.kind == "addon" then
		eq(type(r.male) == "number" and type(r.female) == "number", true, "outfit looks " .. m.key)
	end
end

-- ---------------------------------------------------------------- date math
eq(S.toUnix(20261101, 12), t(2026, 11, 1, 12), "YYYYMMDD at the hour")
eq(S.toUnix("2026-11-01", 0), t(2026, 11, 1, 0), "YYYY-MM-DD")
eq(S.toUnix(1790000000), 1790000000, "unix time passes through")
eq(S.toUnix(20261301, 0), nil, "month 13 invalid")
eq(S.toUnix(-5), nil, "negative invalid")
eq(S.toUnix("soon"), nil, "text invalid")
local s1 = seasons[1]
local a, b = S.times(s1)
eq(a, t(2026, 11, 1, 12), "start")
eq(b, t(2027, 1, 31, 12), "finish")
eq(S.status(s1, t(2026, 11, 1, 11, 59)), "upcoming", "a minute before the start")
eq(S.status(s1, t(2026, 11, 1, 12)), "active", "at the start")
eq(S.status(s1, t(2027, 1, 31, 11, 59)), "active", "a minute before the end")
eq(S.status(s1, t(2027, 1, 31, 12)), "ended", "at the end")
eq(S.status({id = 9, start = 20270101, finish = 20261201}, t(2026, 12, 15)), "ended", "finish before start never runs")
-- overrides (/season start|end)
local ov = {[1] = {start = t(2026, 10, 8, 9)}}
eq(S.status(s1, t(2026, 10, 9), ov), "active", "started early by /season start")
ov = {[1] = {finish = t(2026, 12, 1)}}
eq(S.status(s1, t(2026, 12, 2), ov), "ended", "ended early by /season end")
eq(S.active(seasons, t(2026, 12, 1)).id, 1, "active season")
eq(S.active(seasons, t(2027, 2, 15)), nil, "between seasons")
eq(S.upcoming(seasons, t(2027, 2, 15)).id, 2, "next season")
eq(S.upcoming(seasons, t(2026, 10, 1)).id, 1, "earliest upcoming")
eq(S.upcoming(seasons, t(2027, 6, 1)), nil, "nothing upcoming")
eq(S.formatDuration(93784), "1d 2h", "duration days")
eq(S.formatDuration(7500), "2h 5m", "duration hours")
eq(S.formatDuration(300), "5m", "duration minutes")
eq(S.formatDuration(20), "under a minute", "duration seconds")
eq(S.formatDuration(-1), "under a minute", "negative duration")
-- over a year end and a DST change: whole calendar days
eq(S.toUnix(20270101, 12) - S.toUnix(20261231, 12) >= 82800, true, "next day")

-- ---------------------------------------------------------------- realms
local during, after = t(2026, 12, 1), t(2027, 2, 15)
eq(S.realm(nil, during, seasons), 0, "standard character")
eq(S.realm({season = 1, migrated = 0}, during, seasons), 1, "season character")
eq(S.realm({season = 1, migrated = 12345}, during, seasons), 0, "migrated")
eq(S.realm({season = 1, migrated = 0}, after, seasons), 0, "season over: standard even before the migration")
eq(S.realm({season = 7, migrated = 0}, during, seasons), 0, "unknown season")
eq(S.tagRealm(nil, during, seasons), nil, "untagged item")
eq(S.tagRealm(0, during, seasons), 0, "standard tag")
eq(S.tagRealm(1, during, seasons), 1, "season tag")
eq(S.tagRealm(1, after, seasons), 0, "season tag after the season")

-- ---------------------------------------------------------------- join eligibility
local function join(info, when, o)
	return S.joinCheck(info, C, when or during, o)
end
local ok, why = join({level = 1, items = 0})
eq(ok and ok.id, 1, "fresh character joins")
ok, why = join({level = 7, items = 0})
eq(ok and ok.id, 1, "level 7 joins")
ok, why = join({level = 8, items = 0})
eq(ok, nil, "level 8 refused")
eq(why:find("level 7 or lower", 1, true) ~= nil, true, "level reason")
ok, why = join({level = 1, items = 3})
eq(ok, nil, "items in the depot refused")
eq(why:find("depot", 1, true) ~= nil, true, "depot reason")
ok, why = join({level = 1, items = 0, party = true})
eq(ok, nil, "in a party refused")
ok, why = join({level = 1, items = 0, house = true})
eq(ok, nil, "house owner refused")
ok, why = join({level = 1, items = 0, row = {season = 1, migrated = 0}})
eq(ok, nil, "already joined")
eq(why:find("already a", 1, true) ~= nil, true, "already reason")
ok, why = join({level = 1, items = 0, row = {season = 1, migrated = 99}})
eq(ok, nil, "a migrated character cannot join again")
ok, why = join({level = 1, items = 0}, t(2026, 10, 1))
eq(ok, nil, "before the season")
eq(why:find("starts in", 1, true) ~= nil, true, "upcoming reason")
ok, why = join({level = 1, items = 0}, t(2027, 7, 1))
eq(why, "No season is running.", "no season")
ok = join({level = 1, items = 0}, t(2026, 10, 1), {[1] = {start = t(2026, 9, 30)}})
eq(ok and ok.id, 1, "joins after /season start")
ok = join({level = 1, items = 0}, t(2027, 3, 10))
eq(ok and ok.id, 2, "second season")

-- ---------------------------------------------------------------- isolation decisions
eq(S.tradeAllowed(1, 1), true, "same season trades")
eq(S.tradeAllowed(0, 0), true, "standard trades")
eq(S.tradeAllowed(1, 0), false, "season -> standard refused")
eq(S.tradeAllowed(0, 1), false, "standard -> season refused")
eq(S.tradeAllowed(1, 2), false, "different seasons refused")
eq(S.tradeAllowed(1, 0, false, true), true, "staff exempt")
eq(S.partyAllowed(1, 0), false, "party across realms refused")
eq(S.partyAllowed(1, 1), true, "party same season")
local okm, key = S.moveCheck({mover = 1, tags = {}})
eq(okm, true, "untagged item")
okm, key = S.moveCheck({mover = 1, tags = {1, 1}})
eq(okm, true, "own realm tags")
okm, key = S.moveCheck({mover = 1, tags = {0}})
eq(okm, false, "season character takes a standard drop")
eq(key, "move", "move reason")
okm, key = S.moveCheck({mover = 0, tags = {0, 1}})
eq(okm, false, "standard loots inside a season corpse")
okm, key = S.moveCheck({mover = 1, mail = 0})
eq(okm, false, "mail to a standard character")
eq(key, "mail", "mail reason")
okm = S.moveCheck({mover = 1, mail = 1})
eq(okm, true, "mail within the season")
okm, key = S.moveCheck({mover = 1, houseFrom = 0})
eq(okm, false, "taking from a standard house")
eq(key, "house", "house reason")
okm, key = S.moveCheck({mover = 0, houseTo = 1})
eq(okm, false, "dropping into a season house")
okm = S.moveCheck({mover = 0, houseTo = 0, houseFrom = 0, tags = {0}})
eq(okm, true, "standard in a standard house")
okm = S.moveCheck({mover = 1, exempt = true, tags = {0}, mail = 0})
eq(okm, true, "staff never blocked")
eq(S.mailReceiver("Kael Vorn\nhello"), "Kael Vorn", "receiver first line")
eq(S.mailReceiver("  Kael Vorn  \r\nTown"), "Kael Vorn", "trimmed, CRLF")
eq(S.mailReceiver(""), nil, "empty label")
eq(S.mailReceiver(nil), nil, "no text")

-- ---------------------------------------------------------------- milestones and the reward track
eq(S.mergeStat("add", 3, 1), 4, "add")
eq(S.mergeStat("add", nil, 5), 5, "add from nothing")
eq(S.mergeStat("max", 7, 5), 7, "max keeps")
eq(S.mergeStat("max", 7, 9), 9, "max raises")
eq(S.mergeStat("count", 2, 1234567), 3, "count ignores the value")
local track = {
	{key = "l100", stat = "level", value = 100, name = "L100", reward = {kind = "title", title = "Ashborn"}},
	{key = "l300", stat = "level", value = 300, name = "L300", reward = {kind = "outfit", male = 667, female = 666, name = "DH"}},
	{key = "b25", stat = "bounty", value = 25, name = "B25", reward = {kind = "mount", id = 105, name = "Doom Skull"}},
	{key = "r10", stat = "rift", value = 10, name = "R10", requires = "ChaosRift", reward = {kind = "title", title = "Rw"}}
}
local function keysOf(list)
	local out = {}
	for _, m in ipairs(list) do
		out[#out + 1] = m.key
	end
	return table.concat(out, ",")
end
local noRift = function(name) return name ~= "ChaosRift" end
local withRift = function() return true end
eq(keysOf(S.milestonesDue(track, {level = 99}, {}, noRift)), "", "level 99: nothing")
eq(keysOf(S.milestonesDue(track, {level = 100}, {}, noRift)), "l100", "level 100")
eq(keysOf(S.milestonesDue(track, {level = 350, bounty = 25}, {}, noRift)), "l100,l300,b25", "several at once")
eq(keysOf(S.milestonesDue(track, {level = 350, bounty = 25}, {l100 = true, b25 = true}, noRift)), "l300", "already reached skipped")
eq(keysOf(S.milestonesDue(track, {level = 1, rift = 12}, {}, noRift)), "", "rift milestone hidden without rifts")
eq(keysOf(S.milestonesDue(track, {level = 1, rift = 12}, {}, withRift)), "r10", "rift milestone with rifts")
local view = S.trackView(track, {level = 150, bounty = 30}, {l100 = {by = "Kael", at = 5}}, noRift)
eq(#view, 3, "view hides the rift milestone without rifts")
eq(view[1].unlocked, true, "unlocked")
eq(view[1].by, "Kael", "unlocked by")
eq(view[1].reward, "Title: Ashborn", "title reward text")
eq(view[2].progress, 150, "progress")
eq(view[2].unlocked, false, "not unlocked")
eq(view[3].progress, 25, "progress capped at the goal")
eq(view[3].reward, "Doom Skull", "named reward text")
local look, addons = S.rewardLook(track[2].reward, true)
eq(look, 666, "female look")
eq(addons, 0, "outfit without addons")
look, addons = S.rewardLook({kind = "addon", male = 667, female = 666, addons = 3}, false)
eq(look, 667, "male look")
eq(addons, 3, "addons")
eq(S.rewardLook(track[3].reward, false), nil, "mount is not an outfit")
-- the shipped track: level 1000 reaches every level milestone
local due = S.milestonesDue(cfg.track, {level = 1000}, {}, noRift)
eq(#due >= 4, true, "shipped level milestones")

-- ---------------------------------------------------------------- end of season (migration)
eq(S.migrationDue({season = 1, migrated = 0}, during, seasons), false, "not during the season")
eq(S.migrationDue({season = 1, migrated = 0}, after, seasons), true, "after the end")
eq(S.migrationDue({season = 1, migrated = 777}, after, seasons), false, "never twice (idempotent)")
eq(S.migrationDue({season = 1, migrated = 0}, t(2026, 12, 2), {[1] = {finish = t(2026, 12, 1)}}), true,
	"after /season end")
eq(S.migrationDue({season = 42, migrated = 0}, during, seasons), true, "season removed from the config")
eq(S.migrationDue(nil, after, seasons), false, "standard character")
local plan = S.migrationPlan({{season = 1, migrated = 0}, {season = 1, migrated = 5}, {season = 2, migrated = 0}},
	t(2027, 3, 10), seasons)
eq(#plan, 1, "only the ended season's unmigrated characters")
eq(plan[1].season, 1, "plan row")
plan = S.migrationPlan(plan, t(2027, 3, 10), seasons)
eq(#plan, 1, "plan is pure (the DB update marks the row)")
plan[1].migrated = 99
eq(#S.migrationPlan(plan, t(2027, 3, 10), seasons), 0, "a migrated row is not planned again")

-- ---------------------------------------------------------------- season uniques
eq(S.uniqueAllowed(nil, 0, during, seasons), true, "normal unique")
eq(S.uniqueAllowed(1, 1, during, seasons), true, "season unique for a season character")
eq(S.uniqueAllowed(1, 0, during, seasons), false, "season unique not for a standard character")
eq(S.uniqueAllowed(1, nil, during, seasons), false, "season unique not without an owner during the season")
eq(S.uniqueAllowed(1, 0, t(2026, 10, 1), seasons), false, "before the season: for nobody")
eq(S.uniqueAllowed(1, 1, t(2026, 10, 1), seasons), false, "before the season: for nobody (season realm)")
eq(S.uniqueAllowed(1, 0, after, seasons), true, "after the season: for everyone")
eq(S.uniqueAllowed(1, nil, after, seasons), true, "after the season: also without an owner")
eq(S.uniqueAllowed(true, 1, during, seasons), true, "season = true means season 1")
eq(S.uniqueAllowed(2, 1, t(2027, 3, 10), seasons), false, "season 1 character during season 2: no season 2 unique")

-- ---------------------------------------------------------------- look text
eq(S.lookLine({season = 1, migrated = 0}, during, seasons, nil, "She"), "She is a Season of Ash character [S1].", "look")
eq(S.lookLine({season = 1, migrated = 0}, during, seasons, nil, "You"), "You are a Season of Ash character [S1].", "own look")
eq(S.lookLine({season = 1, migrated = 5}, after, seasons, nil, "He"), "He is a veteran of Season of Ash.", "veteran")
eq(S.lookLine(nil, during, seasons), nil, "standard: no line")

print("season_test: OK")
