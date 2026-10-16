-- Graceful stop by file (server/README.md "Stop request file"). stop-server.bat (Windows package) and stop-server.sh
-- (Linux package) create `stop.request` in the server folder; every 2.5 s this checks for it. Found: the file is
-- removed, everyone online is told, and after graceMs the server saves (saveServer) and shuts down
-- (Game.setGameState(GAME_STATE_SHUTDOWN): every player saved on the kick, a clean exit with code 0, so the start
-- scripts do not restart it). A file that cannot be removed stops nothing (logged once). A leftover file at startup is
-- removed. Pure part: stop_request_core.lua; numbers: stop_request_config.lua.
-- Assumed engine API (TFS 1.4.2): GlobalEvent onStartup / onThink with interval, Game.broadcastMessage,
-- Game.getGameState / setGameState, saveServer, addEvent.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosStopRequestCore then
	dofile("data/scripts/chaos/stop_request_core.lua")
end

Chaos.stopRequestConfig = dofile("data/scripts/chaos/stop_request_config.lua")
local cfg = Chaos.stopRequestConfig
local K = ChaosStopRequestCore
ChaosStopRequest = ChaosStopRequest or {}
local SR = ChaosStopRequest
SR.fs = SR.fs or K.realFs()

local function log(text)
	print("[ChaosStopRequest] " .. text)
end

local function closing()
	local ok, state = pcall(Game.getGameState)
	return ok and state ~= nil and (state == GAME_STATE_SHUTDOWN or state == GAME_STATE_CLOSED)
end

local function shutdown()
	log("saving and shutting down")
	pcall(saveServer)
	Game.setGameState(GAME_STATE_SHUTDOWN)
end

-- one check; returns the poll result ("none", "stop", "stuck", "busy")
function SR.check()
	if SR.stopping or closing() then
		return "busy"
	end
	local name = K.fileName(cfg)
	local res = K.poll(SR.fs, name)
	if res == "stuck" then
		if not SR.warned then
			SR.warned = true
			log(name .. " found but it cannot be removed: not stopping (remove it by hand, check the folder's rights)")
		end
	elseif res == "stop" then
		SR.stopping = true
		log(name .. " found: stop requested")
		pcall(Game.broadcastMessage, cfg.message, MESSAGE_STATUS_WARNING)
		if (cfg.graceMs or 0) > 0 then
			addEvent(shutdown, cfg.graceMs)
		else
			shutdown()
		end
	end
	return res
end

if cfg.enabled ~= false then
	local startup = GlobalEvent("ChaosStopRequestStartup")
	function startup.onStartup()
		-- a request left from before this start (the server was already down) must not stop it at once
		local name = K.fileName(cfg)
		if SR.fs.exists(name) then
			SR.fs.remove(name)
			log("removed a leftover " .. name)
		end
		return true
	end
	startup:register()

	local poll = GlobalEvent("ChaosStopRequest")
	function poll.onThink(interval)
		SR.check()
		return true
	end
	poll:interval(cfg.intervalMs or 2500)
	poll:register()
end
