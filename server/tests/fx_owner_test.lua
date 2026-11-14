-- Run from the server/ folder: luajit tests/fx_owner_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the effect owner marks (data/lib/chaos_fx_owner.lua, data/scripts/chaos/fxowner.lua, the hook in data/spells/chaos/
-- _supports.lua; O567): the opcode (free: not in the reference server, the reference client, ChaosOpcodes, the client modules but
-- game_effectopacity), the storage, the pure buffer (offsets, floors, repeats, the cap, ids), the glue on a mocked engine (the
-- wrappers of Position:sendMagicEffect / sendDistanceEffect pass every call on unchanged, only a player's spell context is noted,
-- only for a client that wants marks, one message a tick, the wish read once a second, hello on and off, a forced owner, a nest),
-- and that the client's list of warning ids holds every telegraph / warning / danger effect the server has.
dofile("data/scripts/chaos/chaos_constants.lua")

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
local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- ------------------------------------------------------------------ opcode and storage
eq(ChaosOpcodes.fxOwner, 164, "opcode 164")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(seen[v] == nil, "opcode " .. tostring(v) .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, -- the reference server
		126, 127, -- its NPC scripts' currency opcodes
		140, 144, 145, 146, 210, 212, 213, 230, 246}) do -- the reference client's own ExtendedIds
	ok(ChaosOpcodes.fxOwner ~= v, "not an opcode of the reference server or client: " .. v)
end
-- no other client module names 164 as an opcode
local ls = io.popen("ls ../client/overlay/modules 2>/dev/null")
local others = 0
for dir in ls:lines() do
	if dir ~= "game_effectopacity" then
		local ph = io.popen("ls ../client/overlay/modules/" .. dir .. "/*.lua 2>/dev/null")
		for file in ph:lines() do
			local s = readFile(file)
			if s and not file:find("_test.lua", 1, true) and (s:find("[Oo]pcode[%w_]*%s*=%s*164%f[%D]") or s:find("xtended[%w]*Opcode%(%s*164%f[%D]")) then
				others = others + 1
				print("opcode 164 in " .. file)
			end
		end
		ph:close()
	end
end
ls:close()
eq(others, 0, "no other client module on 164")
dofile("../client/overlay/modules/game_effectopacity/effectopacitylogic.lua")
eq(EffectOpacityLogic.OPCODE, 164, "the client module listens on 164")
-- the other Chaos scripts: no other file sends or reads 164 by number
local ps = io.popen("ls data/scripts/chaos/*.lua")
local usedBy = {}
for file in ps:lines() do
	local s = readFile(file)
	if s and not file:find("chaos_constants.lua", 1, true) and not file:find("fxowner.lua", 1, true)
		and (s:find("[Oo]pcode[%w_]*%s*=%s*164%f[%D]") or s:find("sendExtendedOpcode%(%s*164%f[%D]")) then
		usedBy[#usedBy + 1] = file
	end
end
ps:close()
eq(#usedBy, 0, "no other script on 164: " .. table.concat(usedBy, ", "))

eq(Chaos.storage.fxOwner, 7103120, "storage 7103120")
for k, v in pairs(Chaos.storage) do
	if k ~= "fxOwner" and type(v) == "number" then
		ok(v < 7103120 or v > 7103129, "storage block 7103120 - 7103129 is free of " .. k)
	end
end

-- ------------------------------------------------------------------ the lib
dofile("data/lib/chaos_fx_owner.lua")
local C = ChaosFxOwner
eq(C.OPCODE, ChaosOpcodes.fxOwner, "the lib's opcode is the constant")
eq(C.STORAGE, Chaos.storage.fxOwner, "the lib's storage is the constant")
eq(C.cfg.maxMarks <= EffectOpacityLogic.MAX_MARKS, true, "the server never sends more marks than the client reads")
eq(C.cfg.maxOffset <= EffectOpacityLogic.MAX_OFFSET, true, "offsets inside what the client reads")

-- pure: key, buffer, add, payload
eq(C.key(0, 1, -2, 3000), "0:1:-2:3000", "key")
eq(C.payload(C.newBuffer(1, 2, 7)), nil, "an empty buffer has no payload")
eq(C.payload(nil), nil, "no buffer, no payload")
do
	local b = C.newBuffer(32000, 32100, 7)
	ok(C.add(b, 0, 32000, 32100, 7, 3001), "the first tile")
	ok(C.add(b, 0, 32001, 32099, 7, 3001), "a neighbour")
	ok(not C.add(b, 0, 32001, 32099, 7, 3001), "a repeat is refused")
	ok(C.add(b, 1, 32001, 32099, 7, 3001), "the same tile and id as a missile is another mark")
	ok(not C.add(b, 0, 32000, 32100, 6, 5), "another floor")
	ok(not C.add(b, 0, 32000 + 128, 32100, 7, 5), "128 tiles away")
	ok(C.add(b, 0, 32000 + 127, 32100 - 127, 7, 5), "127 tiles away is fine")
	ok(not C.add(b, 0, 32000, 32100, 7, 0), "id 0")
	ok(not C.add(b, 0, 32000, 32100, 7, nil), "no id")
	ok(not C.add(b, 0, 32000, 32100, 7, 70000), "id over 16 bit")
	ok(not C.add(b, 0, 32000, 32100, 7, 12.5), "a fraction")
	ok(not C.add(nil, 0, 1, 2, 7, 5), "no buffer")
	local p = C.payload(b)
	eq(p.b[1], 32000, "base x"); eq(p.b[2], 32100, "base y"); eq(p.b[3], 7, "base z")
	eq(#p.m, 16, "four marks of four numbers")
	eq(p.m[5], 0, "kind"); eq(p.m[6], 1, "dx"); eq(p.m[7], -1, "dy"); eq(p.m[8], 3001, "id")
	eq(p.m[12], 3001, "the missile mark")
	eq(p.m[9], 1, "its kind is 1")
	-- what the client reads is what this makes
	local x, y, z, flat = EffectOpacityLogic.parseMarks({action = "marks", data = p})
	eq(x, 32000, "the client reads x"); eq(z, 7, "z"); eq(#flat, 16, "all four marks")
end
do
	local b = C.newBuffer(100, 100, 7)
	local added = 0
	for i = 1, 1000 do
		if C.add(b, 0, 100 + (i % 50), 100 + math.floor(i / 50) % 50, 7, 1 + (i % 7)) then
			added = added + 1
		end
	end
	eq(b.n, C.cfg.maxMarks, "the buffer stops at maxMarks")
	eq(added, C.cfg.maxMarks, "and said so")
	ok(not C.add(b, 0, 100, 100, 7, 4000), "a full buffer refuses")
end

-- ------------------------------------------------------------------ the glue on a mocked engine
local clock = 1000
local realTime = os.time
os.time = function() return clock end
local events = {}
local function runEvents()
	local list = events
	events = {}
	for _, e in ipairs(list) do
		e.fn(unpack and unpack(e.args) or table.unpack(e.args))
	end
end
-- the engine's addEvent as captured by the lib: reload it with a mock
addEvent = function(fn, delay, ...)
	events[#events + 1] = {fn = fn, delay = delay, args = {...}}
	return #events
end
ChaosFxOwner = nil
dofile("data/lib/chaos_fx_owner.lua")
C = ChaosFxOwner

local storageReads = 0
local players = {}
local function newPlayer(id)
	local p = {id = id, storage = {}, sent = {}}
	function p:getId() return self.id end
	function p:getStorageValue(k) storageReads = storageReads + 1; return self.storage[k] or -1 end
	function p:setStorageValue(k, v) if v == -1 then self.storage[k] = nil else self.storage[k] = v end end
	function p:sendExtendedOpcode(op, buf) self.sent[#self.sent + 1] = {op = op, buf = buf} end
	players[id] = p
	return p
end
Player = function(id) return players[id] end
-- no json in the plain interpreter: the lib sends through C.send, which a test replaces
local messages = {}
function C.send(player, data)
	messages[#messages + 1] = {pid = player:getId(), data = data}
	return true
end

local calls = {}
Position = {
	sendMagicEffect = function(self, effect, ...) calls[#calls + 1] = {"magic", self, effect, ...}; return true end,
	sendDistanceEffect = function(self, to, effect, ...) calls[#calls + 1] = {"missile", self, to, effect, ...}; return true end,
}
local function pos(x, y, z) return {x = x, y = y, z = z} end

-- the caster stub of the spell side: ChaosSupportsSpell.cast() -> player id, spell id
local caster
ChaosSupportsSpell = {cast = function() if caster then return caster, 1 end return nil end}

eq(C.owner(), nil, "no owner outside a cast")
ok(C.install(Position), "installs")
ok(not C.install(Position), "only once")
local installedMagic = Position.sendMagicEffect
C.install(Position)
eq(Position.sendMagicEffect, installedMagic, "a second install keeps the first wrappers")

local a = newPlayer(1)
local b = newPlayer(2)

-- every call goes on unchanged
caster = nil
local r = Position.sendMagicEffect(pos(10, 10, 7), 3001, "x")
eq(r, true, "the result is the raw call's")
eq(calls[#calls][1], "magic", "the raw call ran")
eq(calls[#calls][3], 3001, "with the effect")
eq(calls[#calls][4], "x", "and the extra argument")
Position.sendDistanceEffect(pos(10, 10, 7), pos(14, 10, 7), 12, "y")
eq(calls[#calls][1], "missile", "the raw missile call ran")
eq(calls[#calls][4], 12, "with the missile id")
eq(calls[#calls][5], "y", "and the extra argument")
eq(#events, 0, "outside a cast: nothing scheduled")
eq(#messages, 0, "outside a cast: no message")

-- a cast of a player who does not want marks: nothing, and the storage is read once for many effects
caster = 1
storageReads = 0
for i = 1, 40 do Position.sendMagicEffect(pos(10 + i % 5, 10, 7), 3001) end
eq(storageReads, 1, "the wish is read once for 40 effects")
eq(#events, 0, "no event for a player who wants nothing")
runEvents()
eq(#messages, 0, "no message for a player who wants nothing")
eq(#calls > 40, true, "all 40 effects were sent")

-- the player says hello need 1
C.setNeed(a, true)
eq(a.storage[C.STORAGE], 1, "the storage says 1")
caster = 1
local before = #calls
Position.sendMagicEffect(pos(100, 200, 7), 3001)
Position.sendMagicEffect(pos(101, 200, 7), 3001)
Position.sendMagicEffect(pos(101, 200, 7), 3001) -- a repeat
Position.sendMagicEffect(pos(100, 201, 7), 3002)
Position.sendDistanceEffect(pos(100, 200, 7), pos(104, 200, 7), 12)
Position.sendMagicEffect(pos(100, 200, 6), 3001) -- another floor
eq(#calls - before, 6, "all six calls went on")
eq(#events, 1, "one flush scheduled for the tick")
eq(events[1].delay, 0, "now (the next dispatcher tick)")
eq(#messages, 0, "nothing sent before the tick ends")
runEvents()
eq(#messages, 1, "one message")
eq(messages[1].pid, 1, "to the caster")
local m = messages[1].data
eq(m.b[1], 100, "base x"); eq(m.b[2], 200, "base y"); eq(m.b[3], 7, "base z")
eq(#m.m, 16, "four marks: three effects and a missile; the repeat and the other floor are dropped")
eq(m.m[1], 0, "first is an effect"); eq(m.m[4], 3001, "its id")
eq(m.m[6], 1, "dx of the second"); eq(m.m[9], 0, "third kind"); eq(m.m[11], 1, "dy of the third"); eq(m.m[12], 3002, "its id")
eq(m.m[13], 1, "the missile kind"); eq(m.m[16], 12, "the missile id")
eq(#a.sent, 0, "the mock sender was used, not the player")
eq(C.bufs[1], nil, "the buffer is gone")
-- the next tick starts a new buffer
Position.sendMagicEffect(pos(300, 300, 7), 3001)
eq(#events, 1, "a new flush")
runEvents()
eq(#messages, 2, "a second message")
eq(messages[2].data.b[1], 300, "with its own base")

-- another player's effects are not noted for the first; this one wants nothing
caster = 2
Position.sendMagicEffect(pos(100, 200, 7), 3001)
eq(#events, 0, "player 2 wants nothing: no flush")
-- both want it, two casts in one tick give two messages
C.setNeed(b, true)
caster = 1
Position.sendMagicEffect(pos(1, 1, 7), 5)
caster = 2
Position.sendMagicEffect(pos(2, 2, 7), 6)
runEvents()
eq(#messages, 4, "one message each")
eq(messages[3].pid, 1, "first caster"); eq(messages[4].pid, 2, "second caster")
eq(messages[4].data.m[4], 6, "its own effect")

-- hello need 0 drops what is waiting
caster = 1
Position.sendMagicEffect(pos(5, 5, 7), 9)
C.setNeed(a, false)
eq(a.storage[C.STORAGE], nil, "the storage is -1 again")
runEvents()
eq(#messages, 4, "a wish withdrawn in the tick: nothing is sent")
Position.sendMagicEffect(pos(5, 5, 7), 9)
eq(#events, 0, "and nothing is noted now")

-- the wish is read again after a second
caster = 2
storageReads = 0
Position.sendMagicEffect(pos(7, 7, 7), 9)
runEvents()
C.wish[2] = nil
b.storage[C.STORAGE] = nil -- changed behind the cache (another Lua state)
Position.sendMagicEffect(pos(7, 7, 7), 9)
eq(#events, 0, "the cache is empty: the storage is read and says no")
b.storage[C.STORAGE] = 1
clock = clock + 1
Position.sendMagicEffect(pos(7, 7, 7), 9)
eq(#events, 1, "a second later the storage is read again and says yes")
runEvents()

-- a forced owner (a revscript's own effects) and its nesting
caster = nil
C.as(a, function() eq(C.owner(), 1, "forced owner") end)
eq(C.owner(), nil, "restored")
C.setNeed(a, true)
C.as(1, function()
	Position.sendMagicEffect(pos(50, 50, 7), 77)
	C.as(b, function() eq(C.owner(), 2, "nested owner") end)
	eq(C.owner(), 1, "outer owner back")
end)
runEvents()
eq(messages[#messages].pid, 1, "a forced owner is marked")
eq(messages[#messages].data.m[4], 77, "its effect")
local okErr = pcall(C.as, 1, function() error("boom") end)
eq(okErr, false, "an error in the function goes on")
eq(C.owner(), nil, "the owner is restored after an error")

-- bad positions and a player that left
caster = 1
Position.sendMagicEffect(nil, 5)
Position.sendMagicEffect("x", 5)
Position.sendMagicEffect({x = "a", y = 1, z = 7}, 5)
Position.sendMagicEffect(pos(9, 9, 7), nil)
runEvents()
local n = #messages
Position.sendMagicEffect(pos(9, 9, 7), 5)
players[1] = nil
runEvents()
eq(#messages, n, "the player left before the flush: nothing")
players[1] = a
C.forget(1)
eq(C.bufs[1], nil, "forgotten")
eq(C.wish[1], nil, "wish forgotten")

-- ------------------------------------------------------------------ wiring
local sup = readFile("data/spells/chaos/_supports.lua")
ok(sup and sup:find("data/lib/chaos_fx_owner.lua", 1, true), "_supports.lua loads the owner lib")
ok(sup and sup:find("ChaosFxOwner.install", 1, true), "_supports.lua installs the wrappers")
local glue = readFile("data/scripts/chaos/fxowner.lua")
ok(glue and glue:find("ChaosOpcodes.fxOwner", 1, true), "fxowner.lua reads the opcode")
ok(glue and glue:find("setNeed", 1, true), "fxowner.lua keeps the wish")
ok(glue and glue:find('"extendedopcode"', 1, true), "fxowner.lua listens on extended opcodes")

-- ------------------------------------------------------------------ the client's warning list holds every server warning effect
local names = {}
local function scan(path)
	local s = readFile(path)
	if not s then return end
	for name, id in s:gmatch("ChaosVfx%.([%w_]+)%s*=%s*{%s*id%s*=%s*(%d+)") do
		names[#names + 1] = {name = name, id = tonumber(id)}
	end
	for name, id in s:gmatch("\n%s*([%w_]+)%s*=%s*{%s*id%s*=%s*(%d+)") do
		names[#names + 1] = {name = name, id = tonumber(id)}
	end
end
local pf = io.popen("ls data/lib/chaos_vfx.lua data/lib/*fx_ids.lua 2>/dev/null")
for file in pf:lines() do scan(file) end
pf:close()
ok(#names > 100, "the effect tables were found (" .. #names .. ")")
local listed = {}
for _, id in ipairs(EffectOpacityLogic.WARNING_IDS) do listed[id] = true end
local warnings = 0
for _, e in ipairs(names) do
	if e.name:find("telegraph", 1, true) or e.name:find("warning", 1, true) or e.name:find("danger", 1, true) then
		warnings = warnings + 1
		ok(listed[e.id], "warning effect " .. e.name .. " (" .. e.id .. ") is in the client's WARNING_IDS")
	end
end
ok(warnings >= 8, "found the warning effects (" .. warnings .. ")")
local known = {}
for _, e in ipairs(names) do known[e.id] = true end
for _, id in ipairs(EffectOpacityLogic.WARNING_IDS) do
	ok(known[id], "WARNING_IDS holds an effect the server knows: " .. id)
end

os.time = realTime
print(string.format("fx_owner_test: %d checks, %d failures", checks, fails))
if fails > 0 then os.exit(1) end
