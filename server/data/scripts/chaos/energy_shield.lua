-- Energy shield bar after a reconnect (server/README.md "Energy shield", engine patch 0015, client game_energyshield). The
-- engine sends "es:<current>:<max>" on ChaosOpcodes.energyShield (224) only when the shield changes, and a reconnect into
-- a character still online runs no login event, so the bar stayed hidden. Once in the game the client sends "hello" on
-- the same opcode and gets the engine's text again (ChaosEnergyShield.helloAnswer, tests/energy_shield_test.lua).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosEnergyShield or not ChaosEnergyShield.helloAnswer then
	dofile("data/lib/chaos_energy_shield.lua")
end

local E = ChaosEnergyShield
local OPCODE = ChaosOpcodes.energyShield or 224

local login = CreatureEvent("ChaosEnergyShieldLogin")
function login.onLogin(player)
	player:registerEvent("ChaosEnergyShieldOpcode")
	return true
end
login:type("login")
login:register()

local opcode = CreatureEvent("ChaosEnergyShieldOpcode")
function opcode.onExtendedOpcode(player, code, buffer)
	if code ~= OPCODE then
		return
	end
	local text = E.helloAnswer(player, buffer)
	if text then
		player:sendExtendedOpcode(OPCODE, text)
	end
end
opcode:type("extendedopcode")
opcode:register()
