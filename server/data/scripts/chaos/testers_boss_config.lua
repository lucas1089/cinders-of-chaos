-- Tester copies of the key bosses (testers_boss.lua, O652, server/README.md "The rest of the closed audit (O589)" step 10). Plain data, Lua 5.1 / LuaJIT
-- and 5.3.
return {
	enabled = true,

	-- no player within this many tiles of the bot (one floor): a copy is made in secret, only while nobody can see it (the goblin's rule, O650)
	clearRadius = 40,
	-- no copy within this many tiles of a lair's boss spawn (the Boss Spawns tracker matches a kill by its place; the lair is the players')
	lairGuard = 45,
	-- the copy appears this many tiles from the bot (the first free tile of a ring, nearest to this)
	spotDistance = 7,
	-- tiles round the copy that make its fight arena (boss_mechanics.lua attach, a box of walkable tiles outside protection zones)
	arenaRadius = 10,
	-- tiles within which the guide says fight; the bot's own rotation does the rest
	reach = 6,
	-- the copy's health as a share of the boss's: a copy is hurt by one tester, so it is made weak enough to fall in a few minutes; its
	-- telegraphs, adds and enrage are the boss's own (the mechanics read the health the copy has)
	healthShare = 0.02,
	-- seconds a copy stays when nobody kills it (then it is removed, nothing is paid)
	lifeSeconds = 480,

	-- the bosses a tester may ask for (the names of boss_mechanics_config.lua profiles with telegraphs): the highest `refLevel` the bot's level
	-- reaches is chosen. Weekly island bosses and the arena world bosses are the players' events (testers do not enter them); their mechanics are played here.
	bosses = {
		"Kaelgor the Infernal Warlord", "Skaldra the Rime Queen", "The Rotmother", "Nyxareth the Void Archon", "Vharok the Blood Colossus",
		"Talath", "Malgrath, the Drowned Crown"
	}
}
