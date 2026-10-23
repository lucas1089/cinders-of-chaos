-- Remote admin commands by file (remote_cmd.lua; server/README.md "Remote admin commands"): the pure part.
-- chaos-ctl.sh (server/deploy) and the admin app append one command per line to `remote.cmd` in the server folder; the
-- engine takes the file, runs the whitelisted commands and logs each. Nothing else is ever run: a line is one of
-- broadcast, kick, save, open, close, catalog, panel and spectate followed by an argument checked here.
-- Tested by tests/remote_cmd_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosRemoteCmdCore = ChaosRemoteCmdCore or {}
local K = ChaosRemoteCmdCore

K.DEFAULT_FILE = "remote.cmd"
K.MAX_LINES = 20
K.MAX_LINE = 300 -- most commands
K.MAX_PANEL_LINE = 1400 -- panel lines carry a JSON of parameters
K.MAX_FILE = 32768

-- the file name to watch: a bare name in the server folder, else the default (same rule as stop_request_core.lua)
function K.fileName(cfg)
	local name = type(cfg) == "table" and cfg.file or nil
	if type(name) ~= "string" or #name == 0 or #name > 64 or not name:match("^[%w_%-%.]+$") or name:find("..", 1, true)
			or name:sub(1, 1) == "." then
		return K.DEFAULT_FILE
	end
	return name
end

local function isName(arg)
	return #arg >= 3 and #arg <= 29 and arg:match("^%a[%a '%-]*$") ~= nil
end

-- one line -> {cmd = "...", arg = "..." or nil, ...}, or nil and a reason
--   panel RID ACTION|ACTOR|JSON   an admin panel action (chaos/admin) run as the online admin character ACTOR;
--                                 RID digits (the caller finds the answer by it), ACTION like players.kick, JSON an object
--   catalog ACTOR                 writes the panel's catalog for ACTOR's group to the catalog file
--   spectate NAME                 starts or renews the admin app's live view of NAME (spectate.lua), read only
function K.parse(line)
	if type(line) ~= "string" then
		return nil, "not text"
	end
	line = line:gsub("\r", "")
	if #line > K.MAX_PANEL_LINE then
		return nil, "line too long"
	end
	if line:find("[\1-\8\11\12\14-\31\127]") or line:find("\0", 1, true) then
		return nil, "control characters"
	end
	local cmd, arg = line:match("^%s*(%a+)%s*(.-)%s*$")
	if not cmd then
		return nil, "empty"
	end
	cmd = cmd:lower()
	if cmd ~= "panel" and #line > K.MAX_LINE then
		return nil, "line too long"
	end
	if cmd == "save" or cmd == "open" or cmd == "close" then
		if arg ~= "" then
			return nil, cmd .. " takes no argument"
		end
		return {cmd = cmd}
	elseif cmd == "broadcast" then
		if #arg < 1 or #arg > 200 then
			return nil, "broadcast text must be 1-200 characters"
		end
		return {cmd = cmd, arg = arg}
	elseif cmd == "kick" then
		if not isName(arg) then
			return nil, "not a character name"
		end
		return {cmd = cmd, arg = arg}
	elseif cmd == "catalog" then
		if not isName(arg) then
			return nil, "not a character name"
		end
		return {cmd = cmd, arg = arg, actor = arg}
	elseif cmd == "spectate" then
		if not isName(arg) then
			return nil, "not a character name"
		end
		return {cmd = cmd, arg = arg}
	elseif cmd == "panel" then
		local rid, rest = arg:match("^(%d+)%s+(.+)$")
		if not rid or #rid > 12 then
			return nil, "panel RID ACTION|ACTOR|JSON"
		end
		local action, actor, json = rest:match("^([^|]+)|([^|]+)|(.+)$")
		if not action or not action:match("^[%w_%.]+$") or #action > 64 then
			return nil, "bad action id"
		end
		if not isName(actor) then
			return nil, "not a character name"
		end
		if json:sub(1, 1) ~= "{" or json:sub(-1) ~= "}" then
			return nil, "parameters must be a JSON object"
		end
		return {cmd = cmd, rid = tonumber(rid), action = action, actor = actor, json = json}
	end
	return nil, "unknown command"
end

-- An admin character that is not online: a stand-in built from its database row {guid, account, group, name}. The
-- identity calls the panel uses (name, group, guid, account, audit log) work; anything that needs the character in the
-- world (position, teleport, ghost, speed, conditions, storage) raises a clear error, which ChaosAdmin.execute turns
-- into the answer of the action. Actions that only act on other players or on the server therefore run offline.
function K.virtualActor(row)
	local actor = {}
	local group = {
		getId = function() return row.group end,
		getAccess = function() return true end,
		getName = function() return "admin" end,
	}
	local own = {
		isPlayer = function() return true end,
		isCreature = function() return true end,
		getName = function() return row.name end,
		getId = function() return 0 end,
		getGuid = function() return row.guid end,
		getAccountId = function() return row.account end,
		getIp = function() return 0 end,
		getGroup = function() return group end,
		sendTextMessage = function() return true end,
		sendCancelMessage = function() return true end,
		registerEvent = function() return true end,
		unregisterEvent = function() return true end,
	}
	return setmetatable(actor, {
		__index = function(_, method)
			if own[method] then
				return function() return own[method]() end
			end
			return function()
				error("this action needs " .. row.name .. " in the game (" .. tostring(method) .. "); log in or pick another action", 0)
			end
		end,
	})
end

-- the text of a taken file -> list of parsed commands (at most MAX_LINES) and a list of refused lines {line, reason}
function K.parseAll(text)
	local cmds, refused, n = {}, {}, 0
	for line in tostring(text or ""):gmatch("[^\n]+") do
		n = n + 1
		if n > K.MAX_LINES then
			refused[#refused + 1] = {line = "(more than " .. K.MAX_LINES .. " lines)", reason = "ignored"}
			break
		end
		local c, why = K.parse(line)
		if c then
			cmds[#cmds + 1] = c
		else
			refused[#refused + 1] = {line = line:sub(1, 60), reason = why}
		end
	end
	return cmds, refused
end

-- takes the file: renamed first (a writer that appends later makes a new file, nothing is lost), read, removed.
-- fs = {exists, rename, read, remove}. Returns the text, or nil when there is no file or it could not be taken.
function K.take(fs, name)
	if not fs.exists(name) then
		return nil
	end
	local work = name .. ".work"
	if fs.exists(work) then
		fs.remove(work)
	end
	if not fs.rename(name, work) then
		return nil, "stuck"
	end
	local text = fs.read(work)
	fs.remove(work)
	return text or ""
end

function K.realFs(ioLib, osLib)
	ioLib, osLib = ioLib or io, osLib or os
	return {
		exists = function(name)
			local f = ioLib.open(name, "rb")
			if f then
				f:close()
				return true
			end
			return false
		end,
		rename = function(a, b)
			return osLib.rename(a, b) and true or false
		end,
		read = function(name)
			local f = ioLib.open(name, "rb")
			if not f then
				return nil
			end
			local text = f:read(K.MAX_FILE)
			f:close()
			return text
		end,
		remove = function(name)
			return osLib.remove(name) and true or false
		end,
		-- mode "a" appends, "w" replaces; returns true when written
		write = function(name, text, mode)
			local f = ioLib.open(name, mode == "a" and "ab" or "wb")
			if not f then
				return false
			end
			f:write(text)
			f:close()
			return true
		end,
		size = function(name)
			local f = ioLib.open(name, "rb")
			if not f then
				return 0
			end
			local n = f:seek("end") or 0
			f:close()
			return n
		end
	}
end

-- a name from the config like fileName
function K.bareName(value, default)
	if type(value) ~= "string" or #value == 0 or #value > 64 or not value:match("^[%w_%-%.]+$") or value:find("..", 1, true)
			or value:sub(1, 1) == "." then
		return default
	end
	return value
end

return K
