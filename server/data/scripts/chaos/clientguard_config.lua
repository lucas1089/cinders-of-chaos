-- Client guard, Lua part (clientguard.lua, clientguard_core.lua; server/README.md "Client guard").
-- The engine (src-patch 0021) does the login gate and the HMAC handshake and holds the mode, keys and builds in
-- config.lua (clientGuardMode, clientGuardKey, ...). This file only has the numbers of the cheap Lua check on top: a
-- client that passed the engine must also say hello from our overlay (client module game_chaosguard, extended opcode
-- ChaosOpcodes.clientGuardHello) soon after the login, with enough of our modules loaded.
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

Chaos.clientGuard = {
	-- seconds after the login by which the hello must have come (the client sends it at onGameStart, within a second)
	helloTimeout = 30,
	-- the hello reports how many of our modules (game_*, client_chaos_*) the client loaded; the overlay has about 90,
	-- a client running our binary with its own scripts instead has few or none
	minModules = 20,
	-- connection states of player:getClientGuard() that must say hello: checked by the engine (or let in after a log line
	-- in log mode). "bypass" (staff from a staff IP), "none" (guard off) and "failed" are not checked.
	checkedStates = { pending = true, verified = true, logged = true },
}
