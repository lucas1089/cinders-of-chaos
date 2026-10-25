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
	}

	-- Not kept: the base's thunder (a 50% chance per drop to strike a player standing on the drop's tile, 1-5 energy
	-- damage, about once in 30 seconds out in the rain). The server no longer places drops.
}
