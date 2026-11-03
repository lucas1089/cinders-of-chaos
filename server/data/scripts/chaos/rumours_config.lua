-- Tavern rumours (O394; rumours.lua, rumours_core.lua, rumours_run.lua, the NPC Dorrin Alewright of
-- service_npcs_config.lua; server/README.md "Tavern rumours (O394)"). Every number. Plain data, no engine calls: the NPC
-- reads it in its own Lua state and rumours.lua in the main one, and both must plan the same appearances.
-- Lua 5.1 / LuaJIT and Lua 5.3.
return {
	enabled = true,

	-- what a rumour may be about, looking `horizonMinutes` ahead; a rumour is told only `leadMinutes` or more before
	-- the thing happens (a hint for the next hour, not a report of what is on now)
	horizonMinutes = 60,
	leadMinutes = 3,
	sources = {apparition = true, invasion = true, worldboss = true},

	-- the fee per rumour (gold, carried coins then the bank: Chaos.pay): base + perLevel x level, at most max.
	-- Nothing is charged when the keeper has nothing new for that player.
	fee = {base = 200, perLevel = 2, max = 2000},

	-- percent of rumours that are false (flavour): a believable apparition in another place and another window. The
	-- true rumour it replaced counts as heard (the player paid for that one).
	falseChance = 15,

	-- the vague time: a window of `width` minutes that holds the true time, starting `before` minutes (random in the
	-- range) earlier, rounded down to `round` minutes. Shown in server time.
	window = {width = 30, before = {5, 20}, round = 5},

	-- the rare appearances rumours.lua makes itself, planned per hour in advance from the hour and `salt` alone (the
	-- NPC and the spawner compute the same plan; a restart changes nothing):
	--   chance      percent of hours with one appearance
	--   minute      the minute of the hour it shows (random in the range)
	--   graceSeconds a spawn missed by this much (the server was down) is dropped
	--   minOnline   no spawn with fewer players online (the hint stays a rumour then)
	--   radius      the spawn tile: a free, walkable tile this far (min, max) from the region's point, same floor,
	--               never a protection zone or a house (ChaosInvasion.tileOk when loaded)
	--   monsters    by weight; kind "goblin" = a Treasure Goblin variant (ChaosTreasureGoblin.spawn, its own loot and
	--               escape rules), at the region's level
	--   regions     fixed places {key, name, level, point = {x, y, z}}; huntPlaces = true adds every hunt of
	--               data/lib/chaos_hunt_places.lua (install_content_areas.py: the planned hunts by their arrival tile,
	--               the base hunts of the teleport hall by their destination), level = the middle of the band
	--   levels      only regions whose level is in this range
	apparitions = {
		chance = 35,
		minute = {8, 52},
		graceSeconds = 180,
		minOnline = 1,
		radius = {6, 18},
		salt = 39401,
		monsters = {
			{kind = "goblin", variant = "hoarder", name = "Treasure Goblin", weight = 70},
			{kind = "goblin", variant = "gem", name = "Gem Goblin", weight = 20},
			{kind = "goblin", variant = "shard", name = "Shard Goblin", weight = 10}
		},
		-- the two hunting grounds of invasion_config.lua (read from the real map); more can be added here
		regions = {
			{key = "cinderholdfields", name = "the Cinderhold fields", level = 150, point = {x = 32345, y = 32315, z = 7}},
			{key = "thornmerewilds", name = "the Thornmere wilds", level = 100, point = {x = 32370, y = 31710, z = 7}}
		},
		huntPlaces = true,
		levels = {20, 2500}
	},

	-- the world boss: its rotation (chaos_constants.lua Chaos.worldBoss: hours and the global storage of the last boss)
	-- names the next one; mode "random" gives an unnamed beast
	worldBoss = {unknownName = "a great beast"}
}
