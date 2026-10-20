-- Remote admin commands by file (remote_cmd.lua; server/README.md "Remote admin commands"): the pure part.
-- chaos-ctl.sh (server/deploy) and the admin app append one command per line to `remote.cmd` in the server folder; the
-- engine takes the file, runs the whitelisted commands and logs each. Nothing else is ever run: a line is one of
-- broadcast, kick, save, open, close followed by an argument checked here. Tested by tests/remote_cmd_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosRemoteCmdCore = ChaosRemoteCmdCore or {}
local K = ChaosRemoteCmdCore

K.DEFAULT_FILE = "remote.cmd"
K.MAX_LINES = 20
K.MAX_LINE = 300

-- the file name to watch: a bare name in the server folder, else the default (same rule as stop_request_core.lua)
function K.fileName(cfg)
	local name = type(cfg) == "table" and cfg.file or nil
	if type(name) ~= "string" or #name == 0 or #name > 64 or not name:match("^[%w_%-%.]+$") or name:find("..", 1, true)
			or name:sub(1, 1) == "." then
		return K.DEFAULT_FILE
	end
	return name
end

-- one line -> {cmd = "...", arg = "..." or nil}, or nil and a reason
function K.parse(line)
	if type(line) ~= "string" then
		return nil, "not text"
	end
	line = line:gsub("\r", "")
	if #line > K.MAX_LINE then
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
		if #arg < 3 or #arg > 29 or not arg:match("^%a[%a '%-]*$") then
			return nil, "not a character name"
		end
		return {cmd = cmd, arg = arg}
	end
	return nil, "unknown command"
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
			local text = f:read(8192)
			f:close()
			return text
		end,
		remove = function(name)
			return osLib.remove(name) and true or false
		end
	}
end

return K
