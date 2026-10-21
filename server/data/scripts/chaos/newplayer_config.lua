-- New-player settings (newplayer.lua, newplayer_tutorial.lua, newplayer_core.lua). Loaded with
--     ChaosNewPlayerConfig = dofile("data/scripts/chaos/newplayer_config.lua")
-- Data only, no engine calls (the unit test loads it). Item ids are SERVER ids (items.xml of the base server).
-- Overview: server/README.md "New players".
--
-- Kits are keyed by a kit name; `vocations` maps a vocation id to a kit name. A vocation that is not listed falls back
-- to its base class (Chaos.classes.baseOf, then the engine's Vocation(id):getDemotion()), then to `default`.
-- Vocation names are never written here: messages read them from Vocation(id):getName(), so the class rework can
-- rename vocations without touching this file. Other scripts extend the tables through ChaosNewPlayer.setKit /
-- ChaosNewPlayer.kitFor (newplayer_core.lua).
--
-- Slots: head, necklace, backpack, armor, right (the shield hand), left (the weapon hand), legs, feet, ring, ammo (the second ring slot).
-- An equip entry whose slot is taken goes into the kit backpack instead. `minLevel` + `fallback`: below minLevel the
-- fallback is equipped and the real weapon goes into the backpack (a wand of level 7 is no use at level 1).
-- Checked in the base server's weapons.xml / movements.xml: every item below can be worn or wielded by its classes at
-- level 1 (the wands and rods at level 7, with a level 1 fallback); the Thief line gets what add_vocations.py lets it
-- use (one-handed swords, the Ranger's armour). No throwing stars: the shuriken spells need none (data/lib/chaos_throwables.lua).
-- Weight: a level 1 character carries 400-470 oz (start_stats.lua). Every kit stays under about 360 oz with everything
-- in it (the warrior's brass set is the heaviest); what does not fit goes to the inbox.
-- Potions: the only starting potions are the two Everfull potions (potions_config.lua, ChaosPotions.giveAll; owner
-- request 2026-10-16). No kit carries stock health or mana potions; the milestone gifts below still do.
-- Two parts (2026-10-16): the WEARABLE part (`equip`, the kit backpack and the Everfull potions; NP.giveWearable) and
-- the REST (`backpack` rows, `common.items`, the temple scroll, the gold, a spare weapon of `minLevel`; NP.giveKit).
-- Without the tutorial island (the default since the owner's design of 2026-10-16) both come at the first login, in the
-- login event itself, so the character's first frame in Cinderhold shows it wearing its kit. With the island on, the
-- wearable part comes on arrival and the rest when it ends.

return {
	-- ------------------------------------------------------------------ kits
	kits = {
		warrior = {
			equip = {
				{slot = "left", id = 8602}, -- jagged sword
				{slot = "right", id = 2525}, -- dwarven shield
				{slot = "head", id = 2460}, -- brass helmet
				{slot = "armor", id = 2465}, -- brass armor
				{slot = "legs", id = 2478}, -- brass legs
				{slot = "feet", id = 2643} -- leather boots
			},
			backpack = {},
			role = "melee"
		},
		ranger = {
			equip = {
				{slot = "left", id = 2456}, -- bow (two-handed)
				-- no arrows: bows fire without ammunition (data/lib/chaos_archery_config.lua); quivers come from loot
				{slot = "head", id = 2458}, -- chain helmet
				{slot = "armor", id = 2660}, -- ranger's cloak
				{slot = "legs", id = 2468}, -- studded legs
				{slot = "feet", id = 2643}
			},
			backpack = {},
			role = "ranged"
		},
		mystic = { -- Mystic, Elementalist, Illusionist: wands and rods
			equip = {
				{slot = "left", id = 2190, minLevel = 7, fallback = 23719}, -- wand of vortex; scorcher below level 7
				{slot = "right", id = 2175}, -- spellbook
				{slot = "head", id = 2461}, -- leather helmet
				{slot = "armor", id = 8819}, -- magician's robe
				{slot = "legs", id = 2649}, -- leather legs
				{slot = "feet", id = 2643}
			},
			backpack = {},
			role = "caster"
		},
		thief = {
			equip = {
				{slot = "left", id = 2379}, -- dagger (a one-handed sword)
				{slot = "head", id = 2461},
				{slot = "armor", id = 2467}, -- leather armor
				{slot = "legs", id = 2468},
				{slot = "feet", id = 2643}
			},
			backpack = {
				{id = 2379, count = 1} -- the second dagger (owner 2026-10-17: the Thief starts with 2 daggers)
			},
			role = "ranged" -- the Royal Paladin's potions (add_vocations.py)
		},
		monk = { -- the Monk line fights unarmed: no weapon, the light armour the Ranger may wear (add_vocations.py)
			equip = {
				{slot = "head", id = 2461}, -- leather helmet
				{slot = "armor", id = 2467}, -- leather armor
				{slot = "legs", id = 2468}, -- studded legs
				{slot = "feet", id = 2643}
			},
			backpack = {},
			role = "ranged" -- the Royal Paladin's potions (add_vocations.py)
		},
		necromancer = { -- the Necromancer line wields and wears what the Mystic does (add_vocations.py): the caster kit
			base = "mystic"
		},
		templar = { -- the Templar line: a one-handed sword and a shield, the armour the Warrior wears (add_vocations.py)
			base = "warrior"
		},
		berserker = { -- the Berserker wields two-handed weapons only (add_vocations.py): a battle axe, no shield. Not
			-- based on "warrior": an inherited row would keep the warrior's shield hand
			equip = {
				{slot = "left", id = 2378}, -- battle axe (two-handed, no level)
				{slot = "head", id = 2460}, -- brass helmet
				{slot = "armor", id = 2465}, -- brass armor
				{slot = "legs", id = 2478}, -- brass legs
				{slot = "feet", id = 2643} -- leather boots
			},
			backpack = {},
			role = "melee"
		},
		samurai = { -- one katana-style sword: the base server's katana (a one-handed sword, no level) instead of the dagger
			base = "thief",
			equip = {
				{slot = "left", id = 2412} -- katana
			}
		},
		ninja = { -- like the Thief (which carries the second dagger for the off hand)
			base = "thief"
		},
		default = {
			equip = {
				{slot = "left", id = 2406}, -- short sword
				{slot = "right", id = 2512}, -- wooden shield
				{slot = "head", id = 2461},
				{slot = "armor", id = 2467},
				{slot = "legs", id = 2649},
				{slot = "feet", id = 2643}
			},
			backpack = {},
			role = "melee"
		}
	},

	-- vocation id -> kit, by the class ids of Chaos.classes.ids (chaos_constants.lua, docs/CLASSES.md): a character is
	-- created as Warrior 4, Ranger 3, Mystic 1, Thief 11, Monk 17, Necromancer 20 or Templar 23 (the last three behind the
	-- store's class unlock); the ascended classes are listed too (staff re-grants, a
	-- class changed before the first login). The retired ids 2, 6 and 9 have no row (class_migration.lua moves them;
	-- they would get `default`). A new class needs one row here, or ChaosNewPlayer.setKit from its own script.
	vocations = {
		[4] = "warrior", -- Warrior
		[8] = "warrior", -- Juggernaut
		[14] = "berserker", -- Berserker
		[3] = "ranger", -- Ranger
		[7] = "ranger", -- Deadeye
		[15] = "ranger", -- Beastmaster
		[1] = "mystic", -- Mystic
		[5] = "mystic", -- Elementalist
		[10] = "mystic", -- Illusionist
		[11] = "thief", -- Thief
		[12] = "ninja", -- Ninja
		[13] = "samurai", -- Samurai
		[17] = "monk", -- Monk
		[18] = "monk", -- Shadowfist
		[19] = "monk", -- Iron Sage
		[20] = "necromancer", -- Necromancer
		[21] = "necromancer", -- Lich
		[22] = "necromancer", -- Bone Lord
		[23] = "templar", -- Templar
		[24] = "templar", -- Inquisitor
		[25] = "templar" -- Sentinel
	},
	-- vocations the kit never handles: the base server's creaturescripts/firstitems.lua already equips vocation 0
	skipVocations = {[0] = true},

	-- every kit's backpack also gets these
	common = {
		backpackId = 1988, -- backpack
		items = {
			{id = 2789, count = 20}, -- brown mushrooms (light: ham weighs 20 oz a piece)
			{id = 2120, count = 1}, -- rope
			{id = 2554, count = 1} -- shovel
		},
		templeScrollUses = 3, -- the store's Temple Teleport Scroll (Chaos.shopServices.templeScroll), 0 = none
		gold = 500 -- gold coins (player:addMoney)
	},

	-- ------------------------------------------------------------------ home town (owner request 2026-10-15)
	-- The main city: new characters live there (their temple, respawn and Town Portal). A brand-new character (no kit
	-- yet) whose town is not `id` and not in `keep` is moved to `id` once, at its first login (before the tutorial
	-- island; with the island off it is sent to the new temple at once). Characters that already have their kit keep
	-- their town. `keep`: town ids the website offers as a free choice (CHAOS_START_TOWNS) that are kept as chosen; {}
	-- = every new character goes to `id`. id = 0 turns it off (the town of the character's creation stays).
	-- Cinderhold (town 2) was chosen by data: server/README.md "Main city". The website's default is the same town.
	homeTown = {id = 2, keep = {}},

	-- the base server's starter chest (data/scripts/customs/actions/first_chest.lua, action id and storage 33735):
	-- characters that got the kit are marked as having opened it, so nobody collects two starter sets. nil = leave the
	-- chest alone.
	baseChestStorage = 33735,

	-- ------------------------------------------------------------------ milestone gifts (one time per character)
	-- potions by kit role; the base potions script refuses the strong ones to some vocations, so each role gets what
	-- it may drink (add_vocations.py: the Thief and Monk lines drink the Royal Paladin's, "ranged")
	milestones = {
		{level = 20, orbs = 1, potions = {
			melee = {{7618, 50}}, ranged = {{7618, 25}, {7620, 25}}, caster = {{7620, 50}}}},
		{level = 50, orbs = 2, potions = {
			melee = {{7588, 50}}, ranged = {{7588, 25}, {7589, 25}}, caster = {{7589, 50}}}},
		{level = 100, orbs = 3, items = {{27990, 2}}, -- Stamina Extension (the store item, +2 h of stamina each)
			potions = {melee = {{7591, 50}}, ranged = {{8472, 50}}, caster = {{7590, 50}}}},
		{level = 200, orbs = 5, potions = {
			melee = {{8473, 50}}, ranged = {{26030, 50}}, caster = {{26029, 50}}}},
		-- 2026-10-15: gifts over the whole level range (the Next Goals bands, goals_config.lua); Orbs of Fate (29857)
		-- and Grafting (29855) from 300 on. At most 10 milestones (storages 7100260 - 7100269).
		{level = 300, orbs = 5, items = {{29857, 1}}, potions = {
			melee = {{8473, 75}}, ranged = {{26030, 75}}, caster = {{26029, 75}}}},
		{level = 500, orbs = 6, items = {{29857, 2}, {27990, 2}}, potions = {
			melee = {{8473, 100}}, ranged = {{26030, 100}}, caster = {{26029, 100}}}},
		{level = 800, orbs = 8, items = {{29857, 2}, {29855, 1}}, potions = {
			melee = {{8473, 100}}, ranged = {{26030, 100}}, caster = {{26029, 100}}}},
		{level = 1000, orbs = 10, items = {{29857, 3}, {29855, 1}, {27990, 2}}, potions = {
			melee = {{8473, 100}}, ranged = {{26030, 100}}, caster = {{26029, 100}}}},
		{level = 1500, orbs = 12, items = {{29857, 3}, {29855, 2}}, potions = {
			melee = {{8473, 100}}, ranged = {{26030, 100}}, caster = {{26029, 100}}}},
		{level = 2000, orbs = 15, items = {{29857, 5}, {29855, 3}}, potions = {
			melee = {{8473, 100}}, ranged = {{26030, 100}}, caster = {{26029, 100}}}}
	},
	orbId = 29856, -- Orb of Upheaval

	-- ------------------------------------------------------------------ welcome (one time, after the kit)
	welcome = {
		title = "Welcome to Cinders of Chaos",
		-- %s = character name, %s = vocation name, %s = the gift line (NP.giftLine: the milestone levels still ahead)
		text = "Welcome, %s the %s.\n\n" ..
			"Your starter kit is in your backpack. Next steps:\n" ..
			"- Character > Spellbook (Alt+S): every spell of your class and what it does.\n" ..
			"- The passive tree (top menu, Character): a point every 4 levels past level 8.\n" ..
			"- Adventure > Bounty Board: daily contracts that pay gold and Orbs of Upheaval.\n" ..
			"- The store (top menu, Economy): temple scrolls, stamina and services.\n" ..
			"- Cinderhold is the main city: the two great teleports north of its temple lead to the teleport room, " ..
			"a portal to a hunt of every level.\n" ..
			"- The top menu holds every game window: dungeons, the tower, dailies, bank and stash.\n\n" ..
			"%s",
		toast = "Welcome to Cinders of Chaos! Your kit is in your backpack. Everything else is in the menu at the top.",
		delayMs = 2500,
		-- owner design 2026-10-16: the first login opens the Helper on its Auto setup button (client game_helperrotation
		-- onboarding.lua, through the toast's message, action "newplayer" with openHelper) instead of a modal window;
		-- the welcome text goes to the chat (Server Log). window = true brings the modal back.
		window = false,
		helper = {open = true, hint = "Set up your helper in one click: press Auto setup."},
		firstToast = "Welcome to Cinders of Chaos! You start in Cinderhold at level 8, wearing your kit. Set up your helper in one click."
	},

	-- ------------------------------------------------------------------ storages (Chaos.storage.newPlayer + offset)
	storage = {
		kit = 0, -- os.time when the kit was given
		welcome = 1, -- 1 once the welcome was shown
		stage = 2, -- tutorial: 1..5 = station in progress, 100 = finished, 101 = skipped
		done = 3, -- tutorial: bit (station - 1) set when that station's task is done
		kills = 4, -- tutorial station 1: kills so far
		orbBase = 5, -- tutorial station 4: Orbs of Upheaval owned after the orb was handed out
		flags = 6, -- tutorial bits: 1 spellbook opened, 2 spell cast, 4 passive point given, 8 orb given, 16 mana topped up
		islandUsed = 7, -- tutorial: seconds spent on the island in earlier sessions (instance limits)
		wear = 8, -- os.time when the wearable part of the kit was given (NP.giveWearable: with the kit, or on arrival at
		-- the island while it is on)
		statsFixed = 9, -- 1 once the login checked the start level and stats (NP.fixStats, start_stats.lua)
		milestone = 10 -- + index into milestones (10 .. 19)
	},
	stageDone = 100,
	stageSkipped = 101,

	-- ------------------------------------------------------------------ tutorial island (newplayer_tutorial.lua)
	tutorial = {
		-- owner design 2026-10-16: no tutorial island. New characters start at level 8 in the temple of Cinderhold with
		-- the full kit (start_stats.lua, newplayer.lua). The island's code stays; true brings it back. With false a
		-- character still on the island leaves it at its next login (the temple, the full kit, level 8 stats).
		enabled = false,
		-- instance limits (instance_limits.lua, server/README.md "Instance limits"): a character spends at most
		-- timeLimitMinutes online on the island (the stations take 5-10 minutes); then it leaves as with "Skip
		-- tutorial": the kit, the welcome, its temple. Warnings at warnAt seconds left. The island is one shared place
		-- (no copies, no cap); the training rats are at most maxMonsters at once.
		timeLimitMinutes = 30,
		limits = {warnAt = {300, 60}},
		-- built at startup with Game.createTile, like the world boss arena (newplayer_core.lua NP.layout, NP.islandModel).
		-- Footprint x 4585-4655, y 4589-4621, z 7 (the pens x 4600-4640, y 4600-4610; land, then water out to the view):
		-- the map has no tiles within x/y 4500-5600 (server/README.md "World bosses"); the build checks again and
		-- refuses to build over tiles that are not its own. Then new characters get the kit at once (no island).
		-- Preview: python3 -I server/tools/areagen_export.py preview OUT ... --area tutorial
		origin = {x = 4600, y = 4600, z = 7}, -- the north-west corner of the fence
		rooms = 5, roomW = 7, roomH = 9, -- five pens side by side, separated by fences with one gate (a gap) each
		landPad = 3, -- tiles of land (trees, bushes, lamps, the way to the dock) between the fence and the water
		dockLength = 4, -- the dock on the west shore, on the arrival row (0 = none)
		-- the water reaches past every tile the client can show from inside a pen: its largest view (game_chaosview,
		-- the server's limit 29 x 21) plus one tile, so the view never shows an unmapped (black) tile
		view = {w = 29, h = 21},
		waterRing = 2, -- at least this much water outside the land
		ground = 4526, -- grass (the first of look.grass; kept for the build check)
		markerGround = 406, -- white marble: the lesson tile of every station
		gateGround = 103, -- dirt: the path, and the gate in a divider fence
		water = 4608, -- water (not walkable)
		statue = 1448, -- angel statue: "use" it to read the station's lesson again
		skipStatue = 1447, -- goblin statue beside the arrival tile: "use" it to skip the tutorial
		sign = 1429, -- signpost per station (beside the path where the pen begins): "use" it to read the lesson
		basin = 1481, -- coal basin (light)
		portal = 1387, -- magic forcefield (no destination; the MoveEvent moves the player)
		-- the island's look. Server ids of the stock items; border and fence pieces measured on the live map with
		-- tools/map/derive_borders.py (shore: water over grass; pathEdge: grass over dirt; the fence by neighbours)
		look = {
			grass = {4526, 4527, 4528, 4529, 4530, 4531, 4532, 4533}, -- grass variants
			water = {4608, 4609, 4610, 4611, 4612, 4613}, -- shallow water variants
			path = 103, -- dirt
			dock = 405, -- wooden floor
			shore = {n = 4644, e = 4645, s = 4646, w = 4647, cnw = 4652, cne = 4653, csw = 4654, cse = 4655,
				dnw = 4648, dne = 4649, dsw = 4650, dse = 4651},
			pathEdge = {n = 4542, e = 4543, s = 4544, w = 4545, cnw = 4546, cne = 4547, csw = 4548, cse = 4549,
				dnw = 4550, dne = 4551, dsw = 4552, dse = 4553},
			fence = {post = 1533, vertical = 1534, joint = 1535, horizontal = 1536, southEnd = 1538},
			trees = {2700, 2768, 2703, 2708, 2702}, -- fir, small fir, plum tree, poplar, willow
			bushes = {2767, 2785, 4015}, -- bush, blueberry bush, big fern
			flowers = {2742, 2740, 2743, 6227, 6219, 6218, 24304, 3611}, -- flowers, grass tufts, stones (not blocking)
			lamp = 1480, -- lit street lamp (light 7)
			bollard = 4973, barrel = 1770,
			boat = {3587, 3590, 3589, 3591} -- a small boat, bow to stern, north to south
		},
		aid = {marker = 47501, statue = 47502, skip = 47503, gate = 47504, exit = 47505}, -- the signposts carry `statue`
		modalBase = 47500, -- modal window ids 47500 .. 47510

		-- station 1: kill training monsters (the first that exists)
		monsters = {"Rat", "Cave Rat"},
		kills = 3,
		maxMonsters = 3, -- alive in the first room at once
		spawnDelayMs = 20000, -- they come when the lesson is closed, the lesson tile is stepped on, or after this
		-- station 2: the class spell to cast (vocation id -> kit name like the kits, then the spell); a class without a
		-- spell it can cast at level 1 only has to open the spellbook
		spells = {
			-- Arcane Stitch left with the 15-spell cap (2026-10-20): Minor Mending, the Ranger and Mystic lines level 8 heal
			warrior = {name = "Salve of Scars", words = "saen tin brak", mana = 10},
			ranger = {name = "Minor Mending", words = "saen", mana = 20},
			mystic = {name = "Minor Mending", words = "saen", mana = 20}
		},
		-- station 4: the Orb of Upheaval and the item it is used on (a Common = rarity 1 leather armor)
		orbItem = {id = 2467, rarity = 1},
		-- what the island gives is lent (NP.tutorialReset, server/README.md "Tutorial reset"): every item it creates
		-- carries this custom attribute and is taken back when the character leaves the island
		lentTag = "chaos_tutorial",

		-- the first window on the island (NP.showArrival): Start tutorial / Skip to Cinderhold. %d = timeLimitMinutes
		arrival = {
			title = "Welcome to the Isle of First Blood",
			text = "You are wearing your class's starter gear, with your Everfull health and mana potions in your " ..
				"backpack.\n\n" ..
				"Five short stations (5 to 10 minutes, at most %d) teach fighting, spells, the passive tree and orbs. " ..
				"At the end you arrive at the temple of Cinderhold, the main city, with the rest of your kit and gold.\n\n" ..
				"Played before? Skip to Cinderhold now: you get the same kit. You can also skip later with the goblin " ..
				"statue beside you or Character > Services > Leave Tutorial.",
			toast = "Tutorial or not? Press Skip to Cinderhold in the window, or use the goblin statue beside you."
		},

		lessons = {
			{title = "Station 1: Moving and fighting",
				text = "Welcome to the Isle of First Blood.\n\n" ..
					"Walk with the arrow keys or by clicking the ground. Attack a creature by clicking it in the battle list " ..
					"or with ctrl + click / right click on it. Keep an eye on your health bar.\n\n" ..
					"Task: kill %d of the rats in this pen. The gate to the east opens when you are done.\n\n" ..
					"Experienced? Use the goblin statue (or Character > Services) to take your kit and leave at once.",
				toast = "Station 1: kill %d rats in the first pen."},
			{title = "Station 2: Spells",
				text = "Every class has its own spells. Character > Spellbook in the top menu (Alt+S) lists them with " ..
					"their words, mana, level and what they do.\n\n" ..
					"Task: open your spellbook (Character > Spellbook)%s",
				toast = "Station 2: open your spellbook%s"},
			{title = "Station 3: The passive tree",
				text = "Every 4 levels past level 8 you get a passive point. Spend them in the passive tree (top menu, " ..
					"Character > Passive Tree): start next to the centre and walk outwards. Big nodes are notables; the " ..
					"keystones at the far ends change how your class plays.\n\n" ..
					"Task: you get one free point now. Open the tree, click a node next to the centre and press Apply Plan.",
				toast = "Station 3: spend your free passive point (Apply Plan)."},
			{title = "Station 4: Orbs and crafting",
				text = "Monsters drop orbs. An Orb of Upheaval rerolls the modifiers of an item with a rarity, an Orb of Fate rolls " ..
					"a new rarity, and the other orbs add or remove modifiers.%s\n\n" ..
					"Task: you got an Orb of Upheaval and a Common leather armor. Use the orb on the armor (right click the orb, " ..
					"Use with, then click the armor in your backpack).",
				toast = "Station 4: use the Orb of Upheaval on the leather armor.",
				craftHint = " The crafting bench (Economy > Crafting Bench) shows every orb and what it does."},
			{title = "Station 5: Keystones, bounties and the store",
				text = "Keystones are the big nodes at the edge of the passive tree: they change your class (Cleaving Arc, " ..
					"Ricochet, Arcane Echo...). Plan your path towards one.\n\n" ..
					"The bounty board (Adventure > Bounty Board) gives daily contracts per level band that pay gold and orbs. The store (top menu, Economy) sells " ..
					"cosmetics, stamina and services. Dungeons, the Infinity Tower and the dailies are under Adventure in " ..
					"the top menu.\n\n" ..
					"Step into the forcefield to the east: you get your starter kit and arrive at the temple.",
				toast = "Station 5: step into the forcefield to leave the island."}
		},
		pollMs = 300 -- how often the spell / orb tasks are checked while a player is on them
	}
}
