-- Effect owner marks, the engine glue (O567; the logic is data/lib/chaos_fx_owner.lua, the wrappers of Position:sendMagicEffect and
-- Position:sendDistanceEffect are installed on the spell side by data/spells/chaos/_supports.lua; server/README.md "Effect owner
-- marks"). Here only the client's wish is kept: extended opcode ChaosOpcodes.fxOwner (164), client -> server
--     hello {need = 1 | 0}     "mark my own effects for me" / "stop" (the client's two opacity sliders differ / are the same)
-- stored in player storage Chaos.storage.fxOwner (7103120): 1 while it wants marks, -1 otherwise. Login and logout reset it, so a
-- player on a client that does not know the opcode (an older client, the Unity client) never gets a message. Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosFxOwner or not ChaosFxOwner.setNeed then
	dofile("data/lib/chaos_fx_owner.lua")
end

local O = ChaosFxOwner
local OPCODE = (ChaosOpcodes and ChaosOpcodes.fxOwner) or 164
O.STORAGE = (Chaos.storage and Chaos.storage.fxOwner) or O.STORAGE

local login = CreatureEvent("ChaosFxOwnerLogin")
function login.onLogin(player)
	player:registerEvent("ChaosFxOwnerExtended")
	player:registerEvent("ChaosFxOwnerLogout")
	O.setNeed(player, false)
	return true
end
login:register()

local logout = CreatureEvent("ChaosFxOwnerLogout")
function logout.onLogout(player)
	O.setNeed(player, false)
	O.forget(player:getId())
	return true
end
logout:register()

local ext = CreatureEvent("ChaosFxOwnerExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "hello" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "fxowner.hello", 100) then
		return
	end
	O.setNeed(player, msg.need == 1)
end
ext:type("extendedopcode")
ext:register()
