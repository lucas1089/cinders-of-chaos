-- Run from the server/ folder: luajit tests/rift_probe_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- What a person sees of a rift, for the tester bots (O592; ChaosRift.probe, ChaosRiftCore.guide, ChaosRift.testerClose; helper `!tester rift`):
-- the guide (the guardian first, else the nearest pack monster of the floor, else wait), the probe outside and inside a run, the close.
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
local gameState = 1
GAME_STATE_NORMAL, GAME_STATE_CLOSED, GAME_STATE_SHUTDOWN = 1, 2, 3
local queries = {}
db = {query = function(q) queries[#queries + 1] = q return true end, storeQuery = function() return false end,
	escapeString = function(s) return "'" .. s .. "'" end}
result = {free = function() end}
local function pos(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end
Position = pos
local created = {}
local function newItem(id)
	local it = {id = id, attrs = {}}
	function it:getId() return self.id end
	function it:setActionId(a) self.aid = a end
	function it:getActionId() return self.aid or 0 end
	function it:setCustomAttribute(k, v) self.attrs[k] = v end
	function it:getCustomAttribute(k) return self.attrs[k] end
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:getAttribute(k) return self.attrs[k] end
	function it:remove() self.removed = true return true end
	return it
end
Game = {
	getGameState = function() return gameState end,
	createItem = function(id) local it = newItem(id) created[#created + 1] = it return it end,
	getPlayers = function() return {} end,
	getSpectators = function() return {} end,
	getExperienceStage = function() return 1 end,
}
ItemType = function(id) return {getId = function() return id end, getName = function() return "item" .. id end} end
local players = {}
Player = function(id)
	if type(id) == "string" then
		for _, p in pairs(players) do if p.name == id then return p end end
		return nil
	end
	return players[id]
end
Monster = function() return nil end
json = {encode = function() return "{}" end, decode = function() return {} end}
Tile = function() return nil end
addEvent = function() return 0 end

dofile("data/scripts/chaos/rift.lua")
local RF, R = ChaosRift, ChaosRiftCore
local cfg = ChaosRiftConfig
local ST = Chaos.storage.riftRun
ok(events.ChaosRiftShutdown ~= nil, "the onShutdown event is registered")
ok(events.ChaosRiftLogout ~= nil and events.ChaosRiftLogin ~= nil, "login / logout events")

-- a fake player; the database copy (db) is what a crash keeps: written by save()
local temple = pos(100, 100, 7)
local nextId = 0
local function newPlayer(guid, name)
	nextId = nextId + 1
	local p = {id = 1000 + nextId, guid = guid, name = name, storage = {}, db = {}, items = {}, msgs = {}, at = pos(1, 1, 7)}
	p.getId = function() return p.id end
	p.getGuid = function() return p.guid end
	p.getName = function() return p.name end
	p.getStorageValue = function(_, k) return p.storage[k] or -1 end
	p.setStorageValue = function(_, k, v) p.storage[k] = v end
	p.save = function() for k, v in pairs(p.storage) do p.db[k] = v end p.dbItems = #p.items end
	p.addItemEx = function(_, item) p.items[#p.items + 1] = item return RETURNVALUE_NOERROR end
	p.getInbox = function() return nil end
	p.sendTextMessage = function(_, _, text) p.msgs[#p.msgs + 1] = text end
	p.sendCancelMessage = p.sendTextMessage
	p.teleportTo = function(_, to) p.at = to end
	p.getPosition = function() return p.at end
	p.getTown = function() return {getTemplePosition = function() return temple end} end
	p.registerEvent = function() end
	p.unregisterEvent = function() end
	p.sendExtendedOpcode = function() end
	p.removeCondition = function() end
	p.getCondition = function() return nil end
	p.addCondition = function() end
	p.getLevel = function() return 100 end
	players[p.id] = p
	return p
end
-- a relog / restart: the same character with a new creature id and only what was saved
local function relog(p)
	players[p.id] = nil
	local q = newPlayer(p.guid, p.name)
	for k, v in pairs(p.db) do q.storage[k] = v end
	q.db = {}
	for k, v in pairs(p.db) do q.db[k] = v end
	q.at = p.at
	return q
end

-- the monsters of the mock
local monsters = {}
Monster = function(id) return monsters[id] end
local function monster(id, x, y, z, hp, max)
	local m = {id = id, hp = hp or 100, max = max or 100, at = pos(x, y, z)}
	function m:getPosition() return self.at end
	function m:getHealth() return self.hp end
	function m:getMaxHealth() return self.max end
	monsters[id] = m
	return m
end
local pzTiles = {}
Tile = function(p)
	return {hasFlag = function(_, f) return f == TILESTATE_PROTECTIONZONE and pzTiles[p.x .. "," .. p.y .. "," .. p.z] == true end}
end

-- the pure guide
do
	local at = {x = 100, y = 100, z = 7}
	local function g(o)
		local a = {state = "running", boss = "waiting", pos = at, reach = 4}
		for k, v in pairs(o) do a[k] = v end
		return R.guide(a)
	end
	eq(g({state = "failed"}).mode, "wait", "a run that is over: wait")
	eq(g({}).mode, "wait", "no monster in sight: wait")
	local r = g({monster = {pos = {x = 110, y = 100, z = 7}}})
	ok(r.mode == "walk" and r.goal.x == 110 and r.area == "pack" and r.reach[2] == 4, "a pack monster far away: walk to it")
	eq(g({monster = {pos = {x = 103, y = 101, z = 7}}}).mode, "fight", "within 4 tiles: fight")
	r = g({other = true})
	ok(r.mode == "wait" and r.area == "pack", "monsters left on another floor only: wait (no stairs are known)")
	r = g({boss = "alive", bossPos = {x = 130, y = 100, z = 7}, monster = {pos = {x = 101, y = 100, z = 7}}})
	ok(r.mode == "walk" and r.area == "boss" and r.goal.x == 130, "the guardian is alive: it comes first, before the pack")
	eq(g({boss = "alive", bossPos = {x = 104, y = 100, z = 7}}).mode, "fight", "next to the guardian: fight")
	r = g({boss = "alive", bossPos = {x = 104, y = 100, z = 6}})
	ok(r.mode == "walk" and r.why:find("another floor", 1, true), "the guardian on another floor: walk, the path says no")
end

-- the probe outside and inside
do
	restart = function() RF.runs, RF.runOf = {}, {} end
	restart()
	local a = newPlayer(1, "Tester Aaa")
	a.getItemById = function(_, id) return a.hasKey and {getId = function() return id end} or nil end
	local pr = RF.probe(a)
	ok(pr.inside == false and pr.pz == false and pr.held == false and pr.run == nil and pr.level == 100, "outside: no run, no zone, no key")
	pzTiles["1,1,7"] = true
	a.hasKey = true
	pr = RF.probe(a)
	ok(pr.pz == true and pr.held == true, "in a protection zone with a key")
	-- a run
	local c = R.slotCenter(cfg, 1)
	local L = {start = {x = c.x, y = c.y, z = c.z}, kind = "rooms", floors = {1}}
	local run = R.newRun(cfg, os.time(), 10, 8, R.effects(cfg, {}, 3))
	run.id, run.slot, run.L, run.key = 1, 1, L, {tier = 3, mods = {}}
	run.themeName, run.players, run.size, run.lives = "ash", {[a.id] = {id = a.id, guid = a.guid, name = a.name, entry = pos(1, 1, 7)}}, 1, 3
	run.openerGuid, run.state, run.boss, run.killed, run.total, run.bossAt = a.guid, "running", "waiting", 2, 10, 8
	run.aliveIds, run.bossIds = {[501] = true, [502] = true, [503] = true}, {}
	RF.runs[1], RF.runOf[a.id] = run, run
	a.at = pos(c.x, c.y, c.z)
	monster(501, c.x + 9, c.y, c.z)
	monster(502, c.x + 3, c.y, c.z)
	monster(503, c.x + 2, c.y, c.z + 1) -- another floor
	pr = RF.probe(a)
	ok(pr.inside and pr.run.tier == 3 and pr.run.theme == "ash" and pr.run.killed == 2 and pr.run.total == 10 and pr.run.bossAt == 8, "inside: the counts")
	ok(pr.run.monsters == 3 and pr.run.boss == "waiting" and pr.run.floors == 1 and pr.run.entry.x == c.x, "the monsters, the guardian state, the entry")
	ok(pr.guide.mode == "fight" and pr.guide.goal.x == c.x + 3, "the nearest monster of the floor: in reach, fight")
	monsters[502] = nil
	pr = RF.probe(a)
	ok(pr.guide.mode == "walk" and pr.guide.goal.x == c.x + 9, "the next one: walk to it")
	monsters[501] = nil
	pr = RF.probe(a)
	ok(pr.guide.mode == "wait" and pr.guide.area == "pack", "only another floor is left: wait")
	-- the guardian
	run.boss, run.bossIds = "alive", {[900] = true}
	monster(900, c.x + 20, c.y, c.z, 40, 100)
	pr = RF.probe(a)
	ok(pr.run.bossHp == 40 and pr.run.bossPos.x == c.x + 20 and pr.guide.area == "boss" and pr.guide.mode == "walk", "the guardian: health, place, the guide goes for it")
	-- the close: only the asker's own run
	local b = newPlayer(2, "Tester Bbb")
	eq(RF.testerClose(b), false, "a bot with no run: nothing to close")
	eq(RF.testerClose(a), true, "the asker's own run is closed")
	ok(run.ended and RF.runOf[a.id] == nil, "the run ended and the bot is out")
	eq(RF.probe(a).inside, false, "outside again")
end


-- the omen key of a tester and the omen field of the probe (O599, helper `!tester omen`)
do
	restart()
	local t = newPlayer(7, "Tester Omn")
	t.storage[Chaos.storage.tester] = 1
	t.getLevel = function() return 900 end
	t.getItemById = function() return nil end
	local kind, why = RF.testerOmenKey(t)
	ok(kind ~= nil and why == nil, "a tester gets an omen key: " .. tostring(why))
	local key = t.items[#t.items]
	ok(key and key.id == cfg.omen.key.id and key.attrs.omen_kind == kind, "the key is an omen key of that kind")
	local named, whyN = RF.testerOmenKey(t, "storm")
	eq(named, "storm", "a named kind")
	local bad, whyB = RF.testerOmenKey(t, "nonsense")
	ok(bad == nil and whyB == "no such omen", "an unknown kind is refused")
	t.getLevel = function() return 700 end
	local low, whyL = RF.testerOmenKey(t)
	ok(low == nil and whyL:find("needs level 800", 1, true) ~= nil, "below the omen level: refused")
	t.getLevel = function() return 900 end
	local p = newPlayer(8, "Plain Player")
	p.getLevel = function() return 900 end
	local none, whyP = RF.testerOmenKey(p)
	ok(none == nil and whyP == "not a tester", "a player never gets one")
	eq(#p.items, 0, "nothing reached the player")
	-- inside: the probe names the omen
	local c = R.slotCenter(cfg, 2)
	local L = {start = {x = c.x, y = c.y, z = c.z}, kind = "arena", floors = {1}}
	local run = R.newRun(cfg, os.time(), 0, 0, R.effects(cfg, {}, 1))
	run.id, run.slot, run.L, run.key, run.omen = 2, 2, L, {tier = cfg.maxTier, mods = {}, omen = "storm"}, "storm"
	run.themeName, run.players, run.size, run.lives = "ash", {[t.id] = {id = t.id, guid = t.guid, name = t.name, entry = pos(1, 1, 7)}}, 1, 3
	run.openerGuid, run.state, run.boss, run.killed, run.total, run.bossAt = t.guid, "running", "waiting", 0, 0, 0
	run.aliveIds, run.bossIds = {}, {}
	RF.runs[2], RF.runOf[t.id] = run, run
	t.at = pos(c.x, c.y, c.z)
	local pr = RF.probe(t)
	ok(pr.inside and pr.run.omen == "storm", "inside an omen arena: the probe says which")
	-- a rift of a tier has no omen field
	run.omen = nil
	eq(RF.probe(t).run.omen, nil, "a plain rift: no omen")
	RF.runs[2], RF.runOf[t.id] = nil, nil
	-- the arenas kept for the players: a tester refused while fewer than `reserve` of the slots would stay free; a mixed party never
	ok(cfg.omen.tester and cfg.omen.tester.reserve >= 1 and cfg.omen.tester.reserve < cfg.limits.maxRuns, "config: the omen reserve is under the slots")
end

-- the stairs of a rift of two floors (O651): a hole drops to the ladder below, the ladder climbs to the cell south of the hole
do
	local links = {{hole = {x = 140, y = 100, z = 7}, ladder = {x = 140, y = 100, z = 8}, up = {x = 140, y = 101, z = 7}}}
	local function g(o)
		local a = {state = "running", boss = "waiting", pos = {x = 100, y = 100, z = 7}, reach = 4, links = links}
		for k, v in pairs(o) do a[k] = v end
		return R.guide(a)
	end
	local r = g({other = true, otherPos = {x = 160, y = 100, z = 8}})
	ok(r.mode == "walk" and r.area == "stairs" and r.via == "hole" and r.goal.x == 140 and r.goal.z == 7 and r.reach[1] == 0 and r.reach[2] == 1,
		"monsters on the floor below: walk to the hole")
	ok(r.why:find("another floor", 1, true) ~= nil, "the reason names the other floor")
	r = g({other = true, otherPos = {x = 160, y = 100, z = 8}, pos = {x = 139, y = 100, z = 7}})
	ok(r.mode == "walk" and r.via == "hole", "next to the hole: still walk (the last step is onto it)")
	r = g({other = true, otherPos = {x = 160, y = 100, z = 6}})
	ok(r.mode == "wait" and r.area == "pack", "monsters on a floor above and no ladder on this floor: wait")
	-- on the lower floor: the ladder
	r = g({pos = {x = 150, y = 100, z = 8}, other = true, otherPos = {x = 120, y = 100, z = 7}})
	ok(r.mode == "walk" and r.via == "ladder" and r.goal.x == 140 and r.goal.z == 8, "monsters on the floor above: walk to the ladder")
	r = g({pos = {x = 141, y = 100, z = 8}, other = true, otherPos = {x = 120, y = 100, z = 7}})
	ok(r.mode == "use" and r.via == "ladder" and r.goal.x == 140, "next to the ladder: use it")
	r = g({pos = {x = 140, y = 100, z = 8}, other = true, otherPos = {x = 120, y = 100, z = 7}})
	eq(r.mode, "use", "on the ladder tile (where a fall lands): use it")
	-- the guardian on another floor
	r = g({boss = "alive", bossPos = {x = 190, y = 100, z = 8}})
	ok(r.mode == "walk" and r.via == "hole" and r.why:find("guardian", 1, true) ~= nil, "the guardian on the floor below: to the hole first")
	r = g({pos = {x = 150, y = 100, z = 8}, boss = "alive", bossPos = {x = 190, y = 100, z = 8}})
	ok(r.mode == "walk" and r.area == "boss", "the guardian on this floor: walk to it")
	-- a pack monster on this floor comes before any stairs
	r = g({monster = {pos = {x = 110, y = 100, z = 7}}, other = false})
	ok(r.area == "pack", "a monster on this floor: no stairs")
	-- no stairs known: the old answer
	r = R.guide({state = "running", boss = "waiting", pos = {x = 100, y = 100, z = 7}, other = true, otherPos = {x = 160, y = 100, z = 8}, reach = 4})
	ok(r.mode == "wait" and r.area == "pack", "no links: wait")
	-- the probe: the links of the layout, the floor of the monsters left, the ladder to use
	restart()
	local a = newPlayer(31, "Tester Stp")
	local c = R.slotCenter(cfg, 3)
	local L = {start = {x = c.x, y = c.y, z = c.z}, kind = "rooms", floors = {c.z, c.z + 1}, links = {
		{hole = {x = c.x + 5, y = c.y, z = c.z}, ladder = {x = c.x + 5, y = c.y, z = c.z + 1}, up = {x = c.x + 5, y = c.y + 1, z = c.z}}}}
	local run = R.newRun(cfg, os.time(), 10, 8, R.effects(cfg, {}, 3))
	run.id, run.slot, run.L, run.key = 3, 3, L, {tier = 3, mods = {}}
	run.themeName, run.players, run.size, run.lives = "ash", {[a.id] = {id = a.id, guid = a.guid, name = a.name, entry = pos(1, 1, 7)}}, 1, 3
	run.openerGuid, run.state, run.boss, run.killed, run.total, run.bossAt = a.guid, "running", "waiting", 2, 10, 8
	run.aliveIds, run.bossIds = {[701] = true}, {}
	RF.runs[3], RF.runOf[a.id] = run, run
	a.at = pos(c.x, c.y, c.z)
	a.getItemById = function() return nil end
	monster(701, c.x + 12, c.y, c.z + 1) -- on the floor below
	local pr = RF.probe(a)
	ok(pr.run.floors == 2 and pr.run.links == 1, "the probe counts the floors and the links")
	ok(pr.guide.mode == "walk" and pr.guide.via == "hole" and pr.guide.goal.x == c.x + 5 and pr.guide.goal.z == c.z, "the guide goes to the hole")
	-- on the floor below, the monster above: the ladder, then its use with the client id and the place in the stack
	monsters[701].at = pos(c.x + 2, c.y, c.z)
	a.at = pos(c.x + 5, c.y, c.z + 1)
	ChaosAreaGenConfig = {items = {ladder = 1386}}
	local ladder = {id = 1386, getId = function() return 1386 end}
	ItemType = function(id) return {getId = function() return id end, getName = function() return "item" .. id end, getClientId = function() return 4000 + id end} end
	Tile = function(p)
		return {hasFlag = function() return false end, getItemById = function(_, id) return id == 1386 and p.x == c.x + 5 and ladder or nil end,
			getThingIndex = function() return 2 end}
	end
	pr = RF.probe(a)
	ok(pr.guide.mode == "use" and pr.guide.via == "ladder", "on the ladder tile: use it")
	ok(pr.guide.use and pr.guide.use.x == c.x + 5 and pr.guide.use.z == c.z + 1 and pr.guide.use.clientId == 5386 and pr.guide.use.stack == 2,
		"the ladder to use: its tile, its client id, its place in the stack")
	RF.runs[3], RF.runOf[a.id] = nil, nil
end

print(string.format("rift_probe_test: %d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)
