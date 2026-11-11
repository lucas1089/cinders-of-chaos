-- round4_keystones_config.lua: the numbers of the round 4 keystones of the passive tree (O450, nodes 706, 707, 708;
-- docs/BUILDS.md "Round 4 keystones (O450)", server/README.md "Passive tree: round 4 keystones"). Pure data; rules in
-- round4_keystones_core.lua, engine glue in archetypes.lua (they are archetype keystones: ar* flags, the flag storage, the
-- same hit event). archetypes_config.lua appends `nodes`, `classes` and the three number tables below at its end, so
-- ChaosArchetypesConfig.arMomentum and the rest read from there too. The client tooltips (treedata/nodes.lua) repeat these
-- numbers and server/tests/round4_keystones_test.lua checks that they match.
--
-- Each keystone is a thin reuse of a hook that exists, has a visible price, and is sized at or below the median of the
-- keystones of rounds 1 to 3 that give the same kind of gain (a flat damage factor: Lone Mark +12%, Convergence +12%,
-- Snarewright's Creed +25% on snares). Computed, not measured in game (server/data/spells/README.md "Round 4 keystones").
--
-- The +40% rule of the owner: a specialised build is at most +40% over its class default in its specialty. The test
-- builds the worst legal stack of every keystone (it and two more of the size of the median) and asserts it.

ChaosRound4Config = {
	-- node id of each keystone (new nodes, each in a group of its own, a side branch of an existing node: 706 of the
	-- Speed node 120, 707 of Frostbitten Will 219, 708 of Iron Communion 161) and its flag. Appended to the archetypes'
	-- list, so the bit of each flag in the flag storage is the next one after the 24 of the rounds 1 to 3.
	nodes = {
		{id = 706, flag = "arMomentum"},
		{id = 707, flag = "arAttunement"},
		{id = 708, flag = "arOpenWounds"},
	},

	-- the classes that may take each keystone (the client nodes carry the same list; the test checks it)
	classes = {
		-- the three lines whose class lanes carry speed: Ranger, Thief and Monk (docs/CLASSES.md)
		arMomentum = {"ranger", "deadeye", "beastmaster", "thief", "ninja", "samurai", "monk", "shadowfist", "ironsage"},
		-- the lines that cast more than one element
		arAttunement = {"mystic", "elementalist", "illusionist", "necromancer", "lich", "bonelord", "templar", "inquisitor",
			"sentinel"},
		-- the Monk and Templar lines: fists and one-handed weapons (Open Veins is the Berserker's, two-handed)
		arOpenWounds = {"monk", "shadowfist", "ironsage", "templar", "inquisitor", "sentinel"},
	},

	-- Momentum (Ranger, Thief and Monk lines): your direct hits (weapon and spell, not damage over time) deal +bonusPer%
	-- for every `per`% of movement speed you have above your base speed, at most +cap%. The gain is the statscale family of
	-- the unique items (unique_passives_core.lua), fed with the speed above the base in percent of the base: whole steps,
	-- like the uniques. The speed in use is the clamped walk speed (Creature:getStepSpeed), the base is Player:getBaseSpeed
	-- (data/lib/chaos_speed.lua). A speed-scaling unique (statscale on speed) and Momentum do not add: the larger counts
	-- (the keystone's factor is divided by the unique's, never below 1). Against players the gain is a third (the uniques'
	-- pvpScale). Price: the damage you take x taken.
	arMomentum = {per = 5, bonusPer = 1, cap = 10, taken = 1.08, pvpScale = 1 / 3},

	-- Attunement (Mystic, Necromancer and Templar lines): your elemental damage (fire, ice, energy, earth, death, holy;
	-- not physical, not drain) of the element your tree favours most (the largest incrementX of the tree, the first of that
	-- list on a tie) x locked; the other elements x others. A tree with no element increment locks nothing: no gain, no
	-- price. The rule of Winter's Lattice (its price on fire and energy) with a gain for the one element.
	arAttunement = {locked = 1.11, others = 0.85},

	-- Open Wounds (Monk and Templar lines): a melee hit with a one-handed weapon or bare fists makes the target bleed for
	-- share x the hit over ticks ticks of tickMs (the Barbed Quiver bleed: a stronger bleed replaces a weaker). Price: those
	-- hits x price.
	arOpenWounds = {share = 0.40, ticks = 4, tickMs = 1000, price = 0.92},

	-- what the test reads for the +40% rule (the owner: a specialised build at most +40% over its class default)
	rule = {
		ownerCap = 0.40,
		-- the size of the other two keystones of the worst stack: the median of the flat damage gains of rounds 1 to 3
		-- and the class sections (Lone Mark and Convergence +12%, Snarewright's Creed +25% on its own hits)
		partnerGain = 0.12,
		-- the breakpoints of the models (class_dps_model.py, survival_model.py, pvp_model.py)
		levels = {100, 500, 1000},
		-- the time between two hits of a weapon (the engine's default attack interval): a bleed that is replaced by the next
		-- hit pays out only the part before it, so Open Wounds' sustained gain depends on it
		attackIntervalMs = 2000,
		-- the base speed of a vocation (vocations.xml; the Ninja has 232), the walk speed of the engine
		vocationBase = 220,
		-- the legal speed above the base, in percent of the base speed, from every source a player can have in a fight;
		-- the test checks each number against the file that holds it. Out of combat only: charms (oocspeed, cap 8).
		-- Mounts add a flat speed in the stock mounts.xml, which this repository does not hold: the cap of the gain and the
		-- engine's maxPlayerSpeed hold whatever a mount adds (the test checks that too).
		speed = {
			items = 35, -- the movespeed modifier of the boots (T8 top, chaos_item_mods.lua; the module has no cap since O461, it was 12)
			paragon = 10, -- Paragon Movement Speed, 20 points x 0.5% (chaos_constants.lua)
			vigil = 15, -- Vigil of Haste (vigils_config.lua)
			banner = 10, -- Banner Call, 12 s (rallying_cry.lua)
			ember = 25, -- Ember of Haste, the blessing (blessings_config.lua)
			treeFlat = 80, -- the tree's speed nodes, in speed points: passivetree_effects.lua maxSpeed
		},
	},
}

return ChaosRound4Config
