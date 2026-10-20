-- Remote admin commands by file (remote_cmd.lua, remote_cmd_core.lua; server/README.md "Remote admin commands").
-- Returned as a table, loaded as Chaos.remoteCmdConfig (and by tests/remote_cmd_test.lua). Data only.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,
	file = "remote.cmd", -- a bare file name in the server folder
	intervalMs = 2500, -- how often the folder is checked
	-- the panel commands (admin panel actions run for the phone app): the answers are appended to resultFile, the
	-- catalog goes to catalogFile (both bare names in the server folder)
	resultFile = "remote.result",
	catalogFile = "remote.catalog",
	maxResultBytes = 200000 -- the result file starts again above this size
}
