-- Run from the server/ folder: luajit tests/instance_limits_systems_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The instance limits (server/README.md "Instance limits") in two systems whose own tests do not load the engine file:
--   dungeons.lua         the run's length is the base DungeonTime capped at maxTimeSeconds (the client is told), the
--                        warnings, time up (everyone out where they entered, the cooldown, the box cleaned), the queue's
--                        wait shows the run inside, a relog inside the box leaves the run (temple, cooldown) instead of
--                        standing in it, the staff list and close
--   newplayer_tutorial   the island's time limit counts online time only (kept over a logout), warnings, the end is the
--                        "Skip tutorial" exit (kit, temple), a login past the limit leaves at once, the staff list
-- The other systems' limits are tested in their own files (rift_refund, raid, uber, guildboss, trials_flow, arena_flow,
-- battleground_flow, infinitytower_run, worldboss) and in instance_limits_test.lua.
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

-- ------------------------------------------------------------------ engine mocks
local events = {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function(self) events[(rawget(self, "name") or kind) .. ":" .. kind] = self end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = eventMock("creature"), eventMock("global"), eventMock("talk"),
	eventMock("action"), eventMock("move")
EventCallback = setmetatable({}, {__index = function() return function() end end})
local clockMs = 2000000000
os.mtime = function() return clockMs end
os.time = function(t) -- luacheck: ignore
	return math.floor(clockMs / 1000)
end
local queue = {}
addEvent = function(fn, ms, ...)
	queue[#queue + 1] = {fn = fn, at = clockMs + (ms or 0), args = {...}, n = select("#", ...)}
	return #queue
end
stopEvent = function() end
local unpack = table.unpack or unpack
-- runs the due events (only those `filter` lets through, when given) up to clockMs + ms
local function advance(ms, filter)
	local limit = clockMs + ms
	while true do
		local best, bi
		for i, q in ipairs(queue) do
			if q.at <= limit and (not best or q.at < best.at) then
				best, bi = q, i
			end
		end
		if not best then
			break
		end
		table.remove(queue, bi)
		clockMs = math.max(clockMs, best.at)
		if not filter or filter(best.fn) then
			best.fn(unpack(best.args, 1, best.n))
		end
	end
	clockMs = limit
end
local function P(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
Position = P
db = {query = function() return true end, storeQuery = function() return nil end, asyncQuery = function() end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end}
result = {free = function() end}
local players = {}
local temple = P(1, 1, 7)
local function newPlayer(guid, name, pos)
	local p = {guid = guid, id = guid + 1000, name = name, pos = pos, storage = {}, msgs = {}, cancels = {}, lastLogout = 0}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getPosition() return self.pos end
	function p:teleportTo(q) self.pos = P(q.x, q.y, q.z) end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:sendCancelMessage(t) self.cancels[#self.cancels + 1] = t end
	function p:popupFYI(t) self.msgs[#self.msgs + 1] = t end
	function p:say() end
	function p:registerEvent() end
	function p:unregisterEvent() end
	function p:getLevel() return 500 end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:isPzLocked() return false end
	function p:hasCondition() return false end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getTown() return {getTemplePosition = function() return temple end} end
	function p:getLastLogout() return self.lastLogout end
	function p:getGroup() return {getAccess = function() return false end, getId = function() return 1 end} end
	function p:getVocation() return {getId = function() return 4 end} end
	function p:sendExtendedOpcode() end
	players[guid] = p
	return p
end
Player = function(k)
	for _, p in pairs(players) do
		if p.name == k or p.id == k then
			return p
		end
	end
	return nil
end
local function said(p, text)
	for _, t in ipairs(p.msgs) do
		if t:find(text, 1, true) then
			return true
		end
	end
	return false
end

dofile("data/scripts/chaos/chaos_constants.lua")
local sent = {}
Chaos.send = function(p, opcode, action, data) sent[#sent + 1] = {p = p, action = action, data = data} return true end
Chaos.decode = function(b) return b end
Chaos.select = function() return {} end
Chaos.isMultiClient = function() return false end
dofile("data/scripts/chaos/instance_limits.lua")
local IL = ChaosInstanceLimits

-- ================================================================== dungeons.lua
do
	DUNGEON_SYSTEM = {CooldownTime = 3600, Storages = {timerCooldown = 50203},
		Dungeons = {[1] = {Name = "Test Crypt", NeedParty = false, NeedLevel = false, DungeonTime = 3600,
			FromPos = {x = 500, y = 500, z = 7}, ToPos = {x = 520, y = 520, z = 7}, DungeonPos = {x = 510, y = 510, z = 7}}}}
	Game = {getPlayers = function()
		local l = {}
		for _, p in pairs(players) do l[#l + 1] = p end
		return l
	end, getSpectators = function(c, _, _, rx1, rx2, ry1, ry2)
		local l = {}
		for _, p in pairs(players) do
			local q = p.pos
			if q.z == c.z and q.x >= c.x - rx1 and q.x <= c.x + rx2 and q.y >= c.y - ry1 and q.y <= c.y + ry2 then
				l[#l + 1] = p
			end
		end
		return l
	end}
	dofile("data/scripts/chaos/dungeons.lua")
	local ext = events["ChaosDungeonsExtended:creature"]
	local login, logout = events["ChaosDungeonsLogin:creature"], events["ChaosDungeonsLogout:creature"]
	ok(ext and login and logout, "dungeons: events")
	local cfg = Chaos.dungeons
	eq(cfg.maxTimeSeconds, 900, "dungeons: 15 minutes at most (pack combat)")
	local a = newPlayer(1, "Dara", P(100, 100, 7))
	local b = newPlayer(2, "Elm", P(101, 100, 7))
	login.onLogin(a)
	ext.onExtendedOpcode(a, ChaosOpcodes.dungeons, {action = "queue", data = {id = 1, difficulty = 1}})
	eq(a.pos.x, 510, "dungeons: the run starts, the player is inside")
	local start
	for _, s in ipairs(sent) do
		if s.action == "start" and s.p == a then start = s.data end
	end
	eq(start and start.duration, 900 * 1000, "dungeons: the client's clock is the capped time (60 -> 15 minutes)")
	-- a second player queues: the wait is the run inside (the window's dungeon page)
	ItemType = function(id) return {getId = function() return id end, getClientId = function() return id end} end
	MonsterType = function() return nil end
	ext.onExtendedOpcode(b, ChaosOpcodes.dungeons, {action = "queue", data = {id = 1, difficulty = 1}})
	eq(b.pos.x, 101, "dungeons: one run per dungeon: the second waits")
	sent = {}
	ext.onExtendedOpcode(b, ChaosOpcodes.dungeons, {action = "fetch"})
	local wait
	for _, s in ipairs(sent) do
		if s.action == "dungeon" and s.data.queue then wait = s.data.queue.estimated end
	end
	ok(wait and wait >= 890 * 1000, "dungeons: the queue shows the wait of the run inside: " .. tostring(wait))
	-- staff list
	local found
	for _, r in ipairs(IL.runs()) do
		if r.key == "dungeon" then found = r end
	end
	ok(found and found.players == 1 and found.left == 900 and found.note == "1 queued", "dungeons: listed")
	-- warnings, then time up
	advance((900 - 300 + 3) * 1000)
	ok(said(a, "Bones Dungeon: 5 minutes left"), "dungeons: the 5 minute warning: " .. table.concat(a.msgs, " | "))
	advance(240 * 1000)
	ok(said(a, "Bones Dungeon: 1 minute left"), "dungeons: the 1 minute warning")
	advance(61 * 1000)
	eq(a.pos.x, 100, "dungeons: time up: back where the player entered")
	ok(a.storage[50203] and a.storage[50203] - os.time() <= Chaos.dungeons.failCooldownSeconds and a.storage[50203] > os.time(),
		"dungeons: a failed run (time up): the short fail cooldown")
	-- the waiting player gets the dungeon now (b queued without a cooldown)
	advance(3000)
	eq(b.pos.x, 510, "dungeons: the next in the queue goes in")
	-- b logs out and back in while the server runs: out of the run, not left standing in the box
	b.lastLogout = os.time()
	logout.onLogout(b)
	advance(3000)
	login.onLogin(b)
	eq(b.pos.x, temple.x, "dungeons: a relog inside the box goes to the temple")
	ok(said(b, "You logged out inside the dungeon: your run is over."), "dungeons: told why")
	ok(b.storage[50203] and b.storage[50203] - os.time() <= Chaos.dungeons.failCooldownSeconds,
		"dungeons: leaving by a logout is a failed attempt: the short fail cooldown")
	-- a restart: the first login inside the box goes to the temple without a cooldown
	local c = newPlayer(3, "Fen", P(511, 511, 7))
	c.lastLogout = ChaosDungeonsBoot - 10
	login.onLogin(c)
	eq(c.pos.x, temple.x, "dungeons: after a restart: the temple")
	eq(c.storage[50203], nil, "dungeons: no cooldown for a restart")
	-- staff close: the failure rule
	c.pos = P(100, 100, 7)
	ext.onExtendedOpcode(c, ChaosOpcodes.dungeons, {action = "queue", data = {id = 1, difficulty = 1}})
	eq(c.pos.x, 510, "dungeons: a new run")
	local id
	for _, r in ipairs(IL.runs()) do
		if r.key == "dungeon" then id = r.id end
	end
	ok(Chaos.instances.dungeon.close(id), "dungeons: staff close")
	eq(c.pos.x, 100, "dungeons: out where the player entered")
	ok(said(c, "A gamemaster closed the dungeon."), "dungeons: told")
	players = {}
	queue = {}
end

-- ================================================================== newplayer_tutorial.lua
do
	Game = {getPlayers = function()
		local l = {}
		for _, p in pairs(players) do l[#l + 1] = p end
		return l
	end}
	dofile("data/scripts/chaos/newplayer_core.lua")
	ChaosCommands = ChaosCommands or {register = function() end}
	dofile("data/scripts/chaos/newplayer_tutorial.lua")
	local NP = ChaosNewPlayer
	NP.island = {ok = true}
	NP.kitAndWelcome = function(p) p.kit = true end
	NP.toast = function() end
	local t = NP.cfg().tutorial
	eq(t.timeLimitMinutes, 30, "tutorial: 30 minutes")
	local watch = function(fn) return fn == NP._islandWatch end
	local a = newPlayer(11, "Nova", P(4601, 4601, 7))
	ok(NP.tutorialStart(a), "tutorial: start")
	eq(NP.islandLeft(a), 1800, "tutorial: 30 minutes left")
	advance(10 * 60 * 1000, watch)
	eq(NP.islandLeft(a), 1200, "tutorial: 20 minutes left after 10")
	-- a logout keeps the time spent; offline time does not count
	events["ChaosTutorialLogout:creature"].onLogout(a)
	eq(a.storage[NP.key("islandUsed")], 600, "tutorial: 10 minutes kept")
	advance(60 * 60 * 1000, watch)
	NP.tutorialLogin(a, false)
	eq(NP.islandLeft(a), 1200, "tutorial: an hour offline costs nothing")
	-- the staff list
	local found
	for _, r in ipairs(IL.runs()) do
		if r.key == "tutorial" then found = r end
	end
	ok(found and found.id == "Nova" and found.left == 1200, "tutorial: listed")
	advance(15 * 60 * 1000 + 5000, watch)
	ok(said(a, "Tutorial: 5 minutes left"), "tutorial: the 5 minute warning")
	advance(4 * 60 * 1000, watch)
	ok(said(a, "Tutorial: 1 minute left"), "tutorial: the 1 minute warning")
	advance(65 * 1000, watch)
	eq(a.storage[NP.key("stage")], NP.cfg().stageSkipped, "tutorial: time up counts as skipped")
	eq(a.pos.x, temple.x, "tutorial: at the temple")
	ok(a.kit, "tutorial: with the kit")
	ok(said(a, "Your time on the tutorial island is up"), "tutorial: told why")
	-- a login past the limit leaves at once
	local b = newPlayer(12, "Orin", P(4601, 4601, 7))
	NP.tutorialStart(b)
	events["ChaosTutorialLogout:creature"].onLogout(b)
	b.storage[NP.key("islandUsed")] = 1800
	ok(NP.tutorialLogin(b, false), "tutorial: the login is handled")
	eq(b.pos.x, temple.x, "tutorial: past the limit: out at once")
	ok(b.kit, "tutorial: with the kit")
end

print(string.format("instance_limits_systems_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
