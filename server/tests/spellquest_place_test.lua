-- Run from the server/ folder: luajit tests/spellquest_place_test.lua (and lua5.3; CI runs both)
-- Archivist Odrenna's placement at the startup (spellquest.lua placeStartup, npc_place.lua create; O579). Before: one unguarded
-- timer (an error in it was a "Lua Script Error ... in a timer event"), one try, and a stall tile that took no NPC left the
-- hub without her (the placement returned nil and nothing looked again). Now: the timer never throws, a busy stall tile gets the
-- engine's nearest free tile, an Archivist still missing is asked for again a few times, and ONE line says how it went.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		io.stdout:write("FAIL " .. label .. "\n")
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/spellquest_core.lua")

local registered = {}
local function eventMock(name)
	local e = setmetatable({name = name}, {__index = function() return function() end end})
	e.register = function(self) registered[#registered + 1] = self end
	return e
end
CreatureEvent, GlobalEvent, TalkAction = eventMock, eventMock, eventMock
EventCallback = setmetatable({}, {__index = function() return function() end end})

local timers = {}
function addEvent(fn, ms, ...)
	timers[#timers + 1] = {fn = fn, ms = ms, args = {...}, n = select("#", ...)}
	return #timers
end
local function fire(t)
	return pcall(t.fn, (table.unpack or unpack)(t.args, 1, t.n))
end
local printed = {}
local realPrint = print
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end
	printed[#printed + 1] = table.concat(parts, " ")
end

Game = {getSpectators = function() return {} end, getPlayers = function() return {} end}
dofile("data/lib/chaos_spell_events.lua")
ChaosTrials = {runs = {}}
-- ChaosNpcPlace is the real file (npc_place.lua) on a mocked engine: the stall (booth) of the hub, the tile that takes no NPC
local placedNpcs, refuse = {}, {}
local function npcAt(name, pos)
	local n = {name = name, pos = pos}
	function n:getName() return self.name end
	function n:getPosition() return self.pos end
	function n:isNpc() return true end
	placedNpcs[#placedNpcs + 1] = n
	return n
end
local createCalls = {}
Game.createNpc = function(name, pos, extended)
	createCalls[#createCalls + 1] = {name = name, pos = pos, extended = extended}
	if name == "Broken" then
		return nil -- the NPC's file did not load
	end
	local key = pos.x .. "," .. pos.y
	if refuse[key] and not extended then
		return nil
	end
	if refuse[key] == "all" then
		return nil
	end
	return npcAt(name, extended and {x = pos.x + 1, y = pos.y, z = pos.z} or pos)
end
Position = function(x, y, z) return {x = x, y = y, z = z} end
CONST_PROP_BLOCKSOLID, CONST_PROP_BLOCKPATH, TILESTATE_TELEPORT, TILESTATE_FLOORCHANGE = 1, 2, 3, 4
dofile("data/scripts/chaos/npc_place.lua")
local NP = ChaosNpcPlace

-- ---------------------------------------------------------------- NP.create: the engine's nearest free tile
do
	local npc = NP.create("Stall Keeper", {x = 10, y = 10, z = 7})
	check(npc and npc:getPosition().x == 10, "a free tile: the NPC stands there")
	eq(#createCalls, 1, "one engine call")
	refuse["20,20"] = true
	createCalls = {}
	local before = #printed
	npc = NP.create("Stall Keeper", {x = 20, y = 20, z = 7})
	check(npc and npc:getPosition().x == 21, "a busy tile: the engine's extended search puts her next to it")
	check(createCalls[2] and createCalls[2].extended == true, "the second call asks for the extended search")
	eq(#printed, before + 1, "one line says so")
	check(printed[#printed]:find("took no NPC, placed at 21,20,7", 1, true) ~= nil, "naming the tile and where she stands")
	NP.create("Stall Keeper", {x = 20, y = 20, z = 7})
	eq(#printed, before + 1, "and it is not printed again for the same NPC and tile")
	refuse["30,30"] = "all"
	before = #printed
	check(NP.create("Stall Keeper", {x = 30, y = 30, z = 7}) == nil, "no tile at all: nil")
	check(printed[#printed]:find("error: Stall Keeper cannot be placed at 30,30,7", 1, true) ~= nil, "with an error line that names the XML")
	check(NP.create("Broken", {x = 1, y = 1, z = 7}) == nil, "an NPC that cannot be made: nil")
end

-- ---------------------------------------------------------------- the stall of the hub: a busy stall falls back to the search round the temple
do
	-- the booth path: ChaosNpcBoothsCore answers a spot for the temple; a mocked core stands in for npc_booths_core.lua
	Tile = function() -- open land everywhere
		return {getGround = function() return true end, hasFlag = function() return false end,
			hasProperty = function() return false end, getHouse = function() return nil end,
			getItems = function() return {} end, getTopCreature = function() return nil end}
	end
	ChaosNpcBoothsCore = {cfg = function() return {} end, spotForTemple = function(_, name, temple)
		if name == "Stall Odrenna" then
			return {x = 40, y = 40, z = 7}
		end
	end}
	refuse["40,40"] = "all"
	createCalls = {}
	local npc = NP.place("Stall Odrenna", {x = 100, y = 100, z = 7}, {}, {})
	check(createCalls[1] and createCalls[1].pos.x == 40 and createCalls[1].extended == nil, "the stall tile is tried first")
	check(createCalls[2] and createCalls[2].extended == true, "then the engine's nearest free tile")
	check(createCalls[3] ~= nil and createCalls[3].pos.x ~= 40, "then the search round the temple (the old code returned nil here)")
	refuse["40,40"] = nil
	ChaosNpcBoothsCore = nil
end

-- ---------------------------------------------------------------- the startup
CreatureEvent, GlobalEvent, TalkAction = eventMock, eventMock, eventMock
dofile("data/scripts/chaos/spellquest.lua")
local S = ChaosSpellQuest
local startup
for _, e in ipairs(registered) do
	if e.name == "ChaosSpellQuestStartup" then
		startup = e
	end
end
check(startup and startup.onStartup, "the startup event is registered")
eq(S.archivistsWanted(), 1, "one Archivist wanted (town 2)")

local temple = {x = 100, y = 100, z = 7}
Town = function(id) return {getTemplePosition = function() return temple end} end
local placeCalls, answers = 0, {}
local realPlace = NP.place
NP.place = function()
	placeCalls = placeCalls + 1
	local a = answers[placeCalls]
	if a == "error" then
		error("attempt to index a nil value")
	end
	return a and {npc = true} or nil
end

local function startupRun(plan)
	timers, printed, placeCalls, answers = {}, {}, 0, plan
	startup.onStartup()
	local rounds = 0
	while #timers > 0 and rounds < 10 do
		local t = table.remove(timers, 1)
		local ok, err = fire(t)
		check(ok, "the placement timer never throws (" .. tostring(err) .. ")")
		rounds = rounds + 1
	end
	return rounds
end

-- placed at once: one timer, one line
local rounds = startupRun({true})
eq(rounds, 1, "placed at the first try: one timer")
eq(#printed, 1, "one line")
check(printed[1]:find("1 of 1 Archivist Odrenna placed", 1, true) ~= nil and not printed[1]:find("try", 1, true), "the line: 1 of 1 placed")

-- an error in the placement: caught, tried again, placed on the third try
rounds = startupRun({"error", false, true})
eq(rounds, 3, "an error and a miss: asked again twice")
eq(placeCalls, 3, "three placements")
eq(#printed, 2, "the miss is printed once, then ONE line for the result")
check(printed[1]:find("could not place Archivist Odrenna in town 2", 1, true) ~= nil, "the miss of the town is named")
check(printed[2]:find("1 of 1 Archivist Odrenna placed (try 3)", 1, true) ~= nil, "the result line says on which try")

-- an error outside the engine call (here: the town lookup) is caught by the timer itself
local realTown, townCalls = Town, 0
Town = function(id)
	townCalls = townCalls + 1
	if townCalls == 1 then
		error("boom in the town lookup")
	end
	return realTown(id)
end
rounds = startupRun({true})
Town = realTown
eq(rounds, 2, "an error in the timer: the timer does not throw, it asks again")
check(printed[1] and printed[1]:find("placement error: ", 1, true) and printed[1]:find("boom in the town lookup", 1, true), "the error is named")
check(printed[2] and printed[2]:find("1 of 1 Archivist Odrenna placed (try 2)", 1, true) ~= nil, "and she is placed on the second try")

-- never placed: the last try says so, and it stops after PLACE_TRIES
rounds = startupRun({false, false, false, false, false, false})
eq(rounds, S.PLACE_TRIES, "it stops after the last try")
check(printed[#printed]:find("0 of 1 Archivist Odrenna placed (try " .. S.PLACE_TRIES .. ")", 1, true) ~= nil, "0 of 1, after the tries")
local couldNot = 0
for _, line in ipairs(printed) do
	if line:find("could not place Archivist Odrenna in town 2", 1, true) then
		couldNot = couldNot + 1
	end
end
check(couldNot <= 1, "the miss of the town is printed once, not at every try (" .. couldNot .. ")")

-- the retry timer is the engine's addEvent with the attempt number
startupRun({false})
startup.onStartup()
check(timers[1] and timers[1].ms == 1100 and timers[1].args[1] == 1, "the first timer: 1100 ms, attempt 1")
placeCalls, answers, printed = 0, {false}, {}
fire(table.remove(timers, 1))
check(timers[1] and timers[1].ms == S.PLACE_RETRY_MS and timers[1].args[1] == 2, "the retry: the pause and attempt 2")

NP.place = realPlace
print = realPrint
print(string.format("spellquest_place_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
