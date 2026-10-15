-- Run from the server/ folder: luajit tests/discord_test.lua (no engine; CI runs it with luajit and lua5.3)
-- Discord announcements (data/scripts/chaos/discord_core.lua, discord.lua): switches, the per-minute rate limit, the
-- event texts, level milestones, the daily restart window, the queue INSERT, the schema against sql/chaos_discord.sql,
-- and discord.lua against a mocked engine (records and firsts, world boss start and kill, Ascended and Cinderheart,
-- levels, staff, season start / end once over restarts, server up / restart / down, hooks never stacked). Nothing here
-- does HTTP: the game only writes queue rows.
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label or "") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/discord_config.lua")
dofile("data/scripts/chaos/discord_core.lua")
local D = ChaosDiscordCore
local cfg = ChaosDiscordConfig
local function esc(s)
	return "'" .. tostring(s):gsub("'", "''") .. "'"
end

-- ------------------------------------------------------------------ switches, channels, rate limit
for kind, on in pairs(cfg.events) do
	check(on == true, kind .. " is on by default")
	check(cfg.channels[kind] ~= nil, kind .. " has a channel")
end
check(not D.enabled({enabled = false, events = {record = true}}, "record"), "the master switch")
check(not D.enabled({events = {record = false}}, "record"), "one event off")
check(not D.enabled(cfg, "bazaar_sale"), "the bazaar events are the worker's")
local st = {}
local lim = {perMinute = {default = 2, level = 3}}
check(D.allow(st, lim, "record", 600) and D.allow(st, lim, "record", 610), "two in a minute")
check(not D.allow(st, lim, "record", 650), "the third is dropped")
eq(st.dropped, 1, "dropped rows are counted")
check(D.allow(st, lim, "level", 650), "another kind has its own count")
check(D.allow(st, lim, "record", 660), "a new minute")

-- ------------------------------------------------------------------ events
local ev = D.record(cfg, "New record: Ashmaw in 4:12 by Arwen.")
check(ev.kind == "record" and ev.channel == "records" and ev.title == "New record", "record event")
eq(D.first(cfg, "x").channel, "records", "firsts go to the records channel")
ev = D.worldBossSpawn(cfg, "Ashmaw", 250)
check(ev.title == "World boss: Ashmaw" and ev.fields[1].value == "250+" and ev.channel == "bosses", "world boss spawn")
ev = D.bossKill(cfg, "worldboss_kill", "Ashmaw", 312, {"Arwen", "Bram", "Cora"})
eq(ev.text, "Arwen, Bram and Cora have slain Ashmaw in 5:12.", "kill text")
eq(ev.fields[2].value, "3", "fighters")
ev = D.bossKill(cfg, "cinderheart_kill", "The Cinderheart", 3725, {"Arwen"})
eq(ev.text, "Arwen has extinguished the Cinderheart in 1:02:05.", "the Cinderheart, solo, over an hour")
eq(D.names({"a", "b", "c", "d", "e"}, 3), "a, b, c and 2 more", "long lists are cut")
eq(D.level(cfg, "Arwen", 500, "Juggernaut").text, "Arwen the Juggernaut reached level 500.", "level text")
eq(D.season(cfg, "season_start", {name = "Season of Ash"}).title, "Season of Ash has begun", "season start")
eq(D.season(cfg, "season_end", nil).title, "The season has ended", "season end without a name")
eq(D.status(cfg, "status_restart", "Cinders of Chaos").title, "Daily restart", "restart")
eq(#D.record(cfg, string.rep("x", 3000)).text, 2000, "text cut to 2000")

-- ------------------------------------------------------------------ milestones, restart window
eq(table.concat(D.milestones(499, 500, {500, 1000}), ","), "500", "500 reached")
eq(table.concat(D.milestones(498, 1200, {1000, 500}), ","), "500,1000", "two at once, in order")
eq(#D.milestones(500, 501, {500, 1000}), 0, "already past")
local xml = '<globalevent name="Server Save" time="06:00:00" script="serversave.lua" />\n' ..
	'<!-- <globalevent name="old" time="03:00:00" script="serversave.lua" /> -->'
local h, m = D.saveTime(xml)
check(h == 6 and m == 0, "save time from globalevents.xml")
check(D.saveTime('<!-- <globalevent time="06:00:00" script="serversave.lua" /> -->') == nil, "commented out: none")
check(D.isDailyRestart({hour = 6, min = 5}, 6, 0, 20), "5 minutes after the save")
check(not D.isDailyRestart({hour = 5, min = 59}, 6, 0, 20), "before the save")
check(not D.isDailyRestart({hour = 6, min = 30}, 6, 0, 20), "too late")
check(D.isDailyRestart({hour = 0, min = 10}, 23, 55, 20), "over midnight")
check(not D.isDailyRestart({hour = 6, min = 5}, nil, nil, 20), "no server save configured")

-- ------------------------------------------------------------------ SQL
local sql = D.insertSql("chaos_discord_queue", D.record(cfg, "It's a record"), 1791000000, esc,
	function() return '[]' end)
eq(sql, "INSERT INTO `chaos_discord_queue` (`created_at`, `kind`, `channel`, `title`, `body`, `fields`) VALUES " ..
	"(1791000000, 'record', 'records', 'New record', 'It''s a record', '[]')", "the queue INSERT, escaped")
local f = io.open("sql/chaos_discord.sql", "r")
local file = f and f:read("*a") or ""
if f then f:close() end
check(file:find(D.schemaSql(cfg.table) .. ";", 1, true) ~= nil, "sql/chaos_discord.sql has the queue table")
check(file:find("CREATE TABLE IF NOT EXISTS `chaos_discord_state`", 1, true) ~= nil, "and the worker's state table")

-- ------------------------------------------------------------------ discord.lua against a mocked engine
local queries, async = {}, {}
local configRows = {}
db = {
	escapeString = esc,
	query = function(s) queries[#queries + 1] = s
		local key, v = s:match("VALUES %('([^']+)', '([^']+)'%)")
		if key and s:find("server_config", 1, true) then configRows[key] = v end
		return true end,
	asyncQuery = function(s) async[#async + 1] = s end,
	storeQuery = function(s)
		local key = s:match("`config` = '([^']+)'")
		if key and configRows[key] then return key end
		return false
	end
}
result = {getString = function(id) return configRows[id] end, free = function() end}
json = {encode = function(t) return #t == 0 and "[]" or "[...]" end}
local events, globals = {}, {}
function CreatureEvent(name)
	local e = {name = name}
	function e:type(t) self.t = t end
	function e:register() events[name] = self end
	return e
end
function GlobalEvent(name)
	local e = {name = name}
	function e:interval(ms) self.ms = ms end
	function e:register() globals[name] = self end
	return e
end
SKILL_LEVEL = 8
configManager = {getString = function() return "Cinders of Chaos" end}
configKeys = {SERVER_NAME = 1}

local function mkPlayer(name, group)
	local p = {name = name, group = group or 1, events = {}}
	function p:getName() return self.name end
	function p:getGroup() local g = self.group; return {getId = function() return g end} end
	function p:getVocation() return {getName = function() return "Juggernaut" end} end
	function p:registerEvent(n) self.events[n] = true end
	return p
end

ChaosRecordsCore = {recordText = function(board) return "New record: " .. board end,
	firstText = function(display) return "Realm first: " .. display end}
ChaosRecords = {byKey = {wb_time = {variants = {{key = "ashmaw", name = "Ashmaw"}}},
	ascended = {variants = {{key = "dread", name = "Ascended Dread"}}}}}
function ChaosRecords.submit(run) return run.ok ~= false, "slot" end
Chaos.worldBoss = Chaos.worldBoss or {}
local savedBosses, savedMin = Chaos.worldBoss.bosses, Chaos.worldBoss.minLevel
Chaos.worldBoss.bosses = {{name = "Ashmaw"}, {name = "Grimjaw"}}
Chaos.worldBoss.minLevel = 250
ChaosWorldBoss = {state = {index = 2}}
function ChaosWorldBoss.start(index) if index == 9 then return false, "busy" end return true end
local currentSeason = nil
ChaosSeason = {current = function() return currentSeason end}
Chaos.seasonConfig = {seasons = {{id = 1, name = "Season of Ash"}, {id = 2, name = "Season of Embers"}}}

dofile("data/scripts/chaos/discord.lua")
local X = ChaosDiscord
cfg = ChaosDiscordConfig -- discord.lua loaded the config again
local function rowsOf(kind)
	local n = 0
	for _, s in ipairs(async) do
		if s:find("'" .. kind .. "'", 1, true) then n = n + 1 end
	end
	return n
end

globals.ChaosDiscordStartup.onStartup()
check(queries[1]:find("CREATE TABLE IF NOT EXISTS `chaos_discord_queue`", 1, true), "startup creates the queue")
eq(rowsOf("status_up"), 1, "server up")
eq(configRows[cfg.seasonKey], "0", "the first check only records the season (none)")
local wrapped = ChaosRecords.submit
X.installHooks()
check(ChaosRecords.submit == wrapped, "hooks installed again: not stacked")

ChaosRecordsCore.recordText("wb_time")
ChaosRecordsCore.firstText("Ashmaw")
eq(rowsOf("record"), 1, "a record row"); eq(rowsOf("first"), 1, "a first row")
-- one broadcast per language (records.lua passes lang last): only English posts, and only once
ChaosRecordsCore.recordText("rift", nil, nil, nil, nil, nil, "pt-BR")
ChaosRecordsCore.recordText("rift", nil, nil, nil, nil, nil, "en")
ChaosRecordsCore.recordText("rift", nil, nil, nil, nil, nil, "en")
ChaosRecordsCore.firstText("Grimjaw", nil, nil, "pt-BR")
eq(rowsOf("record"), 2, "the English text once; other languages never")
eq(rowsOf("first"), 1, "a first in Portuguese is not posted")
check(not ChaosWorldBoss.start(9), "a refused start")
eq(rowsOf("worldboss_spawn"), 0, "nothing for a refused start")
check(ChaosWorldBoss.start(), "a start")
eq(rowsOf("worldboss_spawn"), 1, "world boss spawn row")
check(async[#async]:find("World boss: Grimjaw", 1, true), "the boss of the event's index")

ChaosRecords.submit({board = "wb_time", variant = "ashmaw", value = 300, members = {mkPlayer("Bram"), {guid = 5, name = "Arwen"}}})
ChaosRecords.submit({board = "wb_time", variant = "ashmaw", value = 300, members = {}, ok = false})
ChaosRecords.submit({board = "ascended", variant = "dread", value = 200, members = {mkPlayer("Cora")}})
ChaosRecords.submit({board = "ascended", variant = "cinder", value = 900, members = {mkPlayer("Cora")}})
ChaosRecords.submit({board = "tower_floor", value = 30, members = {mkPlayer("Cora")}})
eq(rowsOf("worldboss_kill"), 1, "a counted world boss run posts; a refused one does not")
check(async[#async - 2]:find("Arwen and Bram have slain Ashmaw in 5:00.", 1, true), "fighters sorted by name: " .. async[#async - 2])
eq(rowsOf("ascended_kill"), 1, "Ascended kill"); eq(rowsOf("cinderheart_kill"), 1, "Cinderheart kill")

-- levels
local adv = events.ChaosDiscordAdvance
local arwen, gm = mkPlayer("Arwen"), mkPlayer("Gamemaster", 6)
events.ChaosDiscordLogin.onLogin(arwen)
check(arwen.events.ChaosDiscordAdvance, "login registers the advance event")
eq(adv.onAdvance(arwen, SKILL_LEVEL, 499, 500), true, "advance returns true")
adv.onAdvance(arwen, 0, 499, 500)
adv.onAdvance(gm, SKILL_LEVEL, 999, 1000)
eq(rowsOf("level"), 1, "one milestone; skills and staff never post")
check(async[#async]:find("Arwen the Juggernaut reached level 500.", 1, true), "level row text")

-- seasons: start, the same season again (a restart), end
currentSeason = {id = 1, name = "Season of Ash"}
globals.ChaosDiscordClock.onThink(60000)
eq(rowsOf("season_start"), 1, "season start")
X.lastSeason = nil -- a restart: read from server_config again
globals.ChaosDiscordClock.onThink(60000)
eq(rowsOf("season_start"), 1, "not again after a restart")
currentSeason = nil
globals.ChaosDiscordClock.onThink(60000)
eq(rowsOf("season_end"), 1, "season end")
check(async[#async]:find("Season of Ash has ended", 1, true), "the ended season's name")

-- switched off
cfg.events.record = false
ChaosRecordsCore.recordText("x")
eq(rowsOf("record"), 2, "an event switched off writes nothing")
cfg.events.record = true

-- shutdown: the daily restart or down, written synchronously
local realDate = os.date
local realOpen = io.open
io.open = function(path, mode)
	if path == "data/globalevents/globalevents.xml" then
		return {read = function() return '<globalevent name="Server Save" time="06:00:00" script="serversave.lua" />' end,
			close = function() end}
	end
	return realOpen(path, mode)
end
os.date = function(fmt, t) if fmt == "*t" then return {hour = 6, min = 5} end return realDate(fmt, t) end
queries = {}
globals.ChaosDiscordShutdown.onShutdown()
check(queries[#queries] and queries[#queries]:find("'status_restart'", 1, true), "a shutdown after the save: restart")
os.date = function(fmt, t) if fmt == "*t" then return {hour = 15, min = 0} end return realDate(fmt, t) end
queries = {}
globals.ChaosDiscordShutdown.onShutdown()
check(queries[#queries] and queries[#queries]:find("'status_down'", 1, true), "another time: down")
os.date, io.open = realDate, realOpen
Chaos.worldBoss.bosses, Chaos.worldBoss.minLevel = savedBosses, savedMin

print(string.format("discord_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
