-- Pinnacle bosses (pinnacle.lua, pinnacle_core.lua; server/README.md "Pinnacle bosses (O667)"): every number. Loaded with
--   Chaos.pinnacleConfig = dofile("data/scripts/chaos/pinnacle_config.lua")
-- Plain data, no engine calls (tests/pinnacle_test.lua and tools/pinnacle_model.py read it). Lua 5.1 / LuaJIT and Lua 5.3.
--
-- Four Ascended versions of existing key bosses (Malgrath, Vhoss the Hexmaw, Talath, Varkhul the Ashen Sovereign), shown at
-- level 1900 / 2100 / 2300 / 2500 (the player cap 2500, O672), each a private fight in a runtime-built arena (the pocket boss grid layout), alone or with a
-- party of up to 5. Each is opened by a set of 4 fragments (one of each kind) that the top content drops; the Keeper of the
-- Pinnacle takes the set and opens the arena. Rewards: an exclusive unique, Conquest Tokens, orbs, a title for the first kill
-- of each season and a "deathless" title. The limits of the fight (kill time, boss damage against healing, fragments per hour
-- of top content) are held by tools/pinnacle_model.py against pinnacle_balance_config.lua.
return {
	enabled = true,

	-- ------------------------------------------------------------------ storage (per character, server/README.md "Storage keys")
	-- block 7106400 - 7106459, offsets from `base`:
	--   +0 .. +15 fragments held: boss index (0-3) x 4 + kind (0-3)
	--   +16       the focus: the boss index + 1 the fragments drop for (0 none: a boss the level opens, at random)
	--   +20 .. +23 first kills: a bit per season (season id % 30) the character has killed that boss in
	--   +24 .. +27 deathless: 1 once the character killed that boss in a fight where nobody fell
	--   +28 .. +31 kills of that boss
	--   +32 .. +35 kills since the last unique of that boss (the bad-luck count)
	--   +36       a run in progress: the boss index + 1 (the set is given back at the next login after a crash)
	--   +37       when that run opened (os.time)
	--   +38       the last opening (os.time, the cooldown)
	--   +39 .. +59 free
	storage = {base = 7106400, frag = 0, focus = 16, first = 20, deathless = 24, kills = 28, pity = 32, marker = 36, markerAt = 37,
		lastOpen = 38},

	-- ------------------------------------------------------------------ the fragments
	-- kind 1 drops from a waystone map of tier `minTier` or higher, kind 2 from a rift of tier 15, kind 3 from an Omen guardian,
	-- kind 4 (the keystone) from any of the three. Per clear (the map's boss, the sealed rift, the slain guardian) and per
	-- character in the party: `chance` percent for the source's own kind, `anyChance` percent for the keystone, each its own roll.
	-- The fragment is of the focus boss, else of a boss the character's level opens (at random). A character under every boss's
	-- minLevel gets none. At most `cap` of one kind are held.
	fragments = {
		cap = 6,
		sources = {
			waystone = {kind = 1, minTier = 12, chance = 25, anyChance = 8},
			rift = {kind = 2, minTier = 15, chance = 25, anyChance = 8},
			omen = {kind = 3, chance = 25, anyChance = 8}
		},
		-- the hook of the waystone tiers (O666): ChaosWaystoneTiers.onRunCleared, read from a guarded call (nothing happens while it
		-- does not exist). pinnacle.lua wraps it at startup; the call it hands over names the tier and the finishers.
		hook = {waystone = "onRunCleared"}
	},

	-- ------------------------------------------------------------------ opening
	npc = {name = "Keeper of the Pinnacle", range = 4, towns = {1, 2, 3, 4, 5}, delayMs = 4500,
		offsets = {{-6, -4}, {6, -4}, {-6, 4}, {6, 4}, {-5, -6}, {5, 6}, {-8, -3}, {8, -3}, {-8, 3}, {8, 3}}},
	modal = {list = 7490}, -- the Keeper's modal window id (7480 is the memorial's; 7101-7171 the Oracle's, the spell quest's and the tales')
	party = {max = 5, range = 8}, -- the members within range sqm (same floor) of the opener come along, max in all; they pay no set
	needProtectionZone = true,
	requestMs = 1000, -- the modal answers, per player (ChaosRateLimit)
	enterCooldown = 10, -- seconds between two openings by the same player
	startDelay = 8, -- seconds between the arrival and the boss
	exitDelay = 45, -- seconds after the kill to take what is left before everyone is sent back
	minutes = 20, -- the time limit after the boss appears
	tickMs = 500,
	hudEvery = 2, -- the rift HUD (opcode 228)
	-- a lethal hit is caught: the player goes back where they came from, healed, with no death and no loss. A fall breaks the
	-- deathless title for the whole fight. The others fight on; the last one out ends the run.
	catchLethal = true,
	-- a server restart (shutdown) while a fight is open gives its set back (the players did not choose it)
	refundOnRestart = true,
	limits = {warnAt = {300, 60, 10}, maxRuns = 8, waitlist = true},
	tester = {reserve = 2},

	-- ------------------------------------------------------------------ the arenas (runtime-built, uber_core.lua layout)
	-- x 11520-11711, y 10112-10207, z 7: 4 x 2 slots of 48, below the pocket boss arenas (x 11520-11903, y 10000-10095), east of the
	-- guild boss arenas (x 11264-11455). Free: no map tiles between x/y 3000 and 16000 (server/README.md "Rifts").
	grid = {origin = {x = 11520, y = 10112, z = 7}, cols = 4, slots = 8, spacing = 48},
	arena = {half = 11, anteGap = 2, anteHalfW = 3, anteHalfH = 1},
	groundId = 407,
	wallId = "darkstone",
	basinId = 1481,
	portalId = 1387,
	portalActionId = 47630, -- the way out in the antechamber and in the arena (47630-47639 reserved for the pinnacle arenas)
	dark = {enabled = true, style = "hall", wall = "obsidian_wall", basin = "brazier"},
	look = {seed = 13},

	-- ------------------------------------------------------------------ the fight
	-- health = solo x (1 + perExtra x (players - 1)) in the boss's `health` (the XML health of the solo fight); damage = the hits of
	-- the boss and its adds on players x (solo + perExtra x (players - 1)), at most max. The numbers are the model's
	-- (tools/pinnacle_model.py --derive): the median class kills it in 420 s alone and in 300 s with five.
	damage = {solo = 1.0, perExtra = 0.06, max = 1.3},

	-- ------------------------------------------------------------------ the bosses
	-- key; name = the monster type (data/monster/monsters/chaos/pinnacle/); level = the level it is shown at and hits at (the
	-- engine's level bonus, ChaosLoot.monsterLevel); minLevel = the character level that may open it; refLevel = the character
	-- level the model plans the kill for; health / perExtra = the fight's health (the XML's) and its party curve; fragments = the
	-- four kinds, in order (the first three drop from one content each, the fourth is the keystone); tokens = Conquest Tokens per
	-- player and kill; orbs = per player and kill {chaos (Orb of Upheaval), divine (Orb of Fate), exalted}; unique = the exclusive
	-- unique's name (data/lib/chaos_unique_items.lua) and its base id; title = the short name of the titles.
	bosses = {
		{key = "malgrath", name = "Ascended Malgrath", short = "Malgrath", level = 1900, minLevel = 1800, refLevel = 1900,
			health = 3475000, perExtra = 0.664, tokens = 8, orbs = {chaos = 24, divine = 12, exalted = 2},
			fragments = {"Drowned Crown Shard", "Tidebroken Pearl", "Saltwrit Sigil", "Tidal Keystone"},
			unique = {name = "Signet of the Drowned Crown", id = 2216}},
		{key = "vhoss", name = "Ascended Vhoss", short = "Vhoss", level = 2100, minLevel = 2000, refLevel = 2100,
			health = 3876000, perExtra = 0.666, tokens = 10, orbs = {chaos = 32, divine = 16, exalted = 3},
			fragments = {"Hexmaw Fang", "Veiled Hex Scrap", "Whispering Idol Chip", "Hex Keystone"},
			unique = {name = "Seventh Hex Amulet", id = 2196}},
		{key = "talath", name = "Ascended Talath", short = "Talath", level = 2300, minLevel = 2200, refLevel = 2300,
			health = 4231000, perExtra = 0.666, tokens = 12, orbs = {chaos = 40, divine = 20, exalted = 4},
			fragments = {"Rime Crown Splinter", "Frozen Oath Shard", "Winterglass Tear", "Rime Keystone"},
			unique = {name = "Helm of the Unthawed", id = 5461}},
		{key = "varkhul", name = "Ascended Varkhul", short = "Varkhul", level = 2500, minLevel = 2400, refLevel = 2500,
			health = 4587000, perExtra = 0.666, tokens = 14, orbs = {chaos = 48, divine = 24, exalted = 5},
			fragments = {"Ashen Sovereign Cinder", "Sepulchre Seal", "Embered Oath Sliver", "Ash Keystone"},
			unique = {name = "Ring of the Last Verdict", id = 7708}}
	},

	-- ------------------------------------------------------------------ rewards
	-- the exclusive unique: each player at the kill rolls `chance` percent (x the character's item find, as the Ascended spoils),
	-- and after `pity` kills of that boss without one the next kill gives it. The corpse of the boss carries no loot of its own.
	unique = {chance = 22, pity = 8, itemFindCap = 1.5},
	-- orb item ids: the Ascended Omens' (uber_config.lua orbs)
	orbs = {chaos = 29856, divine = 29857, exalted = 29855},
	-- titles (titles.lua source "pinnacle"): `first` the first kill of a boss by a character in each season (the season's tag
	-- after it), `deathless` a kill in which nobody fell. At most 24 characters.
	titles = {source = "pinnacle", first = "%s Bane %s", deathless = "Deathless %s", color = "#C8A04A", frame = "gold"},
	-- the character's Conquest Tokens (conquest.lua) come from the source "pinnacle" (conquest_config.lua; the detail of the log row is the boss's key)

	staffGroup = 4 -- /pinnacle
}
