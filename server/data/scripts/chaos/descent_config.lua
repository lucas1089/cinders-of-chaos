-- The Ember Descent (descent.lua, descent_core.lua; client game_descent, extended opcode ChaosOpcodes.descent = 205):
-- a roguelike trial of 8-12 rooms built at runtime. Every number of the mode lives here. Returned as a table and loaded
-- as ChaosDescentConfig = dofile("data/scripts/chaos/descent_config.lua"). Lua 5.1 / LuaJIT and Lua 5.3.
-- Item ids are SERVER ids. Overview: server/README.md "The Ember Descent".
return {
	enabled = true,
	name = "The Ember Descent",

	-- ------------------------------------------------------------------ entry
	-- the city portal: a magic forcefield (no destination) with action id aid.portal next to the temple of each town of
	-- townIds (the main city Cinderhold first, server/README.md "Main city"; the first free tile of offsets,
	-- after the world boss portals' spots). Stepping in opens the Descent window.
	-- positions: a fixed tile per town: Cinderhold's is an alcove of the temple's portal gallery
	-- (temple_portals_config.lua `portals`, owner 2026-10-22; tests/cityportals_test.lua checks it); a town without
	-- one uses `offsets`
	portal = {itemId = 1387, townIds = {2, 1}, offsets = {{-3, 3}, {3, 3}, {-3, -3}, {3, -3}, {0, 4}, {4, 1}, {-4, 1}},
		positions = {{town = 2, x = 32363, y = 32245, z = 7}}},
	minLevel = 100,
	maxPlayers = 4,
	partyRange = 8, -- party members within this many sqm (same floor) of the leader come along
	needProtectionZone = true,
	-- runs: one free normal run per day (server day, Chaos.dayKey) and one free weekly run per week (the week of the
	-- leaderboards: Monday resetHour). More runs of either kind cost one Ember Sigil each. Every member of a party pays
	-- for himself (his free run or one sigil); a member with neither stays behind.
	freePerDay = 1,
	-- unused daily free runs bank up to this many (2026-10-15, respect the players' time): three days away, three
	-- free descents waiting. The weekly run is seeded per week and does not bank.
	freeBankDays = 3,
	freeWeeklyPerWeek = 1,
	resetHour = 6, -- the weekly reset hour (leaderboard_config.lua resetHour)

	-- the Ember Sigil: the entry token, crafted in the Descent window (a sink for rune shards and gold). The item is a
	-- stock "red power core" (no script, shop or loot uses it) with this action id and the custom attribute
	-- descent_sigil = 1; its name and description are set when it is made. Not stackable (one sigil a run).
	sigil = {itemId = 10074, actionId = 47710, name = "Ember Sigil",
		description = "A coal that never cools. Enter the Ember Descent once more (the portal at the temple).",
		craft = {shardId = 32051, shards = 25, gold = 50000}},

	-- ------------------------------------------------------------------ the instance
	-- A slot grid far from the map (no map tiles between x/y 3000 and 16000, server/README.md "Rifts"; other runtime
	-- areas: tower 2000+, island 4600+, world boss 5000, siege 5100+, arena 6000+, ascension trial 7000+, Ascended
	-- arenas 7600+, rifts 8192-8447, trials 9000-9400, guild halls 9216+). The Descent covers x 10000-10255, y 10000-10127.
	-- The slots are the rift system's (rift_core.lua R.slotCenter / allocSlot / slotOfPos with this grid; tiles built
	-- with Game.createTile like the rift slots, the dark tile paint of chaos_dark_paint.lua): one square hall per slot,
	-- `half` tiles from the centre to the wall. Each room of a run re-themes the hall (the rift themes, rift_config.lua)
	-- and fills it again, so a run of 12 rooms needs one slot.
	grid = {origin = {x = 10000, y = 10000, z = 7}, cols = 4, rows = 2, spacing = 64},
	room = {half = 10},
	wallId = 5648, -- stone wall (the rift's), the obsidian wall of the dark tile set when it is installed
	basinId = 1481, -- coal basin in the hub corners
	aid = {portal = 47701, exit = 47702, chest = 47703, shrine = 47704, merchant = 47705},
	-- forcefield, reward chest (21584, the rift's; was the plain chest 1740), blazing altar basin, stand
	objects = {exit = 1387, chest = 21584, shrine = 12458, merchant = 10014},

	-- ------------------------------------------------------------------ the run
	rooms = {min = 8, max = 12},
	-- room types after the first (always combat) and before the last (always the boss); the room before the boss is a
	-- merchant. Elite rooms from depth eliteFrom; treasure, shrine and merchant never twice in a row.
	roomWeights = {{"combat", 50}, {"elite", 18}, {"treasure", 10}, {"shrine", 12}, {"merchant", 8}},
	eliteFrom = 3,
	timeLimit = 2700, -- seconds for the whole run (45 minutes); when it runs out the run ends at the depth reached
	chooseSeconds = 40, -- time to pick a boon (then the first card is taken)
	nextRoomDelay = 4, -- seconds between the last pick (or the exit) and the next room
	exitDelay = 8, -- seconds between the end of a run and the trip out
	hudEvery = 5, -- seconds between HUD refreshes
	-- instance limits (instance_limits.lua, server/README.md "Instance limits"): warnings at these seconds left before
	-- timeLimit; at most maxRuns runs at once (8 halls of 19 x 19); a party that finds every hall taken waits in line and
	-- is told when one frees up. A run ends at once when its last player is out, so no idle grace is needed.
	limits = {warnAt = {300, 60, 10}, maxRuns = 8, waitlist = true},
	readySeconds = 90, -- shrine / merchant rooms: after this the party moves on even if not everyone is ready

	-- waves of a combat room: waves = base + floor(depth x perDepth) (at most max); monsters per wave = size.base +
	-- floor(depth x size.perDepth) + size.perExtraPlayer x (players - 1), at most size.max; the Swarm curse adds percent
	waves = {base = 2, perDepth = 0.25, max = 4},
	size = {base = 4, perDepth = 0.34, perExtraPlayer = 2, max = 14},
	types = 3, -- monster types of a room
	spread = 3, -- a wave lands around a random point of the hub, this far
	-- elite room: one wave of base + floor(depth x perDepth) monsters, every one rare or legendary, health x healthMult
	elite = {base = 2, perDepth = 0.25, perExtraPlayer = 1, healthMult = 1.5, legendaryBase = 25, legendaryPerDepth = 5},
	-- treasure room: a guard wave of `guards` (+1 per extra player), then the chest appears; its embers and gold
	treasure = {guards = 3, embers = {base = 40, perDepth = 10}, gold = {base = 2000, perDepth = 800}},
	-- shrine room: using the altar costs this share of the maximum health (never the last point) for a boon choice
	shrine = {healthCost = 20},
	-- the run currency (embers, per player): per kill (an elite room's kills give eliteKill), per cleared room
	embers = {perKill = 2, eliteKill = 6, perRoom = 15},
	-- the merchant (embers): price = base + perDepth x depth
	wares = {
		{key = "mend", name = "Ember Draught", desc = "Restore all your health and mana.", base = 20, perDepth = 3},
		{key = "boon", name = "Boon Cache", desc = "Choose one of three boons.", base = 55, perDepth = 5},
		{key = "cleanse", name = "Ash Cleanse", desc = "Remove your newest curse (its reward bonus goes with it).", base = 40, perDepth = 4},
		{key = "ward", name = "Cinder Shell", desc = "A ward that absorbs 25% of your maximum health, until it breaks.", base = 15, perDepth = 2, value = 25}
	},

	-- escalation by depth (the room number): the monster level window of the bounty pool (bounty_pool.lua) is
	-- party level x (lo + perDepth x depth) .. party level x (hi + perDepth x depth), clamped to minLevel .. maxLevel;
	-- monster health x (1 + health x (depth - 1)), their damage x (1 + damage x (depth - 1)); the tier mix (percent per
	-- monster, monster_tiers.lua) is base + perDepth x depth for each tier.
	escalation = {lo = 0.55, hi = 0.8, perDepth = 0.05, minLevel = 20, maxLevel = 1500, widen = 60, minPoolHealth = 100,
		health = 0.08, damage = 0.06,
		tiers = {magic = {8, 3}, rare = {2, 1.5}, legendary = {-3.2, 0.8}}},

	-- the final boss: the strongest monster type of the boss room's window, legendary, with the rift guardian look of the
	-- room's theme and its own name; health x (healthMult + perExtraPlayer x (players - 1)) on top of the depth scaling
	boss = {healthMult = 6, perExtraPlayer = 2, tier = "legendary",
		names = {["Abyssal Rift"] = "Hollow Archon", ["Obsidian Hall"] = "Obsidian Tyrant",
			["Ashen Crypt"] = "Pyre Lich", ["Forsaken Sanctum"] = "Blighted Matriarch"},
		looks = {["Abyssal Rift"] = 2103, ["Obsidian Hall"] = 2107, ["Ashen Crypt"] = 2111, ["Forsaken Sanctum"] = 2115},
		defaultName = "Ember Tyrant"},

	-- ------------------------------------------------------------------ boons and curses
	-- After every cleared combat, elite and treasure room each player picks one of three boons (a shrine and the
	-- merchant's Boon Cache give the same choice). Boons last for the run only; picking one again stacks it up to max.
	-- value: the effect of one stack (x stacks; a brand and Phoenix Ember do not stack), extra: its second number;
	-- the texts show the total of the stacks held (a card: of the stack it gives). weight: how often it is offered.
	-- kind: what descent.lua does with it (outgoing hits, incoming hits, kills, conditions).
	boons = {
		{key = "ember_edge", name = "Ember Edge", kind = "damage", value = 12, max = 3, weight = 10,
			desc = "+%d%% damage to Descent monsters."},
		{key = "searing_brand", name = "Searing Brand", kind = "convert", element = "fire", value = 50, extra = 15, max = 1, weight = 6,
			desc = "%d%% of your physical damage becomes fire, and that part hits %d%% harder."},
		{key = "rime_brand", name = "Rime Brand", kind = "convert", element = "ice", value = 50, extra = 15, max = 1, weight = 6,
			desc = "%d%% of your physical damage becomes ice, and that part hits %d%% harder."},
		{key = "grave_brand", name = "Grave Brand", kind = "convert", element = "death", value = 50, extra = 15, max = 1, weight = 6,
			desc = "%d%% of your physical damage becomes death, and that part hits %d%% harder."},
		{key = "blood_drinker", name = "Blood Drinker", kind = "leech", value = 5, max = 3, weight = 8,
			desc = "Heal %d%% of the damage you deal."},
		{key = "pyre_burst", name = "Pyre Burst", kind = "burst", value = 20, extra = 2, max = 3, weight = 7,
			desc = "A foe you slay bursts: %d%% of its maximum health as fire to monsters within %d sqm."},
		{key = "soul_harvest", name = "Soul Harvest", kind = "harvest", value = 3, max = 3, weight = 8,
			desc = "Each kill restores %d%% of your health and mana."},
		{key = "echo_strike", name = "Echo Strike", kind = "echo", value = 20, extra = 50, max = 3, weight = 7,
			desc = "%d%% chance that a hit strikes again for %d%% of its damage."},
		{key = "ember_ward", name = "Ember Ward", kind = "ward", value = 10, extra = 20, max = 3, weight = 7,
			desc = "A ward absorbs %d%% of your maximum health; it renews every %d s."},
		{key = "quickstep", name = "Quickstep", kind = "speed", value = 40, max = 2, weight = 6,
			desc = "+%d speed."},
		{key = "keen_eye", name = "Keen Eye", kind = "crit", value = 10, extra = 60, max = 3, weight = 8,
			desc = "%d%% chance to hit for +%d%% damage."},
		{key = "executioner", name = "Executioner", kind = "execute", value = 35, extra = 30, max = 2, weight = 6,
			desc = "+%d%% damage to monsters below %d%% health."},
		{key = "stoneskin", name = "Stoneskin", kind = "reduce", value = 10, max = 3, weight = 8,
			desc = "%d%% less damage taken."},
		{key = "thornmail", name = "Thornmail", kind = "thorns", value = 30, max = 2, weight = 5,
			desc = "Monsters that hit you take %d%% of the damage back."},
		{key = "phoenix_ember", name = "Phoenix Ember", kind = "phoenix", value = 40, max = 1, weight = 3,
			desc = "Once this run, a lethal blow leaves you at %d%% health instead."},
		{key = "ember_tithe", name = "Ember Tithe", kind = "tithe", value = 50, max = 2, weight = 5,
			desc = "+%d%% embers."}
	},
	-- curses: from depth curseFrom, after a combat or elite room the choice may carry a curse (curseChance percent).
	-- Taking it with the boon adds `reward` percent to the player's final rewards and gives `embers` at once.
	curseFrom = 2,
	curseChance = 30,
	curses = {
		{key = "frailty", name = "Frailty", kind = "taken", value = 20, reward = 25, embers = 30,
			desc = "You take %d%% more damage."},
		{key = "withering", name = "Withering", kind = "healing", value = 30, reward = 20, embers = 25,
			desc = "Healing on you is %d%% weaker."},
		{key = "swarm", name = "Swarm", kind = "swarm", value = 30, reward = 25, embers = 30,
			desc = "Rooms hold %d%% more monsters (for the whole party)."},
		{key = "frenzy", name = "Frenzied Foes", kind = "frenzy", value = 60, reward = 20, embers = 25,
			desc = "Monsters are %d faster (for the whole party)."},
		{key = "ashen_purse", name = "Ashen Purse", kind = "purse", value = 40, reward = 15, embers = 0,
			desc = "You find %d%% fewer embers."}
	},

	-- ------------------------------------------------------------------ rewards
	-- At the end of a run (death, time, leaving or the boss slain) every player who was in it gets the rewards of the
	-- depth reached (rooms cleared): gold to the bank = (perDepth x depth + square x depth^2) x (1 + level / levelDiv),
	-- orbs = floor(depth / every) of each line, a unique roll with uniqueChance per 10000 (from depth unique.from:
	-- perDepth per room past it, + clear on a full clear, at most max). A full clear (the boss slain) multiplies gold and
	-- orbs by clearMult. The player's curse rewards add percent to gold, orbs (rounded down) and the unique chance.
	rewards = {
		gold = {perDepth = 3000, square = 400, levelDiv = 400},
		orbs = {{id = 29856, every = 2}, {id = 29857, every = 4}, {id = 29858, every = 6}},
		clearMult = 1.5,
		unique = {from = 6, perDepth = 150, clear = 800, max = 2500},
		-- the run-exclusive uniques (data/items/chaos_items.xml -> chaos_unique_specs.lua; never drop anywhere else):
		-- a roll picks among those whose minDepth the run reached
		uniques = {
			{id = 7384, name = "Emberfall Blade", minDepth = 6},
			{id = 7891, name = "Ashwalker Treads", minDepth = 6},
			{id = 2133, name = "Heart of the Descent", minDepth = 8},
			{id = 2357, name = "Sigil of the Ninth Room", minDepth = 9},
			{id = 7402, name = "Pyre Cleaver", minDepth = 10}
		}
	},
	-- cosmetic titles (name plate, ChaosTitles source "descent"): the best depth reached ever, or a full clear
	titles = {
		{depth = 5, text = "Ashwalker", color = "#e0904a"},
		{depth = 9, text = "Emberdelver", color = "#ff7a2a"},
		{clear = true, text = "Heart of the Descent", color = "#ff4a1a"}
	},
	board = "descent", -- the weekly leaderboard (leaderboard_config.lua): best depth of the weekly seeded run

	-- ------------------------------------------------------------------ persistence
	-- SQL (server/sql/chaos_descent.sql; descent.lua also creates the tables): per character the free runs used, the
	-- best depths and the run log. Storages 7100410 - 7100419 (Chaos.storage.descent): +0 a run in progress (1; the next
	-- login after a crash puts the character back in the temple), +1 the time the next free run is ready (the Boss Spawns
	-- window's cooldown column).
	tables = {players = "chaos_descent_players", runs = "chaos_descent_runs"},
	storage = 7100410
}
