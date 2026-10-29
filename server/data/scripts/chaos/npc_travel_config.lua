-- Travel to an NPC (npc_travel.lua, npc_travel_core.lua; client game_npctravel, extended opcode ChaosOpcodes.npcTravel = 121;
-- server/README.md "Travel to an NPC"): every number and every NPC a panel can send a player to. Plain data, no engine calls
-- (tests/npc_travel_test.lua reads it). Lua 5.1 / LuaJIT and Lua 5.3.
--
-- A panel of the client that fronts an NPC's service (the Factions window, the Gambler, the stash, the Boss Spawns list, ...)
-- carries a "Go to NPC" button; the button sends `travel {k = <key below>}`. The server checks the same places the Town Portal
-- refuses (no arena, rift, dungeon, tower, hideout, instance, tutorial island, no combat, no skull), a cooldown, and
-- puts the player on a free tile in front of the NPC.
--
-- Where an NPC stands is never typed in here, it is read from where the NPC really is, in this order:
--   1. the live NPC: the creature of that name on the map (startup placement, npc_place.lua), whatever its town;
--   2. its stall in the hub (npc_booths_config.lua `booths`, the main city's market of the teleport room), which is also
--      where the front tile is worked out (the carpet walk, `hub.walkY`);
--   3. `pos` of the entry below, when one is set (nothing is set today);
--   4. the temple of `townId` (the NPCs placed "next to the temple": factions_config.lua, professions, ...).
-- With none of them the player is told, in a friendly line, that the NPC is not at their post (and the server logs it).
return {
	enabled = true,

	cooldownSeconds = 30, -- between two journeys of one player (counted from the journey; a refusal does not start it)
	requestMs = 1000, -- the window's travel request, per player (ChaosRateLimit)
	nearRange = 2, -- already this close (same floor) to the NPC: no journey, no cooldown
	maxRing = 2, -- the landing tile is searched this many tiles around the NPC (every service range is 3 or more)

	-- the hub (npc_booths_config.lua): players walk the carpet between the two rows of stalls and talk across the counter
	-- (2 squares). A stall north of walkY is reached from its south, a stall south of it from its north.
	hub = {walkY = 32233},

	-- key -> {name = the NPC's name (data/npc/<name>.xml), townId = the town whose temple the NPC stands next to when it is
	-- not in the hub, pos = {x, y, z} fixed spot (optional), where = English text of the panel line "in the market of the
	-- teleport room, Cinderhold" (translated by Chaos.t, i18n_strings.lua)}
	npcs = {
		stash = {name = "Tavish Coldhand", townId = 2, where = "Tavish Coldhand, the stash keeper, in the market of the teleport room in Cinderhold"},
		pocketboss = {name = "Vessa Hollowmark", townId = 2, where = "Vessa Hollowmark, the pocket boss NPC, in the market of the teleport room in Cinderhold"},
		banker = {name = "Cassian Auric", townId = 2, where = "Cassian Auric, the banker, in the market of the teleport room in Cinderhold"},
		broker = {name = "Halvard Deedkeeper", townId = 2, where = "Halvard Deedkeeper, the house broker, in the market of the teleport room in Cinderhold"},
		services = {name = "Pell Ashmere", townId = 2, where = "Pell Ashmere, the services clerk, in the market of the teleport room in Cinderhold"},
		gambler = {name = "Mordecai Ashwager", townId = 2, where = "Mordecai Ashwager, the Gambler, in the market of the teleport room in Cinderhold"},
		conquest = {name = "Iselde Varrow", townId = 2, where = "Iselde Varrow, the Conquest vendor, in the market of the teleport room in Cinderhold"},
		candlemarks = {name = "Osric the Chandler", townId = 2, where = "Osric the Chandler, in the market of the teleport room in Cinderhold"},
		materials = {name = "Material Broker", townId = 2, where = "the Material Broker, in the market of the teleport room in Cinderhold"},
		lootbuyer = {name = "Loot Buyer", townId = 2, where = "the Loot Buyer, in the market of the teleport room in Cinderhold"},
		trials = {name = "Keeper of Trials", townId = 2, where = "the Keeper of Trials, in the market of the teleport room in Cinderhold"},
		oracle = {name = "Ascendant Oracle", townId = 2, where = "the Ascendant Oracle, in the market of the teleport room in Cinderhold"},
		tales = {name = "Archivist Maelis", townId = 2, where = "Archivist Maelis, in the market of the teleport room in Cinderhold"},
		odrenna = {name = "Archivist Odrenna", townId = 2, where = "Archivist Odrenna, in the market of the teleport room in Cinderhold"},
		apothecary = {name = "Veyra the Apothecary", townId = 2, where = "Veyra the Apothecary, in the market of the teleport room in Cinderhold"},

		-- the four faction NPCs: "faction_" .. the faction's key (factions_config.lua; the test holds the names and towns to it)
		faction_vigil = {name = "Warden Ysolde", townId = 2, where = "Warden Ysolde, in the market of the teleport room in Cinderhold"},
		faction_compact = {name = "Forgemaster Brannoc", townId = 1, where = "Forgemaster Brannoc, next to the temple of Mirewake"},
		faction_choir = {name = "Cantor Velith", townId = 11, where = "Cantor Velith, next to the temple of Bellwatch"},
		faction_circle = {name = "Elder Bramwyn", townId = 4, where = "Elder Bramwyn, next to the temple of Thornmere"}
	},

	-- the places that hold a player (labels as the Town Portal says them); the refusal reads "from <label>"
	labels = {
		arena = "an arena match", worldBoss = "the world boss arena", siege = "a guild siege", rift = "a rift",
		dungeon = "a dungeon", tower = "the Infinity Tower", hideout = "your hideout", marches = "the Scorched Marches"
	}
}
