-- Run from the server/ folder: luajit tests/dungeons_closed_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Dungeons in closed test mode (O589; dungeons.lua, dungeons_core.lua, server/README.md "Dungeons in closed mode (O589)"):
-- the pure rules (side of a queue entry, which entries start a run, the guide) and the engine file against a mocked engine: a tester
-- is refused with the switch off, queues and runs among testers with it on, never ahead of a queued player, never ranked or
-- recorded, ends when the switch goes off; the probe a bot reads (what a person sees) and the close.
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
dofile("data/scripts/chaos/testers_core.lua")
local K = ChaosTestersCore
local DC = ChaosDungeonsCore
local mode = "off"
K.reader = function() return mode end
local function setMode(m)
	mode = m
	K.resetClosedCache()
end
local D = ChaosDungeons
ItemType = function(id) return {getId = function() return id end, getClientId = function() return id end} end

-- ------------------------------------------------------------------ the pure rules
do
	local side, why = DC.sideRefusal(K, true, false)
	eq(side, "player", "a player's side"); eq(why, nil, "a player is never refused here")
	side, why = DC.sideRefusal(K, true, true)
	eq(side, "tester", "a tester's side"); eq(why, nil, "a tester with the switch on: allowed")
	side, why = DC.sideRefusal(K, false, true)
	eq(why, "closed-off", "a tester with the switch off: refused")
	side, why = DC.sideRefusal(nil, true, true)
	eq(why, "closed-off", "no rules loaded: a tester is refused")
	eq(select(2, DC.sideRefusal(nil, true, false)), nil, "no rules loaded: a player is not")
	ok(K.CLOSED_SYSTEMS.dungeon, "dungeon is a closed system of testers_core.lua")
	local g = K.sameSide("dungeon", true, "tester", "player")
	ok(not g, "the rules refuse a tester against a player in the dungeons")

	local function e(guid, diff, joined, side) return {guid = guid, difficulty = diff, joined = joined, side = side} end
	local o = {size = 2, soloWait = 5, now = 100, closedOn = true}
	local diff, list, s = DC.pick({e(1, 1, 99, "player"), e(2, 1, 99, "player")}, o)
	ok(diff == 1 and #list == 2 and s == "player", "a full group of players starts")
	eq(DC.pick({e(1, 1, 99, "player")}, o), nil, "one player waits for a partner: soloWait not over")
	diff, list = DC.pick({e(1, 1, 90, "player")}, o)
	ok(diff == 1 and #list == 1, "one player alone after the solo wait")
	diff = DC.pick({e(1, 1, 99, "player"), e(2, 2, 99, "player")}, {size = 2, soloWait = 5, now = 100, closedOn = true})
	eq(diff, nil, "two players of two difficulties are no group")
	-- the sides never mix, a tester only with the switch on, a player first
	diff, list, s = DC.pick({e(1, 1, 90, "tester"), e(2, 1, 90, "tester")}, o)
	ok(s == "tester" and #list == 2, "two testers start a run with the switch on")
	eq(DC.pick({e(1, 1, 90, "tester"), e(2, 1, 90, "tester")}, {size = 2, soloWait = 5, now = 100, closedOn = false}), nil,
		"testers never start with the switch off")
	diff, list, s = DC.pick({e(1, 1, 80, "tester"), e(2, 1, 95, "player")}, {size = 1, soloWait = 5, now = 100, closedOn = true})
	ok(s == "player" and list[1].guid == 2, "a queued player goes first, though the tester waited longer")
	for _, l in ipairs({{e(1, 1, 80, "tester"), e(2, 1, 80, "player")}, {e(3, 1, 80, "player"), e(4, 1, 80, "tester")}}) do
		local _, got = DC.pick(l, {size = 2, soloWait = 99, now = 100, closedOn = true})
		eq(got, nil, "a tester and a player are never one group")
	end
	diff, list, s = DC.pick({e(1, 1, 80, "tester"), e(2, 1, 80, "player")}, {size = 2, soloWait = 0, now = 100, closedOn = true})
	ok(s == "player" and #list == 1, "with a solo wait of 0 the player goes alone, the tester does not join it")
	diff, list, s = DC.pick({{guid = 5, difficulty = 3, joined = 1}}, {size = 1, soloWait = 0, now = 9, closedOn = false})
	ok(s == "player" and #list == 1, "an entry with no side is a player's (the queue before O589)")

	-- the guide: monsters first, then the boss
	local at = {x = 100, y = 100, z = 8}
	local gd = DC.guide({pos = at, unlocked = false, monster = {pos = {x = 110, y = 100, z = 8}}})
	ok(gd.mode == "walk" and gd.goal.x == 110 and gd.area == "monsters", "far from a monster: walk to it")
	gd = DC.guide({pos = at, unlocked = false, monster = {pos = {x = 102, y = 101, z = 8}}})
	eq(gd.mode, "fight", "within 3 tiles of a monster: fight")
	gd = DC.guide({pos = at, unlocked = false, monster = {pos = {x = 102, y = 101, z = 9}}})
	eq(gd.mode, "walk", "a monster on another floor is not in reach")
	gd = DC.guide({pos = at, unlocked = false})
	ok(gd.mode == "wait" and gd.goal == nil, "no monster in sight: wait")
	gd = DC.guide({pos = at, unlocked = true, bossPos = {x = 130, y = 100, z = 8}})
	ok(gd.mode == "walk" and gd.area == "boss" and gd.goal.x == 130, "unlocked: walk to the boss")
	gd = DC.guide({pos = at, unlocked = true, bossPos = {x = 104, y = 100, z = 8}})
	eq(gd.mode, "fight", "within 4 tiles of the boss: fight")
	gd = DC.guide({pos = at, unlocked = true})
	eq(gd.mode, "wait", "unlocked and no boss yet: wait")
	gd = DC.guide({pos = at, ended = true, unlocked = true, bossPos = at})
	eq(gd.mode, "wait", "an ended run: wait for the exit")
end

-- ------------------------------------------------------------------ the engine file
local ext = events["ChaosDungeonsExtended:creature"]
local kill = events["ChaosDungeonKill:creature"]
local queries, recorded = {}, 0
db.query = function(q) queries[#queries + 1] = q return true end
ChaosRecords = {dungeonClear = function() recorded = recorded + 1 end}
local function runsStored()
	local n = 0
	for _, q in ipairs(queries) do
		if q:find("INSERT INTO", 1, true) and q:find(Chaos.tables.dungeonRuns, 1, true) then n = n + 1 end
	end
	return n
end
local function inside(p) return ChaosDungeonIsInside(p) end
local function queue(p, id) ext.onExtendedOpcode(p, ChaosOpcodes.dungeons, {action = "queue", data = {id = id or 4, difficulty = 1}}) end
local function tester(id, name)
	local t = newCreature(id, name, P(32369, 32241, 7), true)
	t.storage[Chaos.storage.tester] = 1
	return t
end
local function clearMonsters()
	for id, cr in pairs(creatures) do
		if not cr:isPlayer() and id < 100000 then cr:remove() end
	end
end
local function lastMsg(p) return p.msgs[#p.msgs] or "" end

-- 1. the switch off: a tester is refused, as before
do
	setMode("off")
	local t = tester(11, "Tester Aaa")
	queue(t)
	ok(not inside(t) and D.queuedFor(t) == nil, "switch off: a tester does not queue")
	ok(lastMsg(t):find("Closed test mode is off", 1, true) ~= nil, "switch off: the refusal says why (" .. lastMsg(t) .. ")")
	local ok2, why = D.queueJoin(t, 4, 1)
	ok(ok2 == false and why:find("Closed test mode is off", 1, true) ~= nil, "the group queue's door refuses it the same")
end

-- 2. the switch on: a tester queues, plays its own run, it is never ranked or recorded
do
	setMode("on")
	clearMonsters()
	local m1 = newCreature(101, "cave crawler", P(31575, 31617, 8), false)
	local m2 = newCreature(102, "cave lurker", P(31538, 31599, 9), false)
	local boss = newCreature(103, "the rootmaw", P(31701, 31569, 12), false)
	local t = tester(12, "Tester Bbb")
	local pr = D.probe(t)
	ok(not pr.inside and pr.on and pr.list and #pr.list >= 4, "outside: the probe lists the dungeons")
	local entry
	for _, d in ipairs(pr.list) do if d.id == 4 then entry = d end end
	ok(entry and entry.level == 600 and entry.size == 1 and entry.max == 1, "the list names level, size and the difficulty unlocked")
	queue(t)
	ok(inside(t) and D.queuedFor(t) == nil, "switch on: a tester queues; dungeon 4 takes one player: the run starts at once")
	pr = D.probe(t)
	ok(pr.inside and pr.run.side == "tester" and pr.run.dungeon == 4, "inside: the probe names the run and its side")
	ok(pr.run.left == 2 and pr.run.total == 2 and pr.run.percent == 0 and not pr.run.unlocked, "the kill counter: 2 monsters, none dead")
	eq(pr.guide.mode, "walk", "the guide sends the bot to the nearest monster")
	eq(pr.guide.goal.x .. "," .. pr.guide.goal.y .. "," .. pr.guide.goal.z, "31575,31617,8", "...the one on its own floor")
	t.pos = P(31575, 31619, 8)
	eq(D.probe(t).guide.mode, "fight", "near it: fight")
	m1:remove()
	advance(3000)
	pr = D.probe(t)
	ok(pr.run.left == 1 and pr.run.percent == 50, "one dead: 50%")
	eq(pr.guide.goal.z, 9, "only a monster on another floor is left: that is the goal")
	m2:remove()
	advance(3000)
	pr = D.probe(t)
	ok(pr.run.unlocked and pr.run.percent == 100, "all dead: the boss is unlocked")
	eq(pr.guide.area, "boss", "the guide goes for the boss")
	eq(pr.guide.goal.x, 31701, "...where it stands")
	ok(pr.run.bossHp == 100, "the boss's health is read")
	local before = runsStored()
	boss:remove()
	kill.onKill(t, boss)
	advance(15000)
	ok(not inside(t), "the boss fell: the run is won and the tester is out")
	eq(runsStored(), before, "a tester run is never stored on the boards")
	eq(recorded, 0, "a tester run is never recorded (no record, no event)")
	ok(t.pos.x ~= 31575, "the tester is back out of the dungeon")
end

-- 3. a player's clear is stored and recorded (the same code path)
do
	clearMonsters()
	local boss = newCreature(131, "the rootmaw", P(31701, 31569, 12), false)
	local p = newCreature(21, "Real Pia", P(32369, 32241, 7), true)
	local before = runsStored()
	queue(p)
	ok(inside(p), "a player's run starts")
	eq(D.probe(p).run.side, "player", "a player's run has the player side")
	boss:remove()
	kill.onKill(p, boss)
	advance(15000)
	eq(runsStored(), before + 1, "a player's clear is stored")
	eq(recorded, 1, "a player's clear is recorded")
end

-- 4. a player is never kept waiting behind a tester entry, and the two never share a run (dungeon 1 takes two players)
do
	clearMonsters()
	newCreature(141, "prince skeletal", P(31896, 32217, 8), false)
	newCreature(142, "skeleton", P(31700, 32150, 8), false)
	local t = tester(13, "Tester Ccc")
	local p = newCreature(22, "Real Raf", P(32369, 32241, 7), true)
	queue(t, 1)
	eq(D.probe(t).queued, 1, "queued: the probe says which dungeon")
	ok(D.probe(t).list == nil, "queued: no list")
	queue(p, 1)
	advance(9000)
	ok(inside(p) and not inside(t), "the player's run first, though the tester queued first")
	eq(D.queuedFor(t), 1, "the tester keeps its place in the queue")
	eq(D.probe(p).run.members, 1, "the player is alone in its run: the tester does not join it")
	eq(D.probe(p).run.side, "player", "a run of players")
	p.pos = P(temple.x, temple.y, temple.z)
	advance(12000)
	ok(not inside(p), "the player's run is over")
	ok(inside(t), "then the tester's run starts")
	eq(D.probe(t).run.side, "tester", "...a run of testers")
	t.pos = P(temple.x, temple.y, temple.z)
	advance(4000)
	clearMonsters()
end

-- 5. the switch goes off in a run: it ends, the tester is out
do
	setMode("on")
	clearMonsters()
	newCreature(151, "cave crawler", P(31575, 31617, 8), false)
	newCreature(152, "the rootmaw", P(31701, 31569, 12), false)
	local t = tester(14, "Tester Ddd")
	queue(t)
	ok(inside(t), "a tester run is on")
	setMode("off")
	advance(4000)
	ok(not inside(t), "the switch went off: the run ended")
	ok(not D.queuedFor(t), "and not queued")
	-- a queued tester is dropped when the switch goes off
	setMode("on")
	clearMonsters()
	local t2 = tester(15, "Tester Eee")
	queue(t2, 1)
	eq(D.queuedFor(t2), 1, "a tester waits for a partner in dungeon 1")
	setMode("off")
	advance(4000)
	eq(D.queuedFor(t2), nil, "the queued tester is dropped when the switch goes off")
	ok(not inside(t2), "and no run starts")
end

-- 6. the close: only a tester's own run, never a player's
do
	setMode("on")
	clearMonsters()
	newCreature(161, "cave crawler", P(31575, 31617, 8), false)
	newCreature(162, "the rootmaw", P(31701, 31569, 12), false)
	local t = tester(16, "Tester Fff")
	queue(t)
	ok(inside(t), "a tester run is on")
	ok(D.testerClose(t) == true, "the close ends the tester's own run")
	ok(not inside(t), "the tester is out")
	clearMonsters()
	newCreature(163, "the rootmaw", P(31701, 31569, 12), false)
	local p = newCreature(24, "Real Ras", P(32369, 32241, 7), true)
	queue(p)
	ok(inside(p), "a player's run is on")
	local t2 = tester(17, "Tester Ggg")
	ok(D.testerClose(t2) == false, "the close does not touch a player's run")
	ok(D.testerClose(p) == false, "...not even when a player asks")
	ok(inside(p), "the player is still inside")
	p.pos = P(temple.x, temple.y, temple.z)
	advance(4000)
end

-- 7. the bots share one address: two testers are no multi-client (the dungeon refuses one), a tester and a player are
do
	local function pl(isTester, ip)
		return {getIp = function() return ip end, getGroup = function() return {getId = function() return 1 end} end,
			getStorageValue = function() return isTester and 1 or -1 end}
	end
	local a, b, c = pl(true, 7), pl(true, 7), pl(false, 7)
	local realPlayers, realStore = Game.getPlayers, Game.getStorageValue
	Game.getPlayers = function() return {a, b, c} end
	Game.getStorageValue = function() return -1 end
	eq(#Chaos.mcSiblings(a), 1, "a tester's only sibling is the player on its address, not the other tester")
	eq(#Chaos.mcSiblings(c), 2, "a player on the address of two testers is still a multi-client of both")
	Game.getPlayers = function() return {a, b} end
	ok(not Chaos.isMultiClient(a) and not Chaos.isMultiClient(b), "two testers alone: no multi-client")
	Game.getPlayers, Game.getStorageValue = realPlayers, realStore
end

-- 8. difficulties 2 to 6 and the Weekly Challenge for the bots (O651): the TEST ONLY unlock of the bot's own progress, the run at that difficulty with
-- the monsters scaled, the weekly flag of the list and the run
do
	setMode("on")
	clearMonsters()
	-- the progress table as the database keeps it: the last INSERT of a character and dungeon
	local progress = {}
	Chaos.select = function(q)
		local guid, id = q:match("`player_id` = (%d+) AND `dungeon_id` = (%d+)")
		if guid and progress[guid .. ":" .. id] then
			return {{difficulty = progress[guid .. ":" .. id], challenges = ""}}
		end
		return {}
	end
	local realQuery = db.query
	db.query = function(q)
		local g, i, d = q:match("VALUES %((%d+), (%d+), (%d+),")
		if g and q:find(Chaos.tables.dungeonProgress, 1, true) then
			progress[g .. ":" .. i] = tonumber(d)
		end
		return realQuery(q)
	end
	local t = tester(51, "Tester Ddd")
	local plain = newCreature(52, "Real Rita", P(32369, 32241, 7), true)
	local got, why = D.testerUnlock(plain, 4, 3)
	ok(got == nil and why == "not a tester", "a player's progress is never written (" .. tostring(why) .. ")")
	eq(progress["52:4"], nil, "no row of a player")
	got, why = D.testerUnlock(t, 99, 3)
	ok(got == nil and why == "no such dungeon", "no such dungeon")
	got, why = D.testerUnlock(t, 4, 0)
	ok(got == nil and why:find("difficulty 1 to 6", 1, true), "difficulty 0 refused")
	got, why = D.testerUnlock(t, 4, 7)
	ok(got == nil and why:find("difficulty 1 to 6", 1, true), "difficulty 7 refused")
	got = D.testerUnlock(t, 4, 3)
	eq(got, 3, "a tester's difficulty 3 is unlocked")
	eq(progress["51:4"], 3, "...in the tester's own row")
	eq(D.testerUnlock(t, 4, 2), 3, "an unlock never goes down")
	local entry
	for _, d in ipairs(D.probe(t).list) do if d.id == 4 then entry = d end end
	eq(entry.max, 3, "the list shows the difficulty unlocked")
	ok(entry.weekly == nil, "a plain dungeon is no Weekly Challenge")
	-- a dungeon with one difficulty for every run cannot be unlocked
	local keepExtra = Chaos.dungeons.extra[4]
	Chaos.dungeons.extra[4] = {fixedDifficulty = 1}
	got, why = D.testerUnlock(t, 4, 5)
	ok(got == nil and why:find("one difficulty", 1, true), "the Weekly Challenge's dungeon has one difficulty")
	Chaos.dungeons.extra[4] = keepExtra
	-- the run at difficulty 3: the monsters carry it
	local m1 = newCreature(151, "cave crawler", P(31575, 31617, 8), false)
	local m2 = newCreature(152, "cave lurker", P(31538, 31599, 9), false)
	newCreature(153, "the rootmaw", P(31701, 31569, 12), false)
	ext.onExtendedOpcode(t, ChaosOpcodes.dungeons, {action = "queue", data = {id = 4, difficulty = 3}})
	ok(inside(t), "the tester queues for difficulty 3 and its run starts")
	local pr = D.probe(t)
	eq(pr.run.difficulty, 3, "the run is at difficulty 3")
	ok(pr.run.scaled == 2 and pr.run.left == 2, "both monsters of the run carry the difficulty (" .. tostring(pr.run.scaled) .. " of " .. tostring(pr.run.left) .. ")")
	ok(m1.maxHp ~= 1000, "the monster's health is the difficulty's, not the base (" .. tostring(m1.maxHp) .. ")")
	eq(pr.run.weekly, nil, "a plain run is no Weekly Challenge")
	-- a difficulty the character did not unlock is refused by the queue as before
	D.testerClose(t)
	local locked = tester(53, "Tester Eee")
	ext.onExtendedOpcode(locked, ChaosOpcodes.dungeons, {action = "queue", data = {id = 4, difficulty = 4}})
	ok(not inside(locked) and lastMsg(locked):find("still locked", 1, true), "difficulty 4 locked for a bot that did not unlock it (" .. lastMsg(locked) .. ")")
	-- the Weekly Challenge: the list entry and the run say so
	ChaosWeeklyChallengeConfig = {dungeon = {id = 4}}
	entry = nil
	for _, d in ipairs(D.probe(t).list) do if d.id == 4 then entry = d end end
	eq(entry.weekly, true, "the list marks the Weekly Challenge")
	m1:remove()
	m2:remove()
	clearMonsters()
	newCreature(161, "cave crawler", P(31575, 31617, 8), false)
	newCreature(162, "the rootmaw", P(31701, 31569, 12), false)
	t.storage[DUNGEON_SYSTEM.Storages.timerCooldown] = nil
	queue(t, 4)
	ok(inside(t), "the tester's second run starts")
	eq(D.probe(t).run.weekly, true, "the run of the Weekly Challenge says so")
	D.testerClose(t)
	ChaosWeeklyChallengeConfig = nil
	db.query = realQuery
	clearMonsters()
end

print(string.format("dungeons_closed_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
