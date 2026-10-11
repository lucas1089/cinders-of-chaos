-- Client guard, Lua check: pure logic (no engine API; tests/clientguard_test.lua). The engine glue is clientguard.lua.
--
-- Per character: at login, when the engine checked its connection (player:getClientGuard().state in
-- Chaos.clientGuard.checkedStates), a hello is expected within helloTimeout seconds. The hello is the JSON
-- {"action": "hello", "data": {"build": n, "modules": n}} of client module game_chaosguard. Failing it (none in time,
-- malformed, another build than the login packets said, too few of our modules) gives a reason; the engine then logs it
-- and, in "enforce", kicks with the official-client message (player:clientGuardFail).
ChaosClientGuard = ChaosClientGuard or {}
local G = ChaosClientGuard

G.watch = G.watch or {} -- player id -> {due = time, build = n or nil, done = bool}

-- info: player:getClientGuard() (nil on an engine without src-patch 0021 or without a connection)
function G.shouldCheck(info, cfg)
	return type(info) == "table" and info.mode ~= "off" and cfg.checkedStates[info.state] == true
end

function G.login(pid, now, info, cfg)
	if not G.shouldCheck(info, cfg) then
		G.watch[pid] = nil
		return false
	end
	G.watch[pid] = { due = now + cfg.helloTimeout, build = info.official and info.build or nil, done = false }
	return true
end

-- returns true, or false and the reason; a hello for a character that is not watched (relog over a live session,
-- guard off) is ignored (true)
function G.hello(pid, msg, cfg)
	local w = G.watch[pid]
	if not w or w.done then
		return true
	end
	w.done = true
	if type(msg) ~= "table" or msg.action ~= "hello" or type(msg.data) ~= "table" then
		return false, "malformed module hello"
	end
	local build, modules = tonumber(msg.data.build), tonumber(msg.data.modules)
	if not build or not modules then
		return false, "malformed module hello"
	end
	if w.build and build ~= w.build then
		return false, string.format("module hello for build %d, the login said build %d", build, w.build)
	end
	if modules < cfg.minModules then
		return false, string.format("only %d of our client modules loaded (at least %d expected)", modules, cfg.minModules)
	end
	return true
end

-- the reason when the hello is overdue (once), else nil
function G.expire(pid, now, cfg)
	local w = G.watch[pid]
	if not w or w.done or now < w.due then
		return nil
	end
	w.done = true
	return string.format("no module hello from the client within %d s", cfg.helloTimeout)
end

function G.logout(pid)
	G.watch[pid] = nil
end
