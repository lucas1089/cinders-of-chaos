-- The client's helper is told which Everfull potion each slot carries (README "Potions", "The helper and the tiers", O246).
-- Rules: potions_core.lua heldView; send: data/lib/chaos_potions.lua PT.sendHeld; client: game_helperrotation/everfullheld.lua.
-- The message goes out at login, when the client asks (`sync`, once its module is up), after an upgrade (ChaosPotions.upgrade),
-- and whenever a 3 s think finds it changed (a flask emptied or refilled, an item moved into or out of the backpacks).
-- The only client input is `sync`: one per second, no data read from it. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/potions_core.lua")
dofile("data/scripts/chaos/potions_config.lua")
dofile("data/lib/chaos_potions.lua")

local PT = ChaosPotions
local OPCODE = (ChaosOpcodes and ChaosOpcodes.everfull) or 116
local THINK_MS = 3000

local login = CreatureEvent("ChaosPotionsHeldLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPotionsHeldExtended")
	player:registerEvent("ChaosPotionsHeldLogout")
	local id = player:getId()
	addEvent(function() -- the client may not listen yet: it also asks with `sync`
		local p = Player(id)
		if p then
			pcall(PT.sendHeld, p, true)
		end
	end, 1500)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosPotionsHeldLogout")
function logout.onLogout(player)
	PT.forgetHeld(player)
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosPotionsHeldExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "sync" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "everfull.sync", 1000) then
		return
	end
	pcall(PT.sendHeld, player, true)
end
ext:type("extendedopcode")
ext:register()

local think = GlobalEvent("ChaosPotionsHeldThink")
function think.onThink(interval)
	for _, p in ipairs(Game.getPlayers()) do
		local ok, err = pcall(PT.sendHeld, p, false)
		if not ok then
			print("[potions] held view of " .. tostring(p:getName()) .. ": " .. tostring(err))
		end
	end
	return true
end
think:interval(THINK_MS)
think:register()
