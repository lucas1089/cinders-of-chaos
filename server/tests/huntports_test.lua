-- Run from the server/ folder: luajit tests/huntports_test.lua (and lua5.3; CI runs both)
-- O568: the hunt teleports for the map markers. The pure list (ChaosHuntTeleportsCore.ports: one row per hunt of the
-- hall, the plans' camp portals and the base hunts' added ways back as the way out, sorted, off with the config) and
-- the engine side (poi.lua action huntports on a mocked engine): sent only when the client's hello / set says
-- huntports = true (a client that does not know it never does), once per ask, built again after a reload of the hunt
-- teleports, rate limited on `set`, nothing when the hunt teleports are not loaded.
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then
		n = n + 1
		rawset(t, k, n)
		return n
	end
end})

-- ------------------------------------------------------------------ the pure list
dofile("data/scripts/chaos/hunt_teleports_core.lua")
local H = ChaosHuntTeleportsCore
local cfg = dofile("data/scripts/chaos/hunt_teleports_config.lua")

local idx = {
	list = {
		{id = "widowmere", name = "Widowmere", level = {480, 640}, teleport = {x = 31638, y = 32258, z = 6},
			arrival = {x = 16000, y = 14400, z = 6}, exit = {x = 16010, y = 14410, z = 6},
			front = {x = 31638, y = 32257, z = 6}},
		{id = "alder", name = "Alder Fen", level = {10, 40}, teleport = {x = 31634, y = 32254, z = 7},
			arrival = {x = 15700, y = 14400, z = 7}}, -- no exit in the places file, no front: the room's
	},
	base = {
		{id = "base_7_31654_32254", name = "Rotworm", level = {20, 60}, teleport = {x = 31654, y = 32254, z = 7},
			arrival = {x = 32000, y = 32000, z = 8}, front = {x = 31654, y = 32255, z = 7}},
		{id = "base_7_31658_32254", name = "Troll", level = {5, 25}, teleport = {x = 31658, y = 32254, z = 7},
			arrival = {x = 32100, y = 32100, z = 8}, front = {x = 31658, y = 32255, z = 7}},
		{id = "broken", name = "Broken", level = {1, 2}}, -- no teleport: left out
	},
	returns = {{id = "base_7_31654_32254", name = "Rotworm", at = {x = 32001, y = 32001, z = 8},
		pos = {x = 32002, y = 32001, z = 8}, arrival = {x = 32000, y = 32000, z = 8}}},
}
local ports = H.ports(cfg, idx)
eq(#ports, 4, "four hunts: two plans, two base hunts; the one without a teleport is left out")
eq(ports[1].i, "alder", "sorted by id"); eq(ports[2].i, "base_7_31654_32254", "sorted: base first"); eq(ports[4].i, "widowmere", "sorted: last")
local w = ports[4]
eq(w.n, "Widowmere", "the name"); eq(w.l[1], 480, "band low"); eq(w.l[2], 640, "band high")
eq(w.t.x, 31638, "the hall teleport"); eq(w.f.y, 32257, "the tile in front of it (the places file's)")
eq(w.a.x, 16000, "the arrival"); eq(w.b.x, 16010, "a plan's camp portal is its way out")
local a = ports[1]
eq(a.f.y, 32255, "no front in the places file: the room's rule (below a north row teleport)")
eq(a.b, nil, "no way out known: none")
eq(ports[2].b.x, 32002, "a base hunt's added way back (its placed tile, not the `at` of the config)")
eq(ports[3].b, nil, "a base hunt whose way back is the map's own: none")
w.t.x = 1
eq(idx.list[1].teleport.x, 31638, "the rows are copies: the index is not changed")
eq(#H.ports({enabled = false}, idx), 0, "switched off: nothing")
eq(#H.ports(cfg, nil), 0, "no index: nothing")
eq(#H.ports(cfg, {}), 0, "empty index: nothing")
for _, p in ipairs(ports) do
	eq(p.f.z, p.t.z, p.i .. ": the front is on the teleport's floor")
end

-- ------------------------------------------------------------------ the engine side (poi.lua)
local events = {}
local function eventMock(name)
	local e = setmetatable({name = name}, {__index = function() return function() end end})
	e.register = function(self) events[name] = self end
	return e
end
CreatureEvent, GlobalEvent, TalkAction = eventMock, eventMock, eventMock
db = {query = function() return true end, storeQuery = function() return false end, asyncQuery = function() end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end}
result = {getString = function() return "" end, free = function() end}
Game = {getTowns = function() return {} end, getPlayers = function() return {} end, getSpectators = function() return {} end}
addEvent = function() return 0 end
local encoded = 0
json = {encode = function(t) encoded = encoded + 1 return t end}
Tile = function() return nil end
Position = function(x, y, z) return {x = x, y = y, z = z} end

dofile("data/scripts/chaos/chaos_constants.lua")
local chunks = {}
Chaos.send = function() end
Chaos.sendChunked = function(player, op, buffer) chunks[#chunks + 1] = {player = player, op = op, buffer = buffer} end
Chaos.decode = function(buffer) return buffer end
Chaos.t = function(_, s) return s end

dofile("data/scripts/chaos/poi.lua")
local I = ChaosPoi
check(I.sendHuntPorts, "poi.lua exposes sendHuntPorts")
local OP = ChaosOpcodes.mapMarkers
local ext = events.ChaosPoiExtended
check(ext and ext.onExtendedOpcode, "the extended opcode handler is registered")

local ann = {id = 1}
function ann:getId() return self.id end
function ann:getGuid() return 9001 end
function ann:getPosition() return {x = 1, y = 1, z = 7} end
function ann:sendTextMessage() end

-- the hunt teleports are not loaded: nothing, no error
ext.onExtendedOpcode(ann, OP, {action = "hello", data = {huntports = true}})
eq(#chunks, 0, "no hunt teleports loaded: nothing sent")

ChaosHuntTeleports = {idx = idx}
function ChaosHuntTeleports.ports() return H.ports(cfg, ChaosHuntTeleports.idx) end

-- a client that does not know huntports (the Unity client's hello): nothing
ext.onExtendedOpcode(ann, OP, {action = "hello", data = {poi = false, party = false, npcmarks = false}})
eq(#chunks, 0, "a hello without huntports gets none")
ext.onExtendedOpcode(ann, OP, {action = "hello", data = {huntports = false}})
eq(#chunks, 0, "huntports = false gets none")

-- the hello with huntports = true: one chunked message with the list
ext.onExtendedOpcode(ann, OP, {action = "hello", data = {huntports = true}})
eq(#chunks, 1, "one message after the hello")
eq(chunks[1].op, OP, "on the map marker opcode")
eq(chunks[1].buffer.action, "huntports", "the action")
eq(#chunks[1].buffer.data.ports, 4, "four hunts")
eq(chunks[1].buffer.data.ports[4].i, "widowmere", "the list, sorted")

-- asked again: the same buffer, built once
local built = encoded
ext.onExtendedOpcode(ann, OP, {action = "hello", data = {huntports = true}})
eq(#chunks, 2, "sent again on the next hello")
eq(encoded, built, "the buffer is kept while the hunt teleports are the same")

-- a reload of the hunt teleports (a new index): built again
ChaosHuntTeleports.idx = {list = {idx.list[1]}, base = {}, returns = {}}
ext.onExtendedOpcode(ann, OP, {action = "hello", data = {huntports = true}})
eq(encoded, built + 1, "built again for the new index")
eq(#chunks[3].buffer.data.ports, 1, "the new list")

-- a `set` is rate limited like the others; the hello is not
local allowed = false
ChaosRateLimit = {allow = function(_, key) check(key == "poi.ports", "its own rate limit key") return allowed end}
local before = #chunks
ext.onExtendedOpcode(ann, OP, {action = "set", data = {huntports = true}})
eq(#chunks, before, "a set that comes too soon is ignored")
allowed = true
ext.onExtendedOpcode(ann, OP, {action = "set", data = {huntports = true}})
eq(#chunks, before + 1, "a set that is allowed sends the list")
ext.onExtendedOpcode(ann, OP, {action = "set", data = {huntports = false}})
eq(#chunks, before + 1, "turning it off sends nothing (the client hides the markers)")
allowed = false
ext.onExtendedOpcode(ann, OP, {action = "hello", data = {huntports = true}})
eq(#chunks, before + 2, "the hello is not rate limited")

print(string.format("huntports_test: %d checks, %d failed", checks, failures))
if failures > 0 then
	os.exit(1)
end
