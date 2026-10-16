-- Graceful stop by file (stop_request.lua, stop_request_core.lua; server/README.md "Stop request file"). Returned as a
-- table, loaded as Chaos.stopRequestConfig (and by tests/stop_request_test.lua). Data only.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,
	-- the file stop-server.bat / stop-server.sh create, in the server folder (the engine's working folder). A bare file
	-- name only: anything with a folder, "..", or other characters falls back to the default.
	file = "stop.request",
	intervalMs = 2500, -- how often the folder is checked
	graceMs = 3000, -- between the broadcast and the save, so players read it before the kick
	message = "The server is shutting down now (stop requested by the host). Your character is saved."
}
