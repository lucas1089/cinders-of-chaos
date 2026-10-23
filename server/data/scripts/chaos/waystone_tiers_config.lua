-- Waystone tier maps (waystone_tiers.lua, waystone_tiers_core.lua; server/README.md "Waystone tiers"): every number.
-- Plain table: ChaosWaystoneTiers.config = dofile("data/scripts/chaos/waystone_tiers_config.lua"). Lua 5.1 / LuaJIT and 5.3.
--
-- The base waystone system (data/scripts/customs/waystone_system/tier_maps.lua) sends a group with a Waystone Tier
-- item (I to VI) to one of two maps of that tier. Its monsters (data/monster/lua/waystone_portals/waystone_map_<tier>)
-- have about the same experience and health in every tier (hunting level 468-612). Owner 2026-10-23: "the first
-- waystone level 1100 and the last 2500, new waystones for it, a gradual rise; 2-3 scenarios for the low, the middle and
-- the high levels". So there are 15 tiers now (I-VI the base items, VII-XV ours: tools/install_waystone_items.py), each
-- 100 levels above the one before, in three bands of five; a band opens one of the maps of its band (the base's two maps
-- of two base tiers: four scenarios a band). A run's tier sets the level of every monster of the map it opened
-- (tools/patch_waystone_hideout.py part 3 calls ChaosWaystoneTiers.startRun): the level shown after the name, the item
-- level of drops, the late-game damage boost and pack combat read it (ChaosLoot.monsterLevel); health, damage to players
-- and experience follow the engine's own level formulas (health x(1 + 0.0074 L), damage x(1 + 0.0015 L),
-- experience x L), from the monster's hunting level to the run's level, as the generated areas scale theirs
-- (areagen_core.lua A.levelScale). A map with no run yet counts at the first tier of its band.
return {
	enabled = true,

	-- the tiers, in order: the level of the run's monsters and the Waystone Tier item that opens it. I-VI: the base
	-- items (base = true: the base window keys them by their client ids); VII-XV: tools/install_waystone_items.py
	tiers = {
		{level = 1100, item = 29845, base = true},
		{level = 1200, item = 29846, base = true},
		{level = 1300, item = 29847, base = true},
		{level = 1400, item = 29848, base = true},
		{level = 1500, item = 29849, base = true},
		{level = 1600, item = 29850, base = true},
		{level = 1700, item = 41951},
		{level = 1800, item = 41952},
		{level = 1900, item = 41953},
		{level = 2000, item = 41954},
		{level = 2100, item = 41955},
		{level = 2200, item = 41956},
		{level = 2300, item = 41957},
		{level = 2400, item = 41958},
		{level = 2500, item = 41959}
	},

	-- the bands: tiers first..last open a map of the base tiers `maps` (each base tier has two maps, see `maps` below)
	--   low  1100-1500: the water cave and the cave of tier I, the plain and the cave of tier II
	--   mid  1600-2000: the plain and the cave of tier III, the forest and the underground of tier IV
	--   high 2100-2500: the desert, the ice, the undead cave, the forest & desert
	bands = {
		{name = "low", first = 1, last = 5, maps = {1, 2}},
		{name = "mid", first = 6, last = 10, maps = {3, 4}},
		{name = "high", first = 11, last = 15, maps = {5, 6}}
	},

	-- waystone drops (ChaosWaystoneTiers.retierDrops, after loot.lua's level gate): a waystone dropped outside the maps
	-- is a Tier I; inside a run of tier T it is T, T+1 or T+2 by these chances (never above the last tier), and the
	-- run's boss always drops one of tier T+1 as well
	drops = {
		inside = {{step = 0, chance = 60}, {step = 1, chance = 30}, {step = 2, chance = 10}},
		bossNext = true
	},

	-- the engine's level factors (config.lua monsterBonus*: the same numbers areagen_core.lua A.levelScale uses)
	healthPerLevel = 0.0074,
	damagePerLevel = 0.0015,

	-- the bosses of the base tiers (the base files already rise by base tier: 300k to 1M health): damage to players x
	-- this (player report 2026-10-22: "the boss barely damages"); in a run above the first tier of its band, health,
	-- damage and experience x the engine's level factors from that first tier's level to the run's
	bossDamage = {1.0, 1.1, 1.2, 1.3, 1.4, 1.5},

	-- Morgrath (tier V) takes damage only next to a Katoi Pillar, Nyxdrath (tier VI) only of the element of the pillar
	-- next to it (the base boss files; tools/patch_waystone_bosses.py). Away from a pillar a hit now keeps this share
	-- instead of nothing (player report 2026-10-22: "health bar stays at 100%"), and the attacker is told the rule at
	-- most every hintSeconds.
	shieldedShare = 0.25,
	hintSeconds = 20,

	-- the maps of each base tier (tier_maps.lua teleportMapping: fromPos / toPos of each area); the map's monsters are
	-- that base tier's (below), whatever the run's tier
	maps = {
		{tier = 1, from = {x = 33314, y = 33066, z = 8}, to = {x = 33606, y = 33178, z = 8}},
		{tier = 1, from = {x = 32848, y = 33353, z = 7}, to = {x = 33096, y = 33506, z = 7}},
		{tier = 2, from = {x = 33294, y = 32984, z = 7}, to = {x = 33463, y = 33140, z = 7}},
		{tier = 2, from = {x = 33100, y = 33083, z = 8}, to = {x = 33281, y = 33215, z = 8}},
		{tier = 3, from = {x = 32847, y = 33173, z = 7}, to = {x = 33067, y = 33294, z = 7}},
		{tier = 3, from = {x = 32911, y = 33044, z = 8}, to = {x = 33073, y = 33241, z = 8}},
		{tier = 4, from = {x = 33112, y = 33168, z = 7}, to = {x = 33303, y = 33308, z = 7}},
		{tier = 4, from = {x = 33156, y = 33305, z = 8}, to = {x = 33349, y = 33453, z = 8}},
		{tier = 5, from = {x = 33351, y = 33170, z = 7}, to = {x = 33556, y = 33356, z = 7}},
		{tier = 5, from = {x = 32930, y = 32960, z = 7}, to = {x = 33245, y = 33129, z = 7}},
		{tier = 6, from = {x = 32890, y = 33257, z = 8}, to = {x = 33107, y = 33437, z = 8}},
		{tier = 6, from = {x = 33124, y = 33376, z = 7}, to = {x = 33395, y = 33582, z = 7}}
	},

	-- the monsters of each tier (the base folders waystone_map_<tier>; the map spawns of each tier's two maps hold
	-- exactly these) and its boss (waystone_bosses/boss_waystone_<tier>_map_<n>.lua)
	monsters = {
		{"Armorcoil", "Blazefang", "Gorgulith", "Nexlurith", "Voidwagner"},
		{"Aegis Sentinel", "Flarevein Wyrm", "Gloomstinger", "Pyroquill", "Toxic Mauler"},
		{"Ashfang Wrym", "Bloodspark Adept", "Glacial Hellcharger", "Nightfang Widow", "Shadowcrystal Widow"},
		{"Bloodshade Reaper", "Duskhorn Drake", "Nightflare Dreadknight", "Shadowvein Wrym", "Umbral Arcanist"},
		{"Hellmaw Brute", "Mirethorn Hexer", "Mossfang Drake", "Plague Warbringer", "Viridscale Wrym"},
		{"Embermaw Archon", "Inferno Juggernaut", "Pitlord Incarnate", "Stormvein Wrym", "Waterglow Conjurer"}
	},
	bosses = {"Vorgrun of the Jade Fangs", "Fractalis the Shardmaw", "Frostreaver the Glacialblade",
		"Rhazgor the Crimson Slayer", "Morgrath the Umbral Archmage", "Nyxdrath the Midnight Terror"},

	-- the layout audit (tools/audit_waystone_maps.py, run on an installed base server; tests/waystone_layouts_test.lua keeps
	-- this table and the maps above in step). One row per entry of `maps`: status "ok" (arrival, levers, boss room and
	-- spawns all reachable on the map as the server runs it, with `clearPath` applied) or "retired" (the map is left out
	-- of the options of its band: add its `from` to `retired` below). Audited 2026-10-23 on the base map: all 12 ok; the
	-- two tier IV maps (forest, underground) only with `clearPath` (the raw map fails: lever cut off).
	layouts = {
		{map = 1, name = "Water cave (tier I)", status = "ok"},
		{map = 2, name = "Cave (tier I)", status = "ok"},
		{map = 3, name = "Plain (tier II)", status = "ok"},
		{map = 4, name = "Cave (tier II)", status = "ok"},
		{map = 5, name = "Plain (tier III)", status = "ok"},
		{map = 6, name = "Cave (tier III)", status = "ok"},
		{map = 7, name = "Forest (tier IV)", status = "ok", needs = "clearPath"},
		{map = 8, name = "Underground (tier IV)", status = "ok", needs = "clearPath"},
		{map = 9, name = "Desert (tier V)", status = "ok"},
		{map = 10, name = "Ice (tier V)", status = "ok"},
		{map = 11, name = "Undead cave (tier VI)", status = "ok"},
		{map = 12, name = "Forest and desert (tier VI)", status = "ok"}
	},
	-- maps the audit failed and nothing can fix: their `from` corner; WT.optionsFor leaves them out of the band's options
	-- (a band always keeps at least two maps)
	retired = {},

	-- blocking items taken off the map at startup so a tier's boss lever can be reached on foot (player report
	-- 2026-10-22: "one layout has no boss lever"). Found with the base map (tools/map/otbm.py): in both tier IV maps the
	-- lever and the tiles its group stands on are cut off from the arrival.
	--   tier IV, forest (lever 33209,33239,7): a pocket of 152 tiles closed by one small fir tree
	--   tier IV, underground (lever 33282,33426,8): the corridor grid's platforms are joined by rope bridges whose two
	--   rows both carry a rope railing (block solid); the north railing of the two bridges on the way to the lever goes
	-- An entry whose item is not on its tile (any more) is skipped.
	clearPath = {
		{x = 33217, y = 33237, z = 7, item = 2768},
		{x = 33263, y = 33412, z = 8, item = 3784},
		{x = 33264, y = 33412, z = 8, item = 3770},
		{x = 33265, y = 33412, z = 8, item = 3770},
		{x = 33266, y = 33412, z = 8, item = 3770},
		{x = 33267, y = 33412, z = 8, item = 3770},
		{x = 33274, y = 33412, z = 8, item = 3784},
		{x = 33275, y = 33412, z = 8, item = 3770},
		{x = 33276, y = 33412, z = 8, item = 3770},
		{x = 33277, y = 33412, z = 8, item = 3770}
	}
}
