-- Run from the server/ folder: luajit tests/weekend_test.lua (and lua5.3; CI runs both)
-- The Weekend Ritual (O321): weekend_core.lua (the clock, the window, the rotation, what is due, the calendar, the
-- config check) and the glue of weekend.lua on a mocked engine (bonuses, season characters, announcements, the
-- highlight, the switch, the events calendar, the rift hook, the experience cap order).

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

-- ---------------------------------------------------------------- mocked engine
local nconst = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then
		nconst = nconst + 1
		rawset(t, k, nconst)
		return nconst
	end
end})

local realTime = os.time
local fakeNow = 0
os.time = function(tbl)
	if tbl then
		return realTime(tbl)
	end
	return fakeNow
end

local regs, pending = {}, {}
EventCallback = setmetatable({register = function(_, idx)
	for k, v in pairs(pending) do
		regs[#regs + 1] = {name = k, fn = v, index = idx}
	end
	pending = {}
end}, {__newindex = function(_, k, v) pending[k] = v end})

local globals = {}
local gevents, cevents, talks = {}, {}, {}
function GlobalEvent(name)
	local o = {name = name}
	function o:interval(ms) self.ms = ms end
	function o:register() gevents[name] = o end
	return o
end
function CreatureEvent(name)
	local o = {name = name}
	function o:register() cevents[name] = o end
	return o
end
function TalkAction(words)
	local o = {words = words}
	function o:separator() end
	function o:register() talks[words] = o end
	return o
end

local broadcasts, toasts = {}, {}
Game = {
	getStorageValue = function(k) return globals[k] or -1 end,
	setStorageValue = function(k, v) globals[k] = v end,
	getPlayers = function() return {} end,
	broadcastMessage = function(text) broadcasts[#broadcasts + 1] = text end
}
ChaosNotify = {gmBroadcast = function(_, text) toasts[#toasts + 1] = tostring(text) end}

local bossStarts, invasionStarts = {}, {}
local bossBusy = false
ChaosWorldBoss = {
	start = function(i)
		if bossBusy then return false, "a world boss event is already running" end
		bossStarts[#bossStarts + 1] = i or "rotation"
		return true
	end,
	findBoss = function(name) return name == "Grimhorn" and 2 or false end
}
ChaosInvasion = {start = function(area, faction) invasionStarts[#invasionStarts + 1] = tostring(area) return true end}
ChaosSeason = {realmOf = function(p) return p.realm or 0 end}

local function newPlayer(name, realm)
	local p = {name = name, realm = realm, lines = {}}
	function p:getId() return 1 end
	function p:getStorageValue() return -1 end
	function p:sendTextMessage(t, text) self.lines[#self.lines + 1] = text end
	function p:getGroup() return {getId = function() return self.group or 1 end} end
	return p
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/events_schedule.lua")
-- a community goal's rift answer already in place, as community.lua leaves it
ChaosRiftCore = {hooks = {world = function() return {keyChance = 5, rewardMult = 15, extraMods = 1} end}}
local weekendLoot = dofile("data/scripts/chaos/loot_config.lua")
dofile("data/scripts/chaos/weekend.lua")

local K = ChaosWeekendCore
local W = ChaosWeekend
local cfg = Chaos.weekendConfig
cfg.utcOffsetHours = -3 -- Sao Paulo, whatever zone the test machine has
local OFF = -3 * 3600

local function loc(y, m, d, h, mi, s)
	return K.daysFromCivil(y, m, d) * 86400 + (h or 0) * 3600 + (mi or 0) * 60 + (s or 0) - OFF
end

-- ---------------------------------------------------------------- the clock
eq(K.daysFromCivil(1970, 1, 1), 0, "epoch day")
eq(K.daysFromCivil(2026, 10, 30), 20756, "days of 2026-10-30")
do
	local y, m, d = K.civilFromDays(20756)
	eq(y * 10000 + m * 100 + d, 20261030, "civil from days")
	for _, ymd in ipairs({{2000, 2, 29}, {2024, 12, 31}, {2027, 1, 1}, {1999, 3, 1}}) do
		local a, b, c = K.civilFromDays(K.daysFromCivil(ymd[1], ymd[2], ymd[3]))
		eq(a * 10000 + b * 100 + c, ymd[1] * 10000 + ymd[2] * 100 + ymd[3], "round trip " .. ymd[1])
	end
end
do
	local p = K.parts(loc(2026, 10, 30, 18, 5, 9), OFF)
	eq(p.wday, 6, "2026-10-30 is a Friday")
	eq(p.hour * 100 + p.min, 1805, "local clock")
	eq(p.sec, 9, "local seconds")
	eq(K.parts(loc(2026, 11, 1, 23, 59), OFF).wday, 1, "Sunday is 1")
	eq(K.parts(loc(2026, 10, 31, 12, 0), OFF).wday, 7, "Saturday is 7")
	eq(K.stamp(loc(2026, 11, 1, 23, 59, 59), OFF), "2026-11-01 23:59:59", "stamp")
end
eq(K.span(7500), "2h 05m", "span hours")
eq(K.span(45 * 60), "45m", "span minutes")
eq(K.span(2 * 86400 + 3 * 3600), "2d 3h", "span days")
eq(K.offset({utcOffsetHours = -3}, 0), -10800, "fixed offset")
check(type(K.offset({}, realTime())) == "number", "server offset is a number")

-- ---------------------------------------------------------------- the window
local fri = loc(2026, 10, 30, 18, 0)
local mon = loc(2026, 11, 2, 0, 0)
do
	local w = K.window(cfg, fri - 1, OFF)
	check(not w.active, "Friday 17:59:59 is not in it")
	eq(w.nextStart, fri, "the next start is Friday 18:00")
	eq(w.nextKey, 20261030, "the next key")
	w = K.window(cfg, fri, OFF)
	check(w.active, "Friday 18:00:00 is in it")
	eq(w.startsAt, fri, "starts")
	eq(w.endsAt, mon, "ends Monday 00:00")
	eq(w.key, 20261030, "key is the first day")
	eq(w.nextStart, fri + 7 * 86400, "while it runs the next start is next week")
	check(K.window(cfg, loc(2026, 10, 31, 20, 0), OFF).active, "Saturday evening")
	w = K.window(cfg, loc(2026, 11, 1, 23, 59, 59), OFF)
	check(w.active, "Sunday 23:59:59")
	eq(w.remaining, 1, "one second left")
	w = K.window(cfg, mon, OFF)
	check(not w.active, "Monday 00:00 is out")
	eq(w.nextStart, loc(2026, 11, 6, 18, 0), "after Monday: Friday")
	check(not K.window(cfg, loc(2026, 11, 4, 12, 0), OFF).active, "Wednesday")
	check(not K.window(cfg, loc(2026, 10, 30, 12, 0), OFF).active, "Friday noon")
	-- the year turns inside a weekend: 2027-01-01 is a Friday
	w = K.window(cfg, loc(2027, 1, 2, 10, 0), OFF)
	check(w.active, "new year weekend")
	eq(w.key, 20270101, "new year key")
	eq(K.stamp(w.endsAt, OFF), "2027-01-04 00:00:00", "new year end")
	-- the same instant read in UTC is three hours later on the clock: Friday 17:00 local is Friday 20:00 UTC
	check(K.window(cfg, fri - 3600, 0).active, "read in UTC the window is already open at 17:00 local")
end
-- a window that crosses no Sunday (Friday to Saturday) and one longer than a week behave
do
	local c = {schedule = {start = {weekday = 3, hour = 9, minute = 0}, finish = {weekday = 4, hour = 9, minute = 59}},
		rotation = {"a"}, themes = {a = {name = "A", text = "a", xp = 1.1}}, epoch = 20260106}
	local w = K.window(c, loc(2026, 10, 27, 12, 0), OFF) -- 2026-10-27 is a Tuesday
	check(w.active, "Tuesday to Wednesday window")
	eq(K.stamp(w.endsAt, OFF), "2026-10-28 10:00:00", "ends after the last minute")
	check(not K.window(c, loc(2026, 10, 28, 10, 0), OFF).active, "just after")
end

-- ---------------------------------------------------------------- the rotation
do
	local seen, order = {}, {}
	for i = 0, 7 do
		local w = K.window(cfg, fri + i * 7 * 86400 + 3600, OFF)
		order[#order + 1] = w.themeKey
		seen[w.themeKey] = (seen[w.themeKey] or 0) + 1
	end
	eq(order[1], "rifts", "the weekend of 2026-10-30 (43 weeks after the epoch) is rifts")
	eq(order[2], "growth", "then it wraps to the first")
	eq(order[3], "plenty", "plenty")
	eq(order[4], "training", "training")
	eq(order[5], order[1], "four weekends later the same")
	eq(order[8], order[4], "and again")
	eq(seen.growth, 2, "every theme comes twice in eight weekends")
	local epochWeekend = K.window(cfg, loc(2026, 1, 2, 19, 0), OFF)
	eq(epochWeekend.themeKey, "growth", "the epoch's weekend is the first theme")
	-- before the epoch the rotation still works (floored)
	local before = K.window(cfg, loc(2025, 12, 26, 19, 0), OFF)
	eq(before.themeKey, "rifts", "the weekend before the epoch is the last theme")
	-- forceTheme
	cfg.forceTheme = "plenty"
	eq(K.window(cfg, fri + 3600, OFF).themeKey, "plenty", "forced theme")
	cfg.forceTheme = "nope"
	eq(K.window(cfg, fri + 3600, OFF).themeKey, "rifts", "an unknown forced theme is ignored")
	cfg.forceTheme = nil
	local up = K.upcoming(cfg, fri + 86400, OFF, 3)
	eq(#up, 3, "three upcoming")
	eq(up[1].startsAt, fri, "the running weekend first")
	eq(up[2].startsAt, fri + 7 * 86400, "then next week")
	eq(up[3].themeKey, "plenty", "and its theme")
end

-- ---------------------------------------------------------------- what the theme gives
do
	local growth = K.window(cfg, loc(2026, 1, 3, 12, 0), OFF)
	local m = K.mults(cfg, growth, false)
	eq(m.xp, 1.25, "growth xp")
	eq(m.loot, 1, "growth loot")
	eq(m.skill, 1, "growth skill")
	eq(m.riftReward, 0, "growth rift")
	m = K.mults(cfg, growth, true)
	eq(m.xp, 1, "a season character gets no experience bonus")
	cfg.seasonCharacters = true
	eq(K.mults(cfg, growth, true).xp, 1.25, "unless the config lets it")
	cfg.seasonCharacters = false
	eq(K.mults(cfg, K.window(cfg, loc(2026, 1, 7, 12, 0), OFF), false).xp, 1, "outside the window: nothing")
	eq(K.mults(cfg, nil, false).loot, 1, "no window: nothing")
	local rifts = K.window(cfg, fri + 3600, OFF)
	eq(K.mults(cfg, rifts, false).riftReward, 25, "rifts theme")
	-- tries
	eq(K.scaleTries(10, 1.25, function() return 0.1 end), 13, "tries: 12.5 rounds up on a low roll")
	eq(K.scaleTries(10, 1.25, function() return 0.99 end), 12, "tries: and down on a high one")
	eq(K.scaleTries(10, 1, function() return 0 end), 10, "tries: no bonus")
	eq(K.scaleTries(0, 1.25), 0, "tries: zero stays zero")
	local sum = 0
	for _ = 1, 4000 do
		sum = sum + K.scaleTries(1, 1.25)
	end
	check(sum > 4800 and sum < 5200, "one try at a time keeps the bonus on average (" .. sum .. ")")
end

-- ---------------------------------------------------------------- the highlight
do
	local w = K.window(cfg, fri + 3600, OFF)
	eq(K.highlightAt(cfg, w, OFF), loc(2026, 10, 31, 19, 0), "Saturday 19:00")
	cfg.highlight.enabled = false
	eq(K.highlightAt(cfg, w, OFF), nil, "highlight off")
	cfg.highlight.enabled = true
	cfg.highlight.weekday, cfg.highlight.hour = 6, 20
	eq(K.highlightAt(cfg, w, OFF), loc(2026, 10, 30, 20, 0), "Friday 20:00 is the same day as the start")
	cfg.highlight.weekday, cfg.highlight.hour = 7, 19
end

-- ---------------------------------------------------------------- what is due
do
	local function kinds(list)
		local out = {}
		for _, a in ipairs(list) do out[#out + 1] = a.kind end
		return table.concat(out, ",")
	end
	local done = {}
	local function run(t)
		local list = K.due(cfg, t, OFF, done)
		for _, a in ipairs(list) do
			for _, k in ipairs(a.mark or {}) do done[k] = true end
		end
		return list
	end
	eq(kinds(run(fri - 60)), "", "nothing before the start")
	eq(kinds(run(fri + 5)), "start", "the start")
	eq(kinds(run(fri + 35)), "", "once only")
	eq(kinds(run(loc(2026, 10, 31, 18, 29))), "", "Saturday 18:29: no warning yet")
	local list = run(loc(2026, 10, 31, 18, 30, 5))
	eq(kinds(list), "warnhl", "30 minutes before")
	eq(list[1].minutes, 30, "30")
	eq(kinds(run(loc(2026, 10, 31, 18, 40))), "", "10 minutes before is at 18:50")
	list = run(loc(2026, 10, 31, 18, 50, 1))
	eq(list[1] and list[1].minutes, 10, "10 minutes before")
	eq(kinds(run(loc(2026, 10, 31, 19, 0, 0))), "highlight", "the highlight at 19:00")
	eq(kinds(run(loc(2026, 10, 31, 19, 0, 30))), "", "and not twice")
	eq(kinds(run(loc(2026, 11, 1, 22, 59))), "", "Sunday 22:59: not yet")
	list = run(loc(2026, 11, 1, 23, 0, 10))
	eq(kinds(list), "endwarn", "one hour before the end")
	eq(list[1].minutes, 60, "60 minutes")
	eq(kinds(run(loc(2026, 11, 1, 23, 30))), "", "once only")
	-- a server that starts late: the start is not announced hours later, the late warning is the closest one
	done = {}
	eq(kinds(run(fri + 31 * 60)), "", "a start seen 31 minutes late is not announced")
	done = {}
	list = run(loc(2026, 10, 31, 18, 55))
	eq(kinds(list), "warnhl", "restart at 18:55")
	eq(list[1].minutes, 10, "says 10 minutes, not 30")
	check(done["warn30:20261030"] and done["warn10:20261030"], "the earlier warning is marked too")
	-- a highlight that could not start is offered again until the grace is over
	done = {}
	check(kinds(K.due(cfg, loc(2026, 10, 31, 19, 10), OFF, {["start:20261030"] = true, ["warn30:20261030"] = true, ["warn10:20261030"] = true})) == "highlight",
		"still offered at 19:10")
	check(kinds(K.due(cfg, loc(2026, 10, 31, 19, 21), OFF, {["start:20261030"] = true, ["warn30:20261030"] = true, ["warn10:20261030"] = true})) == "",
		"given up after 20 minutes")
end

-- ---------------------------------------------------------------- the login preview
do
	local pv = K.preview(cfg, loc(2026, 10, 29, 18, 0), OFF)
	check(pv ~= nil, "Thursday 18:00: 24 hours before")
	eq(pv.wait, 86400, "24 hours")
	eq(pv.themeKey, "rifts", "its theme")
	check(K.preview(cfg, loc(2026, 10, 28, 12, 0), OFF) == nil, "Wednesday noon: 54 hours, too early")
	check(K.preview(cfg, fri + 60, OFF) == nil, "while it runs: none")
	check(K.preview(cfg, loc(2026, 11, 2, 9, 0), OFF) == nil, "Monday: none")
end

-- ---------------------------------------------------------------- the calendar
do
	local cal = K.calendar(cfg, loc(2026, 10, 15, 12, 0), OFF, 62)
	eq(#cal, 9, "nine weekends from 2026-10-01 over 62 days")
	eq(cal[1].startdate.date, "2026-10-02 18:00:00", "first start")
	eq(cal[1].enddate.date, "2026-10-04 23:59:59", "first end")
	eq(cal[5].startdate.date, "2026-10-30 18:00:00", "fifth start")
	eq(cal[5].enddate.date, "2026-11-01 23:59:59", "fifth end")
	eq(cal[1].name, "Weekend Ritual", "name")
	check(cal[1].colorlight and cal[1].colordark and cal[1].description ~= "", "colours and description")
	for i = 2, #cal do
		check(cal[i].startdate.date > cal[i - 1].startdate.date, "sorted " .. i)
	end
	-- a weekend that began in the previous month and is still going on the 1st
	cal = K.calendar(cfg, loc(2026, 11, 10, 12, 0), OFF, 30)
	eq(cal[1].startdate.date, "2026-10-30 18:00:00", "a weekend still running on the 1st is listed")
	eq(cal[2].startdate.date, "2026-11-06 18:00:00", "then the 6th")
	cal = K.calendar(cfg, loc(2026, 8, 20, 12, 0), OFF, 31)
	eq(cal[1].startdate.date, "2026-07-31 18:00:00", "July 31 runs into August")
	local feb = K.calendar(cfg, loc(2026, 5, 5, 12, 0), OFF, 31)
	eq(feb[1].startdate.date, "2026-05-01 18:00:00", "a weekend that starts on the 1st")
end

-- ---------------------------------------------------------------- the config
eq(#K.validate(cfg), 0, "the shipped config is fine: " .. table.concat(K.validate(cfg), "; "))
do
	local function broken(mut)
		local c = dofile("data/scripts/chaos/weekend_config.lua")
		mut(c)
		return K.validate(c)
	end
	check(#broken(function(c) c.themes.growth.xp = 2 end) > 0, "xp 2 is refused")
	check(#broken(function(c) c.themes.plenty.loot = 1.6 end) > 0, "loot 1.6 is refused")
	check(#broken(function(c) c.themes.training.skill = 3 end) > 0, "skill 3 is refused")
	check(#broken(function(c) c.themes.rifts.riftReward = 80 end) > 0, "riftReward 80 is refused")
	check(#broken(function(c) c.themes.rifts = {name = "x", text = "y"} end) > 0, "a theme that gives nothing")
	check(#broken(function(c) c.rotation = {"ghost"} end) > 0, "an unknown theme in the rotation")
	check(#broken(function(c) c.rotation = {} end) > 0, "an empty rotation")
	check(#broken(function(c) c.epoch = 20260103 end) > 0, "an epoch on another weekday")
	check(#broken(function(c) c.highlight.weekday = 3 end) > 0, "a highlight outside the window")
	check(#broken(function(c) c.highlight.weekday, c.highlight.hour, c.highlight.minute = 1, 23, 50 end) > 0,
		"a highlight whose grace runs past the end")
	check(#broken(function(c) c.highlight.kind = "dragon" end) > 0, "an unknown highlight kind")
	check(#broken(function(c) c.schedule.start.weekday = 9 end) > 0, "a bad weekday")
	check(#broken(function(c) c.tickSeconds = 1 end) > 0, "a tick that is too fast")
	check(#broken(function(c) c.highlight.enabled = false; c.highlight.kind = "dragon" end) == 0, "a highlight that is off is not checked")
end
do
	-- the experience goes in before the cap
	local capCfg = dofile("data/scripts/chaos/xpcap_config.lua")
	check(cfg.xpIndex < capCfg.index, "the weekend's experience (" .. cfg.xpIndex .. ") comes before the cap (" .. capCfg.index .. ")")
	-- the shipped values with the cap: x1.25 of the weekend with Blood Moon's x1.5 stays far under the cap of x4
	check(cfg.themes.growth.xp * Chaos.events.list[1].bonus.xp < capCfg.cap, "weekend x Blood Moon is under the cap")
	-- every text has a pt-BR entry
	local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
	for key, th in pairs(cfg.themes) do
		check(pt[th.name] ~= nil, "pt-BR name of " .. key)
		check(pt[th.text] ~= nil, "pt-BR text of " .. key)
	end
	check(pt[cfg.calendar.name] ~= nil, "pt-BR calendar name")
	for _, d in ipairs(K.WEEKDAYS) do
		check(pt[d] ~= nil, "pt-BR weekday " .. d)
	end
	-- the storage keys are in the reserved block and differ
	local seen = {}
	for name, key in pairs(cfg.globalStorage) do
		check(key >= 7103040 and key <= 7103049, "storage " .. name .. " is in its block")
		check(not seen[key], "storage " .. name .. " is unique")
		seen[key] = true
	end
end

-- ---------------------------------------------------------------- the glue
local function callback(name, index)
	for _, r in ipairs(regs) do
		if r.name == name and r.index == index then
			return r.fn
		end
	end
end
local xp = callback("onGainExperience", 55)
local skill = callback("onGainSkillTries", 6)
check(xp ~= nil, "the experience callback is at index 55")
check(skill ~= nil, "the skill callback is at index 6")
local monster = {isMonster = function() return true end}
local npc = {isMonster = function() return false end}
local hero, rookie = newPlayer("Hero", 0), newPlayer("Racer", 3)

-- ordinary Wednesday
fakeNow = loc(2026, 11, 4, 12, 0)
W.cache = nil
eq(xp(hero, monster, 100, 100), 100, "Wednesday: no bonus")
eq(W.lootMult({player = hero}), 1, "Wednesday: loot")
check(next(ChaosEvents.dynamic) == nil, "Wednesday: no dynamic event")

-- the rifts weekend of 2026-10-30
fakeNow = fri + 60
W.cache = nil
W.tick(fakeNow)
check(ChaosEvents.dynamic.weekend_ritual ~= nil, "the dynamic event while it runs")
eq(ChaosEvents.dynamic.weekend_ritual.untilTime, mon, "until Monday")
eq(ChaosEvents.bonus("xp"), 1, "ChaosEvents.bonus is untouched: the theme is not a calendar bonus")
do
	local mine
	for _, line in ipairs(ChaosEvents.describeActive(nil, hero)) do
		if line:find("Weekend Ritual", 1, true) then mine = (mine and mine .. "|" or "") .. line end
	end
	check(mine and mine:find("Ritual of Rifts", 1, true) and mine:find("Sunday at 23:59", 1, true), "!events names the theme and the end: " .. tostring(mine))
end
eq(xp(hero, monster, 100, 100), 100, "rifts weekend: no experience bonus")
local hook = ChaosRiftCore.hooks.world
local wm = hook(hero, {})
eq(wm.rewardMult, 15 + 25, "the rift hook adds 25 to the community's 15")
eq(wm.keyChance, 5, "and keeps its key chance")
eq(wm.extraMods, 1, "and its extra modifiers")
eq(hook(rookie, {}).rewardMult, 15, "a season character gets only the community's answer")
-- a reload of the file wraps nothing twice
local before = ChaosRiftCore.hooks.world
dofile("data/scripts/chaos/weekend.lua")
eq(ChaosRiftCore.hooks.world, before, "a second load keeps the same hook")
eq(hook(hero, {}).rewardMult, 40, "and the same sum")
cfg = Chaos.weekendConfig -- the reload read the config again
cfg.utcOffsetHours = -3

-- the announcements of the start
eq(#broadcasts, 1, "one broadcast at the start")
check(broadcasts[1]:find("WEEKEND RITUAL: the weekend begins! Ritual of Rifts", 1, true), "start text: " .. broadcasts[1])
check(broadcasts[1]:find("until Sunday at 23:59", 1, true), "start text names the end: " .. broadcasts[1])
eq(#toasts, 1, "and one toast")
eq(globals[7103041], 20261030, "the start is recorded")
W.tick(fakeNow + 30)
eq(#broadcasts, 1, "the next pass says nothing")
W.done = {}
W.tick(fakeNow + 60)
eq(#broadcasts, 1, "a restart (memory cleared) does not say it again: the storage remembers")

-- the growth weekend: force the theme to test the experience and the skill callbacks
cfg.forceTheme = "growth"
W.cache = nil
eq(xp(hero, monster, 100, 100), 125, "growth: +25% experience")
eq(xp(hero, npc, 100, 100), 100, "growth: not from a non-monster source")
eq(xp(rookie, monster, 100, 100), 100, "growth: not for a season character")
cfg.forceTheme = "training"
W.cache = nil
do
	local sum = 0
	for _ = 1, 2000 do
		sum = sum + skill(hero, 1, 1)
	end
	check(sum > 2300 and sum < 2700, "training: about +25% tries (" .. sum .. ")")
	sum = 0
	for _ = 1, 200 do
		sum = sum + skill(rookie, 1, 1)
	end
	eq(sum, 200, "training: not for a season character")
	eq(skill(hero, 1, 0), 0, "training: zero stays zero")
end
cfg.forceTheme = "plenty"
W.cache = nil
eq(W.lootMult({player = hero}), 1.25, "plenty: loot")
eq(W.lootMult({player = rookie}), 1, "plenty: not for a season character")
eq(weekendLoot.rateMult({player = hero}), 1.25 * ChaosEvents.bonus("loot"), "loot_config.lua rateMult carries it (Loot Frenzy runs on Fridays)")
cfg.forceTheme = nil
W.cache = nil

-- Saturday: warnings and the highlight
for i = #broadcasts, 1, -1 do broadcasts[i] = nil end
fakeNow = loc(2026, 10, 31, 18, 30, 10)
W.tick(fakeNow)
eq(#broadcasts, 1, "30 minute warning")
check(broadcasts[1]:find("the weekend highlight, a world boss, begins in 30 minutes", 1, true), "warning text: " .. tostring(broadcasts[1]))
fakeNow = loc(2026, 10, 31, 18, 50, 10)
W.tick(fakeNow)
eq(#broadcasts, 2, "10 minute warning")
fakeNow = loc(2026, 10, 31, 19, 0, 5)
bossBusy = true
W.tick(fakeNow)
eq(#bossStarts, 0, "a running boss: the highlight waits")
eq(globals[7103043], nil, "and is not marked done")
bossBusy = false
fakeNow = fakeNow + 30
W.tick(fakeNow)
eq(#bossStarts, 1, "the highlight starts the boss of the rotation")
eq(bossStarts[1], "rotation", "no fixed boss: the rotation")
eq(globals[7103043], 20261030, "and is marked done")
fakeNow = fakeNow + 30
W.tick(fakeNow)
eq(#bossStarts, 1, "once")
-- named boss, invasion kind
globals[7103043] = nil
cfg.highlight.boss = "Grimhorn"
W.done = {}
W.tick(fakeNow)
eq(bossStarts[2], 2, "a named boss")
globals[7103043] = nil
cfg.highlight.boss = "Nobody"
W.done = {}
W.tick(fakeNow)
eq(#bossStarts, 2, "an unknown boss name starts nothing")
cfg.highlight.boss = nil
cfg.highlight.kind = "invasion"
W.done = {}
W.tick(fakeNow)
eq(#invasionStarts, 1, "an invasion highlight")
eq(invasionStarts[1], "random", "in a random area")
cfg.highlight.kind = "worldboss"

-- the end warning
for i = #broadcasts, 1, -1 do broadcasts[i] = nil end
fakeNow = loc(2026, 11, 1, 23, 0, 10)
W.tick(fakeNow)
check(broadcasts[#broadcasts] and broadcasts[#broadcasts]:find("it ends in 60 minutes (Sunday at 23:59)", 1, true),
	"end warning: " .. tostring(broadcasts[#broadcasts]))

-- the login line before the start (Thursday)
fakeNow = loc(2026, 11, 5, 18, 0)
W.cache = nil
W.tick(fakeNow)
check(ChaosEvents.dynamic.weekend_ritual == nil, "the dynamic event is gone after the weekend")
do
	local p = newPlayer("Late", 0)
	cevents.ChaosWeekendLogin.onLogin(p)
	eq(#p.lines, 1, "a countdown line on Thursday")
	check(p.lines[1]:find("Weekend Ritual starts Friday at 18:00 (in 1d 0h): Ritual of Growth", 1, true), "countdown: " .. tostring(p.lines[1]))
end

-- the events calendar carries the weekends
do
	local cal = ChaosEvents.calendar(loc(2026, 10, 15, 12, 0)).eventlist
	local n = 0
	for _, e in ipairs(cal) do
		if e.name == "Weekend Ritual" then n = n + 1 end
	end
	check(n >= 8, "the calendar lists the weekends (" .. n .. ")")
end

-- the switch
do
	fakeNow = fri + 60
	W.cache = nil
	cfg.enabled = false
	check(not W.enabled(), "enabled = false")
	eq(xp(hero, monster, 100, 100), 100, "off in the config: no bonus")
	eq(#W.calendarEntries(fakeNow), 0, "off: no calendar entries")
	cfg.enabled = true
	W.cache = nil
	check(W.enabled(), "on again")
	local ok = ChaosAdminPending["events.weekend"].handler({}, {mode = "off"})
	check(ok, "the admin action answers")
	check(not W.enabled(), "switched off by staff")
	eq(globals[7103040], 1, "kept in the global storage")
	eq(W.window(fakeNow).active, false, "no window while off")
	eq(#W.calendarEntries(fakeNow), 0, "no calendar entries while off")
	for i = #broadcasts, 1, -1 do broadcasts[i] = nil end
	globals[7103041] = nil
	W.done = {}
	W.tick(fakeNow)
	eq(#broadcasts, 0, "nothing is announced while off")
	local msgOn = select(2, ChaosAdminHooks.weekend_ritual.start())
	check(W.enabled(), "the event hook start switches it on")
	check(type(msgOn) == "string" and msgOn:find("Running", 1, true), "and says what runs: " .. tostring(msgOn))
	ChaosAdminHooks.weekend_ritual.stop()
	check(not W.enabled(), "the event hook stop switches it off")
	ChaosAdminHooks.weekend_ritual.start()
	-- /weekend
	local staff = newPlayer("Staff", 0)
	staff.group = 5
	talks["/weekend"].onSay(staff, "/weekend", "off")
	check(not W.enabled(), "/weekend off")
	talks["/weekend"].onSay(staff, "/weekend", "on")
	check(W.enabled(), "/weekend on")
	talks["/weekend"].onSay(staff, "/weekend", "status")
	check(staff.lines[#staff.lines]:find("Running", 1, true) ~= nil, "/weekend status")
	local player = newPlayer("Player", 0)
	talks["/weekend"].onSay(player, "/weekend", "off")
	check(W.enabled() and #player.lines == 0, "a player cannot switch it")
	local gm = newPlayer("Gm", 0)
	gm.group = 4
	talks["/weekend"].onSay(gm, "/weekend", "off")
	check(W.enabled(), "a group 4 character sees the status but cannot switch")
end

print(string.format("weekend_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
