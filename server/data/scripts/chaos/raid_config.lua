-- The Ashen Sepulchre: the weekly raid (raid.lua, raid_core.lua; client game_raid, extended opcode ChaosOpcodes.raid =
-- 213). Every number of the raid lives here. Returned as a table and loaded as
-- ChaosRaidConfig = dofile("data/scripts/chaos/raid_config.lua"). Lua 5.1 / LuaJIT and Lua 5.3.
-- Item ids are SERVER ids. Overview: server/README.md "The Ashen Sepulchre (weekly raid)".
local UPHEAVAL, FATE, EXALTED = 29856, 29857, 29855

return {
	enabled = true,
	name = "The Ashen Sepulchre",

	-- ------------------------------------------------------------------ entry
	-- the city portal: a magic forcefield (no destination) with action id aid.portal next to the temple of each town of
	-- townIds (the main city Cinderhold first, server/README.md "Main city"; the first free tile of offsets,
	-- after the world boss and Descent portals). Stepping in opens the window.
	portal = {itemId = 1387, townIds = {2, 1}, offsets = {{4, 3}, {-4, 3}, {4, -3}, {-4, -3}, {0, 5}, {5, 0}, {-5, 0}, {2, 3},
		{-2, 3}, {3, -2}, {-3, -2}},
		-- positions: a fixed tile per town: Cinderhold's is an alcove of the temple's portal gallery
		-- (temple_portals_config.lua `portals`; tests/cityportals_test.lua checks it); a town without one uses `offsets`
		positions = {{town = 2, x = 32375, y = 32245, z = 7}}},
	minLevel = 800,
	minPlayers = 1, -- the raid opens for one player alone up to a party of 15 inside partyRange of the opener
	-- (owner 2026-10-24: all content solo). basePlayers = the group the boss numbers below were measured for (5, the old
	-- minimum): the XML health, packs and the soak need are theirs; fewer raiders scale down, more scale up (scaling)
	basePlayers = 5,
	maxPlayers = 15,
	partyRange = 12, -- party members within this many sqm (same floor) of the opener come along
	needProtectionZone = true,
	staffGroup = 4, -- /raid; staff may open with fewer players (/raid open)

	-- ------------------------------------------------------------------ the week
	-- the lockout week starts on resetDay (os.date wday: 1 = Sunday, 2 = Monday ...) at resetHour, server local time:
	-- the same rule as every other weekly reset (leaderboards, bounty weekly chest, Descent weekly run: Monday 06:00)
	resetDay = 2,
	resetHour = 6,

	-- ------------------------------------------------------------------ the instance
	-- One raid instance per slot of a grid far from the map (no map tiles between x/y 3000 and 16000, server/README.md
	-- "Rifts"; other runtime areas: tower 2000+, island 4600+, world boss 5000, siege 5100+, arena 6000+, ascension trial
	-- 7000+, Ascended arenas 7600+, rifts 8192-8447, trials 9000-9400, guild halls 9216-9535, the Ember Descent x
	-- 10000-10255 / y 10000-10127). The raid covers x 10400-10911, y 10000-10511, z 7 (2 x 2 slots of 256). The slots
	-- are the rift system's (rift_core.lua R.slotCenter / allocSlot / slotOfPos with this grid). A slot is a row west to
	-- east: the entry hall, then for each boss a corridor (its trash) and the boss room. Doors (walls) close a corridor
	-- until the boss before it is slain and its trash is cleared; a boss fight seals the room.
	grid = {origin = {x = 10400, y = 10000, z = 7}, cols = 2, rows = 2, spacing = 256},
	hall = {half = 5}, -- the entry hall: 11 x 11
	corridor = {length = 10, half = 2}, -- 10 long, 5 wide
	room = {half = 11}, -- a boss room: 23 x 23
	wallId = 5648, -- stone wall (the dark tile set's obsidian wall when installed)
	doorId = 1546, -- the doors of the corridors: iron bars (blocking), put back when a door closes
	basinId = 1481, -- coal basins in the corners
	groundId = 407, -- black marble floor (stock); the dark tile set paints the rooms when installed
	dark = {enabled = true, style = "hall", wall = "obsidian_wall", basin = "brazier"},
	aid = {portal = 47801, exit = 47802, font = 47803},
	objects = {exit = 1387, font = 1360}, -- the exit forcefield in the hall; the Font of Ash (a fountain, used from next
	-- to it) in the corners of the rooms with hexes
	idleMinutes = 5, -- an empty instance (nobody inside) is closed after this; its progress stays saved for the week (was 10)
	-- instance limits (instance_limits.lua, server/README.md "Instance limits"): one opening of a raid lasts at most
	-- sessionMinutes; then everyone goes back where they came from and the slot closes. Nothing is lost: the kills and
	-- cleared corridors are saved for the week and the raid can be continued (a fight still going at that moment ends as
	-- a wipe). 150 minutes: five enrage timers (9 + 10 + 11 + 11 + 16 minutes since 2026-10-13) and the trash take about 60-90 minutes with
	-- a few wipes. Warnings at warnAt seconds left; at most maxRuns raids at once (the 2 x 2 grid); a party that finds
	-- every wing taken waits in line and is told when one frees up.
	sessionMinutes = 150,
	limits = {warnAt = {600, 300, 60, 10}, maxRuns = 4, waitlist = true},
	tickMs = 250,
	hudEvery = 2, -- seconds between HUD refreshes (the client counts the clock down in between)
	wipeSeconds = 4, -- a fight with nobody standing in the room for this long is a wipe: the boss resets
	pullDelay = 2, -- seconds between the first step into a room and the boss's first mechanic

	-- ------------------------------------------------------------------ scaling
	-- boss health = the XML's (set for basePlayers) x (1 + healthPerPlayer x (players - basePlayers)); trash, adds and
	-- totems the same with their own factor. players = the raid members inside the instance at the pull. Under
	-- basePlayers the health follows the group's damage instead (raid_core.lua K.smallMult, the balance model below): one
	-- raider kills in the time five do, so solo is as long as the base fight, not 30% longer. Sundered fades when the
	-- tank is alone, and a soak circle asks for as many raiders as there are (its total scales with them).
	healthPerPlayer = 0.18,
	trashPerPlayer = 0.12,
	addPerPlayer = 0.10,
	-- the balance model (raid_core.lua killTime): refDps of a well-geared level 1000 character (uber_config.lua model),
	-- uptime = share of the fight spent hitting the boss (mechanics move you); a fifth of a raid heals or tanks at
	-- supportShare of the damage
	model = {refDps = 3000, uptime = 0.75, supportEvery = 5, supportShare = 0.6},

	-- ------------------------------------------------------------------ fallen players
	-- a lethal hit inside the raid is caught: the player lands in the entry hall, healed, and cannot come back into a
	-- sealed room until the fight ends (no real death, no loss). Everyone fallen or out = a wipe.
	fallen = {healShare = 1.0},

	-- ------------------------------------------------------------------ telegraphs (uber_core.lua's way)
	-- tiles are marked at once (warnEffect) and one turn later (fillEffect), the hit lands warnMs after the first mark
	telegraph = {warnMs = 2200, turnMs = 1100, warnEffect = "warning_zone", fillEffect = "warning_fill"},
	enrage = {damageMult = 1.75, everyMult = 0.6, pulseShare = 0.10, pulseMs = 4000},

	-- ------------------------------------------------------------------ mechanics
	-- Every mechanic a boss phase lists by key, with its numbers. share = a share of the hit player's maximum health.
	--   sunder   tank swap: the boss's melee hits put a stack of Sundered on its target (+stackPct % damage taken from
	--            the boss per stack, gone after expireMs without a hit; on the buff bar). From swapAt stacks the boss
	--            turns to the other player in melee range with the fewest stacks; with nobody there it brings down
	--            Crushing Verdict on its target (telegraphed, verdictShare x (1 + stacks x stackPct / 100)).
	--   cleave   positional: a cone in front of the boss towards its target; everyone in it but the target is hit
	--   sweep    positional: a cone behind the boss (away from its target); everyone in it is hit
	--   soak     split damage: circles near random players; when the hit lands its total (totalShare) is split among
	--            the players standing inside; fewer than `need` inside and everyone else in the room takes overflowShare
	--   adds     priority: adds every `every` ms; each living one makes the boss take reducePct % less damage (at most
	--            maxReduce) and heals it healPct % of its health every 5 s
	--   marks    spread: a circle under every player, hit after the warning: step out and away from the others
	--   totem    kill the totem: effigies that put a stack of Hexed on everyone in the room every hexMs (stackShare x
	--            stacks per tick, on the buff bar) and detonate after lifeMs (detonateShare to everyone)
	--   hex      dispel: Withering Hex on random players (an engine curse: the Font of Ash (the cure curse spell is retired) takes it
	--            off); not cleansed within windowMs it bursts on everyone within radius sqm of the hexed player
	mechanics = {
		sunder = {stackPct = 15, swapAt = 4, maxStacks = 8, expireMs = 20000, challengeRange = 1, verdictShare = 0.55,
			warnMs = 2000},
		cleave = {every = 11000, length = 7, spread = 3, share = 0.6},
		sweep = {every = 9000, length = 6, spread = 3, share = 0.55},
		soak = {every = 17000, radius = 1, warnMs = 4000, totalShare = 1.5, need = 3, needPerPlayers = 5, perCircle = 7,
			overflowShare = 0.35},
		adds = {every = 40000, base = 1, perPlayers = 4, reducePct = 15, maxReduce = 60, healPct = 1},
		marks = {every = 14000, radius = 1, share = 0.45},
		totem = {every = 38000, base = 1, perPlayers = 8, lifeMs = 22000, hexMs = 3000, stackShare = 0.02, maxStacks = 10,
			detonateShare = 0.6},
		hex = {every = 26000, base = 1, perPlayers = 5, windowMs = 8000, radius = 2, burstShare = 0.45, subId = 71060}
	},

	-- ------------------------------------------------------------------ the bosses (in order)
	-- health/look: the XML (data/monster/monsters/chaos/raid/); phases: at = health fraction where the phase starts (the
	-- first at 1), mech = the mechanics of the phase (keys above). enrageAt: seconds after the pull (5 raiders at the measured median 2,600 finish about 20% before it; server/README.md "Solo kill times"). adds / totem: the
	-- monster names. roles: the composition hint of the journal. gear: the base items of the boss's gear rolls.
	bosses = {
		{key = "ulthar", name = "Gravewarden Ulthar", enrageAt = 540, add = nil,
			intro = "The warden of the first gate still keeps his watch. His flail has broken every shield brought here.",
			roles = "2 tanks (swap at 4 stacks), healers 1 per 5, the rest damage behind him.",
			phases = {
				{at = 1.0, name = "The Watch", mech = {"sunder", "cleave"}, yell = "NONE PASS THE FIRST GATE!"},
				{at = 0.4, name = "Last Watch", mech = {"sunder", "cleave", "marks"}, yell = "I HAVE BURIED BETTER THAN YOU!"}
			},
			gear = {29878, 29879, 29880, 29882, 29884, 29886}},
		{key = "morwen", name = "Morwen the Ash-Sister", enrageAt = 600, add = "Cinder Acolyte",
			intro = "She sang the dead to sleep, until the sleep turned to ash. Her acolytes still answer her.",
			roles = "1 tank, 2 soak groups of 3 or more, ranged on the acolytes first.",
			phases = {
				{at = 1.0, name = "The Ash Choir", mech = {"soak", "adds"}, yell = "SING WITH ME, AND BURN!"},
				{at = 0.5, name = "Requiem", mech = {"soak", "adds", "marks"}, yell = "THE LAST VERSE IS YOURS!"}
			},
			gear = {29861, 29862, 29863, 29864, 29866, 29867}},
		{key = "colossus", name = "The Marrow Colossus", enrageAt = 660, add = nil,
			intro = "A thousand graves were emptied to build it. It does not know which way it faces.",
			roles = "1 tank in front, nobody behind it, everyone spread for the bone blooms.",
			phases = {
				{at = 1.0, name = "Grinding Bones", mech = {"sweep", "marks"}, yell = "BONE... TO... BONE..."},
				{at = 0.5, name = "Shattering", mech = {"sweep", "marks", "cleave"}, yell = "BREAK! BREAK! BREAK!"}
			},
			gear = {29869, 29870, 29871, 29872, 29875, 29876}},
		{key = "hexmaw", name = "Vhoss the Hexmaw", enrageAt = 660, add = nil, totem = "Hex Effigy",
			intro = "Its effigies watch from every wall. Each one it raises is a curse waiting to be spoken.",
			roles = "1 tank, a kill team for the effigies, healers or a Templar ready to lift the hex (or the Font of Ash).",
			phases = {
				{at = 1.0, name = "The Effigies", mech = {"totem", "hex"}, yell = "EVERY WALL HAS EYES!"},
				{at = 0.45, name = "Hexfall", mech = {"totem", "hex", "cleave"}, yell = "SPEAK THE CURSE WITH ME!"}
			},
			gear = {29865, 29868, 29873, 29877, 29881, 29889}},
		{key = "sovereign", name = "Varkhul the Ashen Sovereign", final = true, enrageAt = 960, add = "Cinder Acolyte",
			totem = "Hex Effigy",
			intro = "The Sepulchre was built to keep him in. He has been waiting for someone to open the last door.",
			roles = "2 tanks, 2 soak groups, an effigy team, a dispeller; everything you learned on the way down.",
			phases = {
				{at = 1.0, name = "The Throne", mech = {"sunder", "cleave"}, yell = "KNEEL. ALL OF YOU."},
				{at = 0.7, name = "Court of Ash", mech = {"sunder", "soak", "adds"}, yell = "MY COURT WILL SING YOU DOWN!"},
				{at = 0.4, name = "The Last Sovereign", mech = {"sunder", "totem", "hex", "sweep"},
					yell = "THE SEPULCHRE IS MINE, AND SO ARE YOU!"}
			},
			gear = {29878, 29879, 29884, 29862, 29866, 29870, 29875, 29889, 29890}}
	},

	-- the trash of each corridor (before boss i): packs of monsters (raid/ folder) with a tier mix (monster_tiers.lua
	-- percent per monster); per pack base + floor(players / perPlayers) monsters, at most max
	trash = {
		{packs = {{"Sepulchre Ghoul", "Bone Lancer"}, {"Bone Lancer", "Sepulchre Ghoul"}}},
		{packs = {{"Hex Cultist", "Cinder Hound"}, {"Cinder Hound", "Sepulchre Ghoul"}}},
		{packs = {{"Marrow Knight", "Bone Lancer"}, {"Marrow Knight", "Sepulchre Ghoul"}}},
		{packs = {{"Hex Cultist", "Ashen Reaper"}, {"Ashen Reaper", "Cinder Hound"}}},
		{packs = {{"Ashen Reaper", "Marrow Knight"}, {"Hex Cultist", "Marrow Knight"}, {"Ashen Reaper", "Cinder Hound"}}}
	},
	trashPack = {base = 3, perPlayers = 3, max = 8},
	trashTiers = {magic = 30, rare = 10, legendary = 0},

	-- ------------------------------------------------------------------ loot (personal, per eligible player and boss)
	-- A character may loot each boss once per lockout week; a kill without loot still counts for the raid's progress
	-- (helping others). gold to the bank; orbs; gearRolls items of the boss's gear list at an item level of
	-- gearLevel[1]..gearLevel[2] (chaos_item_mods.lua rules: the rarity from the boss tier, x rarityFind); a unique roll
	-- with uniqueChance per 10000 over the raid uniques that name the boss; marks: the raid vendor's currency.
	loot = {
		boss = {gold = 2500000, orbs = {{id = UPHEAVAL, count = 6}, {id = FATE, count = 2}}, gearRolls = 2, uniqueChance = 150,
			marks = 20},
		final = {gold = 6000000, orbs = {{id = UPHEAVAL, count = 12}, {id = FATE, count = 5}, {id = EXALTED, count = 1}},
			gearRolls = 3, uniqueChance = 400, marks = 45},
		gearLevel = {120, 130},
		rarityFind = 1.5
	},
	-- the raid uniques (data/items/chaos_items.xml -> chaos_unique_specs.lua; never dropped anywhere else): a unique roll
	-- picks among the ones that list the boss (the final boss lists all of them)
	uniques = {
		{id = 7422, name = "Gravewarden's Verdict", bosses = {"ulthar", "sovereign"}},
		{id = 8865, name = "Shroud of the Ash-Sister", bosses = {"morwen", "sovereign"}},
		{id = 2504, name = "Marrowforged Greaves", bosses = {"colossus", "sovereign"}},
		{id = 2124, name = "Eye of the Hexmaw", bosses = {"hexmaw", "sovereign"}},
		{id = 2498, name = "Crown of the Last Sovereign", bosses = {"sovereign"}}
	},
	-- the final boss: the account's achievement "raid_sovereign" unlocks the kill effect Sovereign's Pyre (cosmetics id
	-- 109, cosmetics_config.lua); the guilds of the eligible players get a trophy (guild stat raidClears, shown on the
	-- trophy room statue) and trophyGxp guild XP each, once per guild and kill
	trophyGxp = 300,

	-- ------------------------------------------------------------------ the raid vendor (Sepulchre Marks)
	-- marks are a per-character balance (chaos_raid_players). The vendor shows `slots` offers of the pool each week,
	-- picked by the week's seed (the same for everyone, raid_core.lua vendorStock); every offer at most `weekly` times a
	-- week per character. Gear is fixed like the faction quartermasters' (rarity, item level, exactly these modifiers at
	-- these tiers, the middle of each tier's range; factions_core.lua gearProblems checks them against
	-- chaos_item_mods.lua): a catch-up below the world boss drops (item level 145).
	vendor = {
		slots = 5,
		pool = {
			{key = "v_helm", kind = "gear", name = "Sepulchre Warden Helm", price = 120, weekly = 1,
				id = 2491, itemKind = "helmet", rarity = 4, level = 130, mods = {{"monsterreduction", 7}, {"regen", 7}, {"lifeonkill", 7}}},
			{key = "v_plate", kind = "gear", name = "Sepulchre Ashplate", price = 160, weekly = 1,
				id = 2487, itemKind = "armor", rarity = 4, level = 130, mods = {{"monsterreduction", 7}, {"thorns", 7}, {"regen", 7}}},
			{key = "v_legs", kind = "gear", name = "Sepulchre Greaves", price = 140, weekly = 1,
				id = 2495, itemKind = "legs", rarity = 4, level = 130, mods = {{"dodge", 7}, {"thorns", 7}, {"regen", 7}}},
			{key = "v_boots", kind = "gear", name = "Sepulchre Treads", price = 100, weekly = 1,
				id = 7886, itemKind = "boots", rarity = 4, level = 130, mods = {{"dodge", 7}, {"movespeed", 7}}},
			{key = "v_blade", kind = "gear", name = "Sepulchre Cleaver", price = 180, weekly = 1,
				id = 7434, itemKind = "weapon", rarity = 4, level = 130, mods = {{"bossdamage", 7}, {"physpen", 7}, {"attackspeed", 7}}},
			{key = "v_wand", kind = "gear", name = "Sepulchre Hexwand", price = 180, weekly = 1,
				id = 8920, itemKind = "weapon", rarity = 4, level = 130, mods = {{"elepen", 7}, {"dot", 7}, {"manaonhit", 7}}},
			{key = "v_amulet", kind = "gear", name = "Sepulchre Pendant", price = 130, weekly = 1,
				id = 2131, itemKind = "jewel", rarity = 4, level = 130, mods = {{"bossdamage", 7}, {"cdr", 7}, {"healing", 7}}},
			{key = "v_shield", kind = "gear", name = "Sepulchre Bulwark", price = 150, weekly = 1,
				id = 2514, itemKind = "shield", rarity = 4, level = 130, mods = {{"block", 7}, {"reflect", 7}, {"regen", 7}}},
			{key = "v_upheaval", kind = "orbs", name = "Ashen Upheaval (10)", price = 40, weekly = 3,
				items = {{id = UPHEAVAL, count = 10}}},
			{key = "v_fate", kind = "orbs", name = "Sealed Fate (3)", price = 60, weekly = 2,
				items = {{id = FATE, count = 3}}},
			{key = "v_exalted", kind = "orbs", name = "Sovereign's Exalted Orb", price = 150, weekly = 1,
				items = {{id = EXALTED, count = 1}}},
			-- the weekly Orb of Unveiling bundle (veiled modifiers, data/lib/chaos_veiled_config.lua vendorBundle)
			{key = "v_unveiling", kind = "orbs", name = "Veilbreaker's Bundle (2)", price = 90, weekly = 1,
				items = {{id = 32257, count = 2}}}
		},
		-- these are always in stock (orb bundles), the rest of the slots come from the gear of the pool by the seed
		always = {"v_upheaval", "v_fate", "v_unveiling"},
		gearLimits = {maxLevel = 130, maxRarity = 4}
	},

	-- ------------------------------------------------------------------ records
	-- the weekly board "raid_clear" (leaderboard_config.lua, mode "min"): seconds from the first pull to the final kill
	-- of a raid that killed all its bosses in one sitting (a continued raid does not count)
	board = "raid_clear",
	-- achievement stats (achievements_data.lua): raid_kills, raid_<boss key>, raid_clears, raid_flawless (the final
	-- boss with nobody fallen in its fight), raid_speed (a clear under speedSeconds)
	speedSeconds = 1800,

	-- ------------------------------------------------------------------ persistence
	-- SQL (server/sql/chaos_raid.sql; raid.lua also creates the tables): lockouts per character, week and boss; the raid
	-- instances of a week (bosses killed, trash cleared, members); the characters' marks and records; vendor purchases.
	-- Storages 7100440 - 7100449 (Chaos.storage.raid): +0 inside a raid instance (1; the next login after a crash goes to
	-- the temple), +1 .. +5 the end of this week's lockout of boss 1..5 (0 = free; the Boss Spawns window's cooldown).
	tables = {lockouts = "chaos_raid_lockouts", instances = "chaos_raid_instances", members = "chaos_raid_members",
		players = "chaos_raid_players", purchases = "chaos_raid_purchases"},
	storage = 7100440
}
