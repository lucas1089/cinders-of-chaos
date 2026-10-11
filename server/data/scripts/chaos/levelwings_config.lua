-- Level-up wings (levelwings.lua, levelwings_core.lua; client game_levelwings; server/README.md "Level-up wings"):
-- every number. Plain table, loaded with
--     ChaosLevelWingsConfig = dofile("data/scripts/chaos/levelwings_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,

	-- one character plays the wings at most once in this time; a level-up inside it is dropped (the stock text and
	-- effect still show). Covers a staff set_level pressed again and again, and several kills in a row that each give
	-- a level. Several levels from one experience gain are one onAdvance call, so they play once anyway.
	playerCooldownMs = 4000,

	-- one viewer is sent at most viewerMax wings per viewerWindowMs (mass level-ups on one screen)
	viewerWindowMs = 1000,
	viewerMax = 3,

	-- the whole server sends at most globalMax level-up broadcasts per globalWindowMs (a staff command levelling
	-- everyone at once); the rest are dropped
	globalWindowMs = 1000,
	globalMax = 40,

	-- spectators: players who see the character's tile (the engine's view range), this floor only
	multifloor = false,

	-- forget throttle entries older than this (memory), checked at most once per pruneEveryMs
	pruneAfterMs = 60000,
	pruneEveryMs = 30000
}
