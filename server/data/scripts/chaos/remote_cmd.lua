-- Remote admin commands by file (server/README.md "Remote admin commands"). chaos-ctl.sh and the admin app append lines
-- to `remote.cmd` in the server folder; every 2.5 s this takes the file and runs each whitelisted line: broadcast TEXT,
-- kick NAME, save, open, close. Each command is logged with "[ChaosRemoteCmd]"; refused lines are logged and skipped.
-- A leftover file at startup is removed, not obeyed. Pure part: remote_cmd_core.lua; numbers: remote_cmd_config.lua.
-- Assumed engine API (TFS 1.4.2): GlobalEvent onStartup / onThink with interval, Game.broadcastMessage,
-- Game.setGameState, Player(name), player:remove(), saveServer.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosRemoteCmdCore then
	dofile("data/scripts/chaos/remote_cmd_core.lua")
end

Chaos.remoteCmdConfig = dofile("data/scripts/chaos/remote_cmd_config.lua")
local cfg = Chaos.remoteCmdConfig
local K = ChaosRemoteCmdCore
ChaosRemoteCmd = ChaosRemoteCmd or {}
local RC = ChaosRemoteCmd
RC.fs = RC.fs or K.realFs()

local function log(text)
	print("[ChaosRemoteCmd] " .. text)
end

local handlers = {
	broadcast = function(c)
		Game.broadcastMessage(c.arg, MESSAGE_STATUS_WARNING)
		return "broadcast sent"
	end,
	kick = function(c)
		local p = Player(c.arg)
		if not p then
			return "no player online named " .. c.arg
		end
		p:remove()
		return "kicked " .. c.arg
	end,
	save = function()
		saveServer()
		return "saved"
	end,
	open = function()
		Game.setGameState(GAME_STATE_NORMAL)
		return "server open"
	end,
	close = function()
		Game.setGameState(GAME_STATE_CLOSED)
		return "server closed"
	end
}

-- one check; returns the number of commands run
function RC.check()
	local name = K.fileName(cfg)
	local text, why = K.take(RC.fs, name)
	if text == nil then
		if why == "stuck" and not RC.warned then
			RC.warned = true
			log(name .. " found but it cannot be renamed: nothing run (check the folder's rights)")
		end
		return 0
	end
	local cmds, refused = K.parseAll(text)
	for _, r in ipairs(refused) do
		log("refused (" .. r.reason .. "): " .. r.line)
	end
	local ran = 0
	for _, c in ipairs(cmds) do
		local ok, res = pcall(handlers[c.cmd], c)
		log(c.cmd .. (c.arg and (" " .. c.arg) or "") .. ": " .. (ok and tostring(res) or ("error " .. tostring(res))))
		ran = ran + 1
	end
	return ran
end

if cfg.enabled ~= false then
	local startup = GlobalEvent("ChaosRemoteCmdStartup")
	function startup.onStartup()
		local name = K.fileName(cfg)
		if RC.fs.exists(name) then
			RC.fs.remove(name)
			log("removed a leftover " .. name)
		end
		return true
	end
	startup:register()

	local poll = GlobalEvent("ChaosRemoteCmd")
	function poll.onThink(interval)
		RC.check()
		return true
	end
	poll:interval(cfg.intervalMs or 2500)
	poll:register()
end
