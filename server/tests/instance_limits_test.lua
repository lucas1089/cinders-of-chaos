-- Run from the server/ folder: luajit tests/instance_limits_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The shared instance limits (server/README.md "Instance limits"):
--   core      warnings (each mark once, marks behind at the start skipped, the smallest of two crossed), idle grace,
--             the wait estimate, the busy text, the waiting line (add, position, expiry, cap, next), texts
--   glue      instance_limits.lua on a mocked engine: warnings to the players (chat + toast), the idle rule, busy + line,
--             freed tells the first in line who is online and outside every instance (nobody during a shutdown),
--             /instances list / close / line through the registry (Chaos.registerInstance runs / close), logout leaves
--             the line, staff only
--   rooms     tools/patch_base_bossrooms.py on a stock-shaped lever room script (written here), then the patched script
--             against the mocked engine: the lever is locked while a session runs (with when it frees up), the script's
--             own kick timer is stopped, warnings at 5 min / 1 min / 10 s, time up: everyone to the exit and the room's
--             monsters removed, an empty room frees up after the idle grace, a boss kill lets the script's own exit run
--             and frees the room when it is empty, a login inside a closed room goes to the exit (inside its own
--             running room it stays), a clean shutdown closes the rooms; the tool is idempotent, keeps CRLF, leaves
--             other shapes alone, --dry-run writes nothing
--   step-in   a stock-shaped miniboss file (two rooms entered by a tile, CRLF; written here): both rooms patched, a file
--             with one room of another shape left alone whole; on the mocked engine each room locks on its own (the
--             other room of the file stays free), the script's kick timer is stopped, a monster on the tile starts
--             nothing, time up sends everyone to the room's exit and removes its monsters
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- ======================================================================== core
local K = dofile("data/scripts/chaos/instance_limits_core.lua")
ok(K == ChaosInstanceLimitsCore, "the core is a global table too")

do -- warnings
	local st = {}
	eq(K.warning(st, 600, {300, 60, 10}), nil, "first look: nothing")
	eq(K.warning(st, 301, {300, 60, 10}), nil, "301 s: nothing")
	eq(K.warning(st, 300, {300, 60, 10}), 300, "300 s: the 5 minute mark")
	eq(K.warning(st, 299, {300, 60, 10}), nil, "each mark once")
	eq(K.warning(st, 61, {300, 60, 10}), nil, "61 s")
	eq(K.warning(st, 9, {300, 60, 10}), 10, "two marks crossed at once: the smaller")
	eq(K.warning(st, 5, {300, 60, 10}), nil, "and the other is spent")
	local late = {}
	eq(K.warning(late, 180, {300, 60, 10}), nil, "a 3 minute run starts")
	eq(K.warning(late, 170, {300, 60, 10}), nil, "no 5 minute warning in a 3 minute run")
	eq(K.warning(late, 60, {60, 300, 10}), 60, "marks in any order")
	eq(K.warning(nil, 10, {10}), nil, "no state: nothing")
	eq(K.warning({}, "x", {10}), nil, "no number: nothing")
	local exact = {}
	K.warning(exact, 300, {300, 60})
	eq(K.warning(exact, 299, {300, 60}), nil, "a run that starts on a mark skips it")
end

do -- idle
	local st = {}
	eq(K.idle(st, 100, true, 120), false, "occupied")
	eq(K.idle(st, 110, false, 120), false, "empty: the grace starts")
	eq(K.idleLeft(st, 150, 120), 80, "grace left")
	eq(K.idle(st, 229, false, 120), false, "119 s empty")
	eq(K.idle(st, 230, false, 120), true, "120 s empty: close")
	eq(K.idle(st, 231, true, 120), false, "somebody back: open again")
	eq(st.emptySince, nil, "the grace is reset")
	eq(K.idleLeft(st, 231, 120), nil, "not empty: no grace")
	eq(K.idle({}, 0, false, 0), true, "grace 0: at once")
end

do -- eta, caps, texts
	eq(K.eta({}, 1), nil, "nothing running: unknown")
	eq(K.eta({300, 100, 200}, 1), 100, "first in line: the first to end")
	eq(K.eta({300, 100, 200}, 3), 300, "third: the third")
	eq(K.eta({300, 100, 200}, 4), 100 + 300, "fourth: a round more")
	eq(K.eta({-5, nil}, 1), 0, "negative counts as now")
	eq(K.eta({100, 200}, 3, 600), 100 + 600, "a round is the full time when given")
	eq(K.capReached(3, 4), false, "under the cap")
	eq(K.capReached(4, 4), true, "at the cap")
	eq(K.capReached(99, 0), false, "0 = no cap")
	eq(K.clock(59), "0:59", "clock")
	eq(K.clock(3725), "1:02:05", "clock hours")
	eq(K.about(30), "under a minute", "about seconds")
	eq(K.about(61), "~2 min", "about rounds up")
	eq(K.about(3600), "~1 h", "about hours")
	eq(K.about(3660 + 30), "~1 h 2 min", "about hours and minutes")
	eq(K.leftText(300), "5 minutes left", "5 minutes")
	eq(K.leftText(60), "1 minute left", "1 minute")
	eq(K.leftText(10), "10 seconds left", "10 seconds")
	eq(K.leftText(90), "90 seconds left", "90 seconds")
	eq(K.ordinal(1) .. K.ordinal(2) .. K.ordinal(3) .. K.ordinal(4) .. K.ordinal(11) .. K.ordinal(22), "1st2nd3rd4th11th22nd",
		"ordinals")
	eq(K.busyText("rifts", 240, 2), "All rifts are busy. Try again in ~4 min. You are 2nd in line: you will be told when one is free.",
		"busy text with a wait and a place")
	eq(K.busyText("arenas", 20), "All arenas are busy. One frees up in under a minute.", "busy text, under a minute")
	eq(K.busyText("halls"), "All halls are busy. Try again in a moment.", "busy text without an estimate")
	local l = K.limits({warnAt = {300}, idleSeconds = 180, maxRuns = 0}, {maxRuns = 4})
	eq(l.maxRuns, 4, "own value wins")
	eq(l.idleSeconds, 180, "default fills in")
end

do -- the waiting line
	local line = {}
	eq(K.waitAdd(line, 11, 0, 60, "A"), 1, "first")
	eq(K.waitAdd(line, 12, 0, 60, "B"), 2, "second")
	eq(K.waitAdd(line, 11, 10, 60, "A"), 1, "again: same place, renewed")
	eq(K.waitPos(line, 12), 2, "position")
	eq(K.waitAdd(line, 13, 10, 60, "C", 2), nil, "the line is full")
	K.waitPrune(line, 65)
	eq(#line, 1, "B expired (added at 0, 60 s), A renewed at 10")
	eq(K.waitNext(line, 66).id, 11, "next is A")
	eq(#line, 0, "taken off")
	K.waitAdd(line, 14, 0, nil, "D")
	eq(K.waitRemove(line, 14), true, "removed")
	eq(K.waitRemove(line, 14), false, "removed once")
	eq(K.waitNext(line, 0), nil, "empty line")
end

-- ======================================================================== glue (mocked engine)
local events = {}
local function eventMock(kind)
	return function(name)
		local e = {name = name, kind = kind}
		function e:type(t) self.t = t end
		function e:separator() end
		function e:register() events[(self.name or kind) .. ":" .. tostring(self.t or kind)] = self end
		function e:aid(a) self.aidv = a end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action = eventMock("creature"), eventMock("global"), eventMock("talk"), eventMock("action")
local gameState = 1
GAME_STATE_NORMAL, GAME_STATE_SHUTDOWN, GAME_STATE_CLOSED = 1, 2, 3
local now = 1000000
os.time = function() return now end -- luacheck: ignore
local timers, nextTimer = {}, 0
addEvent = function(fn, ms, ...)
	nextTimer = nextTimer + 1
	timers[nextTimer] = {fn = fn, at = now * 1000 + ms, args = {...}}
	return nextTimer
end
stopEvent = function(id) if id then timers[id] = nil end end
local function runTimers()
	local due = {}
	for id, t in pairs(timers) do
		if t.at <= now * 1000 then
			due[#due + 1] = {id = id, t = t}
		end
	end
	table.sort(due, function(a, b) return a.id < b.id end)
	for _, d in ipairs(due) do
		if timers[d.id] then
			timers[d.id] = nil
			d.t.fn((table.unpack or unpack)(d.t.args))
		end
	end
end
local function advance(sec)
	for _ = 1, sec do
		now = now + 1
		runTimers()
	end
end

local function P(x, y, z)
	return setmetatable({x = x, y = y, z = z}, {__index = {sendMagicEffect = function() end}, __add = function(a, b)
		return P(a.x + b.x, a.y + b.y, a.z + b.z)
	end})
end
Position = P
local players, creatures = {}, {}
local toasts = {}
local function newPlayer(id, name, pos, staff)
	local p = {id = id, guid = id + 500, name = name, pos = pos, msgs = {}, cancels = {}, staff = staff}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getPosition() return self.pos end
	function p:teleportTo(q) self.pos = P(q.x, q.y, q.z) end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:sendCancelMessage(t) self.cancels[#self.cancels + 1] = t end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getGroup() return {getAccess = function() return staff == true end, getId = function() return staff and 6 or 1 end} end
	function p:getTown() return {getTemplePosition = function() return P(1, 1, 7) end} end
	players[id] = p
	creatures[#creatures + 1] = p
	return p
end
local function lastMsg(p) return p.msgs[#p.msgs] or "" end
Player = function(key)
	if type(key) == "string" then
		for _, p in pairs(players) do
			if p.name == key then return p end
		end
		return nil
	end
	return players[key]
end
local monsters = {}
Monster = function(id) return monsters[id] end
local monsterSeq = 9000
local function newMonster(name, pos)
	monsterSeq = monsterSeq + 1
	local m = {id = monsterSeq, name = name, pos = pos}
	function m:getId() return self.id end
	function m:getName() return self.name end
	function m:getPosition() return self.pos end
	function m:isPlayer() return false end
	function m:isMonster() return true end
	function m:registerEvent() end
	function m:remove()
		monsters[self.id] = nil
		for i, c in ipairs(creatures) do
			if c == self then table.remove(creatures, i) break end
		end
		self.removed = true
	end
	monsters[m.id] = m
	creatures[#creatures + 1] = m
	return m
end
Game = {
	getGameState = function() return gameState end,
	getPlayers = function()
		local l = {}
		for _, p in pairs(players) do l[#l + 1] = p end
		return l
	end,
	getSpectators = function(c, _, _, minx, maxx, miny, maxy)
		local l = {}
		for _, cr in ipairs(creatures) do
			local q = cr:getPosition()
			if q.z == c.z and q.x >= c.x - minx and q.x <= c.x + maxx and q.y >= c.y - miny and q.y <= c.y + maxy then
				l[#l + 1] = cr
			end
		end
		return l
	end,
	createMonster = function(name, pos) return newMonster(name, pos) end,
	createItem = function() return nil end,
	getReturnMessage = function() return "" end
}
ChaosNotify = {send = function(p, title, text) toasts[#toasts + 1] = {p = p, title = title, text = text} return true end}
local bars = {}
ChaosTileBars = {set = function(id, def) bars[id] = def end, removePrefix = function(prefix)
	for id in pairs(bars) do
		if id:sub(1, #prefix) == prefix then bars[id] = nil end
	end
end}

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/instance_limits.lua")
local IL = ChaosInstanceLimits
ok(IL and IL.warn and IL.busy and IL.freed, "the glue is loaded")
ok(events["/instances:talk"] ~= nil, "/instances is registered")
ok(events["ChaosBossRoomsLogin:login"] ~= nil and events["ChaosBossRoomsShutdown:global"] ~= nil, "room login / shutdown events")

do -- warnings to the players
	local a = newPlayer(1, "Ann", P(10, 10, 7))
	local run = {}
	IL.warn(run, 400, {a}, "Rift")
	eq(#a.msgs, 0, "no warning at 400 s")
	IL.warn(run, 300, {a}, "Rift")
	eq(lastMsg(a), "Rift: 5 minutes left. Everyone inside is sent out when the time runs out.", "5 minute warning")
	eq(#toasts, 1, "and a toast")
	IL.warn(run, 10, {a}, "Rift")
	ok(lastMsg(a):find("10 seconds left", 1, true) ~= nil, "10 s warning")
	eq(#toasts, 1, "no toast under a minute")
	IL.warn(run, 9, {a}, "Rift", {warnAt = {300, 60, 10}})
	eq(#a.msgs, 2, "the 60 s mark was crossed with the 10 s one: one message")
	ok(not IL.idle(run, true), "occupied")
	ok(not IL.idle(run, false, {idleSeconds = 60}), "empty: grace")
	now = now + 60
	ok(IL.idle(run, false, {idleSeconds = 60}), "empty for the grace: close")
	players[1] = nil
	creatures = {}
end

do -- busy, the line and freed
	local a = newPlayer(2, "Bo", P(10, 10, 7))
	local b = newPlayer(3, "Cy", P(10, 10, 7))
	local t = IL.busy(a, "rift", "rifts", {400, 100}, {waitlist = true})
	eq(t, "All rifts are busy. Try again in ~2 min. You are 1st in line: you will be told when one is free.", "busy text")
	t = IL.busy(b, "rift", "rifts", {400, 100}, {waitlist = true})
	ok(t:find("~7 min", 1, true) and t:find("2nd in line", 1, true), "the second waits for the second run: " .. t)
	eq(IL.busy(a, "rift", "rifts", {400, 100}, {waitlist = false}),
		"All rifts are busy. Try again in ~2 min.", "without the line")
	-- Bo is inside another instance now: skipped (and taken off), Cy is told
	Chaos.registerInstance("zz_test", {label = "a test", inside = function(p) return p.name == "Bo" end})
	local told = IL.freed("rift", "the rifts")
	eq(told, b, "the first in line outside every instance is told")
	ok(lastMsg(b):find("A place in the rifts is free now", 1, true) ~= nil, "message")
	eq(#IL.line("rift"), 0, "both are off the line")
	Chaos.instances.zz_test = nil
	IL.busy(a, "rift", "rifts", {}, {})
	gameState = GAME_STATE_SHUTDOWN
	eq(IL.freed("rift", "the rifts"), nil, "nobody is told while the server closes")
	gameState = GAME_STATE_NORMAL
	eq(#IL.line("rift"), 1, "the line is kept")
	events["ChaosInstanceLimitsLogout:logout"].onLogout(a)
	eq(#IL.line("rift"), 0, "a logout leaves the line")
	eq(IL.freed("rift"), nil, "empty line")
	players[2], players[3] = nil, nil
	creatures = {}
end

do -- /instances
	local closed
	Chaos.registerInstance("zz_runs", {label = "test runs", runs = function()
		return {{id = 7, what = "tier 3", left = 125, players = 2, idle = 30}, {id = 8, players = 0}}
	end, close = function(id) closed = id return true, "closed " .. id end})
	Chaos.registerInstance("zz_broken", {label = "broken", runs = function() error("boom") end})
	local gm = newPlayer(4, "Gm", P(1, 1, 7), true)
	local pl = newPlayer(5, "Pl", P(1, 1, 7))
	local talk = events["/instances:talk"]
	eq(talk.onSay(pl, "/instances", ""), true, "a player's /instances is plain chat")
	eq(#pl.msgs, 0, "players get nothing")
	eq(talk.onSay(gm, "/instances", "zz_runs"), false, "staff")
	ok(table.concat(gm.msgs, "\n"):find("zz_runs 7, tier 3, 2:05 left, 2 player(s), empty, closes in 0:30", 1, true) ~= nil,
		"a run with its time left and idle grace")
	ok(table.concat(gm.msgs, "\n"):find("zz_runs 8, no time limit, 0 player(s)", 1, true) ~= nil, "a run without a limit")
	ok(table.concat(gm.msgs, "\n"):find("2 instance(s) running of zz_runs", 1, true) ~= nil, "the count")
	gm.msgs = {}
	talk.onSay(gm, "/instances", "close zz_runs 7")
	eq(closed, 7, "close by type and id")
	eq(lastMsg(gm), "closed 7", "the system's answer")
	talk.onSay(gm, "/instances", "close nothing 1")
	ok(lastMsg(gm):find("Not closed", 1, true) ~= nil, "unknown type")
	talk.onSay(gm, "/instances", "close zz_runs")
	ok(lastMsg(gm):find("Usage", 1, true) ~= nil, "usage")
	IL.busy(pl, "descent", "halls", {}, {})
	talk.onSay(gm, "/instances", "line")
	eq(lastMsg(gm), "descent line: Pl", "the waiting line")
	Chaos.instances.zz_runs, Chaos.instances.zz_broken = nil, nil
	players[4], players[5] = nil, nil
	creatures = {}
	IL.lines = {}
end

-- ======================================================================== base lever boss rooms
local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("instance_limits_test: python3 not found, the boss room part is skipped")
else
	local function readFile(path)
		local f = io.open(path, "rb")
		if not f then return nil end
		local s = f:read("*a")
		f:close()
		return s
	end
	local function writeFile(path, text)
		local f = assert(io.open(path, "wb"))
		f:write(text)
		f:close()
	end
	local function sh(cmd)
		local h = io.popen(cmd .. " 2>&1")
		local out = h:read("*a")
		h:close()
		return out
	end
	local root = os.tmpname()
	os.remove(root)
	local data = root .. "/data"
	local dir = data .. "/scripts/customs/bosses"
	os.execute("mkdir -p '" .. dir .. "' '" .. data .. "/scripts/chaos'")
	-- the stock template (names made up; the shape is the base server's)
	local ROOM = [[
local config = {
    actionId = 45001,
    bossName = "ashen warden",
    bossPosition = Position(1010, 1010, 7),
    bossArea = {
        fromPos = Position(1000, 1000, 7),
        toPos = Position(1020, 1020, 7),
        entrancePos = Position(1002, 1010, 7),
        exitPosition = Position(1030, 1010, 7)
    },
    participantsAllowAnyCount = true,
    participantsPos = {
        Position(1030, 1015, 7),
        Position(1031, 1015, 7)
    },
    attempts = {
        level = 100,
        storage = 720999,
        seconds = 1800
    },
    createTeleportPos = Position(1010, 1004, 7),
    teleportToPosition = Position(1030, 1010, 7),
    teleportRemoveSeconds = 60,
    kickParticipantAfterSeconds = 60 * 10,
    leverIds = {1945, 1946}
}

local function getSpectators()
    if not config.centerPosition then
        config.diffX = math.ceil((config.bossArea.toPos.x - config.bossArea.fromPos.x) / 2)
        config.diffY = math.ceil((config.bossArea.toPos.y - config.bossArea.fromPos.y) / 2)
        config.centerPosition = config.bossArea.fromPos + Position(config.diffX, config.diffY, 0)
    end
    return Game.getSpectators(config.centerPosition, false, false, config.diffX, config.diffX, config.diffY, config.diffY)
end

local wardenAction = Action()

function wardenAction.onUse(player, item, fromPos, target, toPos, isHotkey)
    local participants = {}
    for index, pos in pairs(config.participantsPos) do
        local tile = Tile(pos)
        if not tile then error("[Warning - Tile not found]") end
        local participant = tile:getTopVisibleCreature(player)
        if participant and participant:isPlayer() then
            if index == 1 and participant ~= player then
                player:sendCancelMessage("Only the first participant can pull the lever.")
                return true
            end
            participants[#participants +1] = participant
        end
    end

    local spectators = getSpectators()
    for _, spectator in pairs(spectators) do
        if spectator:isPlayer() then
            player:sendCancelMessage("At this time the room is occupied, please try again later.")
            return true
        end
    end

    for _, spectator in pairs(spectators) do spectator:remove() end
    local boss = Game.createMonster(config.bossName, config.bossPosition)
    if not boss then error(Game.getReturnMessage(RETURNVALUE_NOTENOUGHROOM)) end
    boss:registerEvent("wardenSystemDeath")
    for index, participant in pairs(participants) do
        participant:teleportTo(config.bossArea.entrancePos, false)
    end

    config.kickEventId = addEvent(function ()
        for _, spectator in pairs(getSpectators()) do
            if spectator:isPlayer() then
                spectator:teleportTo(config.bossArea.exitPosition, false)
                spectator:sendTextMessage(MESSAGE_INFO_DESCR, "It's been a long time and you haven't managed to defeat the boss.")
            else
                spectator:remove()
            end
        end
    end, config.kickParticipantAfterSeconds * 1000)

    item:transform(item:getId() == config.leverIds[1] and config.leverIds[2] or config.leverIds[1])
    return true
end

wardenAction:aid(config.actionId)
wardenAction:register()

local creatureEvent = CreatureEvent("wardenSystemDeath")

function creatureEvent.onDeath()
    stopEvent(config.kickEventId)
    addEvent(function ()
        for _, spectator in pairs(getSpectators()) do
            if spectator:isPlayer() then
                spectator:teleportTo(config.teleportToPosition, false)
            end
        end
    end, config.teleportRemoveSeconds * 1000)
    return true
end

creatureEvent:register()
]]
	local crlf = ROOM:gsub("\n", "\r\n"):gsub("actionId = 45001", "actionId = 45002")
	-- two rooms in one file (stepped on, not a lever): not this shape, left alone
	local OTHER = "local config = {\n    bossArea = {},\n    kickParticipantAfterSeconds = 60,\n}\nlocal config = {\n}\n"
	writeFile(dir .. "/warden.lua", ROOM)
	writeFile(dir .. "/warden_crlf.lua", crlf)
	writeFile(dir .. "/minis.lua", OTHER)
	writeFile(data .. "/scripts/chaos/ours.lua", ROOM) -- ours: never touched
	local tool = "python3 -I tools/patch_base_bossrooms.py '" .. data .. "'"
	local out = sh(tool .. " --dry-run")
	ok(out:find("patched aid45001 %(dry run") ~= nil, "dry run reports: " .. out)
	eq(readFile(dir .. "/warden.lua"), ROOM, "dry run writes nothing")
	out = sh(tool)
	ok(out:find("warden.lua: patched aid45001", 1, true) ~= nil, "patched: " .. out)
	ok(out:find("minis.lua: unrecognised", 1, true) ~= nil, "another shape is listed and left alone")
	ok(out:find("ours.lua", 1, true) == nil, "scripts/chaos is never read")
	eq(readFile(dir .. "/minis.lua"), OTHER, "the other shape is unchanged")
	eq(readFile(data .. "/scripts/chaos/ours.lua"), ROOM, "ours unchanged")
	local patched = readFile(dir .. "/warden.lua")
	local _, marks = patched:gsub("patch_base_bossrooms%.py", "")
	eq(marks, 4, "three insertions (four marked lines)")
	local c = readFile(dir .. "/warden_crlf.lua")
	ok(c:find('ChaosBossRoomsPending["aid45002"] = config -- Chaos (patch_base_bossrooms.py)\r\n', 1, true) ~= nil, "CRLF kept")
	local _, lf = c:gsub("[^\r]\n", "")
	eq(lf, 0, "no bare LF in a CRLF file")
	out = sh(tool)
	ok(out:find("already patched", 1, true) ~= nil and out:find("patched aid", 1, true) == nil, "second run: nothing new")
	eq(readFile(dir .. "/warden.lua"), patched, "idempotent")

	-- the patched script on the mocked engine
	local item = {id = 1945}
	function item:getId() return self.id end
	function item:transform(id) self.id = id end
	local tiles = {}
	Tile = function(pos)
		local key = pos.x .. ":" .. pos.y .. ":" .. pos.z
		return {getTopVisibleCreature = function() return tiles[key] end}
	end
	local chunk = assert((loadstring or load)(patched, "=warden.lua"))
	chunk()
	local action, death = events["action:action"], events["wardenSystemDeath:creature"]
	ok(action and action.aidv == 45001 and death, "the patched room script registers as before")
	ok(ChaosBossRooms.rooms.aid45001 == nil and ChaosBossRoomsPending.aid45001 ~= nil, "the room waits in the pending list")
	ChaosBossRooms.collect()
	ok(ChaosBossRooms.rooms.aid45001 ~= nil, "collected")
	local lever = P(1030, 1015, 7)
	local function stand(p, at) p.pos = at tiles[at.x .. ":" .. at.y .. ":" .. at.z] = p end
	local a = newPlayer(11, "Ash", P(1030, 1015, 7))
	local b = newPlayer(12, "Bree", P(1031, 1015, 7))
	-- player report 2026-10-22: a pull from beside the lever (nobody on the participant tiles) made the boss, sent
	-- nobody in and locked the room. Now it is refused: no boss, no session, the lever as it was
	local side = newPlayer(14, "Dax", P(1029, 1014, 7))
	local nBefore = #creatures
	action.onUse(side, item, lever)
	ok((side.cancels[1] or ""):find("Stand on the tile in front of the lever", 1, true) ~= nil,
		"a pull from beside the lever is refused: " .. tostring(side.cancels[1]))
	eq(ChaosBossRooms.sessions.aid45001, nil, "no session (the room stays free)")
	eq(#creatures, nBefore, "no boss made")
	eq(item.id, 1945, "the lever did not move")
	-- a lever script that still reports an empty group: no lock, the boss it made is removed
	local stray = newMonster("Ashen warden", P(1010, 1010, 7))
	ChaosBossRooms.started("aid45001", ChaosBossRooms.rooms.aid45001, {})
	eq(ChaosBossRooms.sessions.aid45001, nil, "an empty group locks nothing")
	ok(not Monster(stray:getId()), "and its boss is gone")
	-- a participant the script's teleport left outside (its entrance on a tile that blocks): onto the nearest free
	-- tile of the room next to the entrance
	local oldTile = Tile
	Tile = function(pos)
		local blocked = pos.x == 1002 and pos.y == 1010 -- the entrance itself blocks
		return {getGround = function() return {} end, hasProperty = function() return blocked end,
			getTopCreature = function() return nil end, getTopVisibleCreature = function() return nil end}
	end
	local out = newPlayer(15, "Eli", P(1030, 1015, 7))
	ok(ChaosBossRooms.bringIn(ChaosBossRooms.rooms.aid45001, out), "brought in")
	ok(ChaosBossRooms.inRoom(ChaosBossRooms.rooms.aid45001, out.pos) and not (out.pos.x == 1002 and out.pos.y == 1010)
		and math.abs(out.pos.x - 1002) <= 1 and math.abs(out.pos.y - 1010) <= 1, "next to the blocked entrance, inside")
	eq(ChaosBossRooms.bringIn(ChaosBossRooms.rooms.aid45001, out), false, "already inside: left where it is")
	Tile = oldTile
	players[15] = nil
	for i, cr in ipairs(creatures) do
		if cr == out then table.remove(creatures, i) break end
	end
	stand(a, lever)
	stand(b, P(1031, 1015, 7))
	-- a first group goes in
	action.onUse(a, item, lever)
	eq(a.pos.x, 1002, "the group is in the room")
	local s = ChaosBossRooms.sessions.aid45001
	ok(s ~= nil and s.limit == 600, "a session of the room's own 10 minutes")
	ok(s.bossId ~= nil, "the boss is known")
	local kick = ChaosBossRooms.rooms.aid45001.kickEventId
	eq(kick, nil, "the script's own kick timer was stopped")
	ok(bars["room:aid45001:in"] ~= nil and bars["room:aid45001:lever"] ~= nil, "countdown bars over the entrance and the lever")
	-- a second group at the lever: locked
	local c2 = newPlayer(13, "Cole", P(1030, 1015, 7))
	tiles["1030:1015:7"] = c2
	c2.pos = lever
	action.onUse(c2, item, lever)
	ok((c2.cancels[1] or ""):find("frees up in ~10 min", 1, true) ~= nil, "locked, with the time: " .. tostring(c2.cancels[1]))
	eq(c2.pos.x, 1030, "the second group stays out")
	-- warnings
	advance(300)
	ok(table.concat(a.msgs, "\n"):find("5 minutes left", 1, true) ~= nil, "5 minute warning: " .. table.concat(a.msgs, " | "))
	advance(240)
	ok(table.concat(b.msgs, "\n"):find("1 minute left", 1, true) ~= nil, "1 minute warning to everyone inside")
	advance(50)
	ok(lastMsg(a):find("10 seconds left", 1, true) ~= nil, "10 s warning")
	-- a monster the boss called in, then time up
	newMonster("ember add", P(1005, 1005, 7))
	advance(15)
	eq(a.pos.x, 1030, "time up: at the exit")
	eq(b.pos.y, 1010, "everyone")
	ok(lastMsg(a):find("Time is up", 1, true) ~= nil, "told why")
	eq(ChaosBossRooms.sessions.aid45001, nil, "the room is free")
	local left = 0
	for _, cr in ipairs(creatures) do
		if cr.isMonster and cr:isMonster() and ChaosBossRooms.inRoom(ChaosBossRooms.rooms.aid45001, cr:getPosition()) then
			left = left + 1
		end
	end
	eq(left, 0, "the boss and the add were removed")
	eq(bars["room:aid45001:in"], nil, "bars removed")
	-- the old base timer would have kicked the next group: nothing is pending for it any more
	local pending = 0
	for _ in pairs(timers) do pending = pending + 1 end
	eq(pending, 0, "no timer left behind")

	-- a second group; everyone logs out: the room frees up after the idle grace
	item.id = 1945
	tiles["1030:1015:7"] = a
	a.pos = lever
	tiles["1031:1015:7"] = nil
	action.onUse(a, item, lever)
	ok(ChaosBossRooms.sessions.aid45001 ~= nil, "a new session")
	for i, cr in ipairs(creatures) do
		if cr == a then table.remove(creatures, i) break end
	end
	players[11] = nil
	advance(119)
	ok(ChaosBossRooms.sessions.aid45001 ~= nil, "119 s empty: still held")
	advance(2)
	eq(ChaosBossRooms.sessions.aid45001, nil, "empty for the grace (2 minutes): free")
	-- Ash logs in again: inside a closed room -> the exit
	players[11] = a
	creatures[#creatures + 1] = a
	events["ChaosBossRoomsLogin:login"].onLogin(a)
	eq(a.pos.x, 1030, "a login inside a closed room goes to the exit")
	ok(lastMsg(a):find("has closed", 1, true) ~= nil, "told")

	-- a third group kills the boss: the script's own exit runs; the room frees up as soon as it is empty
	item.id = 1945
	a.pos = lever
	tiles["1030:1015:7"] = a
	action.onUse(a, item, lever)
	s = ChaosBossRooms.sessions.aid45001
	-- a relog inside its own running room stays
	events["ChaosBossRoomsLogin:login"].onLogin(a)
	eq(a.pos.x, 1002, "a login inside its own running room stays")
	monsters[s.bossId]:remove()
	death.onDeath()
	advance(1)
	eq(s.state, "won", "the kill is seen")
	ok(bars["room:aid45001:in"].label == "Room closes", "the bar says when the room closes")
	advance(60)
	eq(a.pos.x, 1030, "the script's own exit after teleportRemoveSeconds")
	advance(1)
	eq(ChaosBossRooms.sessions.aid45001, nil, "empty after a kill: free at once")

	-- staff: /instances lists and closes a room; a clean shutdown closes the rooms
	item.id = 1945
	a.pos = lever
	action.onUse(a, item, lever)
	local list = IL.runs()
	local found
	for _, r in ipairs(list) do
		if r.key == "bossroom" and r.id == "aid45001" then found = r end
	end
	ok(found and found.left == 600 and found.players == 1 and found.what == "Ashen warden", "listed for the staff")
	ok(IL.close("bossroom", "aid45001"), "staff close")
	eq(a.pos.x, 1030, "out")
	ok(lastMsg(a):find("gamemaster", 1, true) ~= nil, "told")
	item.id = 1945
	a.pos = lever
	action.onUse(a, item, lever)
	events["ChaosBossRoomsShutdown:global"].onShutdown()
	eq(a.pos.x, 1030, "a shutdown closes the room (saved at the exit)")
	eq(next(ChaosBossRooms.sessions), nil, "no session left")
	-- the room counts as an instance (Town Portal, hideout refuse there)
	a.pos = P(1005, 1005, 7)
	eq(Chaos.instanceAt(a.pos), "bossroom", "the room's area is an instance")
	-- the time cap: a 60 minute room gets 30
	eq(ChaosBossRooms.limitOf({kickParticipantAfterSeconds = 3600}), 1800, "capped at 30 minutes")
	eq(ChaosBossRooms.limitOf({kickParticipantAfterSeconds = 600}), 600, "a shorter room keeps its time")

	-- ------------------------------------------------------------ step-in rooms (several in one file)
	-- the stock miniboss template (names made up; the shape is the base server's): one config per room, a tile
	-- (MoveEvent onStepIn) instead of a lever, an exit tile inside the room
	local function stepRoom(aid, name, x, var)
		return (([[
local config = {
    actionId = AID,
    bossName = "NAME",
    bossPosition = Position(X5, 2005, 7),
    bossArea = {
        fromPos = Position(X0, 2000, 7),
        toPos = Position(X10, 2010, 7),
        entrancePos = Position(X2, 2002, 7),
        exitPosition = Position(X20, 1990, 7)
    },
    participantsAllowAnyCount = true,
    participantsPos = {
        Position(X20, 1995, 7),
    },
    attempts = {
        level = 100,
        storage = 721001,
        seconds = 1800 -- 30 min
    },
    kickParticipantAfterSeconds = 60 * 10,
}

local function getSpectators()
    if not config.centerPosition then
        config.diffX = math.ceil((config.bossArea.toPos.x - config.bossArea.fromPos.x) / 2)
        config.diffY = math.ceil((config.bossArea.toPos.y - config.bossArea.fromPos.y) / 2)
        config.centerPosition = config.bossArea.fromPos + Position(config.diffX, config.diffY, 0)
    end
    return Game.getSpectators(config.centerPosition, false, false, config.diffX, config.diffX, config.diffY, config.diffY)
end

local VAR = MoveEvent()

function VAR.onStepIn(player, item, fromPosition, target, toPos, isHotkey)
    local participants = {}
    for index, pos in pairs(config.participantsPos) do
        local tile = Tile(pos)
        if not tile then error("[Warning - Tile not found]") end
        local participant = tile:getTopVisibleCreature(player)
        if participant and participant:isPlayer() then
            if index == 1 and participant ~= player then
                player:sendCancelMessage("Only the first participant can pull the lever.")
                return true
            end

            if participant:getStorageValue(config.attempts.storage) >= os.time() then
                player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The player "..participant:getName().." must wait.")
                return true
            elseif participant:getLevel() < config.attempts.level then
                player:sendCancelMessage(string.format("The player %s is not level %d.", participant:getName(), config.attempts.level))
                return true
            end
            participants[#participants +1] = participant
        end
    end

    local spectators = getSpectators()
    for _, spectator in pairs(spectators) do
        if spectator:isPlayer() then
            player:sendCancelMessage("At this time the room is occupied, please try again later.")
            return true
        end
    end

    for _, spectator in pairs(spectators) do spectator:remove() end
    local boss = Game.createMonster(config.bossName, config.bossPosition)
    if not boss then error(Game.getReturnMessage(RETURNVALUE_NOTENOUGHROOM)) end
    for index, participant in pairs(participants) do
        participant:teleportTo(config.bossArea.entrancePos, false)
        participant:setStorageValue(config.attempts.storage, os.time() + config.attempts.seconds)
    end

    config.kickEventId = addEvent(function ()
        for _, spectator in pairs(getSpectators()) do
            if spectator:isPlayer() then
                spectator:teleportTo(config.bossArea.exitPosition, false)
                spectator:sendTextMessage(MESSAGE_INFO_DESCR, "It's been a long time and you haven't managed to defeat the boss.")
            else
                spectator:remove()
            end
        end
    end, config.kickParticipantAfterSeconds * 1000)
    return true
end

VAR:aid(config.actionId)
VAR:type("stepin")
VAR:register()


local exit = MoveEvent()
function exit.onStepIn(player, item, fromPos, target, toPos, isHotkey)
    if not player then
        return false
    end
 player:teleportTo(Position(X20, 1990, 7))
end

exit:aid(AIDX)
exit:type("stepin")
exit:register()


]]):gsub("AIDX", tostring(aid + 1)):gsub("AID", tostring(aid)):gsub("NAME", name):gsub("VAR", var)
			:gsub("X(%d+)", function(d) return tostring(x + tonumber(d)) end))
	end
	local MINIS = (stepRoom(46001, "mire hag", 2000, "mireHag") .. stepRoom(46003, "bog lord", 2100, "bogLord"))
		:gsub("\n", "\r\n")
	-- a second miniboss file whose second room is of another shape: the whole file is left alone
	local MIXED = stepRoom(46011, "reed witch", 2200, "reedWitch") ..
		"local config = {\n    bossArea = {},\n    kickParticipantAfterSeconds = 60,\n}\n"
	local mdir = data .. "/scripts/customs/extensions/marsh"
	os.execute("mkdir -p '" .. mdir .. "'")
	writeFile(mdir .. "/minibosses.lua", MINIS)
	writeFile(mdir .. "/mixed.lua", MIXED)
	out = sh(tool)
	ok(out:find("marsh/minibosses.lua: patched aid46001, aid46003\n", 1, true) ~= nil, "both step-in rooms patched: " .. out)
	ok(out:find("marsh/mixed.lua: unrecognised (room 2 of 2:", 1, true) ~= nil, "a file with a room of another shape: listed")
	eq(readFile(mdir .. "/mixed.lua"), MIXED, "and left alone whole")
	local minis = readFile(mdir .. "/minibosses.lua")
	local _, mmarks = minis:gsub("patch_base_bossrooms%.py", "")
	eq(mmarks, 8, "four marked lines per room")
	ok(minis:find('    if ChaosBossRooms and not ChaosBossRooms.leverUse(player, "aid46003", config) then return true end' ..
		' -- Chaos (patch_base_bossrooms.py)\r\n', 1, true) ~= nil, "the tile's onStepIn gets the lock, CRLF kept")
	local _, mlf = minis:gsub("[^\r]\n", "")
	eq(mlf, 0, "no bare LF in the CRLF file")
	out = sh(tool)
	ok(out:find("marsh/minibosses.lua: already patched", 1, true) ~= nil, "second run: already patched")
	eq(readFile(mdir .. "/minibosses.lua"), minis, "idempotent")

	-- the patched file on the mocked engine
	local moves = {}
	MoveEvent = function()
		local e = {}
		function e:aid(a) self.aidv = a end
		function e:type(t) self.t = t end
		function e:register() moves[self.aidv] = self end
		return e
	end
	assert((loadstring or load)(minis, "=minibosses.lua"))()
	ok(moves[46001] and moves[46002] and moves[46003] and moves[46004], "both rooms and both exit tiles register as before")
	ChaosBossRooms.collect()
	ok(ChaosBossRooms.rooms.aid46001 and ChaosBossRooms.rooms.aid46003, "both rooms known, each with its own config")
	local function stepper(p)
		p.storage = {}
		function p:getStorageValue(k) return self.storage[k] or -1 end
		function p:setStorageValue(k, v) self.storage[k] = v end
		function p:getLevel() return 200 end
		return p
	end
	local tile1, tile2 = P(2020, 1995, 7), P(2120, 1995, 7)
	local fen = stepper(newPlayer(21, "Fen", tile1))
	tiles["2020:1995:7"] = fen
	moves[46001].onStepIn(fen, item, tile1)
	eq(fen.pos.x, 2002, "stepping on the tile: in the room")
	local ms = ChaosBossRooms.sessions.aid46001
	ok(ms ~= nil and ms.limit == 600 and ms.bossId ~= nil, "a session of the room's 10 minutes, the boss known")
	eq(ChaosBossRooms.rooms.aid46001.kickEventId, nil, "the script's own kick timer was stopped")
	ok(bars["room:aid46001:lever"] ~= nil and bars["room:aid46001:lever"].pos.x == 2020, "the 'Room in use' bar over the tile")
	eq(ChaosBossRooms.sessions.aid46003, nil, "the other room of the file is free")
	-- a second player on the same tile: locked; the other room takes them
	local gil = stepper(newPlayer(22, "Gil", tile1))
	tiles["2020:1995:7"] = gil
	moves[46001].onStepIn(gil, item, tile1)
	ok((gil.cancels[1] or ""):find("frees up in ~10 min", 1, true) ~= nil, "locked, with the time: " .. tostring(gil.cancels[1]))
	eq(gil.pos.x, 2020, "stays on the tile")
	gil.pos = tile2
	tiles["2020:1995:7"] = nil
	tiles["2120:1995:7"] = gil
	moves[46003].onStepIn(gil, item, tile2)
	eq(gil.pos.x, 2102, "the other room of the file runs at the same time")
	-- a monster walks onto the first tile: nothing starts (the stock script would make the boss for it)
	local before = #creatures
	local rat = newMonster("marsh rat", tile1)
	tiles["2020:1995:7"] = rat
	moves[46001].onStepIn(rat, item, tile1)
	eq(#creatures, before + 1, "a monster on the tile: no boss made")
	eq(ChaosBossRooms.sessions.aid46001, ms, "and the session is unchanged")
	-- time up: everyone to the room's exit, the room's monsters removed
	newMonster("bog add", P(2005, 2006, 7))
	advance(601)
	eq(fen.pos.x, 2020, "time up: at the room's exit")
	eq(fen.pos.y, 1990, "the exit of this room")
	eq(gil.pos.x, 2120, "the other room's group at its own exit")
	local leftIn = 0
	for _, cr in ipairs(creatures) do
		if cr.isMonster and cr:isMonster() and (ChaosBossRooms.inRoom(ChaosBossRooms.rooms.aid46001, cr:getPosition())
			or ChaosBossRooms.inRoom(ChaosBossRooms.rooms.aid46003, cr:getPosition())) then
			leftIn = leftIn + 1
		end
	end
	eq(leftIn, 0, "the bosses and the add were removed")
	ok(ChaosBossRooms.sessions.aid46001 == nil and ChaosBossRooms.sessions.aid46003 == nil, "both rooms free")
	os.execute("rm -rf '" .. root .. "'")
end

print(string.format("instance_limits_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
