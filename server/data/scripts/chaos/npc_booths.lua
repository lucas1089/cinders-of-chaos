-- The Halls of Services: the engine side (npc_booths_core.lua holds the logic, npc_booths_config.lua the layout).
-- server/README.md "Halls of Services". Owner decision 2026-10-15: every Chaos NPC of Cinderhold (the main city) and of
-- Mirewake stands in a closed booth behind a counter, never wandering (their XML: walkinterval 0), grouped by service.
--
-- At startup, for every hall whose plan is on the map (install step contentareas; the arrival tile exists):
--   * the fixtures: stone counters, partitions and coal basins on the booth rows (stock items, action id
--     aid.fixture, placed again only where missing, so a restart or /reload adds nothing twice);
--   * the hall's exit portal (the plan's, action id 47951 of areagen.lua) gets aid.exit: it leads to the temple of the
--     hall's town;
--   * the way in: the Hall of Services Portal (aid.entry) next to the temple of the hall's town (cityportals.lua).
-- ChaosNpcBooths.spot(name, townId) / .spotForTemple(name, templePosition) give an NPC's booth; ChaosNpcPlace.place
-- (npc_place.lua) and the Keeper of Trials (trials.lua) use them, so the NPCs' own scripts place them there. Without a
-- hall on the map they return nil and the NPCs stand next to the temple as before.
-- Lua 5.1 / LuaJIT and 5.3. Assumed engine API (TFS 1.4): Tile, Game.createItem, Item:setActionId/setAttribute,
-- Game.getTowns, Town:getTemplePosition, MoveEvent, GlobalEvent.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosNpcBoothsCore or not ChaosNpcBoothsCore.rowTiles then
	dofile("data/scripts/chaos/npc_booths_core.lua")
end
if not ChaosCityPortals then
	dofile("data/scripts/chaos/cityportals.lua")
end

ChaosNpcBooths = ChaosNpcBooths or {}
local X = ChaosNpcBooths
local K = ChaosNpcBoothsCore
local EXIT_AID = 47951 -- areagen_config.lua aid.exit: the planned areas' exit portal

local function C()
	return K.cfg()
end

local function log(msg)
	print("[npc_booths] " .. msg)
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

-- a hall is there when its arrival tile is on the map
function X.hallReady(hall)
	if not hall or not C().enabled then
		return false
	end
	local a = hall.arrival or {0, 0, 0}
	local ok, tile = pcall(Tile, P(K.offset(hall, a[1], a[2], a[3])))
	return ok and tile ~= nil and tile:getGround() ~= nil
end

function X.spot(name, townId)
	local hall = K.hallOf(C(), townId)
	if not hall or not X.hallReady(hall) then
		return nil
	end
	local s = K.spot(C(), name, townId)
	return s and P(s) or nil
end

-- the town whose temple is at this position
function X.townAt(temple)
	if not temple then
		return nil
	end
	for _, town in ipairs(Game.getTowns() or {}) do
		local t = town:getTemplePosition()
		if t.x == temple.x and t.y == temple.y and t.z == temple.z then
			return town:getId()
		end
	end
	return nil
end

function X.spotForTemple(name, temple)
	local townId = X.townAt(temple)
	return townId and X.spot(name, townId) or nil
end

-- ------------------------------------------------------------------------------------------------ fixtures
local function hasItem(tile, id)
	return tile:getItemById(id) ~= nil
end

function X.placeFixtures(hall)
	local placed = 0
	for _, f in ipairs(K.fixtures(C(), hall)) do
		local tile = Tile(P(f))
		if not tile or not tile:getGround() then
			log(string.format("no floor for a %s at %d,%d,%d (hall %s)", f.kind, f.x, f.y, f.z, hall.plan))
		elseif not hasItem(tile, f.id) then
			local it = Game.createItem(f.id, 1, P(f))
			if it then
				it:setActionId(C().aid.fixture)
				placed = placed + 1
			end
		end
	end
	return placed
end

function X.retagExit(hall)
	local e = hall.exit
	local tile = e and Tile(P(K.offset(hall, e[1], e[2], e[3])))
	if not tile then
		return false
	end
	for _, it in ipairs(tile:getItems() or {}) do
		local aid = it:getActionId()
		if aid == EXIT_AID or aid == C().aid.exit then
			it:setActionId(C().aid.exit)
			return true
		end
	end
	return false
end

-- the way in, next to the temple: the Hall of Services Portal (cityportals.lua: the hall's `entryOffsets`, checked on
-- the base map, then `entry.offsets`; the first free tile; labelled and marked by cityportals_fx.lua)
function X.placeEntry(hall)
	local e = C().entry
	local offsets = {}
	for _, list in ipairs({hall.entryOffsets or {}, e.offsets}) do
		for _, o in ipairs(list) do
			offsets[#offsets + 1] = o
		end
	end
	local _, positions = ChaosCityPortals.place({kind = "services", aid = C().aid.entry, item = e.item, towns = {hall.town},
		offsets = offsets, log = log})
	local p = positions[1]
	return p and P(p) or nil
end

function X.setup()
	local done = 0
	for _, hall in ipairs(C().halls or {}) do
		if X.hallReady(hall) then
			X.placeFixtures(hall)
			if not X.retagExit(hall) then
				log("no exit portal found in hall " .. hall.plan)
			end
			X.placeEntry(hall)
			done = done + 1
		elseif C().enabled then
			log("hall " .. hall.plan .. " is not on the map (install step contentareas): its NPCs stand next to the temple")
		end
	end
	return done
end

-- ------------------------------------------------------------------------------------------------ the portals
-- the hall a position lies in (its plan's rectangle)
local function hallAt(position)
	for _, hall in ipairs(C().halls or {}) do
		local a, size = hall.at, hall.size or {0, 0}
		if position.z == a.z and position.x >= a.x and position.y >= a.y and position.x < a.x + size[1]
				and position.y < a.y + size[2] then
			return hall
		end
	end
	return nil
end

-- the hall whose town's temple is within 5 squares of a position (the entry portal stands next to it)
local function hallNearTemple(position)
	for _, hall in ipairs(C().halls or {}) do
		local town = Town(hall.town)
		local t = town and town:getTemplePosition()
		if t and t.z == position.z and math.max(math.abs(t.x - position.x), math.abs(t.y - position.y)) <= 5 then
			return hall
		end
	end
	return nil
end

local entry = MoveEvent()
entry:type("stepin")
function entry.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:getPlayer()
	if not player then
		return true
	end
	local hall = hallNearTemple(position)
	if not hall or not X.hallReady(hall) then
		player:teleportTo(fromPosition, true)
		return true
	end
	local a = hall.arrival
	player:teleportTo(P(K.offset(hall, a[1], a[2], a[3])))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
		"The Hall of Services: progression to the west, trade to the east, the Descent and the raid to the south. The portal beside you leads back to the temple."))
	return true
end
entry:aid(C().aid.entry)
entry:register()

local exit = MoveEvent()
exit:type("stepin")
function exit.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:getPlayer()
	if not player then
		return true
	end
	local hall = hallAt(position)
	local town = hall and Town(hall.town) or player:getTown()
	local t = town and town:getTemplePosition()
	if not t then
		player:teleportTo(fromPosition, true)
		return true
	end
	player:teleportTo(t)
	t:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end
exit:aid(C().aid.exit)
exit:register()

local startup = GlobalEvent("ChaosNpcBoothsStartup")
function startup.onStartup()
	local ok, n = pcall(X.setup)
	if not ok then
		log("setup failed: " .. tostring(n))
	end
	return true
end
startup:register()
