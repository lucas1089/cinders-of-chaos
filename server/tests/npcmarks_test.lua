-- Run from the server/ folder: luajit tests/npcmarks_test.lua (and lua5.3; CI runs both)
-- O415: the marks over the NPCs' heads, the engine side (poi.lua) on a mocked engine: the client's hello turns them on
-- (apart from the map markers), the whole list goes out once as a full reset, afterwards only differences, a quest
-- change that pokes sendMarks sends at once, the periodic check sends nothing when nothing changed, and logout and
-- "off" forget the character. The rules are in poi_core.lua (tests/poi_test.lua), the sources in tales_core.lua
-- (tests/tales_test.lua), spellquest.lua and ascension_quest.lua.
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

-- the engine: events are collected by name
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
json = {encode = function() return "{}" end}
Tile = function() return nil end
Position = function(x, y, z) return {x = x, y = y, z = z} end

dofile("data/scripts/chaos/chaos_constants.lua")
local sentMsgs = {}
Chaos.send = function(player, op, action, data) sentMsgs[#sentMsgs + 1] = {player = player, op = op, action = action, data = data} end
Chaos.sendChunked = function() end
Chaos.decode = function(buffer) return buffer end
Chaos.t = function(_, s) return s end

dofile("data/scripts/chaos/poi.lua")
-- the broken source below logs one line per check: keep the test output quiet
local realPrint, brokenLogged = print, 0
print = function(...)
	if tostring((...)):find("mark source broken", 1, true) then
		brokenLogged = brokenLogged + 1
		return
	end
	realPrint(...)
end
local I = ChaosPoi
check(I.sendMarks and I.markSources and I.addMarkSource, "poi.lua exposes the mark sources")

local online = {}
Player = function(id) return online[id] end
Game.getPlayers = function() local out = {} for _, p in pairs(online) do out[#out + 1] = p end return out end
local function mkPlayer(id)
	local p = {id = id}
	function p:getId() return self.id end
	function p:getGuid() return 9000 + self.id end
	function p:getPosition() return {x = 1, y = 1, z = 7} end
	function p:sendTextMessage() end
	return p
end
local ann = mkPlayer(1)
online[1] = ann

-- a source whose answer the test changes
local answer = {{npc = "Archivist Maelis", mark = "new"}}
I.addMarkSource("test", function() return answer end)
I.addMarkSource("broken", function() error("boom") end)

local function marksSent()
	local out = {}
	for _, m in ipairs(sentMsgs) do
		if m.action == "npcmarks" then
			out[#out + 1] = m
		end
	end
	return out
end

local ext = events.ChaosPoiExtended
check(ext and ext.onExtendedOpcode, "the extended opcode handler is registered")
local OP = ChaosOpcodes.mapMarkers

-- nothing before the client asks
I.sendMarks(ann)
eq(#marksSent(), 0, "not before the client's hello")

-- the hello with npcmarks = true, map markers off: the marks come anyway (their own switch)
ext.onExtendedOpcode(ann, OP, {action = "hello", data = {poi = false, party = false, npcmarks = true}})
local got = marksSent()
eq(#got, 1, "one message after the hello")
eq(got[1].data.full, true, "the whole list, as a reset")
eq(#got[1].data.set, 1, "one NPC"); eq(got[1].data.set[1].n, "Archivist Maelis", "Archivist Maelis"); eq(got[1].data.set[1].m, "new", "gold !")
check(I.markWatch[1] and not I.watch[1], "watched for marks, not for map markers")

-- nothing changed: the periodic check sends nothing
sentMsgs = {}
I.sendMarks(ann)
eq(#marksSent(), 0, "no change, nothing sent")

-- a quest step is ready: a difference of one NPC
answer = {{npc = "Archivist Maelis", mark = "ready"}, {npc = "Warden Ysolde", mark = "new"}}
I.sendMarks(ann)
got = marksSent()
eq(#got, 1, "one difference"); eq(got[1].data.full, false, "not a reset")
eq(#got[1].data.set, 2, "both changed or new"); eq(#got[1].data.clear, 0, "nothing gone")

-- one mark goes: it is cleared, the other is not sent again
sentMsgs = {}
answer = {{npc = "Archivist Maelis", mark = "ready"}}
I.sendMarks(ann)
got = marksSent()
eq(#got, 1, "one message"); eq(#got[1].data.set, 0, "the unchanged mark is not repeated")
eq(#got[1].data.clear, 1, "one cleared"); eq(got[1].data.clear[1], "Warden Ysolde", "Warden Ysolde")

-- the think event checks every watched character (questMs) and survives a broken source
sentMsgs = {}
answer = {}
local think = events.ChaosPoiThink
check(think and think.onThink, "the think event")
-- the check runs every cfg.questMs: make the clock believe it is due
local realTime = os.time
os.time = function() return realTime() + 3600 end
think.onThink(2000)
os.time = realTime
got = marksSent()
eq(#got, 1, "the periodic check sent the removal"); eq(got[1].data.clear[1], "Archivist Maelis", "cleared")

-- a second client asking again gets the whole list again (a reset), the off switch forgets the character
sentMsgs = {}
answer = {{npc = "Archivist Odrenna", mark = "locked"}}
ext.onExtendedOpcode(ann, OP, {action = "set", data = {npcmarks = true}})
got = marksSent()
eq(#got, 1, "set: npcmarks on again"); eq(got[1].data.full, true, "a reset"); eq(got[1].data.set[1].m, "locked", "grey !")
sentMsgs = {}
ext.onExtendedOpcode(ann, OP, {action = "set", data = {npcmarks = false}})
check(not I.markWatch[1] and not I.markSent[1], "off: forgotten")
I.sendMarks(ann)
eq(#marksSent(), 0, "and nothing sent")

-- logout forgets it too
ext.onExtendedOpcode(ann, OP, {action = "hello", data = {npcmarks = true}})
check(I.markWatch[1], "on again")
events.ChaosPoiLogout.onLogout(ann)
check(not I.markWatch[1] and not I.markSent[1], "logout forgets the character")

-- the real sources register themselves
for _, file in ipairs({"tales.lua", "spellquest.lua", "ascension_quest.lua"}) do
	local text = io.open("data/scripts/chaos/" .. file):read("*a")
	check(text:find("ChaosPoi.markSources.", 1, true), file .. " registers a mark source")
end

check(brokenLogged > 0, "a broken source is logged, not fatal")
print(string.format("npcmarks_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
print("npcmarks_test: OK")
