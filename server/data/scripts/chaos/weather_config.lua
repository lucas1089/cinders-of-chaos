-- Weather (weather.lua, weather_core.lua; client game_chaosweather; server/README.md "Weather on the client (O208)"):
-- every number. Plain table, loaded with
--     ChaosWeatherConfig = dofile("data/scripts/chaos/weather_config.lua")
-- The rain numbers are the base weather's (customs/globalevents/rain.lua of the base server), so the rain comes and goes as
-- it did. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,

	-- how often the glue looks at the players (a GlobalEvent). The base rain ran every 100 ms for every player.
	tickMs = 3000,

	-- the base's dice: at startup it rains with startChance percent; every rollMs a dry world starts to rain with
	-- startChance percent and a rainy one stops with stopChance percent (the base: 15 / 10 every 5 minutes, one
	-- world-wide state)
	startChance = 15,
	stopChance = 10,
	rollMs = 300000,

	-- how strong a rain is, picked when it starts. 2 is the base's look (one drop every 100 ms for each player). The
	-- weights are percent parts; the client draws 1 light, 2 normal, 3 heavy.
	intensities = {
		{level = 1, weight = 20},
		{level = 2, weight = 60},
		{level = 3, weight = 20}
	},

	-- the client fades the rain in or out over this many ms when the message changes
	fadeMs = 2500,

	-- Where it rains. The base rained for every player on or above the surface: its effects land on the top tile of a
	-- column on floors 0 to 7 (Player.sendWeatherEffect), which nobody sees from a cave, so a player under floor 7 got
	-- none. An area is {name, kind, minZ, maxZ} and may carry a box {x1, y1, x2, y2} (inclusive) to limit it; the
	-- first area that holds the player's tile wins. A player in no area gets "none".
	areas = {
		{name = "surface", kind = "rain", minZ = 0, maxZ = 7}
	},

	-- Ambient particles (O226; client game_chaosweather, option `ambientParticles`): a standing mood of a place that the
	-- client draws as slow specks over the game window, whatever the weather. kind: "embers" (hot or burnt land), "motes"
	-- (fireflies in forest and swamp), "dust" (caves). Same shape as `areas`; the first area that holds the player's tile
	-- wins; a tile in none has no mood (the message carries no `a`, as before). The player's floor and tile are looked at on
	-- the same tick as the rain, so nothing extra runs.
	--  * The two generated hot places are exact (areagen_config.lua origins and sizes).
	--  * The surface places are SAMPLE SITES of docs/MAP_GUIDE.md (the swamp town, the jungle village, the forest by the
	--    river; the map is not in the repository, so the boxes are a guess around those points): widen or move them with
	--    the real extent of each swamp and forest (the map editor shows the tile), one line each.
	--  * Every other tile under the surface (floors 8-15) is a cave: dust.
	ambient = {
		enabled = true,
		areas = {
			{name = "emberdeep", kind = "embers", minZ = 9, maxZ = 10, box = {14400, 14400, 14495, 14475}},
			{name = "cinderfall", kind = "embers", minZ = 7, maxZ = 7, box = {14400, 14560, 14544, 14675}},
			{name = "swamp town", kind = "motes", minZ = 7, maxZ = 7, box = {32880, 32010, 33000, 32110}},
			{name = "jungle village", kind = "motes", minZ = 7, maxZ = 7, box = {32530, 32680, 32630, 32780}},
			{name = "river forest", kind = "motes", minZ = 7, maxZ = 7, box = {32550, 32180, 32660, 32270}},
			{name = "jungle cave", kind = "motes", minZ = 8, maxZ = 10, box = {32630, 32810, 32700, 32880}},
			{name = "caves", kind = "dust", minZ = 8, maxZ = 15}
		}
	},

	-- Colour moods (O234; client game_visualfx, option `screenGrade`): a gentle colour grade of the map picture by area.
	-- kind: "ice" (cold blue), "swamp" (sickly green), "desert" (warm amber), "fire" (warm amber-red), "crypt" (desaturated
	-- and dim). The client holds the numbers (grademood_logic.lua) and eases to the new kind over about 2 s when the
	-- player crosses a border, so a border needs no soft edge here. Same shape and lookup as `ambient.areas` (first area
	-- that holds the tile wins; a tile in none has no mood, the message carries no `m`, the grade is the plain one).
	--  * The generated areas are exact (areagen_config.lua origins and sizes).
	--  * The surface places are SAMPLE SITES of docs/MAP_GUIDE.md (swamp town, the two deserts, the two ice fields; the
	--    map is not in the repository, so these boxes are a guess around those points) and are MARKED FOR THE OWNER TO FIT:
	--    widen or move them with the real extent of each swamp, desert and ice land (the map editor shows the tile), one
	--    line each. Ice sits on floors 6-7 because the sample sites are at z 6 and 7.
	mood = {
		enabled = true,
		areas = {
			{name = "emberdeep", kind = "fire", minZ = 9, maxZ = 10, box = {14400, 14400, 14495, 14475}},
			{name = "cinderfall", kind = "fire", minZ = 7, maxZ = 7, box = {14400, 14560, 14544, 14675}},
			{name = "ossuary", kind = "crypt", minZ = 9, maxZ = 10, box = {14560, 14400, 14689, 14501}},
			{name = "hollow vault", kind = "crypt", minZ = 9, maxZ = 9, box = {14560, 14560, 14675, 14655}},
			{name = "marrow crypts", kind = "crypt", minZ = 9, maxZ = 9, box = {24576, 24576, 24679, 24659}},
			{name = "iron crucible", kind = "fire", minZ = 9, maxZ = 9, box = {24832, 24576, 24935, 24659}},
			{name = "pyre throne", kind = "fire", minZ = 9, maxZ = 9, box = {24832, 24832, 24935, 24915}},
			{name = "swamp town", kind = "swamp", minZ = 7, maxZ = 7, box = {32880, 32010, 33000, 32110}},
			{name = "desert west", kind = "desert", minZ = 7, maxZ = 7, box = {33000, 31330, 33100, 31420}},
			{name = "desert east", kind = "desert", minZ = 7, maxZ = 7, box = {33200, 31310, 33300, 31410}},
			{name = "ice settlement", kind = "ice", minZ = 6, maxZ = 7, box = {31950, 31310, 32040, 31400}},
			{name = "ice field", kind = "ice", minZ = 6, maxZ = 7, box = {32000, 31060, 32100, 31150}}
		}
	},

	-- Not kept: the base's thunder (a 50% chance per drop to strike a player standing on the drop's tile, 1-5 energy
	-- damage, about once in 30 seconds out in the rain). The server no longer places drops.
}
