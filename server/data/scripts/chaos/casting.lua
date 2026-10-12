-- Cast-time spells, the scripts side (the casts themselves: data/lib/chaos_casting.lua; overview: server/README.md
-- "Cast-time spells"). Registers per player: logout and death interrupt a cast and give its cost back, and the
-- extended opcode ChaosOpcodes.castbar (231, client game_castbar):
--   client -> server  cancel                       (interrupts the player's own cast; same refund as moving)
--   server -> client  start {s serial, n name, ms, id spellId}   end {s, r result, t text}
--                     other {c creature id, n name, ms}           otherEnd {c, r}   (casts of players in view)
-- The client never ends a cast with success: completion is the server's timer. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCasting then
	dofile("data/lib/chaos_casting.lua")
end

local C = ChaosCasting
local OPCODE = (ChaosOpcodes and ChaosOpcodes.castbar) or 231

local login = CreatureEvent("ChaosCastingLogin")
function login.onLogin(player)
	player:registerEvent("ChaosCastingLogout")
	player:registerEvent("ChaosCastingDeath")
	player:registerEvent("ChaosCastingExtended")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosCastingLogout")
function logout.onLogout(player)
	C.interrupt(player, "logout")
	return true
end
logout:type("logout")
logout:register()

local death = CreatureEvent("ChaosCastingDeath")
function death.onDeath(creature)
	local player = creature and creature:getPlayer()
	if player then
		C.interrupt(player, "died")
	end
	return true
end
death:type("death")
death:register()

local ext = CreatureEvent("ChaosCastingExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "cancel" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "casting.cancel", 200) then
		return
	end
	C.interrupt(player, "cancel")
end
ext:type("extendedopcode")
ext:register()
