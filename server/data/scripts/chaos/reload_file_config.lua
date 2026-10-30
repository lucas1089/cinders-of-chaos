-- Reload one config table (reload_file_core.lua; server/README.md "Reload one config table (O312)"): the numbers.
-- Returned as a table. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- the only folder the reload reads from, relative to the server folder
	dir = "data/scripts/chaos/",
	-- a file is a config table when its name ends with this (before .lua)
	suffix = "_config",
	-- live copies kept per file (a core that loads its config twice holds two tables)
	maxTracked = 8,
	-- changed keys named in the answer; the rest is counted
	maxChanges = 12,
	-- tables nested deeper than this are not walked (a cycle guard as well)
	maxDepth = 16,
	-- configs that are never reloaded live, with the reason the admin reads
	restartOnly = {
		remote_cmd_config = "its interval is read once when the script starts",
		reload_file_config = "this file sets the reload itself",
	},
}
