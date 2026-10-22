-- Waystone tier maps (waystone_tiers.lua, waystone_tiers_core.lua; server/README.md "Waystone tiers"): every number.
-- Plain table: ChaosWaystoneTiers.config = dofile("data/scripts/chaos/waystone_tiers_config.lua"). Lua 5.1 / LuaJIT and 5.3.
--
-- The base waystone system (data/scripts/customs/waystone_system/tier_maps.lua) sends a group with a Waystone Tier
-- item (I to VI) to one of two maps of that tier. Its monsters (data/monster/lua/waystone_portals/waystone_map_<tier>)
-- have about the same experience and health in every tier (38k-65k experience, 35k-120k health), so their hunting
-- level (bounty_pool.lua, the experience / health estimate) is 468-612 in every tier: player report 2026-10-22 "from
-- tier 1 to tier 4 the monsters are the same level". Here a tier's monsters, inside that tier's maps, count at their
-- hunting level x levelMult[tier]: the level shown after the name, the item level of their drops, the late-game damage
-- boost (monster_damage.lua) and pack combat read it (ChaosLoot.monsterLevel); health, damage to players and experience
-- follow the engine's own level formulas (health x(1 + 0.0074 L), damage x(1 + 0.0015 L), experience x L), as the
-- generated areas scale theirs (areagen_core.lua A.levelScale).
return {
	enabled = true,

	-- the level of a tier's monster = its hunting level x this (tier I stays as it was: 468-612)
	levelMult = {1.0, 1.2, 1.4, 1.6, 1.8, 2.0},

	-- the engine's level factors (config.lua monsterBonus*: the same numbers areagen_core.lua A.levelScale uses)
	healthPerLevel = 0.0074,
	damagePerLevel = 0.0015,

	-- the tier bosses keep their own health and level (the base files already rise by tier: 300k to 1M health); their
	-- damage to players is x this (player report 2026-10-22: "the boss barely damages")
	bossDamage = {1.0, 1.1, 1.2, 1.3, 1.4, 1.5},

	-- Morgrath (tier V) takes damage only next to a Katoi Pillar, Nyxdrath (tier VI) only of the element of the pillar
	-- next to it (the base boss files; tools/patch_waystone_bosses.py). Away from a pillar a hit now keeps this share
	-- instead of nothing (player report 2026-10-22: "health bar stays at 100%"), and the attacker is told the rule at
	-- most every hintSeconds.
	shieldedShare = 0.25,
	hintSeconds = 20,

	-- the maps of each tier (tier_maps.lua teleportMapping: fromPos / toPos of each area)
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
