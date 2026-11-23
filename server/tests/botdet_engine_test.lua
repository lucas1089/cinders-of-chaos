-- Run from the server/ folder: luajit tests/botdet_engine_test.lua [-v] (or lua5.3; CI runs both)
-- botdet.lua against a mocked engine (O722): who is collected (testers and staff are not), the one-second sample, the spell,
-- heal and engine-signal hooks, the batched writes (every 5 minutes and at logout), the hourly score row, the client's
-- integrity chunks and tool codes, /botcheck for staff, the daily purge and top list, and the cost: the per-player think
-- time and the memory of 400 online characters over a simulated half hour. The bounds are loose (a slow CI machine
-- passes); -v prints the numbers that server/README.md "Bot detection events and scores (O722)" quotes.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
local verbose = arg and arg[1] == "-v"
local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		io.write("FAIL " .. label .. "\n")
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/chaos_constants.lua")
local PLAYERS = 400
local SECONDS = 1800

-- ---------------------------------------------------------------- a mocked engine
local clockS, clockMs = 1790000000, 1790000000000
local realTime, realDate = os.time, os.date
os.time = function(t) if t then return realTime(t) end return clockS end
os.mtime = function() return clockMs end
local quiet = print
local logLines = {}
print = function(s) logLines[#logLines + 1] = tostring(s) end
local queries, asyncs = {}, {}
db = {query = function(q) queries[#queries + 1] = q return true end, asyncQuery = function(q) asyncs[#asyncs + 1] = q return true end,
	storeQuery = function() return false end, escapeString = function(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end}
result = {free = function() end}
local function enc(v)
	if type(v) == "table" then
		local parts = {}
		if #v > 0 then
			for _, x in ipairs(v) do parts[#parts + 1] = enc(x) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, k in ipairs(keys) do parts[#parts + 1] = '"' .. k .. '":' .. enc(v[k]) end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif type(v) == "string" then
		return '"' .. v .. '"'
	end
	return tostring(v)
end
json = {encode = enc}
local events, globals, callbacks, talks, scheduled = {}, {}, {}, {}, {}
function CreatureEvent(name)
	local e = {type = function() end, register = function() end}
	events[name] = e
	return e
end
function GlobalEvent(name)
	local e = {register = function() end, type = function() end, interval = function(self, ms) self.ms = ms end}
	globals[name] = e
	return e
end
function TalkAction(words)
	local t = {separator = function() end, register = function(self) talks[words] = self end}
	return t
end
EventCallback = setmetatable({}, {__newindex = function(t, k, v) callbacks[k] = v end, __index = function(t, k) if k == "register" then return function() end end end})
function addEvent(fn, ms, ...) scheduled[#scheduled + 1] = {fn = fn, ms = ms, args = {...}} end
local sent = {}
Chaos.send = function(player, opcode, action, data) sent[#sent + 1] = {player = player, opcode = opcode, action = action, data = data} return true end
Chaos.decode = function(b) return type(b) == "table" and b or nil end
Chaos.limited = function() return false end
Chaos.staffCommand = function(player, words, param) return player.staff == true, player.staff == true end
local selectRows = {}
Chaos.select = function(q, cols)
	for pat, rows in pairs(selectRows) do
		if q:find(pat, 1, true) then return rows end
	end
	return {}
end
Chaos.findPlayer = function(name)
	for _, p in pairs(PLAYERS_BY_NAME or {}) do end
	local p = PLAYERS_BY_NAME and PLAYERS_BY_NAME[name]
	if p then return p.guid, p.name, p end
	if name == "Gone" then return 9999, "Gone", nil end
	return nil
end

local P = {}
P.__index = P
function P:getId() return self.id end
function P:getGuid() return self.guid end
function P:getName() return self.name end
function P:getAccountId() return self.guid end
function P:getHealth() return self.hp end
function P:getMaxHealth() return 1000 end
function P:getMana() return self.mp end
function P:getMaxMana() return 500 end
function P:getGroup() local g = self.group or 1 return {getId = function() return g end, getAccess = function() return g >= 4 end} end
function P:getPosition() return {x = self.x, y = self.y, z = 7} end
function P:getStorageValue() return self.tester and 1 or -1 end
function P:registerEvent(name) self.registered[name] = true end
function P:sendTextMessage(_, text) self.messages[#self.messages + 1] = text end
function P:popupFYI(text) self.messages[#self.messages + 1] = text end
function P:getBotSignals() local s = self.signals self.signals = nil return s end
PLAYERS_BY_NAME = {}
local players, list = {}, {}
local function newPlayer(i, extra)
	local p = setmetatable({id = 10000 + i, guid = i, name = "Char" .. i, hp = 1000, mp = 500, x = 1000 + i, y = 1000, registered = {},
		messages = {}}, P)
	for k, v in pairs(extra or {}) do p[k] = v end
	players[p.id] = p
	list[#list + 1] = p
	PLAYERS_BY_NAME[p.name] = p
	return p
end
function Player(x)
	if type(x) == "number" then return players[x] end
	return PLAYERS_BY_NAME[x]
end
Game = {getPlayers = function() return list end}
Chaos.isTester = function(p) return p.tester == true end

-- the spell events of engine patch 0008, as ChaosSpellEvents keeps them
local spellHooks = {cast = {}, cooldown = {}}
ChaosSpellEvents = {set = function(kind, key, fn) spellHooks[kind][key] = fn end}

local tmpTop = os.tmpname()
Chaos.botdetConfig = dofile("data/scripts/chaos/botdet_config.lua")
local cfg = Chaos.botdetConfig
cfg.report.logFile = tmpTop
dofile("data/scripts/chaos/botdet.lua")
local BD, K = ChaosBotdet, ChaosBotdetCore

-- ---------------------------------------------------------------- registration
for _, name in ipairs({"ChaosBotdetLogin", "ChaosBotdetLogout", "ChaosBotdetHealth", "ChaosBotdetExtended"}) do
	check(events[name] ~= nil, name .. " is registered")
end
eq(globals.ChaosBotdetThink.ms, 1000, "the think runs every second")
check(talks["/botcheck"] ~= nil, "/botcheck is registered")
check(spellHooks.cast.botdet ~= nil and spellHooks.cooldown.botdet ~= nil, "spell cast and cooldown hooks")
check(ChaosAdminPending["security.botcheck_top"] ~= nil and ChaosAdminPending["security.botcheck_show"] ~= nil, "admin panel entries")
globals.ChaosBotdetStartup.onStartup = globals.ChaosBotdetStartup.onStartup
BD.ensureTables()
eq(#queries, 2, "two tables are created")
check(queries[1]:find("chaos_botdet_events", 1, true) and queries[2]:find("chaos_botdet_scores", 1, true), "the table names")
-- the startup DDL agrees with the sql file
do
	local f = io.open("sql/chaos_botdet.sql", "r")
	local sql = f:read("*a")
	f:close()
	for _, col in ipairs({"player_id", "type", "data", "created_at", "hour_ts", "total", "route", "regularity", "reaction", "heal",
			"session", "bonus", "flagged", "notes", "uniq_player_hour"}) do
		check(sql:find("`" .. col .. "`", 1, true) and (queries[1] .. queries[2]):find("`" .. col .. "`", 1, true), "column " .. col .. " in both")
	end
end

-- ---------------------------------------------------------------- who is collected
local tester = newPlayer(1, {tester = true})
local staff = newPlayer(2, {group = 4})
local mira = newPlayer(3)
for _, p in ipairs({tester, staff, mira}) do
	events.ChaosBotdetLogin.onLogin(p)
end
check(not BD.byCid[tester.id], "a tester bot is not collected")
check(not BD.byCid[staff.id], "a staff character is not collected")
check(BD.byCid[mira.id] == mira.guid, "a player is collected")
check(mira.registered.ChaosBotdetHealth and mira.registered.ChaosBotdetExtended, "the hooks are registered on a player")
check(not tester.registered.ChaosBotdetHealth and not staff.registered.ChaosBotdetExtended, "and not on a tester or staff")
check(tester.registered.ChaosBotdetLogout and staff.registered.ChaosBotdetLogout, "the logout is registered for all")
-- the tool list goes to the client only when staff keep one
eq(#scheduled, 1, "one scheduled tool list send"); scheduled[1].fn()
eq(#sent, 0, "an empty tool list sends nothing")
cfg.tools.list = {{code = "cave1", hashes = {"0123456789abcdef"}}}
scheduled = {}
events.ChaosBotdetLogin.onLogin(mira)
scheduled[1].fn()
check(sent[1] and sent[1].action == "tools" and sent[1].opcode == 169 and sent[1].data.t[1][1] == "cave1", "the tool list reaches the client")
cfg.tools.list = {}

-- ---------------------------------------------------------------- the hooks
local st = BD.states[mira.guid]
local k0 = st.pos.n
globals.ChaosBotdetThink.onThink = nil
BD.tick()
clockS, clockMs = clockS + 1, clockMs + 1000
mira.x = mira.x + 1
BD.tick()
check(st.pos.n >= k0 + 1, "a position change is kept")
-- a spell (the cooldown event first, then the cast), a heal, the engine's signals
spellHooks.cooldown.botdet(mira, "Frost", 31, 1, true, "spell", 2000)
spellHooks.cooldown.botdet(mira, "Frost", 31, 1, true, "group", 2000)
spellHooks.cast.botdet(mira, "Frost", 31, 1, true, 30, 0)
eq(#st.pend.spell, 1, "a cast is pending")
check(st.pend.spell[1]:find(",31,100,100,0", 1, true) ~= nil, "with the id and the hit point and mana percentages: " .. st.pend.spell[1])
clockMs = clockMs + 2000
spellHooks.cooldown.botdet(mira, "Frost", 31, 1, true, "spell", 2000)
spellHooks.cast.botdet(mira, "Frost", 31, 1, true, 30, 0)
check(st.pend.spell[2]:find(",1$") ~= nil, "a cast the moment the cooldown ended is marked bound")
mira.hp = 500
events.ChaosBotdetHealth.onHealthChange(mira, mira, 200, COMBAT_HEALING, 0, COMBAT_NONE, 0)
eq(#st.pend.heal, 1, "an own heal is pending")
check(st.pend.heal[1]:find(",50$") ~= nil, "at 50 percent of health: " .. st.pend.heal[1])
events.ChaosBotdetHealth.onHealthChange(mira, nil, 200, COMBAT_HEALING, 0, COMBAT_NONE, 0)
events.ChaosBotdetHealth.onHealthChange(mira, mira, 200, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, 0)
eq(#st.pend.heal, 1, "leech without an attacker and damage are not heals")
mira.signals = {keys = 4, paths = 2, pathSteps = 20, reactions = {{4001, 210}}}
BD.ticks = 4 -- the next tick polls
BD.tick()
eq(st.walk.k, 4, "the engine's key steps"); eq(st.walk.s, 20, "the path steps"); eq(#K.ringList(st.react), 1, "the reaction time")
-- a player without the engine patch has no getBotSignals: nothing breaks
local old = P.getBotSignals
P.getBotSignals = nil
BD.ticks = 9
BD.tick()
P.getBotSignals = old

-- ---------------------------------------------------------------- the batched writes
local before = #asyncs
clockS, clockMs = clockS + 301 + mira.guid % 300, clockMs + 301000
BD.tick()
local inserts = {}
for i = before + 1, #asyncs do
	if asyncs[i]:find("INSERT INTO `chaos_botdet_events`", 1, true) then inserts[#inserts + 1] = asyncs[i] end
end
eq(#inserts, 1, "one multi-row insert after the flush time")
for _, kind in ipairs({"'pos'", "'walk'", "'spell'", "'heal'", "'react'", "'session'"}) do
	check(inserts[1] and inserts[1]:find(kind, 1, true), "a " .. kind .. " row")
end
check(inserts[1] and inserts[1]:find('"v":"0,' .. 1003, 1, true) ~= nil, "the positions are packed")
local before2 = #asyncs
BD.tick()
eq(#asyncs, before2, "nothing is written again before the next flush")
-- the hourly pass: one score row, only when something has data
clockS, clockMs = clockS + 3700, clockMs + 3700000
BD.tick()
local scoreRows = 0
for i = before2 + 1, #asyncs do
	if asyncs[i]:find("INSERT INTO `chaos_botdet_scores`", 1, true) then scoreRows = scoreRows + 1 end
end
eq(scoreRows, 0, "a character with no heuristic data writes no score row")
-- give it a bot-like reaction history so the hourly pass has something to say
for i = 1, 60 do K.onReact(st, cfg, i, 70, clockS) end
st.nextHour = 0
BD.tick()
for i = before2 + 1, #asyncs do
	if asyncs[i]:find("INSERT INTO `chaos_botdet_scores`", 1, true) then scoreRows = scoreRows + 1 end
end
eq(scoreRows, 1, "a score row with data")
check(asyncs[#asyncs]:find("ON DUPLICATE KEY UPDATE", 1, true) ~= nil, "one row a character and hour")
-- the logout flushes and scores once more
local pre = #asyncs
mira.hp = 400
events.ChaosBotdetHealth.onHealthChange(mira, mira, 200, COMBAT_HEALING, 0, COMBAT_NONE, 0)
events.ChaosBotdetLogout.onLogout(mira)
check(#asyncs > pre, "the logout writes")
check(not BD.byCid[mira.id], "and stops collecting")
check(st.offlineAt ~= nil, "the state is kept for a relog")

-- ---------------------------------------------------------------- the client's signals
local ana = newPlayer(4)
events.ChaosBotdetLogin.onLogin(ana)
BD.loadOfficial()
eq(next(BD.official), nil, "no official list: empty")
BD.official = {game_a = "aaaa", game_b = "bbbb"}
local w0 = #asyncs
events.ChaosBotdetExtended.onExtendedOpcode(ana, 100, {})
events.ChaosBotdetExtended.onExtendedOpcode(ana, 169, {action = "integrity", data = {i = 1, n = 1, b = 7, m = {{"game_a", "aaaa"}, {"zz_bot", "1"}}}})
check(#asyncs == w0 + 1 and asyncs[#asyncs]:find("'integrity'", 1, true) and asyncs[#asyncs]:find("zz_bot", 1, true), "an extra module is an event")
events.ChaosBotdetExtended.onExtendedOpcode(ana, 169, {action = "integrity", data = {i = 1, n = 1, b = 7, m = {{"game_a", "aaaa"}}}})
eq(#asyncs, w0 + 1, "an official client adds no event")
cfg.tools.list = {{code = "cave1", hashes = {"0123456789abcdef"}}}
events.ChaosBotdetExtended.onExtendedOpcode(ana, 169, {action = "tools", data = {c = {"cave1", "evil"}}})
check(asyncs[#asyncs]:find("'tool'", 1, true) and asyncs[#asyncs]:find("cave1", 1, true) and not asyncs[#asyncs]:find("evil", 1, true), "a known tool code is an event, an unknown one is not")
cfg.tools.list = {}
events.ChaosBotdetExtended.onExtendedOpcode(ana, 169, "garbage")
events.ChaosBotdetExtended.onExtendedOpcode(ana, 169, {action = "other", data = {}})
eq(#asyncs, w0 + 2, "garbage and unknown actions add nothing")
events.ChaosBotdetLogout.onLogout(ana)

-- ---------------------------------------------------------------- /botcheck
local gm = newPlayer(5, {group = 4, staff = true})
local say = talks["/botcheck"].onSay
eq(say(mira, "/botcheck", "Char3"), true, "a player's /botcheck is passed on to the next handler")
eq(#mira.messages, 0, "and shows nothing")
eq(say(gm, "/botcheck", ""), false, "usage")
check(gm.messages[1]:find("/botcheck <name>", 1, true) ~= nil, "usage text")
gm.messages = {}
events.ChaosBotdetLogin.onLogin(mira)
for i = 1, 60 do K.onReact(BD.states[mira.guid], cfg, i, 70, clockS) end
say(gm, "/botcheck", "Char3")
check(gm.messages[1] and gm.messages[1]:find("online", 1, true) and gm.messages[1]:find("reaction", 1, true) and gm.messages[1]:find("median reaction 70 ms in", 1, true),
	"an online character shows its numbers: " .. tostring(gm.messages[1]))
gm.messages = {}
selectRows["`hour_ts`, `total`, `flagged`, `notes`"] = {{hour_ts = clockS - 600, total = 82, flagged = 1, notes = "total 82 | route 100 (weight 30): loop of 40 cells | regularity 90 (weight 25): cv 0.02"}}
selectRows["`type` IN ('integrity', 'tool')"] = {{type = "integrity", data = '{"b":7,"extra":["zz_bot"]}', created_at = clockS - 100}}
say(gm, "/botcheck", "Gone")
check(gm.messages[1] and gm.messages[1]:find("offline", 1, true) and gm.messages[1]:find("FLAGGED", 1, true) and gm.messages[1]:find("loop of 40 cells", 1, true)
	and gm.messages[1]:find("client signal integrity", 1, true), "an offline character shows its highest stored hour and the client's signals")
gm.messages = {}
say(gm, "/botcheck", "Nobody")
eq(gm.messages[1], "No such character.", "an unknown name")
gm.messages = {}
selectRows["ORDER BY `total` DESC, `hour_ts` DESC"] = {{player_name = "Bota", total = 91, route = 100, regularity = 95, reaction = 80, heal = 90, session = 60, bonus = 5, flagged = 1}}
say(gm, "/botcheck", "top 5")
check(gm.messages[1] and gm.messages[1]:find("Bota", 1, true) and gm.messages[1]:find("FLAG", 1, true), "the top list")
-- the question
gm.messages = {}
ChaosAntibot = {forceCheck = function(p) return true end}
say(gm, "/botcheck", "ask Char3")
check(gm.messages[1] and gm.messages[1]:find("Presence check sent", 1, true), "the question is the presence check")
gm.messages = {}
say(gm, "/botcheck", "ask Nobody")
check(gm.messages[1]:find("not online", 1, true) ~= nil, "a question to nobody")
ChaosAntibot = nil

-- ---------------------------------------------------------------- the daily purge and the top list
scheduled = {}
BD.lastPurge, BD.lastTop = "", ""
local realDateFn = os.date
os.date = function(f, t) if f == "%H" then return "05" end return realDateFn(f, t) end
BD.maintenance(clockS)
os.date = realDateFn
check(#scheduled == 12, "the purge is spread over 12 steps")
asyncs = {}
for _, s in ipairs(scheduled) do s.fn() end
local ev, sc = 0, 0
for _, q in ipairs(asyncs) do
	if q:find("DELETE FROM `chaos_botdet_events` WHERE `created_at` < " .. (clockS - 7 * 86400) .. " LIMIT 5000", 1, true) then ev = ev + 1 end
	if q:find("DELETE FROM `chaos_botdet_scores` WHERE `hour_ts` < " .. (clockS - 90 * 86400) .. " LIMIT 5000", 1, true) then sc = sc + 1 end
end
eq(ev, 12, "events older than 7 days are purged in chunks"); eq(sc, 12, "scores older than 90 days")
local f = io.open(tmpTop, "r")
local top = f and f:read("*a") or ""
if f then f:close() end
os.remove(tmpTop)
check(top:find("botdet top 20", 1, true) and top:find("Bota", 1, true), "the daily top list is written to the log file")
local sched2 = #scheduled
BD.maintenance(clockS)
eq(#scheduled, sched2, "the purge and the list run once a day")

-- ---------------------------------------------------------------- the cost
-- 400 online characters for half an hour: a sample every second, a cast and a heal now and then, the engine's signals every 5 s
local sim = {}
for i = 1, PLAYERS do
	local p = newPlayer(1000 + i)
	p.walkPhase = i
	events.ChaosBotdetLogin.onLogin(p)
	sim[#sim + 1] = p
end
scheduled = {}
asyncs = {}
collectgarbage("collect")
local memBefore = collectgarbage("count")
local tickTotal, ticks, worst = 0, 0, 0
local rnd = 12345
local function rand()
	rnd = (rnd * 1103515245 + 12345) % 2147483648
	return rnd / 2147483648
end
local hookCost, hookN = 0, 0
for s = 1, SECONDS do
	clockS, clockMs = clockS + 1, clockMs + 1000
	local h0 = os.clock()
	for _, p in ipairs(sim) do
		p.x = 2000 + (p.walkPhase + s) % 80
		p.y = 2000 + math.floor((p.walkPhase + s) / 80) % 40
		if rand() < 0.5 then
			spellHooks.cast.botdet(p, "Frost", 31, 1, true, 30, 0)
			hookN = hookN + 1
		end
		if rand() < 0.1 then
			events.ChaosBotdetHealth.onHealthChange(p, p, 100, COMBAT_HEALING, 0, COMBAT_NONE, 0)
			hookN = hookN + 1
		end
		if s % 5 == 0 then p.signals = {keys = 4, paths = 1, pathSteps = 5} end
	end
	hookCost = hookCost + (os.clock() - h0)
	local t0 = os.clock()
	BD.tick()
	local dt = os.clock() - t0
	tickTotal = tickTotal + dt
	ticks = ticks + 1
	if dt > worst then worst = dt end
end
collectgarbage("collect")
local perCharKb = (collectgarbage("count") - memBefore) / PLAYERS
-- the mock's own work (positions, hook calls) is in hookCost; the tick is the sample, the poll, the flushes and the hourly passes
local perPlayerUs = tickTotal / ticks / PLAYERS * 1e6
local rowsWritten = BD.stats.rows
if verbose then
	quiet(string.format("per player and second: %.2f us (tick of %d players: %.2f ms mean, %.2f ms worst); memory %.0f KB a character; " ..
		"%d flushes and %d hourly passes wrote %d rows in %d simulated seconds; hooks %.2f us each", perPlayerUs, PLAYERS,
		tickTotal / ticks * 1000, worst * 1000, perCharKb, BD.stats.flushes, BD.stats.hourly, rowsWritten, SECONDS,
		hookCost / math.max(1, hookN) * 1e6))
end
check(perPlayerUs < 60, "the think costs less than 60 microseconds a player and second: " .. perPlayerUs)
check(worst < 0.060, "the worst tick of 400 players is under 60 ms: " .. worst * 1000)
check(perCharKb < 400, "less than 400 KB a character after half an hour: " .. perCharKb)
check(BD.stats.flushes >= PLAYERS * 5, "every character flushed about every 5 minutes: " .. BD.stats.flushes)
check(rowsWritten < PLAYERS * 6 * 8, "a few rows a flush, not thousands: " .. rowsWritten)
-- one hourly pass over full rings: two hours of position changes, the longest route search
local heavy = BD.states[sim[1].guid]
for i = 1, cfg.rings.pos do
	K.onSample(heavy, cfg, 3000 + (i * 7) % 211, 3000 + (i * 13) % 197, 7, clockS - cfg.rings.pos + i)
end
for i = 1, 200 do
	K.onCast(heavy, cfg, clockMs + i * 2100, clockS + i * 2, 31 + i % 5, false, 100, 100)
	K.onHeal(heavy, cfg, clockMs + i * 3100, clockS + i * 3, 40 + (i % 30))
end
local h0 = os.clock()
for i = 1, 10 do
	BD.hourly(heavy, clockS)
end
local hourlyMs = (os.clock() - h0) / 10 * 1000
if verbose then
	quiet(string.format("one hourly pass over full rings: %.2f ms", hourlyMs))
end
check(hourlyMs < 150, "an hourly pass over full rings takes under 150 ms: " .. hourlyMs)
print = quiet

if failures > 0 then
	print(string.format("botdet_engine_test: %d of %d checks failed", failures, count))
	for _, l in ipairs(logLines) do
		if l:find("botdet", 1, true) then print(l) end
	end
	os.exit(1)
end
print(string.format("botdet_engine_test: %d checks ok", count))
