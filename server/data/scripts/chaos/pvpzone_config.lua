-- The Scorched Marches: an open-world PvP zone with risk and reward (pvpzone.lua, pvpzone_core.lua; client game_pvpzone,
-- extended opcode ChaosOpcodes.pvpZone = 193). Every number of the zone. Loaded with
--     Chaos.pvpZoneConfig = dofile("data/scripts/chaos/pvpzone_config.lua")
-- Plain data, no engine calls (tests/pvpzone_test.lua reads it). Lua 5.1 / LuaJIT and Lua 5.3.
-- Overview: server/README.md "The Scorched Marches (open-world PvP zone)".
-- Item ids are SERVER ids.

local UPHEAVAL, FATE, AWAKENING, GILDING = 29856, 29857, 29851, 24691

return {
	enabled = true,
	opcode = 193, -- ChaosOpcodes.pvpZone (client game_pvpzone)
	name = "The Scorched Marches",
	minLevel = 150, -- to enter; also the lowest victim level whose defeat counts (anti-farming)

	-- ------------------------------------------------------------------ where the zone is
	-- "build": built at runtime with Game.createTile in the empty part of the map (no base map edit), one instance per
	--          realm (standard = slot 0; a running season gets its own slot, so season and standard characters never
	--          share embers, piles, the shrine or its buff).
	-- "map":   an existing area of the loaded map, given by `area` below (its own walls, spawns and monsters; nothing is
	--          built). One instance only: `area.realm` is the only realm let in. Not tried on a live map yet.
	mode = "build",
	-- slot i at origin + (i % cols, i // cols) x spacing; x/y 13312 - 13823 (clear of every other runtime area)
	grid = {origin = {x = 13312, y = 13312, z = 7}, cols = 4, slots = 4, spacing = 128},
	field = {innerW = 72, innerH = 56}, -- the walkable inside of an instance (outer wall around it)
	-- stock things (the battleground uses the same set)
	ids = {
		ground = 407, -- black marble floor: the scorched plain
		gateGround = 413, -- stone floor: the gate yards around the safe exits
		ring = 406, -- white marble floor: the shrine circle and the exit circles
		wall = 5648, -- stone wall (outer wall and ruins)
		pillar = 1514, -- stone pillar (cover)
		shrine = 1481, -- coal basin: the Cinder Shrine itself (unwalkable)
		exitMark = 1436, -- castle flag beside an exit circle
		pile = 2249 -- "ashes": the ember pile a defeated player leaves (a marker; the pile itself lives in the script)
	},
	-- the look of the field (build mode; pvpzone_core.lua K.layout, deterministic, the same in every slot). Every id is a
	-- stock item the generated hunting areas use (areagen_config.lua grounds, borders, obstacles; areaplan/decor_kits.json
	-- decoration). Local coordinates 1..innerW x 1..innerH; every list is laid in one half and turned 180 degrees for the
	-- other, so both gates have the same cover (fair).
	look = {
		-- natural ground: scorched rock, basalt fields with their border pieces, crack patches (lava cracks) with the
		-- rock's border over them (areagen families rockfloor / basalt / cracks)
		rock = {9068, 9069, 9070, 9071, 9072, 9073},
		basalt = {17625, 17626, 17627, 17628},
		cracks = {5815},
		-- border pieces (areagen_config.lua `pieces`): basalt over rock, rock over the cracks
		basaltEdge = {n = 17630, e = 17631, s = 17629, w = 17632, cnw = 17639, cne = 17640, csw = 17638, cse = 17637,
			dnw = 17635, dne = 17636, dsw = 17634, dse = 17633},
		crackEdge = {n = 7079, e = 7080, s = 7081, w = 7082, cnw = 7083, cne = 7084, csw = 7085, cse = 7086,
			dnw = 7087, dne = 7088, dsw = 7089, dse = 7090},
		-- paved: the roads (flagstone, weighted), the plaza around the shrine and the gate yards, the ruined hall floor
		road = {{3152, 25}, {3153, 25}, {3154, 5}, {3155, 5}, {3156, 3}, {3157, 1}},
		hall = 414,
		-- ground patches: ellipses (x, y = centre, rx, ry = radii) with a rough edge
		patches = {
			{kind = "basalt", x = 22, y = 16, rx = 9, ry = 6}, {kind = "basalt", x = 16, y = 42, rx = 5, ry = 4},
			{kind = "basalt", x = 44, y = 8, rx = 6, ry = 4}, {kind = "basalt", x = 8, y = 26, rx = 4, ry = 5},
			{kind = "cracks", x = 36, y = 8, rx = 5, ry = 3}, {kind = "cracks", x = 14, y = 32, rx = 5, ry = 4},
			{kind = "cracks", x = 30, y = 46, rx = 6, ry = 3}, {kind = "cracks", x = 50, y = 22, rx = 4, ry = 5},
			{kind = "cracks", x = 28, y = 20, rx = 3, ry = 2}
		},
		plazaRadius = 6, -- paved plaza around the shrine (Chebyshev)
		-- roads from a gate yard to the shrine plaza and on to the ruins: 3 wide, a list of waypoints joined by straight
		-- runs (local coordinates, one half; the other half is the turn)
		roads = {
			{{13, 50}, {27, 50}, {27, 42}, {36, 42}, {36, 34}},
			{{30, 28}, {14, 28}}
		},
		-- blocking fixtures with light, beside the objectives: {dx, dy} from the shrine / the exit, and the item
		shrineLights = {id = 1486, at = {{-3, -3}, {3, -3}, {-3, 3}, {3, 3}}}, -- big coal basins in the capture circle
		shrineBeacons = {id = 7059, at = {{-7, -7}, {7, -7}, {-7, 7}, {7, 7}}}, -- glowing skull pillars, the shrine's beacons
		gateLights = {id = 1481, at = {{-4, 4}, {4, 4}, {-4, -1}, {4, -1}}}, -- coal basins in the gate yard
		-- cover: clumps of blocking pieces. Each clump {x, y, r, chance}: tiles within r of the centre get a piece with this
		-- % chance when the field stays connected (checked tile by tile) and the tile is natural ground away from the
		-- gates, the roads and the spawn points. `on = "cracks"`: only on crack ground.
		cover = {
			{name = "charred trees", ids = {2713, 2714, 2715, 2716, 2709, 2710, 2717, 2718}, clumps = {
				{x = 10, y = 20, r = 5, chance = 38}, {x = 24, y = 8, r = 4, chance = 34}, {x = 46, y = 40, r = 5, chance = 36},
				{x = 5, y = 36, r = 3, chance = 40}, {x = 40, y = 20, r = 4, chance = 32}, {x = 18, y = 52, r = 3, chance = 34}}},
			{name = "scorched rock", ids = {24939, 24940, 24941, 24942, 24943, 24944, 22110, 22111, 22112, 22113}, clumps = {
				{x = 33, y = 32, r = 3, chance = 30}, {x = 20, y = 30, r = 4, chance = 30}, {x = 8, y = 46, r = 4, chance = 36},
				{x = 44, y = 26, r = 3, chance = 28}, {x = 38, y = 14, r = 3, chance = 30}, {x = 52, y = 46, r = 3, chance = 30}}},
			{name = "bone fields", ids = {6395, 6396, 6398, 6400, 11253}, clumps = {
				{x = 15, y = 20, r = 3, chance = 20}, {x = 28, y = 38, r = 3, chance = 18}}},
			{name = "lava holes", ids = {389, 8575, 22571}, on = "cracks", clumps = {
				{x = 36, y = 8, r = 4, chance = 28}, {x = 14, y = 32, r = 4, chance = 30}, {x = 30, y = 46, r = 5, chance = 26},
				{x = 50, y = 22, r = 4, chance = 28}}}
		},
		-- decoration (never blocks): percent chance per natural tile
		decor = {
			cracks = {ids = {5840, 5841, 5842, 5843}, chance = 30}, -- lava cracks on crack ground
			rock = {ids = {3610, 3611, 3613, 1320, 1325}, chance = 5},
			bones = {ids = {3124, 3125, 3126, 6524, 7567}, chance = 1.5},
			wall = {ids = {1308, 1311, 1313, 1315, 1320, 1325}, chance = 14}, -- rubble along the outer wall
			plaza = {ids = {3124, 3125, 3126, 6524, 7567, 7568}, chance = 7} -- remains around the shrine
		},
		keepClear = 2 -- no cover within this many tiles of a gate yard
	},

	-- map mode: the rectangle (inclusive), its safe exits, the shrine, the spawn points (optional, the map's own spawns
	-- are scaled anyway) and the realm allowed in (0 = standard characters)
	area = nil, -- e.g. {x1 = 32000, y1 = 32000, x2 = 32080, y2 = 32060, z = 7, exits = {{x =, y =, z =}}, shrine = {x =, y =, z =},
	--          spawns = {}, realm = 0}

	-- ------------------------------------------------------------------ entering
	entry = {
		needPz = true, -- only from a protection zone (a temple, a depot): no escape from a hunt or a fight
		protectSeconds = 10, -- after entering: no damage, cannot attack or be attacked players (ends when attacking)
		cooldownSeconds = 90, -- after a defeat, before entering again
		-- the confirmation the client shows (the server checks that it was accepted). One line each.
		rules = {
			"Open PvP: every player in the Marches can attack you, whatever the world's rules, and you them.",
			"No skulls and no unjustified kills in here. Nobody really dies: you are defeated and thrown out.",
			"Your equipment and experience are safe. Your carried Embers are not: they fall where you are defeated, and your killer can take them.",
			"Embers are only banked when you leave through a safe exit (stand in its circle for a few seconds without fighting).",
			"Monsters here are stronger and drop more. Logging out inside: you come back at a safe exit."
		}
	},
	-- Hardcore (season mode) characters: a Hardcore life is one life. Decided: NOT allowed in at all (allow = false).
	-- In here a player decides when you fall (gank, ambush, outnumbered); a death that is not a death would also be a
	-- hole in the mode. With allow = true they would need a second explicit confirmation (`hcAccept`).
	hardcore = {allow = false},
	-- Self-Found (season mode) characters may enter; they never take another player's ember pile.
	ssf = {takePiles = false},

	-- ------------------------------------------------------------------ inside
	-- safe exits: stand inside the circle (Chebyshev radius) for channelSeconds without dealing or taking damage
	exit = {radius = 1, channelSeconds = 5},
	-- logged in inside (a logout there, a crash, a restart): held for holdSeconds (no damage), then moved to the nearest
	-- safe exit with protectSeconds of protection
	login = {holdSeconds = 3, protectSeconds = 10},
	-- PvP damage and healing between players scale like the battleground (battleground_config.lua `normalise`, the
	-- bracket of the target sets the reference level); healing from others is not scaled
	pvpScale = true,
	assistSeconds = 10, -- a player's hit in the victim's last seconds makes him the killer when a monster lands the last blow
	-- the battle lock (the engine's CONDITION_INFIGHT: the PvP lock and the white skull ride on it, renewed with the
	-- server's pzLocked time by every player hit). Beta 2026-10-20: it outlived the zone by 3+ minutes. Inside it is cut
	-- to maxSeconds every tick; leaving (exit, defeat, any way out) removes it, and again `clearAfterMs` later, because a
	-- cancelled lethal hit still runs the engine's attack bookkeeping after onPrepareDeath and puts it back.
	combatLock = {maxSeconds = 60, clearAfterMs = {100, 1000}},
	hudSeconds = 2, -- HUD refresh while inside

	-- ------------------------------------------------------------------ embers (the zone's currency)
	carry = {max = 2500}, -- carried at most (more is lost, the player is told)
	bankMax = 200000, -- banked at most
	-- per monster killed inside (the player with the most damage), by tier (monster_tiers.lua)
	monsterEmbers = {normal = 2, magic = 6, rare = 15, legendary = 40, boss = 150},
	death = {
		-- where a defeat sends the player (decided 2026-10-20, beta report: "respawns on a safe zone" with a 3+ minute
		-- debuff): "temple", the home town's temple, the place every other death sends a character, never inside the
		-- zone (the entry cooldown would keep him waiting there) and never the protection zone he happened to enter from
		-- (a depot, a hideout door). "entry" = back where he entered (the behaviour before).
		respawn = "temple",
		dropShare = 1.0, -- share of the carried embers that fall into the pile (the rest burns)
		ownerSeconds = 30, -- only the killer may take the pile this long (a monster's victim: anyone at once)
		pileSeconds = 120, -- then the pile burns out
		pickupRange = 1 -- stand on the pile or next to it
	},
	-- what one player may take from piles of other players
	pickup = {perKillMax = 800, perDayMax = 4000},

	-- ------------------------------------------------------------------ anti-farming (as guild wars): a defeat counts
	-- (reputation, the pile for the killer, stats) only if none of these say no; else the pile burns and nothing is given
	antiFarm = {
		sameIp = true,
		sameAccount = true,
		minLevelRatio = 0.6, -- the victim has at least this share of the killer's level
		sameVictimMinutes = 30, -- the same victim counts again for the same killer only after this
		minSecondsInside = 20 -- a victim who entered less than this ago does not count
	},

	-- ------------------------------------------------------------------ factions: the pledge (flag)
	-- a player pledges the Marches to one faction (factions_config.lua); unpledged players fight but earn no reputation
	-- and cannot take the shrine. Defeating a player pledged to another faction gives reputation to the own faction
	-- (factions.lua gain, source "pvpzone": diminishing returns, weekly cap, rival loss).
	reputation = {
		minRank = "neutral", -- pledging needs at least this rank with the faction
		changeHours = 24, -- a new pledge only this long after the last one
		perKill = 40,
		rivalMult = 1.0, -- victim of the faction's sworn rival (factions_config.lua `rival`)
		otherMult = 0.5, -- victim of one of the two other factions; same faction: nothing
		dailyCap = 400 -- reputation from Marches kills per character and faction day
	},

	-- ------------------------------------------------------------------ the Cinder Shrine (zone event)
	contest = {
		firstMinutes = 15, -- after the server start (or the instance build) the first contest
		everyMinutes = 120, -- then one contest every this long (from the start of the last one)
		windowMinutes = 20, -- a contest not won in this time ends without a holder (the old control runs out)
		warden = {name = "Demon", title = "Shrine Warden", hpMult = 6}, -- must fall before the shrine can be taken
		-- capture: pledged players of ONE faction alone in the circle raise its progress by 100 / seconds per second
		-- x (1 + perExtra x (n - 1)) up to maxRate; two factions inside = contested (no change); a faction with nobody
		-- inside loses decayPerSecond. First to 100 takes the shrine.
		capture = {radius = 3, seconds = 60, perExtra = 0.25, maxRate = 2, decayPerSecond = 0.5},
		holdMinutes = 60, -- the faction-wide buff of the holder (every character pledged to it, in that realm)
		buff = {exp = 10, loot = 10}, -- percent: experience from monsters and the loot rate, anywhere
		embers = {capture = 200, warden = 100} -- to every pledged player of the capturing faction in the circle / to the
		-- warden's killer (most damage)
	},

	-- ------------------------------------------------------------------ monsters inside
	monsters = {
		hpMult = 1.6, -- health
		damageMult = 1.35, -- their damage to players
		expMult = 1.5, -- experience
		lootMult = 1.5, -- the Chaos loot rate (loot_config.lua rateMult)
		respawnSeconds = 90, -- an empty spawn point (build mode) refills after this
		-- build mode: one of these per spawn point (picked by the point's number); stock monsters of the base server
		list = {"Dragon Lord", "Hellhound", "Grim Reaper", "Undead Dragon", "Blightwalker", "Fury", "Destroyer",
			"Dark Torturer", "Plaguesmith", "Behemoth", "Hellspawn", "Hand of Cursed Fate"},
		spawnSpacing = 9, -- spawn points on a grid this far apart, away from the exits and the shrine
		keepAway = {exit = 9, shrine = 7}
	},

	-- ------------------------------------------------------------------ the vendor (banked embers)
	-- Orbs, consumables and cosmetics only: never power above PvE gear.
	--   kind "item": {id, count}; kind "cosmetic": a cosmetics_config.lua key with source "pvp"; weekly = purchases per
	--   week (Monday 06:00), nil = no limit
	vendor = {
		{key = "upheaval", kind = "item", id = UPHEAVAL, count = 3, cost = 300, weekly = 5, name = "3 Orbs of Upheaval"},
		{key = "awakening", kind = "item", id = AWAKENING, count = 2, cost = 350, weekly = 5, name = "2 Orbs of Awakening"},
		{key = "gilding", kind = "item", id = GILDING, count = 2, cost = 350, weekly = 5, name = "2 Orbs of Gilding"},
		{key = "fate", kind = "item", id = FATE, count = 1, cost = 500, weekly = 3, name = "1 Orb of Fate"},
		{key = "ghp", kind = "item", id = 7591, count = 50, cost = 80, name = "50 great health potions"},
		{key = "gmp", kind = "item", id = 7590, count = 50, cost = 80, name = "50 great mana potions"},
		{key = "gsp", kind = "item", id = 8472, count = 50, cost = 80, name = "50 great spirit potions"},
		{key = "uhp", kind = "item", id = 8473, count = 50, cost = 150, name = "50 ultimate health potions"},
		{key = "c_kill", kind = "cosmetic", cosmetic = "kill_marchfire", cost = 4000, name = "Kill effect: Marchfire"},
		{key = "c_loot", kind = "cosmetic", cosmetic = "loot_scorched", cost = 3000, name = "Loot labels: Scorched Earth"},
		{key = "c_chat", kind = "cosmetic", cosmetic = "chat_marchember", cost = 3500, name = "Chat name: Marchember"}
	},

	-- ------------------------------------------------------------------ boards, achievements, storage, tables
	leaderboard = "marches", -- weekly board (leaderboard_config.lua): embers banked
	-- achievements_data.lua stats: pvpzone_kills (counted defeats of pledged rivals), pvpzone_banked (embers banked in
	-- total), pvpzone_haul (most embers banked at one exit), pvpzone_captures (shrine captures stood in the circle)
	-- player storages 7100520 - 7100529 reserved: +0 inside (1; also the crash marker), +1 protected until (os.time),
	-- +2 carried embers, +3 return x, +4 return y, +5 return z, +6 entered at (os.time)
	storage = {inside = 7100520, protect = 7100521, carried = 7100522, retX = 7100523, retY = 7100524, retZ = 7100525,
		enteredAt = 7100526},
	tables = {
		players = "chaos_pvpzone_players", -- banked embers, pledge, stats, daily and weekly counters per character
		control = "chaos_pvpzone_control", -- the shrine holder per realm (survives a restart)
		purchases = "chaos_pvpzone_purchases" -- vendor purchases (the log and the weekly limits)
	},
	tickMs = 1000,
	staffGroup = 4 -- /marches staff commands
}
