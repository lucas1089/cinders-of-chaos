-- The NPC booths of the hub: the engine side (npc_booths_core.lua holds the logic, npc_booths_config.lua the stalls).
-- server/README.md "Hub NPC booths". Owner 2026-10-22: the Chaos NPCs of the main city stand in the stalls of the hub
-- (the market of Cinderhold's teleport room) where the base server's shop NPCs stood; the Hall of Services is gone.
--   ChaosNpcBooths.spot(name, townId) / .spotForTemple(name, templePosition)   the NPC's stall (a Position), or nil.
--       ChaosNpcPlace.place (npc_place.lua) and the Keeper of Trials (trials.lua) ask it first, so each system's own
--       startup code puts its NPC in the stall. The stalls are the base map's: nothing is built here.
--   A character who logs in inside a retired Hall of Services (its tiles may still be on a map that had it) is sent
--   to the temple of the hall's town, so nobody is stuck in a hall no portal leads out of any more.
-- Lua 5.1 / LuaJIT and 5.3. Assumed engine API (TFS 1.4): Tile, Town, Player:teleportTo, CreatureEvent.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosNpcBoothsCore or not ChaosNpcBoothsCore.spotForTemple then
	dofile("data/scripts/chaos/npc_booths_core.lua")
end

ChaosNpcBooths = ChaosNpcBooths or {}
local X = ChaosNpcBooths
local K = ChaosNpcBoothsCore

local function C()
	return K.cfg()
end

function X.spot(name, townId)
	local s = K.spot(C(), name, townId)
	return s and Position(s.x, s.y, s.z) or nil
end

function X.spotForTemple(name, temple)
	local s = K.spotForTemple(C(), name, temple)
	return s and Position(s.x, s.y, s.z) or nil
end

-- the temple a character inside a retired hall goes to: the hall's town, else the character's own
function X.relocate(player)
	local hall = K.retiredHallAt(C(), player:getPosition())
	if not hall then
		return false
	end
	local town = Town(hall.town) or player:getTown()
	local t = town and town:getTemplePosition()
	if not t then
		return false
	end
	player:teleportTo(t)
	t:sendMagicEffect(CONST_ME_TELEPORT)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
		"The Hall of Services is closed: you were brought to the temple. Its NPCs stand in the market of the teleport room, its portals at the temple."))
	return true
end

local login = CreatureEvent("ChaosRetiredHallLogin")
function login.onLogin(player)
	local ok, err = pcall(X.relocate, player)
	if not ok then
		print("[npc_booths] " .. tostring(err))
	end
	return true
end
login:type("login")
login:register()
