-- The Weekend Ritual (weekend.lua, weekend_core.lua; tests/weekend_test.lua; server/README.md "Weekend Ritual (O321)").
-- Every number of the system is here. Returned as a table, loaded as
--     Chaos.weekendConfig = dofile("data/scripts/chaos/weekend_config.lua")
-- No engine calls. Lua 5.1 / LuaJIT and Lua 5.3.
--
-- Every weekend, Friday 18:00 to Sunday 23:59 server time: one theme from the rotation below (a bonus for everybody,
-- free, no store item) and a fixed Saturday highlight (a world boss or an invasion at a set hour).
-- Times are the server's clock. The machine runs in America/Sao_Paulo (docs/OWNER_TODO.md); set `utcOffsetHours` only
-- to pin the schedule to a fixed offset (-3 for Sao Paulo, which has no daylight saving time since 2019).
-- The tables `schedule`, `rotation`, `themes` and `highlight` are plain data: the website calendar can read them.
local C = {}

-- The switch. false: nothing runs (no bonus, no announcement, no highlight). Staff can also switch the ritual off and on
-- without a reload: the admin panel (Events > Weekend Ritual), `/weekend off|on`, or Events > Start / Stop event
-- "weekend_ritual". That choice is a global storage and survives a restart; this switch still wins over it.
C.enabled = true

C.timezone = "America/Sao_Paulo" -- for the website and the docs; the machine's zone decides
C.utcOffsetHours = nil -- nil: the server's own zone

-- weekday numbers follow os.date("*t").wday: 1 = Sunday ... 7 = Saturday. `finish` is the last minute of the window.
C.schedule = {
	start = {weekday = 6, hour = 18, minute = 0},
	finish = {weekday = 1, hour = 23, minute = 59}
}

-- The themes, one per weekend in the order of `rotation`. The weekend that starts on the day `epoch` (YYYYMMDD, a Friday)
-- has the first one. All values are bonuses for everybody for free.
--   xp         x on the experience of a monster kill (before the experience cap, see xpIndex)
--   loot       x on the Chaos loot rate (loot_config.lua rateMult, under its maxRate)
--   skill      x on skill and magic level training tries
--   riftReward percent richer rift chests (the rift's world modifiers, like Ember Tides)
-- The limits in weekend_core.lua K.validate (tests check them): xp and loot at most 1.5, skill at most 2, riftReward at
-- most 50. Blood Moon (Saturday and Sunday, +50% experience) stays and multiplies with the experience theme; the
-- experience cap (xpcap_config.lua cap, x4 of the kill's base) still applies on top of both.
C.epoch = 20260102
C.rotation = {"growth", "plenty", "training", "rifts"}
C.themes = {
	growth = {name = "Ritual of Growth", xp = 1.25,
		text = "Monsters give 25% more experience."},
	plenty = {name = "Ritual of Plenty", loot = 1.25,
		text = "Monsters drop 25% more Chaos loot."},
	training = {name = "Ritual of Training", skill = 1.25,
		text = "Skill and magic level training gives 25% more tries."},
	rifts = {name = "Ritual of Rifts", riftReward = 25,
		text = "Rift chests are 25% richer."}
}
-- a theme key here holds the rotation on that theme (a test weekend, a special weekend); nil: the rotation decides
C.forceTheme = nil

-- Season characters (season.lua realm above 0) race on a fresh start and get no world buffs, rested hunting or returning
-- boost (season_config.lua, catchup_config.lua). false: the personal theme bonuses (experience, loot, skill, rift
-- chests) skip them; the announcements and the highlight are for everybody. true: they get the bonus too.
C.seasonCharacters = false

-- EventCallback indexes. xpIndex must stay below the experience cap (xpcap_config.lua index 85), or the cap would not
-- see the bonus; a test checks it. skillIndex is after the store's training buffs (shop_services.lua, 5).
C.xpIndex = 55
C.skillIndex = 6

-- The Saturday highlight, at a fixed hour of the weekend.
--   kind     "worldboss": the next boss of the rotation (or `boss`, a name part as /worldboss start takes it),
--            "invasion": an invasion (`area` and `faction` keys of invasion_config.lua, "random" for either)
--   weekday, hour, minute   when it starts (inside the window)
--   graceMinutes   a start that fails (another event is running) is tried again every tick until then
--   warnMinutes    broadcasts before the start
-- 19:00 keeps clear of the scheduled world boss of every 6 hours (03:00, 09:00, 15:00, 21:00; worldBoss in
-- chaos_constants.lua): the fight is over well before 21:00.
C.highlight = {
	enabled = true,
	kind = "worldboss",
	boss = nil,
	area = "random",
	faction = nil,
	weekday = 7, hour = 19, minute = 0,
	graceMinutes = 20,
	warnMinutes = {30, 10}
}

-- Announcements. The start is announced if the server sees it within startGraceMinutes of the start; a restart later in
-- the weekend does not repeat it (the weeks done are kept in a global storage).
C.startGraceMinutes = 30
C.endWarnMinutes = 60 -- one broadcast this long before the end
C.loginPreviewHours = 48 -- a login line this long before the start ("starts Friday at 18:00")
C.tickSeconds = 30

-- The events calendar (events_schedule.lua E.calendar: the login screen and the client's Event Calendar): one entry per
-- weekend with these colours. The days of the window are shown; the hours are in the description.
C.calendar = {
	name = "Weekend Ritual",
	description = "The weekend ritual: Friday 18:00 to Sunday 23:59 server time. A theme bonus for the whole weekend " ..
		"and a world boss on Saturday at 19:00.",
	colorlight = "#e0762b", colordark = "#7a3a10"
}

-- Global storages (server/README.md "Storage keys", block 7103040 - 7103049): +0 the staff switch (0 follows the
-- config, 1 off), +1 the weekend (YYYYMMDD of its first day) whose start was announced, +2 whose end was announced,
-- +3 whose highlight was started. +4..9 free.
C.globalStorage = {off = 7103040, started = 7103041, ended = 7103042, highlight = 7103043}

-- /weekend status needs this group; on and off need switchGroup (the same rule as /harvest)
C.staffGroup = 4
C.switchGroup = 5

return C
