-- The weekly guild boss (guildboss.lua, guildboss_core.lua; client game_guildwar "Guild Boss" tab, extended opcode
-- ChaosOpcodes.guildWar = 197): every number. Loaded with  Chaos.guildBossConfig = dofile("data/scripts/chaos/guildboss_config.lua")
-- Plain data, no engine calls (tests/guildboss_test.lua reads it). Lua 5.1 / LuaJIT and Lua 5.3.
-- Overview: server/README.md "The weekly guild boss".
--
-- The week: the members fuel the Summoning Stone in their guild hall with gold and materials (embers; a gold sink:
-- the fuel is spent on the summon and what is left at the weekly reset is gone). With the stone full, the leader or a
-- vice-leader summons Gorvath the Banner-Eater: every member of the guild standing in the hall comes along into a
-- runtime-built arena. One kill per guild and week; a failed attempt keeps half of the fuel.
return {
	enabled = true,

	-- ------------------------------------------------------------------ the week (Monday 06:00, like the guild board)
	resetDay = 2, -- 1 = Sunday ... 2 = Monday (raid_core.lua weekKey)
	resetHour = 6,

	-- ------------------------------------------------------------------ fuel (embers)
	-- the stone needs need.base + need.perLevel x guild level embers (guild level 5: 625, 10: 750, 20: 1000)
	need = {base = 500, perLevel = 25},
	gold = {perEmber = 10000, min = 100000}, -- 10,000 gold = 1 ember; a gold donation is at least 100,000
	-- materials (server ids): embers per item. A donation hands over every one of that kind the member carries (up to
	-- maxPerDonation).
	materials = {
		{key = "shard", id = 32051, name = "rune shard", embers = 2},
		{key = "fragment", id = 32071, name = "omen fragment", embers = 3},
		{key = "upheaval", id = 29856, name = "Orb of Upheaval", embers = 5},
		{key = "fate", id = 29857, name = "Orb of Fate", embers = 25},
		{key = "grafting", id = 29855, name = "Orb of Grafting", embers = 60}
	},
	maxPerDonation = 100,
	failKeep = 0.5, -- a failed attempt keeps this share of the stone's need as fuel (the rest is burnt)
	maxAttempts = 3, -- summons per guild and week

	-- ------------------------------------------------------------------ the summon
	summonRank = 2, -- the leader and the vice-leaders
	minPlayers = 2, -- members in the hall that come along (with the summoner)
	maxPlayers = 20,
	minLevel = 150, -- members below stay behind
	startDelay = 10, -- seconds between the arrival and the boss
	exitDelay = 25, -- seconds after the kill before everyone is sent back to the hall
	tickMs = 250,
	hudEvery = 2, -- the rift HUD (opcode 228) like the Ascended arenas

	-- ------------------------------------------------------------------ the arena (runtime-built, uber_core.lua layout)
	-- x 11264-11455, y 10000-10095, z 7: 4 x 2 slots of 48. Free: no map tiles between x/y 3000 and 16000 (server/README.md
	-- "Rifts"), away from the other runtime areas (tower 2000+, island 4600+, world boss 5000, siege 5100+, arena 6000+,
	-- ascension trial 7000+, Ascended 7600-7700, rifts 8192-8447, trials 9000-9160, guild halls 9216-9535, the Ember
	-- Descent x 10000-10255 / y 10000-10127, the raid x 10400-10911 / y 10000-10511).
	grid = {origin = {x = 11264, y = 10000, z = 7}, cols = 4, slots = 8, spacing = 48},
	arena = {half = 10, anteGap = 2, anteHalfW = 3, anteHalfH = 1},
	groundId = 407,
	wallId = 5648,
	basinId = 1481,
	portalId = 1387,
	portalActionId = 47608, -- the Ember Gate of the guild boss arena (guild hall action ids 47601-47607)
	stoneId = 1560, -- obelisk: the Summoning Stone in every guild hall
	stoneActionId = 47609,
	dark = {enabled = true, style = "hall", wall = "obsidian_wall", basin = "brazier"},
	lives = {base = 3, perPlayers = 3, reenterSeconds = 8, shieldSeconds = 3}, -- base + 1 per perPlayers players

	-- ------------------------------------------------------------------ telegraphs (uber_core.lua U.pattern / markPlan)
	telegraph = {warnMs = 2000, turnMs = 1000, enragedWarnMs = 1200, share = 0.5, enragedShare = 0.75,
		warnEffect = "warning_zone", fillEffect = "warning_fill"},
	hazard = {share = 0.06, pulseMs = 1000},
	enrage = {damageMult = 1.6, everyMult = 0.5, pulseShare = 0.07, pulseMs = 4000},
	addHealthPerExtraPlayer = 0.35,
	patterns = {
		cone = {length = 7, spread = 3},
		ring = {inner = 3, outer = 7},
		circle = {radius = 3},
		marks = {radius = 1},
		cross = {halfWidth = 1},
		half = {},
		lines = {count = 3},
		eye = {safe = 2}
	},

	-- ------------------------------------------------------------------ the boss
	-- health = the XML health x (1 + healthPerExtraPlayer x (players - 1)); enrage / limit in seconds after it appears
	boss = {key = "gorvath", name = "Gorvath", boss = "Gorvath the Banner-Eater", add = "Banner Wraith",
		healthPerExtraPlayer = 0.6, enrageAt = 600, limit = 780, element = "death", hitEffect = "shadow_eruption",
		phases = {
			{at = 1.0, name = "The Gnawed Standard", every = 9000, patterns = {"cone", "ring", "marks"},
				yell = "YOUR BANNER WILL HANG IN MY GULLET!"},
			{at = 0.66, name = "Torn Colours", every = 8000, patterns = {"cross", "circle", "half"},
				adds = {base = 1, perPlayer = 0.5, every = 30000}, yell = "RISE, FALLEN STANDARD-BEARERS!"},
			{at = 0.33, name = "The Last Rally", every = 7000, patterns = {"cone", "ring", "cross", "eye", "lines"},
				hazard = {kind = "pools", count = 3, perPlayer = 0.5, radius = 1, effect = "burning", lastMs = 18000},
				adds = {base = 1, perPlayer = 0.25, every = 40000}, heal = {perAdd = 0.004},
				yell = "EVERY OATH YOU SWORE IS ASH IN MY MOUTH!"}
		}},

	-- ------------------------------------------------------------------ rewards
	-- every participant still in the arena at the kill (or fallen and waiting at the gate) who dealt at least
	-- minDamageShare of the boss's damage, or healed: gold to the bank balance and orbs (backpack, else store inbox).
	reward = {gold = 1500000, orbs = {{id = 29856, count = 6}, {id = 29857, count = 2}}, minDamageShare = 0.01},
	-- the guild: guild XP (guild levels) once per kill, and a banner tier from its weekly kills in total
	gxp = {base = 400, perPlayer = 20, max = 800},
	banners = {
		{kills = 1, name = "Ember Banner"},
		{kills = 4, name = "Cinder Banner"},
		{kills = 10, name = "Blazing Banner"},
		{kills = 20, name = "Banner of the Undying Flame"}
	},

	-- the balance model (like uber_config.lua): a level 600 character deals refDps; uptime = time on the boss
	model = {refDps = 1400, uptime = 0.75},
	targets = {party2 = 495, party5 = 420, party10 = 395}, -- seconds the health was set for (tests/guildboss_test.lua)
	bossHealth = 650000, -- must match the XML (tests/guildboss_test.lua checks it)

	board = {rows = 10},
	staffGroup = 4, -- /guildboss

	tables = {week = "chaos_guildboss_week", contrib = "chaos_guildboss_contrib", runs = "chaos_guildboss_runs"}
}
