-- Pocket bosses (pocketboss.lua, pocketboss_core.lua; client game_bossspawns "Pocket" button, extended opcode
-- ChaosOpcodes.bossSpawns = 217, actions pocket*): every number. Loaded with
--   Chaos.pocketBossConfig = dofile("data/scripts/chaos/pocketboss_config.lua")
-- Plain data, no engine calls (tests/pocketboss_test.lua reads it). Lua 5.1 / LuaJIT and Lua 5.3.
-- Overview: server/README.md "Pocket bosses". Numbers to review: docs/OWNER_TODO.md "Pocket bosses".
--
-- A pocket is a private copy of a boss that is otherwise time-gated or contested (the world bosses, the weekly island
-- bosses, the bosses of the random base raids such as Moloveth), opened any time from the Boss Spawns window. It costs
-- one daily charge per player (party members each spend one) and pays less than the scheduled fight: the scheduled and
-- contested versions stay the full-reward social events.
return {
	enabled = true,

	-- ------------------------------------------------------------------ charges (per character and boss)
	-- daily: free charges per boss and day; the day turns at resetHour:00 server time (0 = midnight: the day of
	-- Chaos.dayKey, as the daily reward and the Ember Descent's free run). Unused daily charges do not carry over.
	-- bonus: extra charges added by ChaosPocketBoss.addCharges (the online-time shop): at most bonusPerDay added per boss
	-- and day, at most bonusMax held per boss; held bonus charges stay over the reset and are spent after the daily ones.
	charges = {daily = 3, resetHour = 0, bonusPerDay = 3, bonusMax = 6},

	-- persistence: one row per character and boss (sql/chaos_pocketboss.sql; pocketboss.lua also creates it). A charge
	-- is written to the database at the moment it is spent, before the teleport: a logout, a crash or a death never
	-- gives it back.
	table = "chaos_pocketboss",

	-- ------------------------------------------------------------------ opening
	party = {max = 5, range = 8}, -- party members within range sqm (same floor) of the opener come along, max in all
	needProtectionZone = true,
	requestMs = 1000, -- the window's pocket actions, per player (ChaosRateLimit)
	enterCooldown = 10, -- seconds between two openings by the same player (a fight just left cannot be reopened at once)
	startDelay = 6, -- seconds between the arrival and the boss
	exitDelay = 30, -- seconds after the kill to loot the corpse before everyone is sent back
	tickMs = 500,
	hudEvery = 2, -- the rift HUD (opcode 228), like the guild boss
	-- a lethal hit inside a pocket is caught: the player goes back where they came from, healed, with no death and no
	-- loss; the charge stays spent. The others fight on; the last one out ends the pocket.
	catchLethal = true,
	-- a server restart (shutdown) while a pocket is open gives its charges back (the players did not choose it)
	refundOnRestart = true,
	-- no stacking: a character rewarded by the scheduled or contested fight of a boss (world boss event, island or raid
	-- spawn) cannot open the pocket of that same boss for this many seconds
	noStackSeconds = 3600,
	-- instance limits (instance_limits.lua): warnings at warnAt seconds left; at most maxRuns pockets at once (the
	-- grid's slots); a party that finds them all in use waits in line and is told when one frees up
	limits = {warnAt = {300, 60, 10}, maxRuns = 16, waitlist = true},

	-- ------------------------------------------------------------------ the arenas (runtime-built, uber_core.lua layout)
	-- x 11520-11903, y 10000-10095, z 7: 8 x 2 slots of 48, east of the guild boss arenas (x 11264-11455). Free: no map
	-- tiles between x/y 3000 and 16000 (server/README.md "Rifts"); away from the other runtime areas (raid x 10400-10911,
	-- battleground y 11264+, hideouts 12288+).
	grid = {origin = {x = 11520, y = 10000, z = 7}, cols = 8, slots = 16, spacing = 48},
	arena = {half = 11, anteGap = 2, anteHalfW = 3, anteHalfH = 1},
	groundId = 407,
	wallId = 5648,
	basinId = 1481,
	portalId = 1387,
	portalActionId = 47620, -- the way out in the antechamber (47620-47629 reserved for pocket bosses)
	dark = {enabled = true, style = "hall", wall = "obsidian_wall", basin = "brazier"},

	-- ------------------------------------------------------------------ the bosses
	-- Read from the systems that own them (never drift): the world bosses of Chaos.worldBoss, and the Boss Spawns
	-- entries (bossspawns_config.lua) of the categories below. A monster type the server does not have is left out.
	-- Not pocketed (decided 2026-10-15): the Ashen Sepulchre (open any time, its loot is the weekly lockout; its
	-- mechanics live in raid.lua), dungeon bosses (queue any time), the guild boss (the guild's weekly fuel), lair
	-- bosses (back in seconds to an hour), rift / Omen / Ascended / tower / trial / Descent bosses (already private).
	--
	-- Per category:
	--   minLevel   level needed (nil = the original's: Chaos.worldBoss.minLevel for the world bosses; the open-world
	--              island and raid bosses have none, so a floor is set here)
	--   xpMult     experience of the pocket's monsters x this
	--   lootMult   the corpse x this (loot.lua: a stack keeps count x mult, any other item stays with chance = mult, so
	--              even the always-dropped items are not guaranteed; the Chaos rolls, gems and uniques x mult too)
	--   minutes    time limit after the boss appears
	--   health     boss (and adds) health = the type's x (solo + perExtra x (players - 1)), at most max
	--   damage     the hits of the pocket's monsters on players x (solo + perExtra x (players - 1)), at most max
	--   tokens     Conquest Tokens per player and kill (ChaosConquest.grant(player, "pocketboss:<key>", n))
	categories = {
		world = {xpMult = 0.6, lootMult = 0.6, minutes = 15, tokens = 3,
			-- the world bosses carry 16-22 M health for up to 40 players: 3% solo (480-660 k)
			health = {solo = 0.03, perExtra = 0.025, max = 0.15},
			damage = {solo = 0.5, perExtra = 0.1, max = 0.9}},
		island = {minLevel = 250, xpMult = 0.6, lootMult = 0.6, minutes = 12, tokens = 2,
			health = {solo = 0.5, perExtra = 0.25, max = 1.5},
			damage = {solo = 0.75, perExtra = 0.05, max = 1.0}},
		raid = {minLevel = 150, xpMult = 0.6, lootMult = 0.6, minutes = 10, tokens = 1,
			health = {solo = 0.6, perExtra = 0.25, max = 1.5},
			damage = {solo = 0.8, perExtra = 0.05, max = 1.0}}
	},
	-- per boss key (bossspawns_config.lua keys; world bosses world_1 .. world_5): any field of a category above
	overrides = {
		raid_moloveth = {minLevel = 250, tokens = 2} -- a boss passive point (bosspoints_config.lua id 7)
	},
	-- boss keys left out
	exclude = {},
	-- the Boss Spawns window: these categories list their bosses by pocket level, then name (the 25 raid bosses)
	sortSpawns = {raid = true},

	-- the world bosses' event rewards in the pocket (Chaos.worldBoss.reward), for every player present at the kill:
	-- the base orbs x lootMult (rounded at random), one gear roll of the boss's gear list (the world boss sets) at
	-- gearChance x lootMult, one unique roll at uniqueChance x lootMult. No bank gold, no pool, no podium, no title.
	worldReward = {base = true, gear = true, unique = true},

	-- ------------------------------------------------------------------ the scheduled / contested fights
	-- Personal loot: the island bosses and the random raid bosses are open-world fights where only the corpse owner
	-- (the most damage) had loot. Now every other player whose contribution (damage on the boss + healWeight x healing
	-- on players fighting it) is at least minPercent % of the boss's max health gets a personal roll of the boss's own
	-- loot table (each entry with its chance x lootMult, count 1..max), into the backpack (the rest to the store inbox).
	-- The corpse owner keeps the corpse. Pocket kills never count here.
	contested = {enabled = true, categories = {island = true, raid = true}, minPercent = 2.0, healWeight = 1.0,
		lootMult = 1.0, maxPlayers = 30, healRange = 10, scanSeconds = 3},

	staffGroup = 4 -- /pocketboss
}
