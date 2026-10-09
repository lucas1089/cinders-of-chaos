-- Settings of the ascension quest (ascension_quest.lua, rules in ascension_quest_core.lua, docs/CLASSES.md "Ascension
-- quest"). Returned as a table; ascension_quest_core.lua puts it in Chaos.ascensionQuest. The level rule and the two
-- ascended classes of every base class are NOT here: they are read at run time from Chaos.classes.ascension
-- (minLevel, choices), so a new class line gets the quest without changes in this file.
return {
	enabled = true,

	-- the NPC (server/data/npc/Ascendant Oracle.xml + scripts/ascendant_oracle.lua). At startup it is placed in the temple
	-- of every town listed here, on the first free tile of `offsets` around the temple position, unless an NPC of that
	-- name already stands within 8 tiles (placed with the map editor). positions = {{x, y, z}, ...} places it exactly.
	npc = {
		name = "Ascendant Oracle",
		spawn = true,
		townIds = {1},
		positions = {},
		offsets = {{2, -2}, {-2, -2}, {2, 2}, {-2, 2}, {3, 0}, {-3, 0}, {0, -3}, {0, 3}, {1, -2}, {-1, -2}},
		-- the confirmations (modal windows) only work this close to the Oracle
		range = 6
	},

	-- storages (player). stage: 0 not started, 1 the Calling heard (Proof running), 2 Proof done (Trial open),
	-- 3 Trial won (the Choice), 4 ascended through the quest
	storage = {
		stage = 7101000,
		proof = 7101001, -- Proof of Strength points
		cooldown = 7101002, -- os.time until the Trial may be tried again
		attempts = 7101003, -- Trial attempts (information)
		trialWon = 7101004 -- os.time of the Trial victory (information)
	},

	-- stage 2, Proof of Strength: rare and legendary monsters at the player's level. A kill counts when the monster's
	-- hunting level (bounty_pool.lua, else 1.6 x sqrt(experience) raised by health / 60, as tools/gen_bounty_pool.py
	-- estimates it) is at least levelShare x the player's level (and at least minMonsterLevel).
	proof = {
		needed = 10,
		points = {rare = 1, legendary = 3},
		levelShare = 0.6,
		minMonsterLevel = 40
	},

	-- stage 3, the Trial: a runtime-built room per attempt (Game.createTile, the footprint must be empty, as rift.lua and
	-- arena.lua check). Slots on a grid east of the arena grid; nothing else uses x/y 7000..7100.
	trial = {
		grid = {origin = {x = 7000, y = 7000, z = 7}, cols = 4, slots = 8, spacing = 24},
		inner = 13, -- inner width / height of the room (odd: a centre tile)
		groundId = 407, -- black marble floor
		wallId = 5648, -- stone wall
		basinId = 1481, -- coal basin (light) in the corners
		-- dark tile set (server/README.md "Dark tile set"): with the set installed the walls and lights use these and
		-- the room is painted with the `style` of data/lib/chaos_dark_paint.lua (nothing solid on the floor: the
		-- fight needs room to move); else the ids above are used
		dark = {enabled = true, wall = "ruined_wall", basin = "brazier", style = "trial"},
		timeLimitSeconds = 180,
		countdownSeconds = 3, -- the guardian appears after this
		cooldownSeconds = 600, -- after a failed attempt
		winExitSeconds = 6, -- after the victory, back to the Oracle
		tickMs = 500,
		-- the guardian is tuned for levels 100-130: the player's level is clamped into that band, health and damage grow
		-- linearly with it (x1.0 at 100, x(130/100) at 130). Players above 130 meet the level 130 guardian.
		scaleMin = 100,
		scaleMax = 130,
		guardianHealth = 6000, -- at scaleMin
		-- the guardian's own XML attacks are multiplied by this x the scale (onHealthChange)
		guardianDamage = 1.0,
		enrageBelow = 0.3, -- "enrage": below this share of health the guardian hits harder
		enrageMultiplier = 1.5,
		-- "stillness": standing on the same tile this long is punished with a slam of `share` of the max health
		stillWarnMs = 2000,
		stillMs = 3000,
		stillShare = 0.2,
		-- "adds": every `every` ms, `count` shades around the guardian (at most `max` alive)
		addEvery = 15000,
		addCount = 2,
		addMax = 4,
		addHealth = 600, -- at scaleMin
		-- "zones": every `every` ms, `count` tiles around the player are marked; after `delay` ms they burst for `share`
		-- of the max health (the player's own tile is always one of them)
		zoneEvery = 6000,
		zoneCount = 5,
		zoneDelay = 1500,
		zoneShare = 0.25,
		zoneRadius = 2,
		-- the monsters (data/monster/monsters/chaos/ascension/); renamed and dressed per class at run time
		guardianMonster = "Ascension Warden",
		addMonster = "Warden Shade"
	},

	-- the guardian of each base class (keyed by base vocation id; a line without an entry gets `default`).
	-- mechanics: any of "stillness", "adds", "zones", "enrage"
	guardians = {
		[4] = {name = "Warden of Iron", look = {lookType = 131, lookHead = 95, lookBody = 95, lookLegs = 95, lookFeet = 95, lookAddons = 3},
			add = {name = "Iron Thrall", look = {lookType = 298}}, mechanics = {"stillness", "enrage"},
			hint = "It crushes those who stand their ground too long. Keep moving."},
		[3] = {name = "Warden of the Hunt", look = {lookType = 240},
			add = {name = "Hunting Hound", look = {lookType = 3}}, mechanics = {"adds", "stillness"},
			hint = "Its hounds come in packs; a hunter who stands still becomes prey."},
		[1] = {name = "Warden of the Veil", look = {lookType = 130, lookHead = 0, lookBody = 94, lookLegs = 114, lookFeet = 95, lookAddons = 1},
			add = {name = "Veil Phantasm", look = {lookType = 241, lookHead = 20}}, mechanics = {"zones", "adds"},
			hint = "The ground under you will burn with runes. Read the marks and step aside."},
		[11] = {name = "Warden of Shadows", look = {lookType = 320},
			add = {name = "Shadow Cutthroat", look = {lookType = 152, lookHead = 95, lookBody = 95, lookLegs = 95, lookFeet = 95, lookAddons = 3}},
			mechanics = {"zones", "stillness"},
			hint = "Shadows do not stay still, and neither may you."},
		[17] = {name = "Warden of the Still Fist", look = {lookType = 57},
			add = {name = "Silent Acolyte", look = {lookType = 57}}, mechanics = {"stillness", "zones"},
			hint = "Stillness is the lesson it teaches the hard way: keep your feet moving."},
		[20] = {name = "Warden of Bones", look = {lookType = 99},
			add = {name = "Risen Bones", look = {lookType = 1542}}, mechanics = {"adds", "zones"},
			hint = "It raises the dead around it. Break them before they bury you."},
		[23] = {name = "Warden of Dawn", look = {lookType = 73},
			add = {name = "Dawn Zealot", look = {lookType = 73}}, mechanics = {"zones", "enrage"},
			hint = "Its light burns where it falls, and it grows fierce as it fades."},
		default = {name = "Warden of Ascension", look = {lookType = 1540},
			add = {name = "Lost Aspirant", look = {lookType = 233}}, mechanics = {"stillness", "adds"},
			hint = "Keep moving and break what it calls."}
	},

	-- the paths of the Calling (the Oracle's words per ascended class, keyed by the word of
	-- Chaos.classes.ascension.choices); a word without an entry shows the vocation's own description
	paths = {
		juggernaut = "the Juggernaut, an unbreakable wall: taunts, damage reduction, a shield that blocks and reflects",
		berserker = "the Berserker, two-handed fury: cleaving blows and a rage that grows as your blood runs out",
		deadeye = "the Deadeye, the single perfect shot: crossbows, marks and critical strikes",
		beastmaster = "the Beastmaster, never alone: beasts that fight beside you and arrows that splash",
		elementalist = "the Elementalist, master of ruin: fire, ice and energy woven into great storms",
		illusionist = "the Illusionist, the hidden hand: strength for your allies, weakness for your foes, some healing",
		ninja = "the Ninja, two blades in the dark: very fast strikes and the shadow step",
		samurai = "the Samurai, one blade, one breath: slow heavy strikes, parries and counters",
		shadowfist = "the Shadowfist, the killing touch: pressure points, flurries and chi spent in one burst",
		ironsage = "the Iron Sage, the mountain that guards: chi wards on allies, stuns, the Mantra of Stone",
		lich = "the Lich, the slow death: curses, life drain and corpses that burst",
		bonelord = "the Bone Lord, master of the army: more skeletons, the Bone Golem, sacrifices",
		inquisitor = "the Inquisitor, the burning judgement: holy fire on every foe around you",
		sentinel = "the Sentinel, the shield of the faithful: a stronger aura, taunts and Lay on Hands"
	},

	-- modal window ids (answered in ascension_quest.lua); the confirm id is confirmBase + the ascended vocation id
	modal = {trial = 7101, choice = 7102, confirmBase = 7110},

	-- rewards
	title = {enabled = true, prefix = "Ascended ", color = "#c9a24a"},
	broadcast = "%s has passed the Trial of Ascension and walks the path of the %s.",

	-- !ascend: "oracle" (players are sent to the Oracle; staff keeps the old command; a migrated character's one free
	-- switch keeps working) or "open" (the old command for everyone, the quest is optional)
	command = "oracle",
	staffGroup = 4 -- group id from which on a character counts as staff (gamemasters, gods)
}
