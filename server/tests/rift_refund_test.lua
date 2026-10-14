-- Run from the server/ folder: luajit tests/rift_refund_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The rift key refund with a mocked engine (rift.lua loaded for real): a clean shutdown (onShutdown, or the kick of a
-- closed server) ends every run, sends everyone to the temple and gives the key back once while the guardian lives; a
-- sealed run gives none; the next login and the next restart give nothing more. The crash refund at login: once, and
-- never after a logout, a death, the timer or a removal without a logout event.
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
local function keysOf(p)
	local list = {}
	for _, it in ipairs(p.items) do
		if it.id == cfg.key.itemId then list[#list + 1] = it end
	end
	return list
end
local function restart() -- a crash or a restart empties every table of the running server
	RF.runs, RF.runOf, RF.noRefund, RF.revive, RF.pending = {}, {}, {}, {}, {}
	gameState = GAME_STATE_NORMAL
end

-- a run as RF.open leaves it (the key consumed, the marker set and saved), without building the instance
local runId = 0
local function openRun(opener, others, key, state)
	runId = runId + 1
	local slot = runId
	-- the arrival of the slot's layout (inside the slot's square: the tick keeps players there in the run)
	local c = R.slotCenter(cfg, slot)
	local L = {start = {x = c.x, y = c.y, z = c.z}}
	local run = R.newRun(cfg, os.time(), 10, 8, R.effects(cfg, key.mods, key.tier))
	run.id, run.slot, run.L, run.key, run.plan = runId, slot, L, key, {boss = "x"}
	run.fx = run.fx or {}
	run.bonus, run.players, run.size, run.lives, run.revive = {}, {}, 1, 3, {}
	run.openerGuid, run.typeNames, run.claimed, run.finishers = opener.guid, {}, {}, {}
	run.state = state or "running"
	RF.runs[slot] = run
	local list = {opener}
	for _, o in ipairs(others or {}) do list[#list + 1] = o end
	for _, p in ipairs(list) do
		run.players[p.id] = {id = p.id, guid = p.guid, name = p.name, entry = pos(50, 50, 7), xp = {base = 0}}
		RF.runOf[p.id] = run
		p.at = pos(L.start.x, L.start.y, L.start.z)
	end
	-- what RF.open does with the key and the marker
	opener:setStorageValue(ST, key.tier)
	for i = 1, 3 do
		opener:setStorageValue(ST + i, key.mods[i] and R.packMod(cfg, key.mods[i]) or 0)
	end
	opener:setStorageValue(ST + 4, os.time())
	opener:save()
	return run
end
local key = {tier = 6, mods = {{key = cfg.mods[1].key, value = cfg.mods[1].range[1]}}}
local login = events.ChaosRiftLogin.onLogin
local logout = events.ChaosRiftLogout.onLogout
local shutdown = events.ChaosRiftShutdown.onShutdown
-- the engine at a shutdown: onShutdown, then every player is kicked (onLogout) and saved
local function shutdownServer(list)
	gameState = GAME_STATE_SHUTDOWN
	shutdown()
	for _, p in ipairs(list) do
		logout(p)
		p:save()
	end
end

-- 1. a clean shutdown with the guardian alive: temple, the key back once (same tier and modifiers)
do
	restart()
	local a, b = newPlayer(1, "Opener"), newPlayer(2, "Friend")
	local run = openRun(a, {b}, key)
	shutdownServer({a, b})
	ok(run.ended, "the run ended")
	eq(run.state, "interrupted", "state")
	eq(#keysOf(a), 1, "shutdown: the opener gets the key back")
	eq(#keysOf(b), 0, "shutdown: the friend gets no key")
	local k = keysOf(a)[1]
	local back = k and RF.readKey(k)
	eq(back and back.tier, 6, "same tier")
	eq(back and R.encodeMods(back.mods), R.encodeMods(key.mods), "same modifiers")
	eq(a.at, temple, "opener at the temple"); eq(b.at, temple, "friend at the temple")
	eq(a.db[ST], 0, "the marker is cleared in the saved copy")
	eq(a.dbItems, 1, "the key is in the saved copy")
	eq(next(RF.runs), nil, "no run left")
	-- restart, log in: nothing more
	restart()
	local a2 = relog(a)
	login(a2)
	eq(#keysOf(a2), 0, "no second refund at the next login")
	-- another restart, log in again: still nothing
	restart()
	local a3 = relog(a2)
	login(a3)
	eq(#keysOf(a3), 0, "no refund after a second restart")
end

-- 2. a sealed run (guardian dead, chest up): no key; the marker was cleared at the kill (success() does that)
do
	restart()
	local a = newPlayer(3, "Sealer")
	local run = openRun(a, {}, key, "success")
	a:setStorageValue(ST, 0) a:save() -- success() clears the marker
	local delivered = 0
	local deliver = RF.deliver
	RF.deliver = function() delivered = delivered + 1 end
	run.finishers[a.guid] = {name = a.name}
	shutdownServer({a})
	RF.deliver = deliver
	eq(#keysOf(a), 0, "sealed: no key back")
	eq(delivered, 1, "sealed: the unclaimed chest share is handed out")
	eq(a.at, temple, "sealed: at the temple")
	restart()
	local a2 = relog(a)
	login(a2)
	eq(#keysOf(a2), 0, "sealed: nothing at the next login")
end

-- 3. a closed server (no onShutdown, only the kicks): the first kick ends every run
do
	restart()
	local a, b = newPlayer(4, "Closed"), newPlayer(5, "Other")
	openRun(a, {}, key)
	openRun(b, {}, {tier = 2, mods = {}})
	gameState = GAME_STATE_CLOSED
	logout(a); a:save()
	eq(#keysOf(a), 1, "closed: the kicked opener gets the key")
	eq(#keysOf(b), 1, "closed: the other run's opener too (still online at that moment)")
	logout(b); b:save()
	eq(#keysOf(b), 1, "closed: once")
	restart()
	local a2 = relog(a)
	login(a2)
	eq(#keysOf(a2), 0, "closed: nothing at the next login")
end

-- 4. a crash (no event): the saved marker refunds the key at the next login, once
do
	restart()
	local a = newPlayer(6, "Crash")
	openRun(a, {}, key)
	a.at = pos(a.at.x, a.at.y, a.at.z)
	restart() -- kill -9
	local a2 = relog(a)
	login(a2)
	eq(#keysOf(a2), 1, "crash: the key comes back at login")
	eq(a2.storage[ST], 0, "crash: marker cleared")
	a2:save()
	eq(a2.db[ST], 0, "crash: and saved with the key")
	local a3 = relog(a2)
	login(a3)
	eq(#keysOf(a3), 0, "crash: a relog gives nothing more")
	restart()
	local a4 = relog(a3)
	login(a4)
	eq(#keysOf(a4), 0, "crash: a restart gives nothing more")
end

-- 5. no refund after a logout, a death or the timer, even across a crash
do
	restart()
	local a = newPlayer(7, "Quitter")
	openRun(a, {}, key)
	logout(a); a:save() -- a normal logout inside
	restart()
	local a2 = relog(a)
	login(a2)
	eq(#keysOf(a2), 0, "logout inside: the key is spent (also after a crash)")

	restart()
	local d = newPlayer(8, "Dead")
	local run = openRun(d, {}, key)
	events.ChaosRiftPlayerDeath.onDeath(d)
	d:save()
	ok(not RF.runOf[d.id], "dead: out of the run")
	restart()
	local d2 = relog(d)
	login(d2)
	eq(#keysOf(d2), 0, "death inside: the key is spent (also after a crash)")

	restart()
	local t = newPlayer(9, "Timer")
	run = openRun(t, {}, key)
	RF._fail(run, "Time is up!")
	t:save()
	eq(t.at.x, 50, "timer: back at the entry")
	restart()
	local t2 = relog(t)
	login(t2)
	eq(#keysOf(t2), 0, "time up: the key is spent (also after a crash)")
end

-- 6. removed without a logout event: no refund at the next login and none after a restart (the marker leaves the database)
do
	restart()
	local g = newPlayer(10, "Ghost")
	local run = openRun(g, {}, key)
	players[g.id] = nil -- gone without onLogout
	queries = {}
	RF._removePlayer(run, g.id, "none")
	ok(RF.noRefund[g.guid], "noRefund set")
	local deleted = false
	for _, q in ipairs(queries) do
		if q:find("DELETE FROM `player_storage`", 1, true) and q:find("`player_id` = 10", 1, true) then deleted = true end
	end
	ok(deleted, "the marker is deleted from the database")
	-- what the database then holds (the delete applied): no marker
	for i = 0, 4 do g.db[ST + i] = nil end
	local g2 = relog(g)
	login(g2)
	eq(#keysOf(g2), 0, "no refund while the server runs")
	restart()
	local g3 = relog(g2)
	login(g3)
	eq(#keysOf(g3), 0, "no refund after a restart")
end

-- 7. a shutdown after the opener left the run (the friend still inside): no key for anyone
do
	restart()
	local a, b = newPlayer(11, "Leaver"), newPlayer(12, "Stayer")
	local run = openRun(a, {b}, key)
	logout(a); a:save()
	ok(not run.ended, "the friend keeps the run open")
	shutdownServer({b})
	eq(#keysOf(a) + #keysOf(b), 0, "opener gone: no refund")
	eq(b.at, temple, "the friend at the temple")
end

-- 8. an omen arena: the omen key comes back
do
	restart()
	local omenKind = cfg.omen.kinds[1].key
	local gave
	local giveOmen = RF.giveOmenKey
	RF.giveOmenKey = function(p, kind) gave = kind p.items[#p.items + 1] = newItem(cfg.omen.key.id) return kind end
	local a = newPlayer(13, "Omen")
	local run = openRun(a, {}, {tier = 10, mods = {}, omen = omenKind})
	run.omen = omenKind
	a:setStorageValue(ST, R.markerTier(cfg, omenKind)) a:save()
	shutdownServer({a})
	RF.giveOmenKey = giveOmen
	eq(gave, omenKind, "omen: the same omen key back")
	eq(a.db[ST], 0, "omen: marker cleared")
end

-- 9. the opener dies with lives left: the key is spent while away; back in the run (next login) it is covered again
do
	restart()
	local a = newPlayer(14, "Phoenix")
	local run = openRun(a, {}, key)
	events.ChaosRiftPlayerDeath.onDeath(a)
	a:save()
	eq(a.db[ST], 0, "dead with lives left: marker cleared")
	ok(RF.revive[a.guid] == run, "may return")
	local a2 = relog(a)
	login(a2)
	ok(RF.runOf[a2.id] == run, "back in the run at login")
	eq(#keysOf(a2), 0, "no key at that login")
	ok((a2.db[ST] or 0) > 0, "the marker is set (and saved) again")
	shutdownServer({a2})
	eq(#keysOf(a2), 1, "a shutdown after the return gives the key back")
	restart()
	local a3 = relog(a2)
	login(a3)
	eq(#keysOf(a3), 0, "once")
	-- the same, but the run ends while the owner is still away: nothing
	restart()
	local b = newPlayer(15, "Away")
	run = openRun(b, {}, key)
	events.ChaosRiftPlayerDeath.onDeath(b)
	b:save()
	RF._fail(run, "Time is up!")
	local b2 = relog(b)
	login(b2)
	eq(#keysOf(b2), 0, "away when the run ended: no key")
	ok(not RF.runOf[b2.id], "and not put back into the ended run")
end

-- instance limits (instance_limits.lua, server/README.md "Instance limits"): warnings before the end, a run kept open
-- only for a fallen player closes after the idle grace as a failed rift (no key back), the cap with the wait and the
-- waiting line, the staff list and close
do
	restart()
	dofile("data/scripts/chaos/instance_limits.lua")
	local IL = ChaosInstanceLimits
	local a = newPlayer(31, "Limits")
	local run = openRun(a, {}, key)
	local t0 = os.time()
	run.deadline = t0 + 400
	RF._tick(run.slot, run.id)
	eq(#a.msgs, 0, "limits: no warning at 400 s")
	run.deadline = t0 + 300
	RF._tick(run.slot, run.id)
	ok((a.msgs[#a.msgs] or ""):find("Rift: 5 minutes left", 1, true) ~= nil, "limits: 5 minute warning")
	run.deadline = t0 + 9
	RF._tick(run.slot, run.id)
	ok((a.msgs[#a.msgs] or ""):find("Rift: 10 seconds left", 1, true) ~= nil, "limits: 10 s warning")
	-- the cap: one rift at most, a second opener waits in line and is told when it frees up
	cfg.limits.maxRuns = 1
	local b = newPlayer(32, "Waiting")
	b.sendCancelMessage = function(_, t) b.msgs[#b.msgs + 1] = t end
	eq(RF._takeSlot(b), nil, "limits: the cap refuses a second rift")
	ok((b.msgs[#b.msgs] or ""):find("All rifts are busy. One frees up in under a minute. You are 1st in line", 1, true) ~= nil,
		"limits: busy text with the wait and the place: " .. tostring(b.msgs[#b.msgs]))
	cfg.limits.maxRuns = 16
	-- the staff list
	local found
	for _, r in ipairs(IL.runs()) do
		if r.key == "rift" and r.id == run.id then found = r end
	end
	ok(found and found.players == 1 and found.left == 9, "limits: /instances lists the rift with its time left")
	-- the opener falls with lives left and logs out: the run stays open for the idle grace, then fails
	run.players[a.id] = nil
	RF.runOf[a.id] = nil
	run.revive = {[a.guid] = true}
	RF.revive[a.guid] = run
	run.deadline = t0 + 500
	RF._tick(run.slot, run.id)
	ok(not run.ended, "limits: a fallen player keeps the run open (grace)")
	run._limits.emptySince = os.time() - cfg.limits.idleSeconds
	RF._tick(run.slot, run.id)
	ok(run.ended and run.state == "failed", "limits: empty for the grace: the rift fails")
	ok((run.endText or ""):find("Nobody came back in time", 1, true) ~= nil, "limits: why")
	eq(RF.revive[a.guid], nil, "limits: no return to a closed rift")
	ok((b.msgs[#b.msgs] or ""):find("A place in the rifts is free now", 1, true) ~= nil, "limits: the first in line is told")
	-- staff close: the time-out rule
	local c = newPlayer(33, "Closed")
	local run2 = openRun(c, {}, key)
	local okc = Chaos.instances.rift.close(run2.id)
	ok(okc and run2.ended and run2.state == "failed", "limits: staff close fails the rift")
	eq(#keysOf(c), 0, "limits: no key back for a staff close")
	eq(c.at.x, 50, "limits: back where the key was used")
end

print(string.format("rift_refund_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
