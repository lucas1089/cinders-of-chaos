-- Run from the server/ folder: luajit tests/descent_probe_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- What a person sees of the Ember Descent, for the tester bots (O595; ChaosDescent.probe, ChaosDescentCore.guide, ChaosDescent.testerClose,
-- ChaosDescent.testerSigil; helper `!tester descent`), and the rules of a tester beside the players: never mixed, the halls kept for the
-- players, no title, no weekly board, no broadcast.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then fails = fails + 1; print("FAIL " .. what) end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- ------------------------------------------------------------------ engine mocks
local events = {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function() events[name or (kind .. "#" .. tostring(e))] = e end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = eventMock("creature"), eventMock("global"), eventMock("talk"),
	eventMock("action"), eventMock("move")
EventCallback = setmetatable({}, {__index = function() return function() end end})
GAME_STATE_NORMAL, GAME_STATE_CLOSED, GAME_STATE_SHUTDOWN = 1, 2, 3
local queries = {}
db = {query = function(q) queries[#queries + 1] = q return true end, asyncQuery = function(q) queries[#queries + 1] = q return true end,
	storeQuery = function() return false end, escapeString = function(s) return "'" .. s .. "'" end}
result = {free = function() end}
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end, getDistance = function(self, o) return math.max(math.abs(self.x - o.x), math.abs(self.y - o.y)) end} end
local function pos(x, y, z) return Position(x, y, z) end
local created = {}
local function newItem(id)
	local it = {id = id, attrs = {}}
	function it:getId() return self.id end
	function it:setActionId(a) self.aid = a end
	function it:getActionId() return self.aid or 0 end
	function it:setCustomAttribute(k, v) self.attrs[k] = v end
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:isContainer() return false end
	function it:remove() self.removed = true return true end
	return it
end
Game = {
	getGameState = function() return 1 end,
	createItem = function(id) local it = newItem(id) created[#created + 1] = it return it end,
	getPlayers = function() return {} end,
	getSpectators = function() return {} end,
	getExperienceStage = function() return 1 end,
	getStorageValue = function() return -1 end,
	createTile = function() return nil end,
}
ItemType = function(id) return {getId = function() return id end, getName = function() return "item" .. id end} end
local players = {}
Player = function(id) return players[id] end
local monsters = {}
Monster = function(id) return monsters[id] end
json = {encode = function() return "{}" end, decode = function() return {} end}
Tile = function() return nil end
addEvent = function() return 0 end

dofile("data/scripts/chaos/descent.lua")
local X, DC, cfg = ChaosDescent, ChaosDescentCore, ChaosDescentConfig
ok(events.ChaosDescentExtended ~= nil, "the opcode event is registered")

-- ------------------------------------------------------------------ the pure guide
do
	local at = {x = 100, y = 100, z = 7}
	local function g(o)
		local a = {inRun = true, state = "fight", pos = at, reach = 5}
		for k, v in pairs(o) do a[k] = v end
		return DC.guide(a)
	end
	eq(g({inRun = false}).mode, "wait", "outside: wait")
	eq(g({state = "done"}).mode, "wait", "a finished run: wait")
	local r = g({offer = {id = 3, cards = 3}})
	ok(r.mode == "pick" and r.offer == 3 and r.card == 1, "a boon choice is answered first, with the first card")
	r = g({state = "choose", offer = {id = 4}})
	eq(r.mode, "pick", "a choice in the choose state: pick")
	eq(g({state = "rest"}).mode, "ready", "a shrine or merchant room: Continue")
	eq(g({state = "rest", ready = true}).mode, "wait", "already ready: wait for the party")
	eq(g({state = "travel"}).mode, "wait", "the door is opening: wait")
	eq(g({}).mode, "wait", "a fight with no monster in sight: wait")
	r = g({monster = {pos = {x = 112, y = 100, z = 7}}})
	ok(r.mode == "walk" and r.goal.x == 112 and r.area == "pack" and r.reach[2] == 5, "a monster far away: walk to it")
	eq(g({monster = {pos = {x = 104, y = 103, z = 7}}}).mode, "fight", "within 5 tiles: fight")
	eq(g({monster = {pos = {x = 101, y = 100, z = 7}, boss = true}}).area, "boss", "the boss room's monster is the boss")
	eq(g({monster = {pos = {x = 101, y = 100, z = 6}}}).mode, "walk", "another floor: walk (the path says no)")
end

-- ------------------------------------------------------------------ a fake player and run
local temple = pos(100, 100, 7)
local nextId = 0
local function newPlayer(guid, name, tester)
	nextId = nextId + 1
	local p = {id = 1000 + nextId, guid = guid, name = name, storage = {}, items = {}, msgs = {}, at = pos(1, 1, 7), tester = tester, bank = 0, hp = 100}
	p.getId = function() return p.id end
	p.getGuid = function() return p.guid end
	p.getName = function() return p.name end
	p.getStorageValue = function(_, k) return k == Chaos.storage.tester and (p.tester and 1 or -1) or (p.storage[k] or -1) end
	p.setStorageValue = function(_, k, v) p.storage[k] = v end
	p.addItemEx = function(_, item) p.items[#p.items + 1] = item return RETURNVALUE_NOERROR end
	p.getInbox = function() return nil end
	p.sendTextMessage = function(_, _, text) p.msgs[#p.msgs + 1] = text end
	p.sendCancelMessage = function(_, text) p.cancel = text end
	p.teleportTo = function(_, to) p.at = to end
	p.getPosition = function() return p.at end
	p.getTown = function() return {getTemplePosition = function() return temple end} end
	p.registerEvent = function() end
	p.unregisterEvent = function() end
	p.sendExtendedOpcode = function() end
	p.getCondition = function() return nil end
	p.getLevel = function() return 150 end
	p.getParty = function() return nil end
	p.getIp = function() return 0 end
	p.getGroup = function() return {getId = function() return 1 end} end
	p.getSlotItem = function() return nil end
	p.getBankBalance = function() return p.bank end
	p.setBankBalance = function(_, v) p.bank = v end
	p.getMaxHealth = function() return 100 end
	p.getHealth = function() return p.hp end
	p.getMaxMana = function() return 100 end
	p.getMana = function() return 100 end
	p.addMana = function() end
	p.changeSpeed = function() end
	p.getItemCount = function() return 0 end
	players[p.id] = p
	return p
end

-- a protection zone tile
local pzTiles = {}
Tile = function(p)
	return {hasFlag = function(_, f) return f == TILESTATE_PROTECTIONZONE and pzTiles[p.x .. "," .. p.y .. "," .. p.z] == true end}
end

-- the probe outside: how a run would be paid
do
	local a = newPlayer(1, "Tester Aaa", true)
	pzTiles["1,1,7"] = true
	local pr = X.probe(a)
	ok(pr.inside == false and pr.level == 150 and pr.minLevel == cfg.minLevel and pr.pz == true and pr.run == nil, "outside: level, zone, no run")
	eq(pr.pay, "free", "a character that never ran has its free run of the day")
	eq(pr.free, cfg.limits.maxRuns, "every hall is free")
	eq(pr.reserve, cfg.tester.reserve, "the reserve is told")
	a.storage[Chaos.storage.tester] = nil
	eq(X.testerSigil(a), true, "the helper gives a sigil")
	ok(#a.items == 1 and a.items[1].attrs.descent_sigil == 1, "an Ember Sigil in the backpack, marked as one")
end

-- a run: build it by hand as X.start does
local function runOf(a, rooms)
	local plan = DC.generate(cfg, 12345, 5)
	local run = {id = 7, slot = 1, L = {rect = {x1 = 1, x2 = 30, y1 = 1, y2 = 30}, center = {x = 15, y = 15, z = 7}, z = 7}, seed = 1, weekly = false,
		idx = 1, depth = 0, plan = plan, players = {}, order = {a.id}, names = {[a.id] = a.name}, startTime = os.time(), deadline = os.time() + 600,
		state = "fight", monsters = {}, alive = 0, ready = {}, used = {}, wave = 1, waves = 2}
	run.players[a.id] = {id = a.id, guid = a.guid, name = a.name, entry = {x = 1, y = 1, z = 7}, st = DC.newState(), slot = 1, paid = "free", depth = 0, speed = 0}
	X.runs[run.slot], X.runOf[a.id] = run, run
	return run
end
do
	local a = newPlayer(2, "Tester Bbb", true)
	local run = runOf(a)
	a.at = pos(10, 10, 7)
	local function mon(id, x, y, hp)
		local m = {id = id, hp = hp or 100, at = pos(x, y, 7)}
		function m:getPosition() return self.at end
		function m:getHealth() return self.hp end
		function m:getMaxHealth() return 100 end
		monsters[id] = m
		X.monsterRun[id], run.monsters[id] = run, true
		run.alive = run.alive + 1
		return m
	end
	mon(501, 22, 10)
	mon(502, 13, 11)
	local pr = X.probe(a)
	ok(pr.inside and pr.run.room == 1 and pr.run.rooms == run.plan.count and pr.run.state == "fight" and pr.run.monsters == 2, "inside: the room and the monsters")
	ok(pr.run.players == 1 and pr.run.testers == 1 and pr.run.weekly == false and pr.run.offer == nil, "a run of testers only, no choice open")
	ok(pr.guide.mode == "fight" and pr.guide.goal.x == 13, "the nearest monster is in reach: fight")
	monsters[502] = nil
	X.monsterRun[502], run.monsters[502] = nil, nil
	pr = X.probe(a)
	ok(pr.guide.mode == "walk" and pr.guide.goal.x == 22, "the next one: walk")
	-- the boss
	run.bossId = 501
	pr = X.probe(a)
	ok(pr.run.boss and pr.run.boss.hp == 100 and pr.run.boss.pos.x == 22 and pr.guide.area == "boss", "the boss: place, health, the guide goes for it")
	-- a boon choice
	run.state = "choose"
	run.players[a.id].offer = {id = 5, cards = {"a", "b", "c"}, until_ = os.time() + 30}
	pr = X.probe(a)
	ok(pr.run.offer.id == 5 and pr.run.offer.cards == 3 and pr.guide.mode == "pick" and pr.guide.offer == 5, "a choice is open: the guide picks")
	run.players[a.id].offer = nil
	run.state = "rest"
	pr = X.probe(a)
	eq(pr.guide.mode, "ready", "a rest room: Continue")
	run.ready[a.id] = true
	eq(X.probe(a).guide.mode, "wait", "ready: wait")
	-- the close: only the asker, with the rewards of the depth reached
	local b = newPlayer(3, "Tester Ccc", true)
	eq(X.testerClose(b), false, "a bot with no run: nothing to close")
	eq(X.testerClose(a), true, "the asker's own run is closed")
	ok(X.runOf[a.id] == nil and a.msgs[#a.msgs]:find("Depth", 1, true), "the bot is out and told its depth")
	eq(X.probe(a).inside, false, "outside again")
	ok(run.ended, "the last player out ends the run")
end

-- ------------------------------------------------------------------ the rules of a tester beside the players
do
	ChaosTesters = {soloRefusal = function(group, free, reserve)
		local flags, any = {}, false
		for i, m in ipairs(group) do flags[i] = m.tester == true; any = any or flags[i] end
		if not any then return nil end
		dofile("data/scripts/chaos/testers_core.lua")
		local why = ChaosTestersCore.soloRefusal(flags, free, reserve)
		return why and ChaosTestersCore.CLOSED_TEXT[why] or nil
	end}
	local t = newPlayer(10, "Tester Ddd", true)
	local p = newPlayer(11, "Ana", false)
	pzTiles["1,1,7"] = true
	-- the halls are full of players: the tester waits, a player is told the halls are taken
	for i = 1, cfg.limits.maxRuns - cfg.tester.reserve + 1 do X.runs[100 + i] = {players = {}} end
	local okT, whyT = X.start(t, false)
	eq(okT, false, "a tester is refused when fewer than the reserve would stay free")
	eq(whyT, ChaosTestersCore.CLOSED_TEXT.reserve, "the refusal says the halls are the players'")
	for i = 1, cfg.limits.maxRuns - cfg.tester.reserve + 1 do X.runs[100 + i] = nil end
	-- a party of a tester and a player
	t.getParty = function() return {getLeader = function() return t end, getMembers = function() return {p} end} end
	p.at = t.at
	-- the leader pays with the free run, the player is "left behind" by the rule before it: the group is refused as a whole
	local okM, whyM = X.start(t, false)
	eq(okM, false, "a tester's party with a player is not made")
	eq(whyM, ChaosTestersCore.CLOSED_TEXT.mixed, "the refusal says testers and players are never mixed")
end

-- the files: no weekly board entry, no title, no broadcast for a tester
do
	local f = io.open("data/scripts/chaos/descent.lua", "r")
	local src = f:read("*a")
	f:close()
	ok(src:find("not (player and Chaos.isTester(player))", 1, true), "the weekly board skips a tester")
	ok(src:find("no title of a tester bot", 1, true), "the title source skips a tester")
	ok(src:find("not Chaos.isTester(player) then -- a tester's find is never announced", 1, true), "the unique find is not announced for a tester")
end

print(string.format("descent_probe_test: %d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)
