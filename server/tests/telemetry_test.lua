-- Run from the server/ folder: luajit tests/telemetry_test.lua (no engine; CI runs it with luajit and lua5.3)
-- Balance telemetry (data/scripts/chaos/telemetry_core.lua, telemetry.lua) and the wrap helper (wrapchain_core.lua):
-- bands, hunt deltas over resets, online samples, bosses, deaths (areas, killers), casts, economy, the hourly INSERTs
-- (no ids or names in any row), the rollup transaction, the schema against sql/chaos_telemetry.sql, and telemetry.lua
-- against a mocked engine (sample, hour rotation, hooks on records / boss spawns / respec / Loot Bag, deaths, casts,
-- staff left out, wrappers never stacked).
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
dofile("data/scripts/chaos/telemetry_config.lua")
dofile("data/scripts/chaos/telemetry_core.lua")
dofile("data/scripts/chaos/wrapchain_core.lua")
local K = ChaosTelemetryCore
local cfg = ChaosTelemetryConfig
local function esc(s)
	return "'" .. tostring(s):gsub("'", "''") .. "'"
end

-- ------------------------------------------------------------------ bands, clocks
eq(K.bandOf(1, cfg.bands), "1-99", "level 1"); eq(K.bandOf(500, cfg.bands), "500-999", "level 500")
eq(K.bandOf(1500, cfg.bands), "1000+", "level 1500"); eq(K.bandOf(0, cfg.bands), nil, "no band")
eq(K.hourOf(1791003599), 1791000000, "hour start"); eq(K.dayOf(1791003599), 1790985600, "day start")

-- ------------------------------------------------------------------ hunt deltas
local d = K.huntDelta(nil, {exp = 500, loot = 90, sup = 10, kills = 3, elapsed = 100}, 300)
check(d.exp == 0 and d.loot == 0 and d.secs == 0, "the first sample only sets the base")
local last = {exp = 500, loot = 90, sup = 10, kills = 3, elapsed = 100}
d = K.huntDelta(last, {exp = 1500, loot = 290, sup = 40, kills = 9, elapsed = 400}, 300)
check(d.exp == 1000 and d.loot == 200 and d.sup == 30 and d.kills == 6 and d.secs == 300, "a normal delta")
d = K.huntDelta(last, {exp = 1500, loot = 90, sup = 10, kills = 3, elapsed = 900}, 300)
eq(d.secs, 300, "hunting time is capped at the sample length")
d = K.huntDelta(last, {exp = 500, loot = 90, sup = 10, kills = 3, elapsed = 400}, 300)
eq(d.secs, 0, "no experience, no kill: not hunting (a paused or idle session)")
d = K.huntDelta(last, {exp = 200, loot = 5, sup = 0, kills = 1, elapsed = 60}, 300)
check(d.exp == 200 and d.loot == 5 and d.kills == 1 and d.secs == 60, "a reset session: the new values are the gain")

-- ------------------------------------------------------------------ the hour in memory
local acc = K.newAcc(1791000000)
K.addHunt(acc, "300-499", 4, 101, {exp = 1000, loot = 200, sup = 30, kills = 6, secs = 300})
K.addHunt(acc, "300-499", 4, 102, {exp = 3000, loot = 100, sup = 10, kills = 2, secs = 300})
K.addHunt(acc, "300-499", 4, 101, {exp = 500, loot = 0, sup = 0, kills = 1, secs = 120})
K.addHunt(acc, "1-99", 1, 103, {exp = 0, loot = 0, sup = 0, kills = 0, secs = 0})
K.addOnline(acc, {{band = "300-499", voc = 4}, {band = "300-499", voc = 4}, {band = "1-99", voc = 1}})
K.addOnline(acc, {{band = "300-499", voc = 4}})
K.addBoss(acc, "Grimjaw", K.partyOf(3, 10), 125)
K.addBoss(acc, "Grimjaw", K.partyOf(3, 10), 95)
K.addBoss(acc, "Grimjaw", K.partyOf(3, 10), nil)
K.addBoss(acc, "World boss: Ashmaw", K.partyOf(25, 10), 600)
eq(K.partyOf(25, 10), 10, "party sizes above maxParty share one bucket")
K.addDeath(acc, "300-499", "Ashen Caves", "Cinder Imp")
K.addDeath(acc, "300-499", "Ashen Caves", "Cinder Imp")
K.addCast(acc, 4, "Brutal Strike", 101)
K.addCast(acc, 4, "Brutal Strike", 102)
K.addCast(acc, 4, "Brutal Strike", 101)
check(K.addEconomy(acc, "faucet", "loot", "300-499", 300), "a faucet")
check(not K.addEconomy(acc, "sink", "respec", "300-499", 0), "nothing for 0 gold")

local hunt = K.rowsOf("hunt", acc)
eq(#hunt, 1, "a hunt bucket with nothing in it is not written")
eq(table.concat(hunt[1], ","), "300-499,4,2,720,4500,300,40,9", "hunt row: band, class, 2 characters, seconds, sums")
local online = K.rowsOf("online", acc)
eq(#online, 3, "online rows: two buckets and the total")
local byKey = {}
for _, r in ipairs(online) do
	byKey[r[1] .. "|" .. r[2]] = r
end
eq(table.concat(byKey["all|0"], ","), "all,0,2,4,3", "total: 2 samples, sum 4, max 3")
eq(table.concat(byKey["300-499|4"], ","), "300-499,4,2,3,2", "a bucket: sum 3, max 2")
eq(table.concat(byKey["1-99|1"], ","), "1-99,1,2,1,1", "a bucket missing from one sample still averages over both")
local boss = K.rowsOf("boss", acc)
eq(table.concat(boss[1], ","), "Grimjaw,3,3,2,220,95,125", "boss row: 3 kills, 2 timed, total, min, max")
eq(table.concat(K.rowsOf("casts", acc)[1], ","), "4,Brutal Strike,3,2", "casts: 3 casts by 2 characters")
eq(table.concat(K.rowsOf("deaths", acc)[1], ","), "300-499,Ashen Caves,Cinder Imp,2", "deaths row")

local sqls = K.flushSql(acc, cfg.tables, esc)
eq(#sqls, 6, "one INSERT per table with rows")
local all = table.concat(sqls, "\n")
check(not all:find("101", 1, true) and not all:find("102", 1, true), "no character id in any row")
check(sqls[1]:find("INSERT INTO `chaos_telemetry_hunt` (`span`, `at`, `band`, `voc`, `players`", 1, true), "hunt insert: " .. sqls[1]:sub(1, 120))
check(sqls[1]:find("('h', 1791000000, '300-499', 4, 2, 720, 4500, 300, 40, 9)", 1, true), "hunt values")
check(sqls[2]:find("`online_max` = GREATEST(`online_max`, VALUES(`online_max`))", 1, true), "online max kept on a second flush")
local bossSql = sqls[3]
check(bossSql:find("`secs_min` = IF(VALUES(`secs_min`) = 0, `secs_min`", 1, true), "min ignores untimed rows")
check(bossSql:find("`secs_min`", 1, true) < bossSql:find("`kills` = `kills` +", 1, true), "min / max before the sums")
local small = K.flushSql(acc, cfg.tables, esc, 1)
eq(#small, 1 + 3 + 2 + 1 + 1 + 1, "maxRows splits the inserts")

-- ------------------------------------------------------------------ areas and killers
local marks = {
	{k = "temple", x = 1000, y = 1000, z = 7, n = "Temple of Cinderhold"},
	{k = "temple", x = 3000, y = 3000, z = 7, n = "Temple of Saltgrave"},
	{k = "hunt", x = 1100, y = 1100, z = 8, n = "Ashen Caves"},
	{k = "hunt", x = 1130, y = 1100, z = 8, n = "Deep Ashen Caves"},
	{k = "shop", x = 1101, y = 1101, z = 8, n = "Torvald"}
}
eq(K.areaOf({x = 1105, y = 1102, z = 9}, nil, marks, cfg), "Ashen Caves", "the nearest hunting place")
eq(K.areaOf({x = 1128, y = 1100, z = 8}, nil, marks, cfg), "Deep Ashen Caves", "the nearer of two")
eq(K.areaOf({x = 1105, y = 1102, z = 13}, nil, marks, cfg), "near Cinderhold", "too many floors away: the town")
eq(K.areaOf({x = 2900, y = 2950, z = 7}, nil, marks, cfg), "near Saltgrave", "out of range: the nearest temple")
eq(K.areaOf({x = 1, y = 1, z = 7}, "Rift", marks, cfg), "Rift", "an instance first")
eq(K.areaOf({x = 1, y = 1, z = 7}, nil, {}, cfg), "wild", "no marks")
eq(K.killerOf({player = true}), "a player", "PvP: never a name")
eq(K.killerOf({monster = "Cinder Imp"}), "Cinder Imp", "a monster")
eq(K.killerOf(nil), "environment", "no killer")

-- ------------------------------------------------------------------ rollup, schema
local roll = K.rollupSql(cfg.tables, 1790985600, 1700000000)
eq(roll[1], "START TRANSACTION", "rollup in a transaction"); eq(roll[#roll], "COMMIT", "committed at the end")
eq(#roll, 2 + 3 * 6, "copy, delete hourly, delete old daily per table")
check(roll[2]:find("SELECT 'd', `at` - `at` % 86400 AS `day`", 1, true), "daily rows at the day start")
check(roll[2]:find("WHERE `span` = 'h' AND `at` < 1790985600 GROUP BY `day`, `band`, `voc`", 1, true), "hunt grouped: " .. roll[2])
check(roll[3] == "DELETE FROM `chaos_telemetry_hunt` WHERE `span` = 'h' AND `at` < 1790985600", "hourly rows deleted after the copy")
check(roll[4] == "DELETE FROM `chaos_telemetry_hunt` WHERE `span` = 'd' AND `at` < 1700000000", "old daily rows deleted")
local bossRoll
for _, s in ipairs(roll) do
	if s:find("INSERT INTO `chaos_telemetry_boss`", 1, true) then bossRoll = s end
end
check(bossRoll and bossRoll:find("COALESCE(MIN(NULLIF(`secs_min`, 0)), 0)", 1, true), "daily min over timed hours only")
local f = io.open("sql/chaos_telemetry.sql", "r")
local file = f and f:read("*a") or ""
if f then f:close() end
for _, s in ipairs(K.schemaSql(cfg.tables)) do
	check(file:find(s .. ";", 1, true) ~= nil, "sql/chaos_telemetry.sql has: " .. s:sub(1, 60))
end

-- ------------------------------------------------------------------ the wrap helper
local lib = {calls = 0}
function lib.go(x) lib.calls = lib.calls + 1; return x * 2, "two" end
local seenA, seenB = 0, 0
check(ChaosWrapChain.wrap(lib, "go", "a", function(res, x) seenA = seenA + res[1] end), "wrapped a")
check(ChaosWrapChain.wrap(lib, "go", "b", function() seenB = seenB + 1 end), "wrapped b on top")
check(not ChaosWrapChain.wrap(lib, "go", "a", function() seenA = seenA + 100 end), "a again: found under b, not stacked")
check(not ChaosWrapChain.wrap(lib, "go", "b", function() end), "b again: not stacked")
local r1, r2 = lib.go(5)
check(r1 == 10 and r2 == "two" and lib.calls == 1 and seenA == 10 and seenB == 1, "every result through, each hook once")
check(ChaosWrapChain.wrap(lib, "go", "c", function() error("boom") end, function() end), "a failing hook")
eq(lib.go(1), 2, "a failing hook never breaks the call")
lib.go = function() return 0 end -- a /reload of the wrapped script
check(ChaosWrapChain.wrap(lib, "go", "a", function() end), "a /reload: wrapped again")

-- ------------------------------------------------------------------ telemetry.lua against a mocked engine
local queries, async = {}, {}
local configRows = {}
db = {
	escapeString = esc,
	query = function(s) queries[#queries + 1] = s
		local key, v = s:match("VALUES %('([^']+)', '([^']+)'%)")
		if key then configRows[key] = v end
		return true end,
	asyncQuery = function(s) async[#async + 1] = s end,
	storeQuery = function(s)
		local key = s:match("`config` = '([^']+)'")
		if key and configRows[key] then return key end
		return false
	end
}
result = {getString = function(id) return configRows[id] end, free = function() end}
local events, globals, talks = {}, {}, {}
local cbs = {}
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
EventCallback = setmetatable({}, {__newindex = function(t, k, v) cbs[k] = v end})
rawset(EventCallback, "register", function() end)
function TalkAction(words)
	local t = {}
	function t:separator() end
	function t:register() talks[words] = self end
	return t
end
MESSAGE_INFO_DESCR = 22
local creatures = {}
function Creature(id) return creatures[id] end

local function mkPlayer(guid, level, voc, group, pos)
	local p = {guid = guid, level = level, voc = voc, group = group or 1, pos = pos or {x = 1105, y = 1102, z = 8}, events = {}}
	function p:getGuid() return self.guid end
	function p:getId() return 268435456 + self.guid end
	function p:getLevel() return self.level end
	function p:getVocation() local v = self.voc; return {getId = function() return v end} end
	function p:getGroup() local g = self.group; return {getId = function() return g end, getAccess = function() return g >= 4 end} end
	function p:getPosition() return self.pos end
	function p:isPlayer() return true end
	function p:getMaster() return nil end
	function p:getName() return "Name" .. self.guid end
	function p:registerEvent(n) self.events[n] = true end
	function p:sendTextMessage(_, text) self.msg = text end
	creatures[p:getId()] = p
	return p
end
local function mkMonster(id, typeName)
	local m = {id = id, typeName = typeName, events = {}, map = {}}
	function m:getId() return self.id end
	function m:isPlayer() return false end
	function m:isMonster() return true end
	function m:getMaster() return self.master end
	function m:getName() return self.typeName end
	function m:getType() local n = self.typeName; return {name = function() return n end} end
	function m:getPosition() return {x = 5000, y = 5000, z = 7} end
	function m:getDamageMap() return self.map end
	function m:registerEvent(n) self.events[n] = true end
	creatures[id] = m
	return m
end

local players = {mkPlayer(1, 350, 4), mkPlayer(2, 120, 11), mkPlayer(3, 800, 1, 5)}
Game = {getPlayers = function() return players end}
ChaosHunt = {sessions = {}, elapsed = function(s, now) return s.clock end}
ChaosHunt.sessions[1] = {exp = 1000, lootValue = 50, supplyValue = 5, killCount = 2, clock = 100}
ChaosHunt.sessions[3] = {exp = 99999, lootValue = 99999, supplyValue = 0, killCount = 50, clock = 100}
ChaosRecords = {byKey = {wb_time = {variants = {{key = "ashmaw", name = "Ashmaw"}}}}}
local submitted = 0
function ChaosRecords.submit(run) submitted = submitted + 1; return run.ok, "slot" end
ChaosBossSpawns = {ensure = function() return {byType = {grimjaw = true}} end}
function ChaosBossSpawns.onDeath() end
ChaosRespec = {pay = function(player, cost) return cost < 1000 end}
ChaosAutoSell = {sellBag = function(player) return {gold = 777} end}
ChaosSpellEvents = {handlers = {}, set = function(kind, key, fn) ChaosSpellEvents.handlers[kind .. key] = fn end}
Chaos.instanceAt = function(pos) if pos.x == 7000 then return "rift", "Rift" end return nil end

local realTime = os.time
local clock = 1791000000 + 60
os.time = function(t) if t then return realTime(t) end return clock end

dofile("data/scripts/chaos/telemetry.lua")
local T = ChaosTelemetry
T.poiMarks = marks -- the test's markers, not the installed map's
globals.ChaosTelemetryStartup.onStartup()
check(#queries >= 6 and queries[1]:find("CREATE TABLE IF NOT EXISTS `chaos_telemetry_hunt`", 1, true), "startup creates the tables")
check(configRows[cfg.rollupKey] ~= nil, "startup rolls up once and records the day")
local before = #queries
T.rollup(clock)
eq(#queries, before, "no second rollup the same day")

-- logins register the death event
local login = events.ChaosTelemetryLogin
login.onLogin(players[1])
check(players[1].events.ChaosTelemetryDeath, "login registers the death event")

-- first sample: bases only; online counts without staff
eq(T.sample(clock), 2, "two counted characters online (staff left out)")
eq(K.count(T.acc.hunt), 1, "a bucket for the character with a hunt session")
check(T.last[3] == nil, "staff: no hunt base")
ChaosHunt.sessions[1] = {exp = 4000, lootValue = 450, supplyValue = 105, killCount = 12, clock = 400}
clock = clock + 300
T.sample(clock)
local hb = T.acc.hunt["300-499|4"]
check(hb and hb.exp == 3000 and hb.loot == 400 and hb.sup == 100 and hb.kills == 10 and hb.secs == 300, "the second sample adds the delta")
check(T.acc.economy["faucet|loot|300-499"].gold == 400 and T.acc.economy["sink|supplies|300-499"].gold == 100, "loot and supplies as economy")

-- hooks
T.installHooks()
local wrappedSubmit = ChaosRecords.submit
T.installHooks()
check(ChaosRecords.submit == wrappedSubmit, "hooks installed again: not stacked")
ChaosRecords.submit({ok = true, board = "wb_time", variant = "ashmaw", value = 312, members = {players[1], players[2]}, size = 2})
ChaosRecords.submit({ok = false, board = "wb_time", variant = "ashmaw", value = 5, members = {}})
ChaosRecords.submit({ok = true, board = "tower_floor", value = 30, members = {players[1]}})
eq(submitted, 3, "the records still get every run")
local wb = T.acc.boss["World boss: Ashmaw|2"]
check(wb and wb.kills == 1 and wb.total == 312, "an accepted world boss run: kill and time by party size")
eq(K.count(T.acc.boss), 1, "refused runs and other boards are not bosses")

-- a map boss: first hit, then the death
local boss = mkMonster(9001, "Grimjaw")
cbs.onSpawn(boss, boss:getPosition(), false, false)
check(boss.events.ChaosTelemetryBossHit, "a tracked boss gets the first-hit event at spawn")
local imp = mkMonster(9002, "Cinder Imp")
cbs.onSpawn(imp, imp:getPosition(), false, false)
check(not imp.events.ChaosTelemetryBossHit, "an ordinary monster does not")
local hitEv = events.ChaosTelemetryBossHit
local a, b2 = hitEv.onHealthChange(boss, imp, 50, 1, 0, 0, 0)
check(a == 50 and b2 == 1 and T.firstHit[9001] == nil, "a monster's hit does not start the clock; damage unchanged")
hitEv.onHealthChange(boss, players[1], 40, 1, 0, 0, 0)
eq(T.firstHit[9001], clock, "the first player hit starts the clock")
clock = clock + 95
hitEv.onHealthChange(boss, players[2], 40, 1, 0, 0, 0)
boss.map = {[players[1]:getId()] = {}, [players[2]:getId()] = {}, [9002] = {}}
ChaosBossSpawns.onDeath(boss, players[1], players[1])
local gj = T.acc.boss["Grimjaw|2"]
check(gj and gj.kills == 1 and gj.total == 95, "map boss: two players, 95 s")
check(T.firstHit[9001] == nil, "the clock is dropped at the death")

-- economy hooks
check(ChaosRespec.pay(players[1], 500) == true and ChaosRespec.pay(players[1], 5000) == false, "respec pays as before")
eq(T.acc.economy["sink|respec|300-499"].gold, 500, "a paid respec is a sink; a refused one is not")
ChaosAutoSell.sellBag(players[2])
eq(T.acc.economy["faucet|lootbag|100-299"].gold, 777, "a Loot Bag sale is a faucet")
check(T.economy(players[1], "faucet", "autoseller", 120), "the public hook (corpse Auto Seller)")
check(not T.economy(players[3], "faucet", "autoseller", 120), "staff never count")

-- casts
local cast = ChaosSpellEvents.handlers.casttelemetry
check(cast ~= nil, "a cast handler on the spell events")
cast(players[1], "Brutal Strike"); cast(players[1], "Brutal Strike"); cast(players[3], "Brutal Strike")
eq(T.acc.casts["4|Brutal Strike"].casts, 2, "casts per class; staff left out")

-- deaths
local death = events.ChaosTelemetryDeath
death.onDeath(players[1], nil, imp, imp)
players[2].pos = {x = 7000, y = 1, z = 7}
death.onDeath(players[2], nil, players[1], players[1])
local sm = mkMonster(9003, "Bone Hound")
sm.master = players[1]
players[1].pos = {x = 2900, y = 2900, z = 7}
death.onDeath(players[1], nil, sm, nil)
local deathKeys = {}
for key in pairs(T.acc.deaths) do deathKeys[#deathKeys + 1] = key end
table.sort(deathKeys)
eq(table.concat(deathKeys, ";"), "100-299|Rift|a player;300-499|Ashen Caves|Cinder Imp;300-499|near Saltgrave|a player",
	"deaths: area and killer, a summon's master is a player, no names")

-- the hour ends: one async flush, no ids, a fresh hour
async = {}
clock = 1791000000 + 3600 + 10
T.sample(clock)
check(#async >= 5, "the last hour is written asynchronously (" .. #async .. ")")
local flushed = table.concat(async, "\n")
check(not flushed:find("Name1", 1, true) and not flushed:find("268435457", 1, true), "no names or creature ids written")
check(flushed:find("'World boss: Ashmaw', 2, 1, 1, 312", 1, true), "the boss row went out")
eq(T.acc.hour, 1791003600, "a new hour in memory")
eq(K.count(T.acc.boss), 0, "the new hour starts empty")
check(T.last[1] ~= nil, "the hunt base stays (memory only) for the next delta")
players[1] = mkPlayer(1, 350, 4)
Game.getPlayers = function() return {players[1]} end
T.sample(clock + 300)
check(T.last[2] == nil, "a character that logged out loses its base")

-- shutdown writes synchronously
queries = {}
K.addDeath(T.acc, "1-99", "wild", "Rat")
globals.ChaosTelemetryShutdown.onShutdown()
check(#queries >= 1 and queries[#queries]:find("chaos_telemetry", 1, true), "shutdown flushes the hour")

-- the staff command
local gm = mkPlayer(9, 10, 1, 6)
local pl = mkPlayer(8, 10, 1, 1)
eq(talks["/telemetry"].onSay(pl, "/telemetry", ""), true, "a player: words are chat")
eq(talks["/telemetry"].onSay(gm, "/telemetry", ""), false, "staff: swallowed")
check(gm.msg and gm.msg:find("Telemetry hour", 1, true), "the status line")

os.time = realTime
print(string.format("telemetry_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
