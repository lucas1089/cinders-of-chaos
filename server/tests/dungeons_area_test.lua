-- Run from the server/ folder: luajit tests/dungeons_area_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The area of a queue run (dungeons.lua areaOf; server/README.md "dungeons"): the boxes used for "who is inside" (the
-- run's members on every tick, the login and shutdown checks, "cannot queue from inside"), the monster count and the
-- clean-up. Fixture: the real numbers of the base DUNGEON_SYSTEM (FromPos / ToPos / DungeonPos), and positions measured
-- on the base map and its dungeon scripts: the teleports in and out, the lever, the boss and its room, and the outermost
-- spawn of every floor. Each must lie in its dungeon's area: before Chaos.dungeons.extra[id].area, dungeon 4's entry
-- point was 3 tiles south of its box (a queue run ended on its first tick), its spawns and boss room and dungeon 3's
-- floors 8-10 were outside, and dungeon 1's boss room was east of its box. Then two runs against a mocked engine.
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
os.time = function() -- luacheck: ignore
	return math.floor(clockMs / 1000)
end
local queue = {}
addEvent = function(fn, ms, ...)
	queue[#queue + 1] = {fn = fn, at = clockMs + (ms or 0), args = {...}, n = select("#", ...)}
	return #queue
end
stopEvent = function() end
local unpack = table.unpack or unpack
local function advance(ms)
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
		best.fn(unpack(best.args, 1, best.n))
	end
	clockMs = limit
end
local function P(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
Position = P
db = {query = function() return true end, storeQuery = function() return nil end, escapeString = function(s) return "'" .. s .. "'" end}
result = {free = function() end}
local creatures = {}
local temple = P(32369, 32241, 7) -- the base dungeons' own exit teleports lead here
local function newCreature(id, name, pos, isPlayer)
	local c = {id = id, guid = id, name = name, pos = pos, storage = {}, msgs = {}, hp = 1000, maxHp = 1000}
	function c:getId() return self.id end
	function c:getGuid() return self.guid end
	function c:getName() return self.name end
	function c:getPosition() return self.pos end
	function c:teleportTo(q) self.pos = P(q.x, q.y, q.z) end
	function c:isPlayer() return isPlayer end
	function c:isMonster() return not isPlayer end
	function c:getMaster() return nil end
	function c:getHealth() return self.hp end
	function c:getMaxHealth() return self.maxHp end
	function c:setHealth(v) self.hp = v end
	function c:setMaxHealth(v) self.maxHp = v end
	function c:remove() creatures[self.id] = nil end
	function c:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function c:sendCancelMessage(t) self.msgs[#self.msgs + 1] = t end
	function c:popupFYI(t) self.msgs[#self.msgs + 1] = t end
	function c:say() end
	function c:registerEvent() end
	function c:unregisterEvent() end
	function c:getLevel() return 800 end
	function c:getStorageValue(k) return self.storage[k] or -1 end
	function c:setStorageValue(k, v) self.storage[k] = v end
	function c:isPzLocked() return false end
	function c:hasCondition() return false end
	function c:getTown() return {getTemplePosition = function() return temple end} end
	function c:getLastLogout() return os.time() end
	function c:sendExtendedOpcode() end
	creatures[id] = c
	return c
end
Game = {getPlayers = function()
	local l = {}
	for _, c in pairs(creatures) do
		if c:isPlayer() then l[#l + 1] = c end
	end
	return l
end, getSpectators = function(c, _, _, rx1, rx2, ry1, ry2)
	local l = {}
	for _, cr in pairs(creatures) do
		local q = cr.pos
		if q.z == c.z and q.x >= c.x - rx1 and q.x <= c.x + rx2 and q.y >= c.y - ry1 and q.y <= c.y + ry2 then
			l[#l + 1] = cr
		end
	end
	return l
end}

-- ------------------------------------------------------------------ the base table (real positions)
DUNGEON_SYSTEM = {CooldownTime = 3600, Storages = {timerCooldown = 50203}, Dungeons = {
	[1] = {Name = "Bones Dungeon", NeedParty = true, AmountParty = 2, NeedLevel = true, Level = 150, DungeonTime = 3600,
		DungeonPos = P(31662, 32143, 8), FromPos = {x = 31630, y = 32134, z = 8}, ToPos = {x = 31851, y = 32300, z = 8}},
	[2] = {Name = "Master of the Elements", NeedParty = true, AmountParty = 2, NeedLevel = true, Level = 200,
		DungeonTime = 3600, DungeonPos = P(31700, 32340, 8), FromPos = {x = 31633, y = 32322, z = 8},
		ToPos = {x = 31855, y = 32596, z = 8}},
	[3] = {Name = "Forbidden Chevalier", NeedParty = true, AmountParty = 2, NeedLevel = true, Level = 500, DungeonTime = 3600,
		DungeonPos = P(32031, 33163, 0), FromPos = {x = 31963, y = 33109, z = 7}, ToPos = {x = 32069, y = 33215, z = 7}},
	[4] = {Name = "Rootmaw", NeedParty = false, AmountParty = 2, NeedLevel = true, Level = 600, DungeonTime = 1800,
		DungeonPos = P(31574, 31623, 8), FromPos = {x = 31564, y = 31614, z = 8}, ToPos = {x = 31586, y = 31620, z = 8}}
}}

dofile("data/scripts/chaos/chaos_constants.lua")
local sent = {}
Chaos.send = function(p, _, action, data) sent[#sent + 1] = {p = p, action = action, data = data} return true end
Chaos.decode = function(b) return b end
Chaos.select = function() return {} end
Chaos.isMultiClient = function() return false end
dofile("data/scripts/chaos/dungeons.lua")
local D = ChaosDungeons

-- ------------------------------------------------------------------ every measured place lies in its dungeon's area
local places = {
	[1] = {
		{31662, 32143, 8, "entry (DungeonPos)"}, {31662, 32142, 8, "exit teleport by the entry"},
		{31762, 32282, 8, "exit teleport by the lever"}, {31770, 32280, 8, "boss lever"}, {31770, 32284, 8, "lever spot 4"},
		{31728, 32244, 8, "skull teleport"}, {31824, 32180, 8, "skull teleport destination"},
		{31856, 32197, 8, "boss room corner"}, {31908, 32236, 8, "boss room corner"}, {31862, 32217, 8, "boss room entrance"},
		{31896, 32217, 8, "boss"}, {31902, 32217, 8, "boss exit teleport"}, {31768, 32281, 8, "boss room kick place"},
		{31760, 32252, 8, "apparition spawn"}, {31741, 32158, 8, "apparition spawn"}, {31704, 32278, 8, "apparition spawn"},
		{31648, 32173, 8, "spawn"}, {31687, 32153, 8, "spawn"}, {31721, 32286, 8, "spawn"}, {31831, 32204, 8, "spawn"}
	},
	[2] = {
		{31700, 32340, 8, "entry (DungeonPos)"}, {31700, 32341, 8, "exit teleport by the entry"},
		{31696, 32428, 8, "teleport"}, {31788, 32495, 8, "teleport destination"}, {31721, 32457, 8, "teleport"},
		{31804, 32439, 8, "teleport destination"}, {31716, 32563, 8, "boss"}, {31715, 32543, 8, "boss tile"},
		{31717, 32571, 8, "boss exit teleport"},
		{31659, 32480, 8, "spawn"}, {31710, 32567, 8, "spawn"}, {31784, 32334, 8, "spawn"}, {31839, 32448, 8, "spawn"}
	},
	[3] = {
		{32031, 33163, 0, "entry (DungeonPos)"}, {32033, 33162, 0, "exit teleport by the entry"},
		{31974, 33148, 10, "boss lever"}, {31974, 33152, 10, "lever spot 4"}, {31975, 33146, 10, "teleport"},
		{31978, 33151, 10, "teleport destination"}, {31970, 33152, 10, "exit teleport by the lever"},
		{32038, 33139, 10, "boss room corner"}, {32061, 33161, 10, "boss room corner"}, {32043, 33151, 10, "boss room entrance"},
		{32049, 33151, 10, "boss"}, {32047, 33143, 10, "boss exit teleport"},
		{32016, 33157, 0, "spawn"}, {32019, 33170, 0, "spawn"}, {32006, 33178, 2, "spawn"}, {32016, 33185, 2, "spawn"},
		{32031, 33162, 3, "spawn"}, {32004, 33155, 4, "spawn"}, {32016, 33187, 4, "spawn"}, {32039, 33156, 5, "spawn"},
		{32026, 33170, 6, "spawn"}, {32008, 33197, 7, "spawn"}, {32036, 33141, 7, "spawn"}, {31996, 33148, 8, "spawn"},
		{32021, 33187, 8, "spawn"}, {31983, 33154, 9, "spawn"}, {32013, 33199, 9, "spawn"}, {32016, 33119, 9, "spawn"},
		{32061, 33157, 9, "spawn"}, {31965, 33163, 10, "spawn"}, {32015, 33229, 10, "spawn"}, {32028, 33226, 10, "spawn"}
	},
	[4] = {
		{31574, 31623, 8, "entry (DungeonPos)"}, {31574, 31625, 8, "exit teleport by the entry"},
		{31667, 31616, 8, "teleport"}, {31525, 31514, 10, "teleport destination"}, {31525, 31513, 10, "teleport"},
		{31668, 31616, 8, "teleport destination"}, {31683, 31554, 11, "boss lever"}, {31683, 31558, 11, "lever spot 4"},
		{31665, 31542, 12, "boss room corner"}, {31725, 31590, 12, "boss room corner"}, {31690, 31553, 12, "boss room entrance"},
		{31701, 31569, 12, "boss"}, {31685, 31549, 12, "boss exit teleport"},
		{31531, 31560, 8, "spawn"}, {31674, 31624, 8, "spawn"}, {31717, 31573, 8, "spawn"}, {31538, 31599, 9, "spawn"},
		{31684, 31615, 9, "spawn"}, {31707, 31593, 9, "spawn"}, {31521, 31533, 10, "spawn"}, {31525, 31515, 10, "spawn"},
		{31685, 31621, 10, "spawn"}, {31521, 31546, 11, "spawn"}, {31551, 31609, 11, "spawn"}, {31672, 31551, 12, "spawn"},
		{31716, 31569, 12, "spawn"}
	}
}
for id, list in pairs(places) do
	for _, q in ipairs(list) do
		ok(D.inside(id, P(q[1], q[2], q[3])), string.format("dungeon %d: %s %d,%d,%d is in the area", id, q[4], q[1], q[2], q[3]))
		for other = 1, 4 do
			if other ~= id then
				ok(not D.inside(other, P(q[1], q[2], q[3])), string.format("dungeon %d: %s not in dungeon %d", id, q[4], other))
			end
		end
	end
end
-- the base box alone missed these (why the extra boxes exist)
local function inBase(id, x, y, z)
	local dg = DUNGEON_SYSTEM.Dungeons[id]
	local f, t = dg.FromPos, dg.ToPos
	return x >= f.x and x <= t.x and y >= f.y and y <= t.y and z >= math.min(f.z, dg.DungeonPos.z) and z <= t.z
end
ok(not inBase(4, 31574, 31623, 8), "dungeon 4: the base box misses its own entry point")
ok(not inBase(1, 31896, 32217, 8), "dungeon 1: the base box misses the boss")
ok(not inBase(3, 32049, 33151, 10), "dungeon 3: the base box misses the boss")
-- not wider than the dungeons: the place their exits lead to, the nearest other hunts
for _, q in ipairs({{32369, 32241, 7, "the exit place"}, {31945, 32217, 8, "the trolls east of dungeon 1"},
	{31560, 31402, 7, "the hunt north of dungeon 4"}, {31574, 31623, 7, "the floor above dungeon 4's entry"},
	{32031, 33163, 11, "the floor below dungeon 3"}}) do
	for id = 1, 4 do
		ok(not D.inside(id, P(q[1], q[2], q[3])), string.format("%s is not in dungeon %d", q[4], id))
	end
end
ok(Chaos.instances.dungeon.at(P(31701, 31569, 12)), "the instance registry: dungeon 4's boss room is a dungeon")
ok(not Chaos.instances.dungeon.at(temple), "the instance registry: the exit place is not")

-- ------------------------------------------------------------------ a queue run of dungeon 4 (solo)
local ext = events["ChaosDungeonsExtended:creature"]
local login = events["ChaosDungeonsLogin:creature"]
local a = newCreature(1, "Dara", P(32369, 32241, 7), true)
-- monsters: one in the entry hall (base box and extra box: counted once), one on floor 9, the boss in its room
newCreature(101, "cave crawler", P(31575, 31617, 8), false)
newCreature(102, "cave lurker", P(31538, 31599, 9), false)
newCreature(103, "the rootmaw", P(31701, 31569, 12), false)
local outsider = newCreature(104, "troll", P(31945, 32217, 8), false)
login.onLogin(a)
ext.onExtendedOpcode(a, ChaosOpcodes.dungeons, {action = "queue", data = {id = 4, difficulty = 1}})
eq(a.pos.x .. "," .. a.pos.y .. "," .. a.pos.z, "31574,31623,8", "dungeon 4: the run starts at DungeonPos")
ok(ChaosDungeonIsInside(a), "dungeon 4: a member")
local start
for _, s in ipairs(sent) do
	if s.action == "start" and s.p == a then start = s.data end
end
eq(start and start.left, 2, "dungeon 4: the monsters of the area, each once (the boss apart)")
advance(3000)
ok(ChaosDungeonIsInside(a), "dungeon 4: still a member after the first tick (the entry point is inside)")
a.pos = P(31690, 31553, 12)
advance(3000)
ok(ChaosDungeonIsInside(a), "dungeon 4: still a member in the boss room")
a.pos = P(31538, 31600, 9)
advance(3000)
ok(ChaosDungeonIsInside(a), "dungeon 4: still a member on floor 9")
a.pos = P(temple.x, temple.y, temple.z) -- the boss room's exit teleport
advance(3000)
ok(not ChaosDungeonIsInside(a), "dungeon 4: out of the area: the run is over")
ok(a.storage[50203] and a.storage[50203] > os.time() and a.storage[50203] - os.time() <= Chaos.dungeons.failCooldownSeconds,
	"dungeon 4: leaving is a failed attempt: the 5 minute fail cooldown")
eq(Chaos.dungeons.failCooldownSeconds, 300, "fail cooldown 5 minutes")
eq(Chaos.dungeons.cooldownSeconds, 900, "clear cooldown 15 minutes")
ok(creatures[101] == nil and creatures[102] == nil and creatures[103] == nil, "dungeon 4: the clean-up reaches every floor")
ok(creatures[104] == outsider, "dungeon 4: a monster outside the area stays")

-- ------------------------------------------------------------------ a queue run of dungeon 1 (two players)
local b = newCreature(2, "Elm", P(32369, 32241, 7), true)
local c = newCreature(3, "Fen", P(32368, 32241, 7), true)
ext.onExtendedOpcode(b, ChaosOpcodes.dungeons, {action = "queue", data = {id = 1, difficulty = 1}})
ext.onExtendedOpcode(c, ChaosOpcodes.dungeons, {action = "queue", data = {id = 1, difficulty = 1}})
ok(ChaosDungeonIsInside(b) and ChaosDungeonIsInside(c), "dungeon 1: the group is in")
b.pos = P(31862, 32217, 8) -- the lever took b into the boss room
advance(3000)
ok(ChaosDungeonIsInside(b), "dungeon 1: still a member in the boss room east of the base box")
c.pos = P(31945, 32217, 8)
advance(3000)
ok(not ChaosDungeonIsInside(c) and ChaosDungeonIsInside(b), "dungeon 1: c walked out, b goes on")
-- a login inside the boss room with no run of its own: the temple
local d = newCreature(4, "Gil", P(31896, 32217, 8), true)
d.getLastLogout = function() return 0 end
login.onLogin(d)
eq(d.pos.x, temple.x, "dungeon 1: a login in the boss room after a restart goes to the temple")

-- ------------------------------------------------------------------ the boss unlock at progressNeeded (85%)
eq(Chaos.dungeons.progressNeeded, 85, "the boss unlocks at 85% of the run's monsters")
do
	ItemType = function(id) return {getId = function() return id end, getClientId = function() return id end} end
	local x2 = Chaos.dungeons.extra[2]
	local unlocked = 0
	x2.unlock = function() unlocked = unlocked + 1 end
	local e = newCreature(5, "Hal", P(32369, 32241, 7), true)
	local f = newCreature(6, "Ivo", P(32368, 32241, 7), true)
	local mons = {}
	for i = 1, 20 do
		mons[i] = newCreature(200 + i, "tornado", P(31700 + i, 32400, 8), false)
	end
	local boss = newCreature(250, "master of the elements", P(31800, 32500, 8), false)
	sent = {}
	ext.onExtendedOpcode(e, ChaosOpcodes.dungeons, {action = "queue", data = {id = 2, difficulty = 1}})
	ext.onExtendedOpcode(f, ChaosOpcodes.dungeons, {action = "queue", data = {id = 2, difficulty = 1}})
	local st
	for _, s in ipairs(sent) do
		if s.action == "start" and s.p == e then st = s.data end
	end
	eq(st and st.need, 85, "dungeon 2: start tells the client the threshold")
	local kill = events["ChaosDungeonKill:creature"]
	for i = 1, 16 do
		mons[i]:remove()
	end
	advance(3000)
	eq(unlocked, 0, "80%: still locked")
	local function unlockedSent(p)
		for _, s in ipairs(sent) do
			if s.p == p and s.action == "killed" and s.data.unlocked then return true end
		end
		return false
	end
	ok(not unlockedSent(e), "80%: no unlock sent")
	mons[17]:remove()
	advance(3000)
	eq(unlocked, 1, "85%: the dungeon's unlock hook (gate, boss)")
	ok(unlockedSent(e) and unlockedSent(f), "85%: every member gets the unlock")
	ok(e.msgs[#e.msgs]:find("Boss unlocked!", 1, true) ~= nil, "85%: the console line")
	advance(3000)
	eq(unlocked, 1, "unlocked once")
	ok(ChaosDungeonIsInside(e), "the run goes on until the boss dies")
	boss:remove()
	kill.onKill(e, boss)
	advance(15000)
	ok(not ChaosDungeonIsInside(e) and not ChaosDungeonIsInside(f), "the boss after the unlock: the run is won")
	local cd = Chaos.dungeons.cooldownSeconds
	ok(e.storage[50203] and e.storage[50203] > os.time() + cd - 60 and e.storage[50203] <= os.time() + cd,
		"a cleared run: the short cooldown (" .. tostring(e.storage[50203] and e.storage[50203] - os.time()) .. " s)")
	ok(f.storage[50203] and f.storage[50203] > os.time(), "a cleared run: every member gets it")
	x2.unlock = nil
end

print(string.format("dungeons_area_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
