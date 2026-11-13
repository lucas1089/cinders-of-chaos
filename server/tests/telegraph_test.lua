-- Run from the server/ folder: luajit tests/telegraph_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the floor telegraphs (server/README.md "Floor telegraphs (O549)"): the opcode is the monster bar's 125 with no new
-- number, the core (telegraph_core.lua: the union of the tiles, the outline of the union, the payload, who gets what, the
-- follow move, the clear at the hit and at the end of a fight, the hello) and the glue (telegraph.lua) against a mocked
-- engine (capable and legacy players, the sprite marks of a pulse sent to the right ones, login, logout, the loop).
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/telegraph_core.lua")
local K = ChaosTelegraphCore
local cfg = dofile("data/scripts/chaos/telegraph_config.lua")

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ------------------------------------------------------------------ opcode: the monster bar's, nothing new
eq(ChaosOpcodes.monsterbar, 125, "the monster bar's opcode")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
ok(ChaosOpcodes.telegraph == nil and ChaosOpcodes.floorTelegraph == nil, "no opcode of its own")

local function sq(x1, y1, x2, y2, z)
	local t = {}
	for y = y1, y2 do
		for x = x1, x2 do
			t[#t + 1] = {x = x, y = y, z = z or 7}
		end
	end
	return t
end

-- ------------------------------------------------------------------ ids and colours
eq(K.validId("bm:12:3", cfg), "bm:12:3", "an id")
eq(K.validId("", cfg), nil, "empty id")
eq(K.validId(12, cfg), nil, "a number is no id")
eq(K.validId("a b", cfg), nil, "a space is no id")
eq(K.validId(string.rep("x", 65), cfg), nil, "an id of 65 characters")
eq(K.validId(string.rep("x", 64), cfg), string.rep("x", 64), "an id of 64 characters")
eq(K.colorOf("violet", cfg), "violet", "a known colour")
eq(K.colorOf("pink", cfg), "orange", "an unknown colour: the default")
eq(K.colorOf(nil, cfg), "orange", "no colour: the default")

-- ------------------------------------------------------------------ normalize: the union of the tiles
local n = K.normalize({{x = 5, y = 3, z = 7}, {x = 4, y = 3, z = 7}, {x = 5, y = 3, z = 7}, {x = 4, y = 2, z = 7}}, cfg)
eq(#n.list, 3, "a tile twice counts once")
eq(n.list[1].x .. "," .. n.list[1].y, "4,2", "sorted by row")
eq(n.list[2].x .. "," .. n.list[2].y, "4,3", "then column")
eq(n.list[3].x .. "," .. n.list[3].y, "5,3", "last")
eq(n.z, 7, "the floor")
eq(n.x1 .. n.y1 .. n.x2 .. n.y2, "4253", "bounding box")
n = K.normalize({{x = 5, y = 3, z = 7}, {x = 6, y = 3, z = 8}, {x = 7, y = 3, z = 7}}, cfg)
eq(#n.list, 2, "tiles of another floor are dropped")
n = K.normalize({{5, 3, 7}, {6, 3, 7}}, cfg)
eq(#n.list, 2, "array tiles")
eq(K.normalize({}, cfg), nil, "no tiles")
eq(K.normalize(nil, cfg), nil, "no list")
eq(K.normalize({{x = "a", y = 1, z = 7}}, cfg), nil, "junk tiles")
eq(K.normalize({{x = 1, y = 1, z = 16}}, cfg), nil, "floor 16")
eq(K.normalize({{x = -1, y = 1, z = 7}}, cfg), nil, "negative x")
local big, why = K.normalize(sq(100, 100, 100 + 17, 100 + 16), cfg) -- 18 x 17 = 306
eq(big, nil, "over maxTiles")
eq(why, "too many tiles", "the reason")
ok(K.normalize(sq(100, 100, 100 + 16, 100 + 16), cfg) ~= nil, "17 x 17 = 289 is within maxTiles")

-- ------------------------------------------------------------------ outline: only the outer edges of the union
local function maskAt(out, x, y)
	for _, e in ipairs(out) do
		if e.x == x and e.y == y then
			return e.m
		end
	end
	return 0
end
local one = K.outline(K.normalize(sq(10, 10, 10, 10), cfg).list)
eq(maskAt(one, 10, 10), 15, "one tile: four sides")
local two = K.outline(K.normalize(sq(10, 10, 11, 10), cfg).list)
eq(maskAt(two, 10, 10), 1 + 4 + 8, "left tile of two: no right side")
eq(maskAt(two, 11, 10), 1 + 2 + 4, "right tile of two: no left side")
local three = K.outline(K.normalize(sq(10, 10, 12, 12), cfg).list)
eq(#three, 8, "3 x 3: the middle has no line")
eq(maskAt(three, 11, 11), 0, "the middle tile")
eq(maskAt(three, 10, 10), 1 + 8, "top left corner")
eq(maskAt(three, 12, 12), 2 + 4, "bottom right corner")
eq(maskAt(three, 11, 10), 1, "top edge")
-- an L: the inner corner tile has its two open sides only
local L = K.normalize({{x = 1, y = 1, z = 7}, {x = 2, y = 1, z = 7}, {x = 1, y = 2, z = 7}}, cfg)
local lo = K.outline(L.list)
eq(maskAt(lo, 1, 1), 1 + 8, "L corner")
eq(maskAt(lo, 2, 1), 1 + 2 + 4, "L arm right")
eq(maskAt(lo, 1, 2), 2 + 4 + 8, "L arm down")
-- the union of two overlapping areas is one outline (the shared tiles have no line between them)
local both = {}
for _, t in ipairs(sq(10, 10, 12, 12)) do
	both[#both + 1] = t
end
for _, t in ipairs(sq(12, 10, 14, 12)) do
	both[#both + 1] = t
end
local un = K.normalize(both, cfg)
eq(#un.list, 15, "two 3 x 3 squares sharing a column: 15 tiles")
local uo = K.outline(un.list)
eq(maskAt(uo, 12, 11), 0, "the shared column's middle tile has no line")
eq(maskAt(uo, 12, 10), 1, "the shared column's top tile has the top line only")
eq(maskAt(uo, 14, 11), 2, "the right edge")
-- a ring: the hole's edge is drawn too
local ring = {}
for _, t in ipairs(sq(10, 10, 12, 12)) do
	if not (t.x == 11 and t.y == 11) then
		ring[#ring + 1] = t
	end
end
local ro = K.outline(K.normalize(ring, cfg).list)
eq(maskAt(ro, 11, 10), 1 + 4, "a ring's top tile has a line on the hole side too")
eq(#ro, 8, "every tile of a ring has a line")

-- ------------------------------------------------------------------ open and the payload
local st = K.newState()
local m = K.open(st, "bm:1:1", sq(100, 200, 102, 201), 2000, 5000, cfg, {color = "red"})
ok(m ~= nil, "a mark opens")
eq(st.count, 1, "counted")
eq(m.hitAt, 7000, "the hit time")
eq(m.color, "red", "the colour")
eq(m.cx .. "," .. m.cy, "101,200", "centre of the box")
eq(m.hx .. "," .. m.hy, "2,1", "reach of the box")
local pl = K.payload(m, 5500)
eq(pl.id, "bm:1:1", "payload id")
eq(pl.z, 7, "payload floor")
eq(pl.x0 .. "," .. pl.y0, "100,200", "payload origin")
eq(#pl.t, 6, "payload tiles")
eq(pl.t[1][1] .. "," .. pl.t[1][2], "0,0", "first tile relative to the origin")
eq(pl.t[6][1] .. "," .. pl.t[6][2], "2,1", "last tile relative to the origin")
eq(pl.c, "red", "payload colour")
eq(pl.ms, 1500, "ms left at the time of the send")
eq(K.payload(m, 9000).ms, 0, "never negative")
-- a big mark stays far under the 8192 byte limit of one message
local widest = K.open(st, "wide", sq(1000, 1000, 1016, 1016), 2000, 0, cfg)
local bytes = 0
for _, t in ipairs(K.payload(widest, 0).t) do
	bytes = bytes + #("[" .. t[1] .. "," .. t[2] .. "],")
end
ok(bytes + 200 < 8192, "17 x 17 tiles fit one message (" .. bytes .. " bytes)")
K.close(st, "wide")
-- refusals: the caller draws the sprites for everybody
eq(K.open(st, "bad id", sq(1, 1, 2, 2), 2000, 0, cfg), nil, "a bad id")
eq(K.open(st, "x", sq(1, 1, 2, 2), 50, 0, cfg), nil, "less than minMs")
eq(K.open(st, "x", sq(1, 1, 2, 2), 99999, 0, cfg), nil, "more than maxMs")
eq(K.open(st, "x", sq(1, 1, 2, 2), "soon", 0, cfg), nil, "a time that is no number")
eq(K.open(st, "x", {}, 2000, 0, cfg), nil, "no tiles")
eq(st.count, 1, "refusals are not counted")
-- the limit of marks alive
local small = K.newState()
local lim = {maxMarks = 2, maxTiles = 300, colors = cfg.colors, defaultColor = "orange"}
ok(K.open(small, "a", sq(1, 1, 1, 1), 2000, 0, lim) ~= nil, "mark 1")
ok(K.open(small, "b", sq(1, 1, 1, 1), 2000, 0, lim) ~= nil, "mark 2")
eq(K.open(small, "c", sq(1, 1, 1, 1), 2000, 0, lim), nil, "mark 3 over maxMarks")
ok(K.open(small, "a", sq(2, 2, 2, 2), 2000, 0, lim) ~= nil, "an id that exists is replaced, not counted again")
eq(small.count, 2, "still two")

-- ------------------------------------------------------------------ who gets what
local st2 = K.newState()
local mk = K.open(st2, "bm:9:1", sq(100, 100, 102, 102), 2000, 0, cfg)
local seeing = {[1] = true, [2] = true}
local out = K.plan(st2, function() return seeing end, 100)
eq(#out, 2, "both capable players near it get the area")
eq(out[1].cid, 1, "in order of id")
eq(out[1].action, "floor", "the floor action")
eq(out[1].data, out[2].data, "one payload for both")
eq(out[1].data.ms, 1900, "the ms left")
eq(#K.plan(st2, function() return seeing end, 200), 0, "told once: nothing more on the next tick")
seeing[3] = true
out = K.plan(st2, function() return seeing end, 300)
eq(#out, 1, "a player who comes into view gets it")
eq(out[1].cid, 3, "that player")
eq(out[1].data.ms, 1700, "with the time left then")
seeing[2] = nil
out = K.plan(st2, function() return seeing end, 400)
eq(#out, 1, "a player who left is told to clear")
eq(out[1].cid, 2, "that player")
eq(out[1].action, "floorclear", "floorclear")
eq(out[1].data.id, "bm:9:1", "which mark")
eq(#K.plan(st2, function() return seeing end, 500), 0, "and not again")
seeing[2] = true
out = K.plan(st2, function() return seeing end, 600)
eq(#out, 1, "back in view: the area again")
eq(out[1].action, "floor", "floor")
-- a follow circle moves: everyone near gets the whole area again, the hit time stays
ok(K.move(st2, "bm:9:1", sq(110, 100, 112, 102), 700, cfg) ~= nil, "move")
out = K.plan(st2, function() return seeing end, 700)
eq(#out, 3, "all three get the new area")
eq(out[1].data.x0, 110, "the new origin")
eq(out[1].data.ms, 1300, "the hit time did not move (2000 from 0)")
eq(K.move(st2, "nope", sq(1, 1, 1, 1), 0, cfg), nil, "move of a mark that is not there")
ok(K.move(st2, "bm:9:1", sq(110, 100, 112, 102), 800, cfg, 500) ~= nil, "move with a new time")
eq(K.payload(st2.marks["bm:9:1"], 800).ms, 500, "the new hit time")
-- a replaced mark (the same id opened again) goes out again too
K.plan(st2, function() return seeing end, 800)
K.open(st2, "bm:9:1", sq(120, 100, 121, 100), 2000, 900, cfg)
out = K.plan(st2, function() return seeing end, 900)
eq(#out, 3, "an opened-again id is sent again to all")
eq(out[1].data.x0, 120, "the new area")
-- nobody sees it: nothing is sent
local st3 = K.newState()
K.open(st3, "q", sq(1, 1, 2, 2), 2000, 0, cfg)
eq(#K.plan(st3, function() return {} end, 0), 0, "nobody near, nothing sent")

-- ------------------------------------------------------------------ clear: the hit, the end of a fight
local st4 = K.newState()
K.open(st4, "bm:5:1", sq(1, 1, 2, 2), 2000, 0, cfg)
K.open(st4, "bm:5:2", sq(5, 5, 6, 6), 2000, 0, cfg)
K.open(st4, "bm:55:1", sq(8, 8, 9, 9), 2000, 0, cfg)
K.plan(st4, function() return {[7] = true, [8] = true} end, 0)
local cl = K.closePrefix(st4, "bm:5:")
eq(#cl, 4, "two marks x two players are cleared")
eq(cl[1].id, "bm:5:1", "in id order")
ok(st4.marks["bm:55:1"] ~= nil, "bm:55 is another fight: not touched by the prefix bm:5:")
eq(st4.count, 1, "counted down")
eq(#K.close(st4, "bm:55:1"), 2, "close tells the players that have it")
eq(#K.close(st4, "bm:55:1"), 0, "a mark that is gone clears nobody")
eq(st4.count, 0, "none left")
-- the hit time passed: the mark goes with the grace
local st5 = K.newState()
K.open(st5, "a", sq(1, 1, 2, 2), 1000, 0, cfg)
K.open(st5, "b", sq(3, 3, 4, 4), 3000, 0, cfg)
K.plan(st5, function() return {[1] = true} end, 0)
eq(#K.expire(st5, 1000, cfg), 0, "at the hit: still inside the grace")
cl = K.expire(st5, 1000 + cfg.graceMs, cfg)
eq(#cl, 1, "after the grace: a is dropped, its viewer told")
eq(cl[1].id, "a", "a")
ok(st5.marks.b ~= nil, "b is still on its way")
eq(st5.count, 1, "counted")

-- ------------------------------------------------------------------ the client's hello
eq(K.clientHello({action = "floorhello", data = {v = 1}}), true, "hello v1")
eq(K.clientHello({action = "floorhello"}), true, "hello without data")
eq(K.clientHello({action = "floorhello", data = {v = 0}}), false, "version 0")
eq(K.clientHello({action = "query", data = {cid = 1}}), false, "the monster bar's query is no hello")
eq(K.clientHello(nil), false, "junk")
local st6 = K.newState()
K.setCapable(st6, 4, true)
eq(K.isCapable(st6, 4), true, "capable")
K.open(st6, "z", sq(1, 1, 1, 1), 2000, 0, cfg)
K.plan(st6, function() return {[4] = true} end, 0)
K.forget(st6, 4)
eq(K.isCapable(st6, 4), false, "forgotten on logout")
eq(#K.plan(st6, function() return {[4] = true} end, 10), 1, "and sent again if it logs in and says hello again")

-- ------------------------------------------------------------------ the sprite marks: who gets them
eq(K.spriteMode(0, 0), "all", "nobody near: the effects go out as before")
eq(K.spriteMode(0, 3), "all", "nobody has the module: exactly as before")
eq(K.spriteMode(2, 0), "none", "everybody has it: no sprite pulses")
eq(K.spriteMode(1, 1), "some", "mixed: the ones without it get theirs")

-- ------------------------------------------------------------------ the glue against a mocked engine
local clock = 0
os.mtime = function() return clock end
local events, globals = {}, {}
function CreatureEvent(name)
	local e = {name = name}
	function e:type(t) self.kind = t end
	function e:register() events[self.name] = self end
	return e
end
function GlobalEvent(name)
	local e = {name = name}
	function e:interval(ms) self.ms = ms end
	function e:register() globals[self.name] = self end
	return e
end
local effects = {} -- every sendMagicEffect: {x, y, z, id, who}
function Position(x, y, z)
	local p = {x = x, y = y, z = z}
	function p:sendMagicEffect(id, who)
		effects[#effects + 1] = {x = self.x, y = self.y, z = self.z, id = id, who = who and who.cid or nil}
	end
	return p
end
json = {
	encode = function(t) return t end, -- the mock keeps the table so the test can read it
	decode = function(s)
		if type(s) == "table" then return s end
		if s == "hello" then return {action = "floorhello", data = {v = 1}} end
		if s == "query" then return {action = "query", data = {cid = 1}} end
		error("bad json")
	end
}
local players = {}
local function mkPlayer(cid, x, y, z)
	local p = {cid = cid, pos = {x = x, y = y, z = z}, sent = {}, events = {}}
	function p:getId() return self.cid end
	function p:getPosition() return self.pos end
	function p:registerEvent(n) self.events[#self.events + 1] = n end
	function p:sendExtendedOpcode(op, payload) self.sent[#self.sent + 1] = {op = op, msg = payload} end
	players[cid] = p
	return p
end
function Player(k)
	return players[k]
end
Game = Game or {}
function Game.getSpectators(pos, multi, onlyPlayers, minX, maxX, minY, maxY)
	local list = {}
	for _, p in pairs(players) do
		if p.pos.z == pos.z and math.abs(p.pos.x - pos.x) <= maxX and math.abs(p.pos.y - pos.y) <= maxY then
			list[#list + 1] = p
		end
	end
	table.sort(list, function(a, c) return a.cid < c.cid end)
	return list
end

dofile("data/scripts/chaos/telegraph.lua")
local T = ChaosTelegraph
ok(globals.ChaosTelegraph and globals.ChaosTelegraph.ms == cfg.tickMs, "loop every tickMs")
ok(events.ChaosTelegraphLogin and events.ChaosTelegraphLogin.kind == "login", "login event")
ok(events.ChaosTelegraphLogout and events.ChaosTelegraphLogout.kind == "logout", "logout event")
ok(events.ChaosTelegraphOpcode and events.ChaosTelegraphOpcode.kind == "extendedopcode", "opcode event")

local ann = mkPlayer(1, 100, 100, 7) -- has the module
local bob = mkPlayer(2, 103, 100, 7) -- does not
local cat = mkPlayer(3, 100, 100, 6) -- another floor, has the module
local far = mkPlayer(4, 300, 100, 7) -- far away, has the module
for _, p in ipairs({ann, bob, cat, far}) do
	events.ChaosTelegraphLogin.onLogin(p)
end
ok(ann.events[1] == "ChaosTelegraphOpcode" and ann.events[2] == "ChaosTelegraphLogout", "login registers the events")
for _, p in ipairs({ann, cat, far}) do
	events.ChaosTelegraphOpcode.onExtendedOpcode(p, 125, "hello")
end
events.ChaosTelegraphOpcode.onExtendedOpcode(bob, 125, "query") -- the monster bar's own question is no hello
eq(K.isCapable(T.state, 1), true, "Ann said hello")
eq(K.isCapable(T.state, 2), false, "Bob did not")
events.ChaosTelegraphOpcode.onExtendedOpcode(bob, 124, "hello")
eq(K.isCapable(T.state, 2), false, "a hello on another opcode is ignored")
events.ChaosTelegraphOpcode.onExtendedOpcode(bob, 125, "junk")
eq(K.isCapable(T.state, 2), false, "junk is ignored")

clock = 1000
local mark = T.open("bm:1:1", sq(99, 99, 101, 101), {ms = 2000, user = "bossMechanics"})
ok(mark ~= nil, "open")
eq(#ann.sent, 1, "Ann gets the area at once")
eq(ann.sent[1].op, 125, "on the monster bar's opcode")
eq(ann.sent[1].msg.action, "floor", "action floor")
eq(ann.sent[1].msg.data.id, "bm:1:1", "the id")
eq(#ann.sent[1].msg.data.t, 9, "nine tiles")
eq(ann.sent[1].msg.data.ms, 2000, "two seconds")
eq(#bob.sent, 0, "Bob has no module: nothing")
eq(#cat.sent, 0, "another floor: nothing")
eq(#far.sent, 0, "too far: nothing")
-- the sprite pulse: Bob gets the sprites, Ann does not
effects = {}
local calls = 0
T.draw(mark, function(who)
	calls = calls + 1
	Position(100, 100, 7):sendMagicEffect(1, who)
end)
eq(calls, 1, "one call, for the one player near who has no module")
eq(effects[1].who, 2, "it is Bob")
-- nobody near has the module: the call is for everybody (who = nil)
local lone = mkPlayer(9, 500, 500, 7)
events.ChaosTelegraphLogin.onLogin(lone)
local m2 = T.open("x:1", sq(500, 500, 502, 502), {ms = 2000})
effects = {}
calls = 0
T.draw(m2, function(who)
	calls = calls + 1
	eq(who, nil, "who is nil when nobody near has the module")
end)
eq(calls, 1, "once, for everybody")
-- everybody near has the module: no call
local alone = mkPlayer(10, 700, 700, 7)
events.ChaosTelegraphLogin.onLogin(alone)
events.ChaosTelegraphOpcode.onExtendedOpcode(alone, 125, "hello")
local m3 = T.open("y:1", sq(700, 700, 702, 702), {ms = 2000})
calls = 0
T.draw(m3, function() calls = calls + 1 end)
eq(calls, 0, "no sprite pulses when every player near has the module")
-- no mark (the switch off, too big a shape): the pulse is for everybody
calls = 0
T.draw(nil, function(who)
	calls = calls + 1
	eq(who, nil, "no mark: everybody")
end)
eq(calls, 1, "once")
eq(T.open("z:1", {}, {ms = 2000}), nil, "no tiles: no mark")
eq(T.open("z:1", sq(1, 1, 20, 20), {ms = 2000}), nil, "too many tiles: no mark")
eq(T.open("z:1", sq(1, 1, 2, 2), {ms = 2000, user = "nobody"}) ~= nil, true, "an unknown user key is not a switch")
Chaos.telegraphConfig.uber = false
eq(T.open("z:2", sq(1, 1, 2, 2), {ms = 2000, user = "uber"}), nil, "a user turned off in the config")
Chaos.telegraphConfig.uber = true
Chaos.telegraphConfig.enabled = false
eq(T.open("z:3", sq(1, 1, 2, 2), {ms = 2000}), nil, "the switch off")
Chaos.telegraphConfig.enabled = true
-- effectTo: a stock effect by name and by number, one player
effects = {}
T.effectTo(bob, {x = 5, y = 6, z = 7}, nil, "CONST_ME_MAGIC_RED")
CONST_ME_MAGIC_RED = 11
T.effectTo(bob, {x = 5, y = 6, z = 7}, nil, "CONST_ME_MAGIC_RED")
T.effectTo(bob, {x = 5, y = 6, z = 7}, nil, 12)
ChaosVfx = {warning_zone = {id = 451, dx = 1, dy = 1}}
T.effectTo(bob, {x = 5, y = 6, z = 7}, "warning_zone", 13)
eq(#effects, 3, "an unknown global name sends nothing; the other three do")
eq(effects[1].id, 11, "the stock constant by name")
eq(effects[2].id, 12, "the stock constant by number")
eq(effects[3].id .. "," .. effects[3].x .. "," .. effects[3].y, "451,6,7", "the named effect at its offset tile")
eq(effects[3].who, 2, "to that one player")
eq(T.effectTo(nil, {x = 1, y = 1, z = 7}, nil, 5), false, "no player: nothing")
-- the circle for one player: the big circle at the centre, the offset of its id
ChaosVfx.big_telegraph_5 = {id = 635, dx = 2, dy = 2}
ChaosBigFx = {live = function() return true end, circleOf = function(tiles) return {x = 100, y = 100, z = 7}, 5 end}
effects = {}
ok(T.circleTo(bob, sq(98, 98, 102, 102), false), "a circle")
eq(effects[1].id .. "," .. effects[1].x, "635,102", "the big warning circle, at its offset")
ChaosBigFx.circleOf = function() return nil end
eq(T.circleTo(bob, sq(98, 98, 102, 102), false), false, "not round: no circle")
ChaosBigFx = nil

-- the move of a follow circle: Ann gets the whole area again
local n0 = #ann.sent
ok(T.move(mark, sq(102, 99, 104, 101)), "move")
eq(#ann.sent, n0 + 1, "the new area is sent")
eq(ann.sent[#ann.sent].msg.data.x0, 102, "the new origin")
eq(T.move({id = "nope"}, sq(1, 1, 1, 1)), false, "a mark that is not there")
eq(T.move(nil, sq(1, 1, 1, 1)), false, "no mark")

-- a player who walks into view later gets the mark on the next tick; one who walks away is told to clear
local dan = mkPlayer(5, 100, 100, 7)
events.ChaosTelegraphLogin.onLogin(dan)
events.ChaosTelegraphOpcode.onExtendedOpcode(dan, 125, "hello") -- the hello sends what is up near it at once
eq(#dan.sent, 1, "hello: the marks up near it are sent")
clock = 1250
dan.pos = {x = 300, y = 300, z = 7}
globals.ChaosTelegraph.onThink(250)
eq(dan.sent[#dan.sent].msg.action, "floorclear", "walked away: clear")
dan.pos = {x = 101, y = 100, z = 7}
globals.ChaosTelegraph.onThink(250)
eq(dan.sent[#dan.sent].msg.action, "floor", "back: the area")
ok(dan.sent[#dan.sent].msg.data.ms <= 1750, "with the time that is left")

-- the hit time passes: the clear goes to everyone who has it, once
local annBefore = #ann.sent
clock = 1000 + 2000 + cfg.graceMs
globals.ChaosTelegraph.onThink(250)
eq(ann.sent[#ann.sent].msg.action, "floorclear", "Ann: cleared at the hit")
eq(ann.sent[#ann.sent].msg.data.id, "bm:1:1", "the mark")
eq(#ann.sent, annBefore + 1, "once")
globals.ChaosTelegraph.onThink(250)
eq(#ann.sent, annBefore + 1, "and not again")
eq(T.state.marks["bm:1:1"], nil, "the server dropped it")

-- the end of a fight: closePrefix clears the fight's marks
clock = 5000
local f1 = T.open("bm:7:1", sq(99, 99, 100, 100), {ms = 3000})
T.open("bm:7:2", sq(101, 99, 102, 100), {ms = 3000})
T.open("bm:70:1", sq(101, 101, 102, 102), {ms = 3000})
local before = #ann.sent
T.closePrefix("bm:7:")
eq(#ann.sent, before + 2, "Ann is told to clear both marks of the fight")
ok(T.state.marks["bm:70:1"] ~= nil, "another fight's mark stays")
T.close("bm:70:1")
ok(f1 ~= nil, "the first handle was returned")

-- logout: nothing is kept
events.ChaosTelegraphLogout.onLogout(ann)
eq(K.isCapable(T.state, 1), false, "Ann is forgotten on logout")

-- the opcode of the hello is the monster bar's
eq(ChaosOpcodes.monsterbar, 125, "still 125")

print(string.format("telegraph_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
