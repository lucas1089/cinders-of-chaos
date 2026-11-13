-- telegraph_config.lua: the numbers of the floor telegraphs (telegraph.lua, telegraph_core.lua; client game_telegraph;
-- server/README.md "Floor telegraphs (O549)"). Plain table, loaded with
--   Chaos.telegraphConfig = dofile("data/scripts/chaos/telegraph_config.lua")
-- No engine calls here (server/tests/telegraph_test.lua reads it with plain Lua).
return {
	-- off: every telegraph draws its sprite marks for everybody, as before O549
	enabled = true,

	-- the loop runs this often (ms): marks that reached their hit are dropped, players who came into view of a mark (or said
	-- hello after it began) get it, players who left it get the clear
	tickMs = 250,

	-- who sees a mark: players on its floor within this many tiles of the area's bounding box (the client's view is 8 / 9
	-- tiles to the sides, 6 / 7 up and down)
	rangeX = 9,
	rangeY = 7,

	-- a mark stays this long after its hit time (ms) before the server drops it and tells the clients to clear it; the client
	-- drops it by itself at the hit
	graceMs = 300,

	-- limits (a telegraph over the limit draws its sprite marks for everybody, as before)
	maxTiles = 300, -- tiles of one mark (the widest shape of the boss files is a 15 x 15 circle, 177 tiles)
	maxMarks = 60, -- marks alive at once
	maxIdLength = 64,
	minMs = 100, -- time to the hit
	maxMs = 12000,

	-- colour keys the client draws (game_telegraph telegraph_logic.lua COLORS); a boss attack is orange
	defaultColor = "orange",
	colors = {orange = true, red = true, green = true, violet = true, blue = true},

	-- the users wired in this repository (each can be turned off on its own: it then draws its sprite marks for everybody)
	bossMechanics = true, -- boss_mechanics.lua: circle, cone, line, ring, cross, puddles, follow
	uber = true, -- uber.lua: the Ascended bosses
	guildBoss = true, -- guildboss.lua
	raid = true, -- raid.lua
	rift = true, -- rift.lua: the guardian's nova and the Veilstorm strikes
	trials = true, -- trials.lua and ascension_quest.lua: the fire zones
}
