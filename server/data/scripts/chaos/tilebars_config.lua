-- tilebars_config.lua: the numbers of the progress bars over tiles (tilebars.lua, tilebars_core.lua; client
-- game_tileoverlays; server/README.md "Progress bars over tiles"). Plain table, loaded with
--   Chaos.tileBarsConfig = dofile("data/scripts/chaos/tilebars_config.lua")
-- No engine calls here (server/tests/tilebars_test.lua reads it with plain Lua).
return {
	enabled = true,

	-- the send loop runs this often (ms): every bar's viewers are worked out, then one message per player that has
	-- something new (bars to draw or to drop)
	tickMs = 250,
	-- a bar whose progress alone changed goes to a player at most this often (ms); label, colour, place and countdown
	-- changes go out on the next tick
	progressMs = 500,
	-- progress changes smaller than this (0..1) are not worth a message; 0 and 1 always are
	minStep = 0.01,

	-- who sees a bar: players on the bar's floor within this many tiles (the client's view is 8 / 9 tiles to the sides,
	-- 6 / 7 up and down)
	rangeX = 9,
	rangeY = 7,

	-- a countdown bar goes away by itself this long after it reached zero (ms), unless it was set with keep = true
	expireGraceMs = 1000,

	maxBars = 500, -- bars alive at once; a new one past this is refused (a warning in the log)
	maxIdLength = 64,
	labelMax = 32, -- characters of a label
	perMessage = 40, -- bars per message (each about 120 bytes, so a message stays far below the 8192 byte limit)
	defaultColor = "#d8b45a",

	-- the users wired in this repository (each can be turned off on its own)
	battleground = true, -- battleground.lua: the capture of each brazier (match id and brazier index)
	professions = true, -- professions.lua: when a gathered node is ready again, for the gatherer only
	invasion = true, -- invasion.lua: the breach meter over the target point while the waves come
}
