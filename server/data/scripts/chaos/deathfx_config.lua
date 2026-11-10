-- Death and spawn effects of monsters (O456; deathfx_core.lua, deathfx.lua, tests/deathfx_test.lua; server/README.md
-- "Death and spawn effects"). Returned as a table, loaded as ChaosDeathFxConfig. Visual only: no damage, area, timing,
-- loot or spawn rule moves. Lua 5.1 / LuaJIT compatible.
--
-- An effect is {id, dx, dy, ms}: the effect id of the client pair, the offset in tiles it is sent at (an effect bigger
-- than a tile is drawn with its bottom-right tile on the tile it is sent to, so a 3x3 effect goes to +1,+1 to sit
-- centred; the same numbers as the ChaosVfx names in data/lib), and its length in ms (a note, the test bounds it). Ids
-- instead of ChaosVfx names so the file needs no other lib to be loaded first. The race is the monster XML race.
return {
	enabled = true,

	death = {
		enabled = true,
		-- a monster that dies: one short effect on its tile by race (chosen by eye on the sheets of pair 60: 300 to 750 ms,
		-- 2x2 or 3x3, centred). A client below the pair of an id shows nothing for it.
		effects = {
			blood = {id = 390, dx = 0, dy = 0, ms = 747}, -- blood_splash, 2x2: a dark red spray
			undead = {id = 584, dx = 1, dy = 1, ms = 720}, -- bone_burst, 3x3: bone shards fly out
			fire = {id = 803, dx = 1, dy = 1, ms = 700}, -- blast_fire3, 3x3: a burst into a fire ring
			energy = {id = 798, dx = 1, dy = 1, ms = 630}, -- blast_lightning, 3x3: white bolts and a blue star
			venom = {id = 811, dx = 1, dy = 0, ms = 700}, -- blast_poison, 3x2: a green venom burst
		},
		-- a boss (MonsterType:isBoss) dies: the large soft effect of its race, 5x5 to 7x7 (chaos_big_fx_ids.lua)
		boss = {
			blood = {id = 655, dx = 2, dy = 2, ms = 840}, -- big_geyser_blood_5
			undead = {id = 647, dx = 3, dy = 3, ms = 910}, -- big_nova_void_7
			fire = {id = 638, dx = 3, dy = 3, ms = 700}, -- big_shock_fire_7
			energy = {id = 652, dx = 3, dy = 3, ms = 600}, -- big_lightning_burst_7
			venom = {id = 645, dx = 3, dy = 3, ms = 840}, -- big_nova_poison_7
		},
		-- the most effects started in one instant (a pack that dies together, a rift wipe): a token bucket. Bosses skip it.
		budget = {capacity = 8, perSecond = 12},
	},

	spawn = {
		enabled = true,
		-- only a map respawn (not the server start, not a monster another script created: rift and tower packs, dungeons,
		-- generated areas, summons, bosses, which come with their own marks) and never a monster that is a boss
		skipStartup = true,
		skipArtificial = true,
		-- 1x1 puffs of pair 50 (effect ids 4102 to 4701), small so that they sit on top of the stock teleport puff of a
		-- respawn a player sees (engine src-patch 0041) without hiding it
		effects = {
			blood = {id = 4174, dx = 0, dy = 0, ms = 700}, -- a red blot that opens and fades
			undead = {id = 4156, dx = 0, dy = 0, ms = 400}, -- a blue grey smoke puff
			fire = {id = 4141, dx = 0, dy = 0, ms = 600}, -- an orange flash
			energy = {id = 4195, dx = 0, dy = 0, ms = 480}, -- a white lightning web
			venom = {id = 4157, dx = 0, dy = 0, ms = 600}, -- a green cloud
		},
		budget = {capacity = 6, perSecond = 6},
	},
}
