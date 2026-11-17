-- Boss lairs: a boss that lives in a small planned area of its own, reached by a portal in a hunt (bosslair.lua, pure
-- logic in bosslair_core.lua). Returned as a table; plain data, Lua 5.1 / LuaJIT and Lua 5.3.
-- Overview: server/README.md "Talath's lair (O616)".
--
-- A lair is a fixed area of server/tools/areaplan/rooms/ (install_all.py step contentareas places it at its own
-- origin, with the boss's map spawn and the exit portal). Its way in is not on the map: bosslair.lua puts a magic
-- forcefield on `portal` at startup, and only while the lair is open. tools/boss_lair_test.py holds every tile here
-- to the compiled plans.
--
-- A lair is open while config.lua `chaosClientPair` is `pair` or more (README "Client pair guard"): the boss's look
-- exists only from that client pair. Below it the portal is not placed, the engine's spawn of the boss is refused
-- (EventCallback onSpawn) and the Boss Spawns window does not list it (bossspawns_config.lua `minPair`).
return {
	enabled = true,

	-- action ids 47890-47899: the lair portals (47890; the rest free)
	aid = 47890,
	portalItem = 1387, -- magic forcefield, as the hunt teleports and the plans' exit portals

	lairs = {
		-- Talath, the hovering shard of ice (owner 2026-11-17: "Talath: put a spawn of it"). A boss for a group: 21M
		-- health, the ice mechanics of boss_mechanics_config.lua (Frost Lance, Winter Ring, Deep Freeze, fair for a
		-- level 650 player). Its lair hangs off the Glacial Col of the Frostvein Reach, the ice hunt of levels 575-690.
		{
			key = "talath",
			monster = "Talath",
			name = "The Shard Hollow",
			pair = 73, -- look 3529 is an outfit of client pair 73 (install step monstercreaturelooks)
			plan = "shard_hollow", -- server/tools/areaplan/rooms/shard_hollow.json
			at = {x = 15840, y = 15500, z = 7}, -- the plan's origin
			arrival = {38, 71, 0}, -- the arrival tile's offset from the origin (the protected Rime Ledge)
			boss = {40, 17, 0}, -- the boss's spawn point, offset from the origin (the Shard Hall)
			hunt = "frostvein_reach", -- server/tools/areaplan/plans/frostvein_reach.json
			portal = {x = 16794, y = 14352, z = 7}, -- the way in: a bare tile in the middle of the Glacial Col
			back = {x = 16794, y = 14354, z = 7}, -- where the lair's exit portal leads (the plan's exit.to)
			minLevel = 500, -- the portal lets nobody in below it: the boss's weakest hit is over 5,000
			respawn = 14400, -- seconds; the plan's boss block (4 hours, like Vharzul the Verdant Eye)
			text = "A rift of frost. Beyond it Talath waits in the Shard Hollow."
		}
	}
}
