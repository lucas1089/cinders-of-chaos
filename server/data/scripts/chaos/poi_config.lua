-- Numbers and names of the points of interest (poi.lua, poi_core.lua; client game_mapmarkers). server/README.md
-- "Map markers". The marks of the map itself are generated at install (data/chaos_poi.lua, tools/gen_poi.py); what is
-- placed when the server starts (the Chaos NPCs, the portals next to the temples, the dungeons) is found here.
-- Lua 5.1 / LuaJIT and 5.3.
return {
	dataFile = "data/chaos_poi.lua",
	revealRange = 20, -- a discoverable mark is revealed when the character comes this close (squares, same floor)
	checkMs = 2000, -- how often the online characters are checked for reveals
	saveMs = 60000, -- the discoveries of a character are written at most this often (and at logout)
	firstScanMs = 20000, -- the runtime marks are looked for this long after the start (the systems place their NPCs and
	rescanMs = 300000, -- portals at startup) and again this often (an event portal comes and goes)
	templeRadius = 12, -- the runtime scan: NPCs and portals this close to a temple
	setMs = 500, -- a client's "set" at most this often
	staffGroup = 4, -- /poi (status | reset | all) for this group and up

	-- the Chaos NPCs (they stand next to temples): name (lower case) -> shown name
	npcs = {
		["material broker"] = "Material Broker (professions)",
		["mordecai ashwager"] = "Mordecai Ashwager, the Gambler",
		["keeper of trials"] = "Keeper of Trials (Vocation Trials)",
		["ascendant oracle"] = "Ascendant Oracle (ascension)",
		["warden ysolde"] = "Warden Ysolde (faction quartermaster)",
		["forgemaster brannoc"] = "Forgemaster Brannoc (faction quartermaster)",
		["cantor velith"] = "Cantor Velith (faction quartermaster)",
		["elder bramwyn"] = "Elder Bramwyn (faction quartermaster)",
		["wandering merchant"] = "Wandering Merchant",
		["archivist maelis"] = "Archivist Maelis (tales and lore)"
	},

	-- the portals the systems put next to the temples, found by their action id, read from the owning system's config
	-- (config file + path) or from a global table (global path), so the numbers live in one place only
	portals = {
		{kind = "portal", name = "Hideout portal", config = "hideout_config.lua", path = {"aid", "enter"}},
		{kind = "guild", name = "Guild hall portal", config = "guild_config.lua", path = {"hall", "aid", "enter"}},
		{kind = "portal", name = "The Ember Descent", config = "descent_config.lua", path = {"aid", "portal"}},
		{kind = "portal", name = "The Ashen Sepulchre (raid)", config = "raid_config.lua", path = {"aid", "portal"}},
		{kind = "portal", name = "Ember Gate (Ascended Omens)", config = "uber_config.lua", path = {"portalActionId"}},
		{kind = "portal", name = "Guild siege portal", config = "siege_config.lua", path = {"aid", "enter"}},
		{kind = "boss", name = "World boss portal", global = {"Chaos", "worldBoss", "aid", "enter"}}
	},

	-- the dungeons of the base dungeon system (DUNGEON_SYSTEM) at their entry point, discovered like hunting areas
	dungeons = true
}
