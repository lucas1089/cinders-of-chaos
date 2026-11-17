-- Run from the server/ folder: luajit tests/siege_closed_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The guild siege in closed test mode (O592; siege.lua, siege_core.lua, server/README.md "The siege and the guild boss in closed mode (O592)"):
-- the pure rules (start refusals, the side of a character, the guide) and the engine file on a mocked engine: the testers' own siege
-- starts only with the switch on, never ahead of a player's siege or sign-up, is never announced, writes no row, champion, buff or
-- leaderboard entry, is invisible to a player, refuses a player at its portal (and a tester at a player's), ends with the switch, and
-- gives the bots what a person sees (`probe`) and the close.
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
local events, moves = {}, {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function(self)
			events[(rawget(self, "name") or kind) .. ":" .. kind] = self
			if kind == "move" then moves[#moves + 1] = self end
		end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = eventMock("creature"), eventMock("global"), eventMock("talk"),
	eventMock("action"), eventMock("move")
EventCallback = setmetatable({}, {__index = function() return function() end end})
Condition = function() return setmetatable({}, {__index = function() return function() end end}) end
local clockMs = 2000000000000
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
local queries = {}
db = {query = function(q) queries[#queries + 1] = q return true end, storeQuery = function() return nil end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end}
result = {free = function() end}
local creatures = {}
local byName = {}
local temple = P(32369, 32241, 7)
local broadcasts = 0
local function newPlayer(id, name, tester, guildId, guildName)
	local c = {id = id, guid = id, name = name, pos = P(32369, 32241, 7), storage = {}, msgs = {}, hp = 1000, bank = 0}
	if tester then
		c.storage[7102900] = 1
	end
	function c:getId() return self.id end
	function c:getPlayer() return self end
	function c:getGuid() return self.guid end
	function c:getName() return self.name end
	function c:getPosition() return self.pos end
	function c:teleportTo(q) self.pos = P(q.x, q.y, q.z) end
	function c:isPlayer() return true end
	function c:isMonster() return false end
	function c:getMaster() return nil end
	function c:getHealth() return self.hp end
	function c:getMaxHealth() return 1000 end
	function c:setHealth(v) self.hp = v end
	function c:getMana() return 0 end
	function c:getMaxMana() return 0 end
	function c:addMana() end
	function c:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = tostring(t) end
	function c:sendCancelMessage(t) self.msgs[#self.msgs + 1] = tostring(t) end
	function c:registerEvent() end
	function c:unregisterEvent() end
	function c:removeCondition() end
	function c:addCondition() end
	function c:setTarget() end
	function c:getSkull() return 0 end
	function c:setSkull() end
	function c:getLevel() return 800 end
	function c:getStorageValue(k) return self.storage[k] or -1 end
	function c:setStorageValue(k, v) self.storage[k] = v end
	function c:getTown() return {getTemplePosition = function() return temple end} end
	function c:getGroup() return {getAccess = function() return false end, getId = function() return 1 end} end
	function c:getGuild()
		return guildId and {getId = function() return guildId end, getName = function() return guildName end} or nil
	end
	function c:getGuildLevel() return 3 end
	function c:getBankBalance() return self.bank end
	function c:setBankBalance(v) self.bank = v end
	function c:getInbox() return nil end
	function c:getIp() return 1 end
	function c:getSex() return 0 end
	creatures[id], byName[name] = c, c
	return c
end
Player = function(key)
	if type(key) == "string" then return byName[key] end
	return creatures[key]
end
Game = {getPlayers = function()
	local l = {}
	for _, c in pairs(creatures) do l[#l + 1] = c end
	return l
end, getTowns = function() return {} end, createTile = function() return {getGround = function() return true end,
	getItemById = function() return nil end} end,
	createItem = function() return {setActionId = function() end, getActionId = function() return 0 end, remove = function() end} end,
	broadcastMessage = function() broadcasts = broadcasts + 1 end}
Tile = function() return nil end
ItemType = function(id) return {getId = function() return id end, getName = function() return "item" .. id end} end

dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.send = function() return true end
Chaos.decode = function(b) return b end
Chaos.isMultiClient = function() return false end
Chaos.giveItem = function(_, _, count) return count end
Chaos.broadcast = function() broadcasts = broadcasts + 1 return "x" end
local signupRows, guildRows = {}, {{id = 71, name = "Tester Guild Alfa"}, {id = 72, name = "Tester Guild Bravo"}}
Chaos.select = function(q)
	if q:find("FROM `guilds` WHERE `name` LIKE", 1, true) then
		return guildRows
	elseif q:find("COUNT(*) AS `n` FROM `guild_membership`", 1, true) then
		return {{n = 3}}
	elseif q:find("chaos_siege_signups", 1, true) and q:find("SELECT", 1, true) then
		return signupRows
	end
	return {}
end
ChaosCityPortals = {register = function() end, place = function() return 1, {{x = 32371, y = 32241, z = 7}} end}
leaderboards = 0
ChaosLeaderboard = {record = function() leaderboards = leaderboards + 1 end}
dofile("data/scripts/chaos/testers_core.lua")
local K = ChaosTestersCore
local mode = "off"
K.reader = function() return mode end
local function setMode(m)
	mode = m
	K.resetClosedCache()
end
-- the engine-side guild rules of testers.lua, on the same pure rules
ChaosTesters = {guildSide = function(gid, name) return gid >= 71 and gid <= 72 and "tester" or (name:sub(1, 7) == "Tester " and nil or "player") end}
ChaosTesters.guildBlocked = function(player, gid, name)
	local isT = Chaos.isTester(player)
	local side = ChaosTesters.guildSide(gid, name)
	return K.guildBlocked(isT, name, side == "tester" or nil, side == "tester", K.closedOn())
end
dofile("data/scripts/chaos/siege.lua")
local S = ChaosSiege
local cfg = Chaos.siegeConfig
cfg.portalPositions = {{x = 32371, y = 32241, z = 7}}
Tile = function(pos) -- only the portal spot is a free walkable tile; the arena tiles do not exist yet
	if pos.x == 32371 and pos.y == 32241 and pos.z == 7 then
		return {getGround = function() return true end, hasProperty = function() return false end, getItemByType = function() return nil end,
			getItemById = function() return nil end}
	end
	return nil
end
cfg.leaderboard = "siege"

-- ------------------------------------------------------------------ the pure rules
do
	local t = S.testerTimes(cfg)
	ok(t.gather > 0 and t.match > t.gather and t.margin > 3600 + t.gather + t.match, "the testers' times: short, the margin outlasts the first warning and the siege")
	local base = {on = true, active = false, now = 1000, at = 1000 + t.margin + 10, playerSignups = 0, guilds = 2}
	eq(S.testerStartRefusal(base, cfg), nil, "start: everything in order")
	local function with(k, v) local c = {} for a, b in pairs(base) do c[a] = b end c[k] = v return c end
	ok(S.testerStartRefusal(with("on", false), cfg):find("off", 1, true), "start: the switch off")
	ok(S.testerStartRefusal(with("on", nil), cfg):find("off", 1, true), "start: a switch that is not true is off")
	ok(S.testerStartRefusal(with("active", true), cfg):find("already running", 1, true), "start: a siege is running")
	ok(S.testerStartRefusal(with("playerSignups", 1), cfg):find("players are signed up", 1, true), "start: players first (a sign-up)")
	ok(S.testerStartRefusal(with("at", 1000 + t.margin - 1), cfg):find("due within", 1, true), "start: players first (the weekly start is near)")
	ok(S.testerStartRefusal(with("guilds", 1), cfg):find("fewer than 2", 1, true), "start: two tester guilds are needed")
	local side, why = S.sideRefusal(K, true, false)
	ok(side == "player" and why == nil, "a player's side: never refused")
	side, why = S.sideRefusal(K, true, true)
	ok(side == "tester" and why == nil, "a tester with the switch on")
	side, why = S.sideRefusal(K, false, true)
	eq(why, "closed-off", "a tester with the switch off")
	eq(select(2, S.sideRefusal(nil, true, true)), "closed-off", "no rules loaded: a tester is refused")
	ok(K.CLOSED_SYSTEMS.siege and K.CLOSED_SYSTEMS.guildboss, "siege and guildboss are closed systems of testers_core.lua")
	ok(not K.sameSide("siege", true, "tester", "player"), "the rules refuse a tester against a player in the siege")

	local at, gate, center = {x = 10, y = 10, z = 7}, {x = 10, y = 20, z = 7}, {x = 10, y = 30, z = 7}
	local function g(o) local a = {phase = "match", where = "arena", pos = at, gate = gate, center = center, radius = 2} for k, v in pairs(o) do a[k] = v end return S.guide(a) end
	eq(g({where = false}).mode, "wait", "outside: wait")
	eq(g({phase = "gather", where = "base"}).mode, "wait", "gathering: the gates are shut")
	eq(g({phase = "ending"}).mode, "wait", "over: wait")
	eq(g({downed = true}).mode, "wait", "downed: wait")
	local r = g({where = "base"})
	ok(r.mode == "walk" and r.goal.y == 20 and r.reach[2] == 0 and r.area == "gate", "in the base during the match: walk to the gate")
	r = g({})
	ok(r.mode == "walk" and r.goal.y == 30 and r.reach[2] == 2 and r.area == "obelisk", "in the arena: walk to the obelisk, within the capture radius")
	r = g({onPoint = true})
	eq(r.mode, "hold", "on the point: hold it")
	r = g({onPoint = true, enemy = {x = 12, y = 12, z = 7}})
	ok(r.mode == "fight" and r.goal.x == 12, "an enemy within 3 tiles on the point: fight")
	eq(g({onPoint = true, enemy = {x = 20, y = 12, z = 7}}).mode, "hold", "an enemy far away: hold")
	eq(g({onPoint = true, enemy = {x = 11, y = 11, z = 8}}).mode, "hold", "an enemy on another floor is no target")
end

-- ------------------------------------------------------------------ the engine file
local function guildMember(id, name, gid, gname, tester)
	return newPlayer(id, name, tester, gid, gname)
end
local enter, gate = moves[1], moves[2]
ok(enter and gate and enter.onStepIn and gate.onStepIn, "the portal and the gate are registered")
local function resultRows()
	local k = 0
	for _, q in ipairs(queries) do
		if q:find("INSERT INTO `chaos_siege_results`", 1, true) or q:find("INSERT INTO `chaos_siege_signups`", 1, true) then k = k + 1 end
	end
	return k
end
local function msgs(p, text)
	for _, m in ipairs(p.msgs) do
		if m:find(text, 1, true) then return true end
	end
	return false
end

-- 1. the switch off: nothing starts
do
	setMode("off")
	local okS, why = S.startTester()
	ok(okS == false and why:find("off", 1, true), "switch off: the testers' siege does not start (" .. tostring(why) .. ")")
	eq(S.state.phase, "idle", "...and nothing runs")
end

-- 2. players first: a sign-up, or a running siege of players, keeps the testers out
do
	setMode("on")
	signupRows = {{guild_id = 5, guild_name = "Real Guild", signed_at = 1}}
	local okS, why = S.startTester()
	ok(okS == false and why:find("players are signed up", 1, true), "a player guild signed up: the testers wait")
	signupRows = {}
end

-- 3. the testers' siege
local alfa1 = guildMember(11, "Tester Aaa", 71, "Tester Guild Alfa", true)
local bravo1 = guildMember(12, "Tester Bbb", 72, "Tester Guild Bravo", true)
local real = guildMember(21, "Real Pia", 5, "Real Guild", false)
local realTester = guildMember(22, "Real Rex", nil, nil, false)
do
	local okS, why = S.startTester()
	ok(okS == true, "switch on, no players due: the testers' siege starts (" .. tostring(why) .. ")")
	eq(S.state.side, "tester", "its side is the testers'")
	eq(S.state.phase, "gather", "it gathers first")
	eq(broadcasts, 0, "never announced: no broadcast")
	eq(resultRows(), 0, "no sign-up row is written")
	local pr = S.probe(alfa1)
	ok(pr.on and pr.running and pr.phase == "gather" and pr.portal and pr.portal.x == 32371, "the tester sees the portal and the phase")
	ok(not pr.inside and pr.guild == "Tester Guild Alfa" and pr.signed, "outside: its guild is in the siege")
	local pp = S.probe(real)
	ok(not pp.running and pp.phase == "idle" and pp.portal == nil, "a player's probe: the siege is not there")
	eq(S.status("en", real):find("Next guild siege", 1, true) ~= nil, true, "a player's status reads the testers' siege as idle")
	ok(S.status("en", alfa1):find("gathering", 1, true) ~= nil, "a tester's status shows it")
	ok(S.status("en", nil, true):find("(testers)", 1, true) ~= nil, "the staff command marks it")
	-- the portal: a player never enters, a tester does
	local from = P(32370, 32241, 7)
	real.pos = P(32371, 32241, 7)
	enter.onStepIn(real, nil, real.pos, from)
	ok(real.pos.x == 32370 and msgs(real, "never mixed"), "a player at the testers' portal is pushed back with the mixed rule")
	eq(S.state.players[21], nil, "...and is no participant")
	alfa1.pos = P(32371, 32241, 7)
	enter.onStepIn(alfa1, nil, alfa1.pos, from)
	ok(S.state.players[11] and S.state.players[11].inside, "a tester of a signed-up tester guild goes in")
	pr = S.probe(alfa1)
	ok(pr.inside and pr.where == "base" and pr.bracket == 1, "inside: in its base")
	eq(pr.guide.mode, "wait", "the gate is shut while gathering")
	-- a tester of no guild
	local lone = newPlayer(23, "Tester Ccc", true)
	lone.pos = P(32371, 32241, 7)
	enter.onStepIn(lone, nil, lone.pos, from)
	ok(S.state.players[23] == nil and msgs(lone, "not signed up") or msgs(lone, "Only members"), "a tester with no guild is refused")
	bravo1.pos = P(32371, 32241, 7)
	enter.onStepIn(bravo1, nil, bravo1.pos, from)
	ok(S.state.players[12] and S.state.players[12].inside, "the other guild's tester goes in")
	advance((S.testerTimes(cfg).gather + 1) * 1000)
	eq(S.state.phase, "match", "after the gather time the gates open")
	pr = S.probe(alfa1)
	eq(pr.guide.mode, "walk", "in the base: walk")
	eq(pr.guide.area, "gate", "...to the gate")
	ok(pr.gate and pr.gate.z == 7 and pr.center and pr.center.z == 7, "the probe gives the gate and the obelisk")
	-- the gate takes it into the arena
	alfa1.pos = P(pr.gate.x, pr.gate.y, pr.gate.z)
	gate.onStepIn(alfa1, nil, alfa1.pos, alfa1.pos)
	pr = S.probe(alfa1)
	ok(pr.where == "arena" and pr.guide.mode == "walk" and pr.guide.area == "obelisk", "through the gate: in the arena, walk to the obelisk")
	-- hold the obelisk
	alfa1.pos = P(pr.center.x, pr.center.y + 1, pr.center.z)
	advance(4000)
	pr = S.probe(alfa1)
	ok(pr.onPoint and pr.guide.mode == "hold", "on the point: hold")
	ok(pr.team.score >= 3 and pr.you.points >= 3, "the hold scores (" .. tostring(pr.team.score) .. ")")
	eq(pr.holder, "Tester Guild Alfa", "the holder is the bot's guild")
	eq(pr.contested, false, "not contested while alone")
	-- the rival comes: a tie contests it, nobody scores
	local pb = S.probe(bravo1)
	bravo1.pos = P(pb.gate.x, pb.gate.y, pb.gate.z)
	gate.onStepIn(bravo1, nil, bravo1.pos, bravo1.pos)
	bravo1.pos = P(pr.center.x, pr.center.y - 1, pr.center.z)
	advance(2000)
	pr = S.probe(alfa1)
	eq(pr.contested, true, "both guilds on the point: contested")
	local score = pr.team.score
	advance(3000)
	eq(S.probe(alfa1).team.score, score, "a contested point scores for nobody")
	ok(#pr.rivals == 1 and pr.rivals[1].name == "Tester Guild Bravo", "the probe names the rival")
	eq(S.probe(alfa1).guide.mode, "fight", "an enemy on the point within reach: fight")
	advance(8000) -- presence: the reward needs the testers' minimum of seconds inside
	-- a stranger asks to close: refused (the asker is not inside while others are)
	ok(S.testerClose(real) == false, "a player cannot close the testers' siege")
	-- the close: standings and rewards, nothing stored
	ok(S.testerClose(alfa1) == true, "a bot inside closes the siege")
	eq(S.state.phase, "ending", "it is ending")
	ok(msgs(alfa1, "Guild siege reward"), "the tester gets its reward")
	eq(broadcasts, 0, "the end is never announced either")
	eq(resultRows(), 0, "no results row")
	ok(next(S.champions) == nil, "no champion guild, so no title and no buff")
	eq(leaderboards, 0, "no leaderboard entry")
	advance((S.testerTimes(cfg).exit + 1) * 1000)
	eq(S.state.phase, "idle", "the siege is over and the arena cleaned")
	ok(alfa1.pos.x == temple.x, "the testers are back at the temple")
end

-- 4. the switch going off stops a running siege
do
	local okS = S.startTester()
	ok(okS == true, "a second siege starts")
	local from = P(32370, 32241, 7)
	alfa1.pos = P(32371, 32241, 7)
	enter.onStepIn(alfa1, nil, alfa1.pos, from)
	ok(S.state.players[11] ~= nil, "a bot is in")
	setMode("off")
	advance(2000)
	ok(S.state.phase == "ending" or S.state.phase == "idle", "the switch went off: the testers' siege ends")
	advance(6000)
	eq(S.state.phase, "idle", "...and is closed out")
	-- with the switch off a tester is refused at a player's portal
	setMode("on")
end

-- 5. the players' siege: a tester never joins, a tester siege gives way, no sign-ups for testers
do
	local joined, text = S.join(alfa1)
	ok(joined == false and text:find("staff helper", 1, true), "a tester cannot sign a guild up")
	signupRows = {{guild_id = 5, guild_name = "Real Guild", signed_at = 1}, {guild_id = 6, guild_name = "Other Guild", signed_at = 2}}
	local okT = S.startTester()
	ok(okT == false, "a testers' siege does not start while players are signed up")
	signupRows = {}
	okT = S.startTester()
	ok(okT == true, "a testers' siege again")
	local okP, why = S.start(true)
	ok(okP == false and why:find("testers' siege was running", 1, true), "a player siege start stops the testers' siege first (players first)")
	advance(6000)
	eq(S.state.phase, "idle", "the testers' siege is gone")
	-- a player siege has the side "player" and refuses a tester at the portal
	signupRows = {{guild_id = 5, guild_name = "Real Guild", signed_at = 1}, {guild_id = 6, guild_name = "Other Guild", signed_at = 2}}
	local okR = S.start(true)
	ok(okR == true, "the players' siege starts")
	eq(S.state.side, "player", "its side is the players'")
	local from = P(32370, 32241, 7)
	alfa1.pos = P(32371, 32241, 7)
	alfa1.msgs = {}
	enter.onStepIn(alfa1, nil, alfa1.pos, from)
	ok(alfa1.pos.x == 32370 and msgs(alfa1, "never mixed"), "a tester at a player siege portal is pushed back")
	ok(S.probe(alfa1).running == false, "the tester's probe: no siege")
	ok(S.probe(real).running == true, "the player's probe: the siege")
	ok(broadcasts > 0, "the players' siege is announced as always")
	signupRows = {}
	S.stop()
	advance(10000)
end

print(string.format("siege_closed_test: %d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)
