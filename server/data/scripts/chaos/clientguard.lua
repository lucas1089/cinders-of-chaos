-- Client guard, Lua check (server/README.md "Client guard"). The engine (src-patch 0021, src/clientguard.h) refuses
-- logins whose packets do not carry the official client's identifier and kicks a connection that does not answer its
-- HMAC challenge; it also holds back every extended opcode a client sends before that answer. On top of that, cheap:
-- a checked connection must send the hello of client module game_chaosguard (ChaosOpcodes.clientGuardHello) within
-- Chaos.clientGuard.helloTimeout seconds, with enough of our modules loaded. A failure goes to
-- player:clientGuardFail(reason): logged (console, data/logs/clientguard.log), and in clientGuardMode "enforce" the
-- player gets "Please use the official Cinders of Chaos client: <url>" and is logged out. Mode "log" only logs, "off"
-- (the engine's default) checks nothing. Rules in clientguard_core.lua, numbers in clientguard_config.lua.
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/clientguard_config.lua")
dofile("data/scripts/chaos/clientguard_core.lua")

local G = ChaosClientGuard
local cfg = Chaos.clientGuard
local OPCODE = ChaosOpcodes.clientGuardHello

local function fail(player, reason)
	if player.clientGuardFail then
		player:clientGuardFail(reason)
	end
end

local function check(pid)
	local player = Player(pid)
	if not player then
		G.logout(pid)
		return
	end
	local reason = G.expire(pid, os.time(), cfg)
	if reason then
		fail(player, reason)
	end
end

local login = CreatureEvent("ChaosClientGuardLogin")
function login.onLogin(player)
	if not player.getClientGuard then
		return true -- an engine without src-patch 0021: nothing to check
	end
	local pid = player:getId()
	if G.login(pid, os.time(), player:getClientGuard(), cfg) then
		player:registerEvent("ChaosClientGuardHello")
		addEvent(check, cfg.helloTimeout * 1000 + 250, pid)
	end
	return true
end
login:type("login")
login:register()

local hello = CreatureEvent("ChaosClientGuardHello")
function hello.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local ok, reason = G.hello(player:getId(), Chaos.decode(buffer), cfg)
	if not ok then
		fail(player, reason)
	end
end
hello:type("extendedopcode")
hello:register()

local logout = CreatureEvent("ChaosClientGuardLogout")
function logout.onLogout(player)
	G.logout(player:getId())
	return true
end
logout:type("logout")
logout:register()
