-- Server texts in the player's language, the engine part (server/README.md "Server texts in pt-BR (Chaos.t)").
-- The client (client_chaos_locale) sends its language with the display scale hello on opcode 157:
--   client -> server  {action = "hello", lang = "pt-BR" | "en"}   at a game start and when the player changes it
-- display_scale.lua answers the same hello with the factor; this file only keeps the language (Chaos.setLang: the
-- session and the storage ChaosI18n.STORAGE). A hello without `lang` (an older client) changes nothing.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
local OPCODE = ChaosOpcodes.displayScale or 157

local login = CreatureEvent("ChaosI18nLogin")
function login.onLogin(player)
	player:registerEvent("ChaosI18nOpcode")
	player:registerEvent("ChaosI18nLogout")
	ChaosI18n.players[player:getId()] = nil
	return true
end
login:type("login")
login:register()

local opcode = CreatureEvent("ChaosI18nOpcode")
function opcode.onExtendedOpcode(player, code, buffer)
	if code ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if msg and msg.action == "hello" and msg.lang ~= nil then
		Chaos.setLang(player, msg.lang)
	end
end
opcode:type("extendedopcode")
opcode:register()

local logout = CreatureEvent("ChaosI18nLogout")
function logout.onLogout(player)
	ChaosI18n.players[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()
