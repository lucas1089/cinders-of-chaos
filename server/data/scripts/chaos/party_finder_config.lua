-- Party Finder (LFG) settings (party_finder.lua, party_finder_core.lua). Loaded with
--     Chaos.partyFinderConfig = dofile("data/scripts/chaos/party_finder_config.lua")
-- Every number of the Party Finder lives here. Listings are in memory only (they are transient: a restart clears them).
-- Overview: server/README.md "Party Finder". Lua 5.1 / LuaJIT and Lua 5.3 compatible.

return {
	enabled = true,

	-- ------------------------------------------------------------------ roles
	-- the three roles of a group (docs/CLASSES.md "Roles in a group"); c = the colour the client draws the role in
	roles = {
		{key = "tank", name = "Tank", c = "#7fb8e8"},
		{key = "healer", name = "Healer", c = "#6fd8a8"},
		{key = "dps", name = "DPS", c = "#e8846a"}
	},
	-- the roles a class may fill, by vocation id (Chaos.classes.ids); the first one is the class's main role, used for
	-- party members who joined without a listing role. A vocation not listed fills `defaultRoles`.
	--   Tank: Juggernaut, Sentinel, Samurai (duelist off-tank); the Warrior and Templar base classes may tank too.
	--   Healer: Illusionist (the best healer), Iron Sage (the second healer), the Sentinel's healing aura; the Mystic base
	--   class already has Purifying Wellspring.
	classRoles = {
		[4] = {"tank", "dps"}, [8] = {"tank", "dps"}, [14] = {"dps"}, -- Warrior, Juggernaut, Berserker
		[3] = {"dps"}, [7] = {"dps"}, [15] = {"dps"}, -- Ranger, Deadeye, Beastmaster
		[1] = {"dps", "healer"}, [5] = {"dps"}, [10] = {"healer", "dps"}, -- Mystic, Elementalist, Illusionist
		[11] = {"dps"}, [12] = {"dps"}, [13] = {"tank", "dps"}, -- Thief, Ninja, Samurai
		[17] = {"dps"}, [18] = {"dps"}, [19] = {"healer", "dps"}, -- Monk, Shadowfist, Iron Sage
		[20] = {"dps"}, [21] = {"dps"}, [22] = {"dps"}, -- Necromancer, Lich, Bone Lord
		[23] = {"tank", "dps"}, [24] = {"dps"}, [25] = {"tank", "healer"} -- Templar, Inquisitor, Sentinel
	},
	defaultRoles = {"dps"},

	-- ------------------------------------------------------------------ activities
	-- key, name, and what a listing names about it:
	--   range = {min, max, label, short}: a from-to range (rift tiers, tower floors); the engine file takes the rift max
	--           tier from rift_config.lua (maxTier)
	--   targets = "dungeons" | "worldBosses" | "omens" | "trials" | "raids": a pick list the engine file fills from the live
	--           configs (Chaos.dungeons.extra, Chaos.worldBoss.bosses, rift_config.lua omen.kinds, trials_config.lua tiers,
	--           raid_config.lua name);
	--           `fallback` when that config is not loaded. "Any" is always offered first.
	--   title = true: a short free text title is required ("other")
	--   maxParty = n: this activity's group size (leader + party + wanted), else the `maxParty` below
	--   perRole = {tank, healer, dps}: wanted count of each role, else `maxPerRole` below
	--   suggest = {tank, healer, dps}: what the client's form proposes when this activity is picked for a new listing
	activities = {
		{key = "rift", name = "Rift", range = {min = 1, max = 15, label = "Tier", short = "T"}},
		{key = "dungeon", name = "Dungeon", targets = "dungeons",
			fallback = {"Bones Dungeon", "Master of the Elements", "Forbidden Chevalier", "Rootkraken"}},
		{key = "worldboss", name = "World Boss", targets = "worldBosses"},
		{key = "omen", name = "Omen", targets = "omens",
			fallback = {"Sangrith the Bloodmoon Herald", "Morvane the Hollow Crown", "Thalcyra the Stormbound Seer"}},
		{key = "tower", name = "Infinity Tower", range = {min = 1, max = 200, label = "Floor", short = "F"}},
		{key = "raid", name = "Raid", targets = "raids", fallback = {"The Ashen Sepulchre"}, -- raid_config.lua name
			-- one engine party of 5-15 (raid_config.lua minPlayers / maxPlayers; TFS parties have no size cap)
			maxParty = 15, perRole = {tank = 3, healer = 4, dps = 12}, suggest = {tank = 2, healer = 3, dps = 9}},
		{key = "trial", name = "Trial", targets = "trials", fallback = {"Normal", "Cruel", "Merciless"}},
		{key = "battleground", name = "Battleground", maxParty = 5}, -- Ember Wells (battleground.lua): the leader queues the party
		{key = "other", name = "Other", title = true}
	},

	-- ------------------------------------------------------------------ listings
	maxParty = 10, -- leader + members + wanted slots of one listing (an activity's maxParty overrides it)
	maxPerRole = 6, -- wanted count of one role (an activity's perRole overrides it)
	maxLevel = 2000, -- highest minimum level a listing may ask for
	noteMax = 80, -- characters of the note (printable ASCII; longer is cut)
	titleMax = 24, -- characters of the "other" title
	expiryMinutes = {15, 30, 60, 120}, -- the choices; a listing closes by itself after it
	defaultExpiry = 60,
	maxListings = 300, -- listings at once on the server (a new one is refused past it)
	maxApplicants = 20, -- pending applications on one listing
	maxApplications = 5, -- pending applications of one character
	inviteSeconds = 90, -- an accepted applicant has this long to join the party; then the slot opens again
	declineCooldown = 120, -- seconds before a declined character may apply to the same listing again
	postCooldown = 20, -- seconds between two new listings of one character (updating your own is not limited by it)
	updateCooldown = 3, -- seconds between two updates of the own listing
	-- note filter: printable ASCII, these words (substring, any case) become asterisks, links are cut
	badWords = {"fuck", "shit", "bitch", "whore", "nazi", "hitler", "cunt", "rape"},
	linkTlds = {"com", "net", "org", "gg", "br", "io", "me", "ly", "tk", "xyz", "info", "biz", "ru", "co", "tv"},

	-- ------------------------------------------------------------------ quick join ("Join as role")
	queueMinutes = 30, -- a queued character leaves the queue after this
	-- a listing with "auto accept quick join" takes a match at once (party invite); otherwise the match is an
	-- ordinary application marked "quick"

	-- ------------------------------------------------------------------ engine
	staffGroup = 4, -- group id from which on a character is staff: sees and joins every realm, may close any listing
	tickMs = 2000, -- reconcile with the engine parties, expiry, queue matching, pushes to open windows
	readMs = 800, -- rate limit of open / list requests (ChaosRateLimit)
	actMs = 400 -- rate limit of every other action
}
