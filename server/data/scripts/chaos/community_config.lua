-- Community goals and the weekly world modifier (community.lua, community_core.lua; client game_community, extended
-- opcode ChaosOpcodes.community = 203). Every number of the system lives here. Returned as a table and loaded as
-- Chaos.communityConfig = dofile("data/scripts/chaos/community_config.lua"). Lua 5.1 / LuaJIT and Lua 5.3.
-- Item ids are SERVER ids. Overview: server/README.md "Community goals and the weekly world modifier".
return {
	enabled = true,
	opcode = 203,
	staffGroup = 4, -- /community; characters of this group or higher add nothing and are never ranked
	-- the week: Monday at resetHour, server local time (the rule of the leaderboards, the bounty board and the raid)
	resetHour = 6,

	-- ------------------------------------------------------------------------------------------------ the goal
	goal = {
		name = "Fuel the Brazier",
		text = "Everything the world does this week feeds the Great Brazier. Each stage lights a blessing for everyone.",
		-- the goal's period: periodDays = 7 is the week above; any other number of days is counted from `epoch` (a Monday,
		-- YYYYMMDD) at resetHour. The period key is the YYYYMMDD of the day the period started.
		periodDays = 7,
		epoch = 20260105,
		target = 1500000, -- points to reach 100%
		-- Season realms (season.lua, realm = the season id of a season character, 0 for everybody else):
		--   "together"  one goal; season characters add to it and get its buffs like everybody else
		--   "separate"  every realm has its own goal, progress, ranking and buffs (the website shows each)
		realms = "together",
		-- per character and day (the day turns at resetHour): points beyond these are not counted
		dailyCap = 12000,
		-- the sources: points per unit and the daily cap of that source (points). The hooks are in community.lua.
		sources = {
			{key = "kill", name = "Monsters slain", points = 1, dailyCap = 4000,
				tierMult = {magic = 2, rare = 4, legendary = 8, boss = 10}, minLevelShare = 0.4},
			{key = "rift", name = "Rifts sealed", points = 120, perTier = 15, dailyCap = 3000},
			{key = "invasion", name = "Invasion waves repelled", points = 40, dailyCap = 2500}, -- per wave of a won invasion
			{key = "worldboss", name = "World bosses slain", points = 400, dailyCap = 2000},
			{key = "orb", name = "Crafting orbs used", points = 12, dailyCap = 1500},
			{key = "brazier", name = "Gold given to the Brazier", points = 1, perGold = 1000, dailyCap = 5000}
		},
		-- the stages: the percent of the target, and the buff it lights for `hours` from the moment it is reached (a
		-- stage reached again in a later period starts a new window; an open window outlives the period it came from).
		-- bonus: xp / loot (fractions: 0.10 = +10%), riftKey (percentage points on a sealed rift's key chance), rep
		-- (fraction on faction reputation gains). text: the buff bar and the website; short: the window's stage chip. Each
		-- stage has its own icon "buff:community_<key>".
		stages = {
			{pct = 25, key = "kindled", name = "Kindled Brazier", hours = 24, bonus = {xp = 0.10},
				text = "+10% experience from monsters", short = "+10% experience"},
			{pct = 50, key = "bounty", name = "Ashen Bounty", hours = 24, bonus = {loot = 0.10},
				text = "+10% Chaos loot quantity (extra loot rolls and currency)", short = "+10% loot"},
			{pct = 75, key = "beacon", name = "Rift Beacon", hours = 24, bonus = {riftKey = 5},
				text = "+5% chance of a new Rift Key when a rift is sealed", short = "+5% key chance"},
			{pct = 100, key = "ablaze", name = "Brazier Ablaze", hours = 48, bonus = {rep = 0.20, xp = 0.05},
				text = "+20% faction reputation and +5% experience", short = "+20% reputation"}
		},
		-- rewards when a period ends (given at the character's next login): the top `top` get the title for titleDays
		-- (name plates, titles.lua); everybody with at least token.minPoints gets the token items (backpack, else inbox)
		rewards = {
			top = 3,
			title = "Keeper of the Flame",
			titleColor = "#f08a4b",
			titleDays = 7,
			token = {minPoints = 1500, items = {{id = 29856, count = 2}, {id = 29857, count = 1}},
				text = "2 Orbs of Upheaval and an Orb of Fate"}
		},
		topShown = 5, -- contributors in the window and on the website
		announceSteps = {10, 25, 50, 75, 90, 100} -- broadcasts as these percents are passed (stages broadcast anyway)
	},

	-- ------------------------------------------------------------------------------------------------ the Brazier
	-- A gold sink in the main temple: an object placed at startup next to the temple (or exactly at `pos`). Using it
	-- opens the donate dialog of the client; the window's Donate button works only within `range` tiles of it.
	brazier = {
		townId = 2, -- the main temple: Cinderhold, the main city (server/README.md "Main city"; nil town: pos must be set)
		pos = nil, -- {x =, y =, z =} to place it exactly
		offsets = {{3, -2}, {-3, -2}, {3, 2}, {-3, 2}, {4, 0}, {-4, 0}, {0, 4}, {0, -4}},
		itemId = 1481, -- coal basin (stock); the dark tile set's "brazier" is used when installed
		darkTile = "brazier",
		actionId = 47901,
		range = 4,
		minGold = 1000,
		maxGold = 10000000, -- per donation
		dailyGold = 5000000, -- per character and day (= the source's dailyCap x perGold)
		description = "The Great Brazier. Gold given to it feeds the community goal."
	},

	-- ------------------------------------------------------------------------------------------------ the week
	-- One or two modifiers from the pool, drawn by the week's seed (the same on every server start, in LuaJIT and in
	-- Lua 5.3); staff may override the week with /community modifier. Two of one `group` never come together.
	-- Effects (community.lua applies each through an existing hook, see server/README.md):
	--   events = {...}        bonuses of the events calendar for everyone (events_schedule.lua ChaosEvents.dynamic):
	--                         tierChance, ambush, goblin, towerPoints, loot, xp (multipliers)
	--   family + xp / loot    the bestiary family's monsters give more experience / Chaos loot (fractions)
	--   riftMods, riftReward  a rift opened this week rolls riftMods more modifiers and its chests are riftReward % richer
	--   orbKeep               percent chance that a crafting orb is not used up (the expected orb cost goes down by it)
	--   rep                   faction reputation gains (fraction)
	week = {
		seedSalt = "brazier",
		count = {{1, 55}, {2, 45}}, -- {how many, weight}
		pool = {
			{key = "ember_tides", name = "Ember Tides", group = "rift", weight = 100, riftMods = 1, riftReward = 15,
				text = "Rifts open with one more modifier, and their rewards are 15% richer."},
			{key = "champions_week", name = "Champions' Week", group = "tier", weight = 100, events = {tierChance = 1.5},
				text = "Magic, rare and legendary monsters appear 50% more often."},
			{key = "restless_dead", name = "Restless Dead", group = "family", weight = 100, family = "undead", xp = 0.30, loot = 0.30,
				text = "Undead give 30% more experience and 30% more Chaos loot."},
			{key = "gilded_week", name = "Gilded Week", group = "goblin", weight = 80, events = {goblin = 2},
				text = "Treasure goblins appear twice as often."},
			{key = "forgefire", name = "Forgefire", group = "craft", weight = 90, orbKeep = 20,
				text = "Crafting orbs cost 20% less: each orb used has a 20% chance to be kept."},
			{key = "dragonfall", name = "Dragonfall", group = "family", weight = 70, family = "dragons", xp = 0.25, loot = 0.25,
				text = "Dragons give 25% more experience and 25% more Chaos loot."},
			{key = "ambush_season", name = "Ambush Season", group = "tier", weight = 70, events = {ambush = 1.5},
				text = "Ambushes after a kill are 50% more likely."},
			{key = "banner_week", name = "Banner Week", group = "rep", weight = 70, rep = 0.20,
				text = "Faction reputation gains are 20% higher."},
			{key = "tower_echoes", name = "Tower Echoes", group = "tower", weight = 60, events = {towerPoints = 1.5},
				text = "The Infinity Tower gives 50% more points."}
		},
		-- when the bestiary is not loaded: monster names with one of these words count for the family
		familyWords = {
			undead = {"skeleton", "zombie", "ghoul", "mummy", "lich", "vampire", "ghost", "banshee", "wraith", "spectre",
				"specter", "phantom", "bonebeast", "undead", "revenant", "crypt", "grave", "bone", "lost soul"},
			dragons = {"dragon", "wyrm", "drake", "wyvern", "hydra"}
		},
		announceOnLogin = true
	},

	-- ------------------------------------------------------------------------------------------------ engine
	flushSeconds = 60, -- contributions and the goal are written to SQL this often (and at logout / a stage)
	pushSeconds = 20, -- an open window gets the state again this often
	requestMs = 1500, -- the client may ask this often
	keepPeriods = 12, -- contribution rows of older periods are deleted at startup
	tables = {
		goal = "chaos_community_goal",
		buffs = "chaos_community_buffs",
		contrib = "chaos_community_contrib",
		week = "chaos_community_week",
		history = "chaos_community_history"
	},
	overrideKey = "chaos_community_override" -- server_config row: "<week>:<key>,<key>" of a staff override
}
