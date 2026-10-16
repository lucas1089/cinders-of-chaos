-- Graceful stop by file (stop_request.lua; server/README.md "Stop request file"): the pure part.
-- Windows closes a console within about 5 seconds, too soon for the engine's save, so the package's stop-server.bat
-- (and stop-server.sh first, the signal as fallback) asks for the stop with a file in the server folder instead. The file
-- name is fixed by the config and checked here; the file's content is never read. Tested by tests/stop_request_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosStopRequestCore = ChaosStopRequestCore or {}
local K = ChaosStopRequestCore

K.DEFAULT_FILE = "stop.request"

-- the file name to watch: a bare name in the server folder (letters, digits, "_", "-", "."; no folder, no "..", not
-- starting with a dot, at most 64 characters), else the default
function K.fileName(cfg)
	local name = type(cfg) == "table" and cfg.file or nil
	if type(name) ~= "string" or #name == 0 or #name > 64 or not name:match("^[%w_%-%.]+$") or name:find("..", 1, true)
			or name:sub(1, 1) == "." then
		return K.DEFAULT_FILE
	end
	return name
end

-- one check. fs = {exists = function(name) -> bool, remove = function(name) -> ok}. Returns
--   "none"   no request
--   "stop"   a request, the file removed: stop now
--   "stuck"  a request whose file could not be removed: no stop (it would stop the next start again at once)
function K.poll(fs, name)
	if not fs.exists(name) then
		return "none"
	end
	if not fs.remove(name) or fs.exists(name) then
		return "stuck"
	end
	return "stop"
end

-- the real file system (io / os): exists = the file opens for reading (its content is not read)
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
		remove = function(name)
			return osLib.remove(name) and true or false
		end
	}
end

return K
