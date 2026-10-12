-- Keep attacking while moving (engine src-patch 0028, client game_kitewalk, extended opcode ChaosOpcodes.kiteWalk = 186;
-- server/README.md "Keep attacking while moving"). The engine does the walking and the attacks; this glue keeps the
-- client option "Keep attacking while moving" in the storage the engine reads (Chaos.storage.kiteWalkOff; the client
-- sends {on = true | false} at every login and when the option changes). Rules: kitewalk_core.lua
-- (tests/kitewalk_test.lua). Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosKiteWalk or not ChaosKiteWalk.update then
	dofile("data/scripts/chaos/kitewalk_core.lua")
end

local K = ChaosKiteWalk
local OPCODE = ChaosOpcodes.kiteWalk or 186
local KEY = Chaos.storage.kiteWalkOff or 7101820

local login = CreatureEvent("ChaosKiteWalkLogin")
function login.onLogin(player)
	player:registerEvent("ChaosKiteWalkOpcode")
	return true
end
login:type("login")
login:register()

local opcode = CreatureEvent("ChaosKiteWalkOpcode")
function opcode.onExtendedOpcode(player, code, buffer)
	if code ~= OPCODE then
		return
	end
	local want = K.update(player:getStorageValue(KEY), Chaos.decode(buffer))
	if want ~= nil then
		player:setStorageValue(KEY, want)
	end
end
opcode:type("extendedopcode")
opcode:register()
