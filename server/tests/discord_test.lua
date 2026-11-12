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

-- ------------------------------------------------------------------ O260: the drop feed event
do
	local ev = D.drop(cfg, "Ann", 812, "Hollow Throne Claymore", "unique")
	eq(ev.kind, "drop", "drop kind")
	eq(ev.channel, "drops", "drop channel")
	eq(ev.title, "Unique find", "drop title")
	eq(ev.text, "Ann (Lv 812) found Hollow Throne Claymore!", "drop text")
	eq(D.drop(cfg, "Bob", 90, "Sword", "legendary").title, "Legendary find", "legendary title")
end

-- ------------------------------------------------------------------ O519: the item's data on the drop post
do
	local function field(ev, name)
		for _, f in ipairs(ev.fields) do
			if f.name == name then return f end
		end
	end
	local function real(ev)
		local n = 0
		for _, f in ipairs(ev.fields) do
			if f.name then n = n + 1 end
		end
		return n
	end
	-- a tooltip as item_tooltip_core.lua T.build makes it (the parts the post reads)
	local tip = {name = "Unraveling Titan Axe of Carnage", slot = "Two-handed axe", rarity = 5,
		base = {{k = "attack", l = "Attack", v = 52}, {k = "defense", l = "Defense", v = 14},
			{k = "attackspeed", l = "Attack Interval", v = 2, fmt = "sec", low = true},
			{k = "protect1", l = "Physical Protection", v = 5, fmt = "pct"},
			{k = "yourinterval", l = "Your Attack Interval", v = 1.7, fmt = "sec"}, {k = "dps", l = "Estimated DPS", v = 99, fmt = "est"}},
		mods = {{t = "Fire +9% dmg", tr = 3, sd = "p"}, {t = "Life on Kill +12", tr = 4, sd = "s", bd = true},
			{t = "Block Chance +4%", tr = 8, sd = "i"}},
		quality = {q = 6, cap = 20}, sockets = {count = 2, list = {{name = "Flawless Ruby", text = "Fire Damage +9%"}, {}}},
		req = {level = 189, magic = 12, voc = "Juggernaut, Berserker"}}
	local d = D.dropDetails(tip, {baseName = "titan axe", monster = "Demon", place = "Ashen Wastes", iconUrl = "/chaos-sprites/items/4417.png"})
	eq(d.base, "Titan Axe (two-handed axe)", "base: the item type, what it is worn as")
	eq(#d.stats, 4, "stats: the type's numbers, not the viewer's rows")
	eq(d.stats[3], "Attack Interval 2s", "an interval in seconds")
	eq(d.stats[4], "Physical Protection 5%", "a protection in percent")
	eq(d.mods[1], "Fire +9% dmg (T3)", "a modifier with its tier")
	eq(d.mods[2], "Life on Kill +12 (T4, bound)", "a bound modifier")
	eq(d.mods[3], "Implicit: Block Chance +4% (T8)", "a corrupted implicit")
	eq(d.mods[4], "Quality +6%", "quality")
	eq(d.mods[5], "Socket 1: Flawless Ruby (Fire Damage +9%)", "a gem")
	eq(d.mods[6], "Socket 2: empty", "an empty socket")
	local ev = D.drop(cfg, "Massador", 189, "Unraveling Titan Axe of Carnage", "legendary", d)
	eq(ev.title, "Legendary find", "the title stays")
	eq(ev.text, "Massador (Lv 189) found Unraveling Titan Axe of Carnage!", "the text stays")
	eq(field(ev, "Base").value, "Titan Axe (two-handed axe)", "Base field")
	check(field(ev, "Base").inline and field(ev, "Requires").inline and field(ev, "Class").inline, "Base, Requires, Class are inline")
	eq(field(ev, "Requires").value, "Level 189, magic level 12", "level and magic level")
	eq(field(ev, "Class").value, "Juggernaut, Berserker", "classes")
	check(not field(ev, "Stats").inline and field(ev, "Stats").value:find("Attack 52\nDefense 14\nAttack Interval 2s", 1, true), "Stats lines")
	eq(field(ev, "Dropped by").value, "Demon in Ashen Wastes", "monster in place")
	check(field(ev, "Modifiers").value:find("Fire +9% dmg (T3)\nLife on Kill", 1, true), "Modifiers lines")
	check(field(ev, "Passive") == nil, "no passive on a rolled item")
	eq(ev.fields[#ev.fields].thumbnail, "/chaos-sprites/items/4417.png", "the thumbnail entry is last")
	eq(real(ev), 6, "six named fields")
	-- only the monster, only the place
	eq(field(D.drop(cfg, "A", 1, "X", "unique", {monster = "Rat"}), "Dropped by").value, "Rat", "monster alone")
	eq(field(D.drop(cfg, "A", 1, "X", "unique", {place = "Mine"}), "Dropped by").value, "Mine", "place alone")
	-- a unique: its passive line, no tier on its modifiers, the base is not its own name
	local utip = {name = "Hollow Throne Claymore", slot = "Two-handed sword", rarity = 7, unique = {name = "Hollow Throne Claymore"},
		base = {{k = "attack", l = "Attack", v = 80}}, mods = {{t = "Sword +3"}},
		passive = {name = "Hollow Crown", text = "Every 8th hit echoes for 40% of its damage. For: warriors.", flavor = "Cold."},
		req = {level = 700, voc = "All classes"}}
	local ud = D.dropDetails(utip, {baseName = "Hollow Throne Claymore"})
	eq(ud.base, "Two-handed sword", "a unique: the slot, not its own name again")
	eq(ud.passive, "Hollow Crown: Every 8th hit echoes for 40% of its damage. For: warriors.", "the passive line")
	eq(ud.mods[1], "Sword +3", "no tier on a unique's modifier")
	local uev = D.drop(cfg, "Ann", 812, "Hollow Throne Claymore", "unique", ud)
	eq(field(uev, "Passive").value, ud.passive, "Passive field")
	check(uev.fields[1].name == "Base" and uev.fields[#uev.fields].name ~= nil, "no thumbnail without a url")
	-- no details: the post of before
	local plain = D.drop(cfg, "Ann", 812, "Hollow Throne Claymore", "unique")
	eq(#plain.fields, 0, "no details: no fields")
	eq(#D.drop(cfg, "Ann", 812, "X", "unique", {}).fields, 0, "empty details: no fields")
	-- switches
	local off = {}
	for k, v in pairs(cfg) do off[k] = v end
	off.dropDetails = {base = false, stats = false, level = false, classes = false, mods = false, passive = false, source = false, icon = false}
	eq(#D.drop(off, "Massador", 189, "Axe", "legendary", d).fields, 0, "every part off: no field")
	off.dropDetails = {mods = false, icon = false}
	local part = D.drop(off, "Massador", 189, "Axe", "legendary", d)
	check(field(part, "Modifiers") == nil and field(part, "Base") ~= nil and part.fields[#part.fields].name ~= nil, "one part off, the others stay")
	-- clipping: many modifier lines go whole, then "+N more"
	local lines = {}
	for i = 1, 80 do lines[i] = string.format("Modifier number %d of the axe +%d%% (T1)", i, i) end
	local big = D.drop(cfg, "A", 1, "X", "unique", {mods = lines, stats = lines, passive = string.rep("p", 3000), monster = string.rep("m", 3000)})
	for _, f in ipairs(big.fields) do
		check(#f.name <= 256 and #f.value <= 1024, "field limits: " .. tostring(f.name))
	end
	check(field(big, "Modifiers").value:find("%+%d+ more") ~= nil, "clipped modifiers say how many are left")
	check(not field(big, "Modifiers").value:find("%.%.%.$"), "no line cut in two")
	local total = #big.title + #big.text
	for _, f in ipairs(big.fields) do total = total + #f.name + #f.value end
	check(total <= 5800, "the whole post within the budget: " .. total)
	-- a single line longer than the field is cut, never inside a UTF-8 character
	local cut = D.clipLines({string.rep("\195\169", 700)}, 1024)
	check(#cut <= 1024 and cut:sub(-3) == "..." and #cut:sub(1, -4) % 2 == 0, "a long line cut on a character")
	eq(D.clipLines({"a", "b", "c"}, 1024), "a\nb\nc", "short lines kept")
	-- the 25 field cap and the limits of any field list
	local many = {}
	for i = 1, 40 do many[i] = {name = "N" .. i, value = "v", inline = true} end
	many[#many + 1] = {thumbnail = "/x.png"}
	local capped = D.fitFields({title = "t", text = "x", fields = many})
	eq(real(capped), 25, "25 named fields at most")
	eq(capped.fields[#capped.fields].thumbnail, "/x.png", "the thumbnail entry is kept and not counted")
	local long = D.fitFields({title = "t", text = "x", fields = {{name = string.rep("n", 400), value = string.rep("v", 2000)}}})
	check(#long.fields[1].name == 256 and #long.fields[1].value == 1024, "name 256, value 1024")
	-- a tight budget cuts the longest value, then drops what is left too short
	local tight = D.fitFields({title = string.rep("t", 250), text = string.rep("x", 2000), fields = {
		{name = "A", value = string.rep("a", 1000)}, {name = "B", value = string.rep("b", 1000)}, {name = "C", value = string.rep("c", 1000)}}}, 4000)
	local tl = #tight.title + #tight.text
	for _, f in ipairs(tight.fields) do tl = tl + #f.name + #f.value end
	check(tl <= 4000, "a tight budget holds: " .. tl)
	-- the queue row keeps the fields as the worker reads them
	local captured
	D.insertSql(cfg.table, ev, 1000, esc, function(t) captured = t return "[]" end)
	eq(captured, ev.fields, "the INSERT carries the fields column")
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

-- ------------------------------------------------------------------ O393: invasions
do
	local ev = D.cityInvasion(cfg, "start", {area = "Cinderhold", faction = "Orc Warband", level = 120, waves = 5, minutes = 20})
	eq(ev.kind, "city_invasion", "invasion kind")
	eq(ev.channel, "announce", "invasion channel")
	eq(ev.title, "Invasion: Cinderhold", "invasion start title")
	check(ev.text:find("The Orc Warband attacks Cinderhold!", 1, true), "invasion start text: " .. ev.text)
	eq(ev.fields[1].value, "120", "the level field")
	ev = D.cityInvasion(cfg, "win", {area = "Cinderhold", faction = "Orc Warband", secs = 400, names = {"Ann", "Bob"}, defenders = 7})
	eq(ev.title, "Cinderhold held", "win title")
	check(ev.text:find("Top defenders: Ann and Bob.", 1, true), "win text: " .. ev.text)
	eq(ev.fields[1].value, "6:40", "fight time"); eq(ev.fields[2].value, "7", "defenders")
	ev = D.cityInvasion(cfg, "lost", {area = "Thornmere", faction = "Undead Legion", occupation = 30})
	eq(ev.title, "Thornmere has fallen", "lost title")
	check(ev.text:find("for 30 minutes", 1, true), "lost text")
	check(D.enabled(cfg, "city_invasion"), "the kind is on")
	-- the website worker knows the kind
	local fh = io.open("../website/overlay/plugins/chaos/discord_lib.php")
	local php = fh and fh:read("*a") or ""
	if fh then fh:close() end
	check(php:find("'city_invasion'", 1, true) ~= nil, "discord_lib.php lists city_invasion")
end

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

-- ------------------------------------------------------------------ O519: X.dropDetails on a mocked engine
do
	dofile("data/scripts/chaos/item_tooltip_core.lua") -- the real splitPassive / refreshPassive
	local realBuild = ChaosItemTooltip.build
	local builds = 0
	ChaosItemTooltip.build = function(item, opts)
		builds = builds + 1
		if item.fail then error("tooltip fault") end
		return {name = item.name, slot = "Two-handed sword", rarity = 7, unique = {name = item.name},
			desc = "Cold iron. Hollow Crown: Every 8th hit echoes for 40% of its damage. For: warriors. (Meant for level 700)",
			base = {{k = "attack", l = "Attack", v = 80}}, mods = {{t = "Sword +3"}}, req = {level = 700, voc = "All classes"}}
	end
	ItemType = function(id) return {getName = function() return "hollow throne claymore" end} end
	ChaosUniquePassivesCore = {entry = function(c, id) return {name = "Hollow Crown"} end,
		text = function(c, e, lang) return "Hollow Crown: Every 8th hit echoes for 40% of its damage. For: warriors." end}
	ChaosUniquePassivesConfig = {}
	ChaosTelemetryConfig = {poiRange = 60, poiFloors = 3}
	ChaosTelemetryCore = {huntAreaOf = function(pos, label, marks, c)
		return label or (marks[1] and pos.x == 100 and marks[1].n) or nil
	end}
	ChaosTelemetry = {marks = function() return {{k = "hunt", n = "Ashen Wastes", x = 100, y = 100, z = 7}} end}
	local item = {name = "Hollow Throne Claymore", getId = function() return 4417 end}
	local monster = {getName = function() return "Demon" end}
	local d = X.dropDetails(item, monster, {x = 100, y = 100, z = 7})
	eq(d.base, "Two-handed sword", "dropDetails: base")
	eq(d.passive, "Hollow Crown: Every 8th hit echoes for 40% of its damage. For: warriors.", "dropDetails: the unique's passive line")
	eq(d.monster, "Demon", "dropDetails: the monster")
	eq(d.place, "Ashen Wastes", "dropDetails: the hunt at the corpse")
	eq(d.iconUrl, "/chaos-sprites/items/4417.png", "dropDetails: the icon path of the server id")
	eq(d.reqLevel, 700, "dropDetails: the level the tooltip says")
	local nothing = X.dropDetails(item, nil, nil)
	check(nothing.monster == nil and nothing.place == nil, "dropDetails: no monster, no place: none")
	-- a fault in the tooltip leaves the rest (the post still has the monster and the icon)
	local fails = X.dropDetails({name = "X", fail = true, getId = function() return 5 end}, monster, nil)
	eq(#fails.mods, 0, "a tooltip fault: no modifier lines")
	eq(fails.monster, "Demon", "a tooltip fault: the monster stays")
	eq(fails.iconUrl, "/chaos-sprites/items/5.png", "a tooltip fault: the icon stays")
	-- no tooltip builder at all (an engine without it)
	ChaosItemTooltip.build = nil
	check(type(X.dropDetails(item, monster, nil)) == "table", "no tooltip builder: still a table")
	ChaosItemTooltip.build = realBuild
	-- the full path: the queue row of a drop with details
	async = {}
	cfg.perMinute.drop = 100
	local rows = {}
	json = {encode = function(t)
		local out = {}
		for _, f in ipairs(t) do out[#out + 1] = (f.name or "thumb") .. "=" .. tostring(f.value or f.thumbnail) end
		return table.concat(out, "|")
	end}
	check(X.drop("Ann", 700, "Hollow Throne Claymore", "unique", d), "a drop with details is queued")
	check(async[#async]:find("Passive=Hollow Crown: Every 8th hit", 1, true) and async[#async]:find("Dropped by=Demon in Ashen Wastes", 1, true)
		and async[#async]:find("thumb=/chaos-sprites/items/4417.png", 1, true), "the row carries the fields")
	check(X.drop("Bob", 90, "Sword", "legendary"), "an old caller without details is queued")
	check(not async[#async]:find("Base=", 1, true), "and has no detail fields")
end

print(string.format("discord_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
