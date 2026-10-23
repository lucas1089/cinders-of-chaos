-- Remote admin commands by file (server/README.md "Remote admin commands"). chaos-ctl.sh and the admin app append lines
-- to `remote.cmd` in the server folder; every 2.5 s this takes the file and runs each whitelisted line: broadcast TEXT,
-- kick NAME, save, open, close, plus panel (any admin panel action, run as the online admin character), catalog
-- (the panel's action list), spectate NAME (the app's live view, spectate.lua; only a new watch is logged) and
-- cast NAME / caststop (the player the engine's cast port mirrors, src-patch 0064; Game.setCastTarget).
-- Each command is logged with "[ChaosRemoteCmd]"; refused lines are logged and skipped.
-- A leftover file at startup is removed, not obeyed. Pure part: remote_cmd_core.lua; numbers: remote_cmd_config.lua.
-- Assumed engine API (TFS 1.4.2): GlobalEvent onStartup / onThink with interval, Game.broadcastMessage,
-- Game.setGameState, Player(name), player:remove(), saveServer, json, and ChaosAdmin (chaos/admin/core.lua) for panel.

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

local function resultName()
	return K.bareName(cfg.resultFile, "remote.result")
end

local function catalogName()
	return K.bareName(cfg.catalogFile, "remote.catalog")
end

-- the admin character a panel command runs as: the online player, or (offline) a stand-in from the database row
-- (K.virtualActor); nil and a reason when it cannot
local function actorFor(name)
	local p = Player(name)
	if p then
		if not (ChaosAdmin and ChaosAdmin.isAdmin and ChaosAdmin.isAdmin(p)) then
			return nil, name .. " is not an admin character"
		end
		return p
	end
	local res = db.storeQuery("SELECT `id`, `account_id`, `group_id`, `name` FROM `players` WHERE `deletion` = 0 AND `name` = "
		.. db.escapeString(name))
	if not res then
		return nil, "no character named " .. name
	end
	local row = {
		guid = result.getNumber(res, "id"), account = result.getNumber(res, "account_id"),
		group = result.getNumber(res, "group_id"), name = result.getString(res, "name"),
	}
	result.free(res)
	local v = K.virtualActor(row)
	if not (ChaosAdmin and ChaosAdmin.isAdmin and ChaosAdmin.isAdmin(v)) then
		return nil, name .. " is not an admin character"
	end
	return v
end

local function writeResult(rid, ok, message, lines)
	local name = resultName()
	local mode = "a"
	if (RC.fs.size and RC.fs.size(name) or 0) > (cfg.maxResultBytes or 200000) then
		mode = "w"
	end
	local line = json.encode({rid = rid, ok = ok and true or false, message = message, lines = lines})
	RC.fs.write(name, line .. "\n", mode)
end

handlers.panel = function(c)
	local actor, why = actorFor(c.actor)
	if not actor then
		writeResult(c.rid, false, why)
		return why
	end
	local okJ, params = pcall(json.decode, c.json)
	if not okJ or type(params) ~= "table" then
		writeResult(c.rid, false, "parameters are not a JSON object")
		return "bad parameters"
	end
	local res = ChaosAdmin.execute(actor, c.action, params)
	writeResult(c.rid, res.ok, res.message, res.lines)
	return c.action .. (res.ok and " ok" or " failed")
end

-- the admin app's live view (spectate.lua): false for a renewal of the same watch, which is not logged
handlers.spectate = function(c)
	if not (ChaosSpectate and ChaosSpectate.watch) then
		return "the spectator script (spectate.lua) is not loaded"
	end
	if ChaosSpectate.watch(c.arg) then
		return "watching " .. c.arg
	end
	return false
end

-- the live cast (engine patch 0064): the cast port mirrors this player's game view; chaos-ctl.sh cast runs the relay
handlers.cast = function(c)
	if not Game.setCastTarget then
		return "this engine has no cast port (src-patch 0064)"
	end
	local open = Game.setCastTarget(c.arg)
	local online = Player(c.arg) ~= nil
	return "casting " .. c.arg .. (online and "" or " (not online now)") .. (open and "" or "; the cast port is closed (castPort)")
end

handlers.caststop = function()
	if not Game.setCastTarget then
		return "this engine has no cast port (src-patch 0064)"
	end
	Game.setCastTarget("")
	return "cast stopped"
end

handlers.catalog = function(c)
	local actor, why = actorFor(c.actor)
	if not actor then
		return why
	end
	local name = catalogName()
	local tmp = name .. ".tmp"
	if not RC.fs.write(tmp, json.encode(ChaosAdmin.buildCatalog(actor)), "w") or not RC.fs.rename(tmp, name) then
		return "cannot write " .. name
	end
	return "catalog written"
end

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
		if not (ok and res == false) then
			log(c.cmd .. (c.arg and (" " .. c.arg) or "") .. (c.action and (" " .. c.action .. " as " .. c.actor) or "") .. ": " .. (ok and tostring(res) or ("error " .. tostring(res))))
		end
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
