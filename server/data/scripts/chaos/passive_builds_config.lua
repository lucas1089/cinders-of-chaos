-- passive_builds_config.lua: the Auto build button of the passive tree (passive_builds.lua, passive_builds_core.lua).
-- The node paths themselves are GENERATED from the real tree data by server/tools/gen_passive_builds.lua into
-- passive_builds_data.lua; this file holds what the generator reads (the recipes) and the texts the player sees.
--
-- Two groups per class, both offered in the client's Auto build list:
--   * Recommended (`roles`): 3 builds per class (all 21 classes). Each one names the keystones / notables of the class it
--     walks to first (`targets`, in order, cheapest legal path), then fills the rest of the budget with the theme `fill`.
--   * Focus (`themes`): one build per theme a class has enough relevant nodes for (`minNodes` nodes with a positive
--     score taken inside the budget). Greedy growth from the start: every step takes the path (through nodes the class
--     may hold) with the best score per point, so each prefix of a build is a legal build too.
--
-- Scoring (the generator): a node's score is sum(weight[stat] * gain / median), where gain is the node's value of the
-- stat capped by what is left under the stat's cap (`caps`, the same numbers as passivetree_effects.lua) and median
-- the median value of that stat over the tree. For a character stat gain is what the node adds on the value curve
-- (`statCurve`) from what the build already has. Nodes with a flag stat (keystones `ks...`, `ct...`, `ar...`, the variants
-- of 621 / 624) and mastery nodes carry a price or a choice: a theme build never takes them, a role build only the ones
-- it names. Plain stat nodes get a tiny base score so a build always spends all its points.
--
-- Texts are English keys; every one has a pt-BR entry in i18n_strings.lua (tests/passive_builds_test.lua checks).
-- Lua 5.1 / LuaJIT and Lua 5.3.

ChaosPassiveBuildsConfig = {
	-- the points the generator spends: what a character owns at level 1000 from levels alone ((1000 - 8) / 4), the
	-- end of the tree budget (Chaos.passive). Boss points and quest points come on top.
	maxPoints = 248,
	-- a theme is offered to a class when its build takes at least this many nodes that score for the theme (a theme
	-- can set its own `minNodes`)
	minNodes = 12,
	-- the base score of a plain stat node
	baseScore = 0.05,
	-- one request per this many ms (the server's other tree actions: 1000)
	rateMs = 1000,
	-- one preview per this many ms (its own limit: the client asks for one right after an Apply); a faster one is
	-- answered with autobuildError {retry = true, wait = this} and the client asks again (O560: was 500, with the generic
	-- 200 ms limit dropping a quick second pick without any answer)
	previewRateMs = 150,
	-- the caps of the stats the effects apply (passivetree_effects.lua charStatCap / maxSpeed / maxAbsorb / maxAttackSpeed, in node units)
	caps = {strength = 120, intelligence = 120, dexterity = 80, vitality = 100, spirit = 100, wisdom = 0,
		speed = 800, absorb = 75, attackSpeed = 15},
	-- the two-tier value curve of the character stats (passivetree_effects.lua charStatKnee / charStatMax /
	-- charStatKneeShare; the caps above): a node scores the value it adds where the build stands on the curve, so a point
	-- past the knee scores what it is worth there (strength 0.2 of a point before the knee's 0.8)
	statCurve = {knee = {strength = 60, intelligence = 60, dexterity = 20, vitality = 50, spirit = 50},
		max = {strength = 60, intelligence = 60, dexterity = 20, vitality = 50, spirit = 50}, kneeShare = 0.8},
	-- stats that never score (crafting, the stat the engine gives nothing for, and spellMod: a spell modifier mastery effect, O451,
	-- is no number to weigh; no build picks one, a role would have to name it in `masteries`)
	ignored = {"craftingSkill", "herbalistSkill", "woodcuttingSkill", "miningSkill", "armorsmithSkill", "jewelsmithSkill",
		"weaponsmithSkill", "wisdom", "spellMod"},

	-- stat groups used by the themes
	groups = {
		increments = {"incrementPhysical", "incrementFire", "incrementIce", "incrementEnergy", "incrementEarth",
			"incrementHoly", "incrementDeath", "incrementArcane", "incrementWater"},
		absorbs = {"absorbPhysical", "absorbFire", "absorbIce", "absorbEnergy", "absorbEarth", "absorbHoly", "absorbDeath",
			"absorbArcane", "absorbWater", "absorbLife", "absorbMana", "absorbAllElements"}
	},

	-- the weapon skill / attribute nodes that matter to a line (added to the damage, crit and hybrid themes;
	-- the defense theme adds the shielding skill for the lines that carry a shield)
	lineSkills = {
		warrior = {swordSkill = 0.5, axeSkill = 0.5, clubSkill = 0.5}, ranger = {distanceSkill = 1},
		mystic = {magicSkill = 1}, thief = {swordSkill = 0.7, distanceSkill = 0.5}, necromancer = {magicSkill = 1},
		monk = {}, templar = {swordSkill = 0.5, clubSkill = 0.5, magicSkill = 0.5}
	},
	lineAttributes = {
		warrior = {strength = 0.3}, ranger = {dexterity = 0.3}, mystic = {intelligence = 0.3}, thief = {dexterity = 0.3},
		necromancer = {intelligence = 0.3}, monk = {strength = 0.2, dexterity = 0.2}, templar = {strength = 0.2, intelligence = 0.2}
	},
	shieldLines = {warrior = true, templar = true, thief = true},

	-- Flagged keystones and notables score for the themes that name their damage type (a flag stat carries a price, so no
	-- plain weight can reach it): keystoneThemes[flag] = {theme keys}. A theme or role build of that theme takes the node
	-- when the class may hold it (its variant on 621 / 624), at keystoneScore. Poison is earth damage here.
	-- tests/passive_builds_test.lua: every tagged keystone a class can hold is in the builds of its theme.
	keystoneScore = 40,
	-- O442 (build variety): every keystone a class may hold is in the Focus build of one theme at least, so the Auto
	-- build list reaches all of them. Left out on purpose, in no theme: Open Hand Creed, Aether Edge and Hollow Vessel
	-- (the audit of 2026-11-09: a price for no gain or a pool that does not hold, tests/passive_builds_test.lua `deny`).
	-- The defense theme has no tag: the Recommended tank roles of the classes stay what they were. The keystones of the
	-- class sections (Living Shadow, Way of the Blade, Hoarded Souls, Bone Colossus, Hundred Hands, Flowing Mercy, Divine
	-- Verdict, Bastion) are not tagged: a theme build never walks through the class notables in front of them (a flagged
	-- node is a choice), and the Recommended builds of those classes hold them. The six keystones of the class sections of
	-- the Warrior, Ranger and Mystic lines (O449) are tagged, because no Recommended build of those classes holds them
	-- (the roles are another task's) and the coverage test wants every keystone in a build; their notables are plain stats.
	-- Each is tagged for a theme that no Recommended role of its class fills with (a role takes the keystones of its fill's
	-- theme), so no Recommended build gets a keystone through the tag: only the Focus builds of the theme do.
	keystoneThemes = {
		-- the damage types (2026-10-30)
		arContagion = {"earth"}, ksBlackbloodCreed = {"earth"}, ksViperVerdict = {"earth"},
		arPyreOath = {"fire"}, arCinderSigil = {"fire", "holy"}, arWinterLattice = {"ice"}, arStormstring = {"energy"},
		ksRadiantRebuke = {"holy"}, ksDawnchain = {"holy"}, ksCorpseBlast = {"death"}, ksReapersToll = {"death"},
		-- sustain, crits, vigils and mana, speed, summons, bleed
		arSanguine = {"leech"}, ksUndyingRage = {"leech"},
		arCascade = {"crit"},
		arVigils = {"mana"},
		arIronTithe = {"mobility"}, arHobble = {"mobility"},
		ksPackAlpha = {"summons"},
		arBarbed = {"physical"},
		-- the five themes of O442
		arSnarewright = {"snares"},
		arReliquary = {"party"}, ksSharedPhantasm = {"party"}, ksInspiringIllusion = {"party"}, ksOvergrowth = {"party"},
		arThornbound = {"retaliation"}, ksThorns = {"retaliation"}, ksPenitentWrath = {"retaliation"},
		ksBulwark = {"retaliation"}, ksImmovable = {"retaliation"}, arLastStand = {"retaliation"},
		ksScarredDiscipline = {"retaliation"},
		arEarthbreaker = {"pack"}, arRampage = {"pack"}, ksCleavingArc = {"pack"}, ksRicochet = {"pack"},
		ksArcaneEcho = {"pack"}, arEffigy = {"pack"}, ksPiercingPalm = {"pack"},
		arExecutioner = {"single"}, ksHuntersFocus = {"single"}, ksDeadeye = {"single"}, arLongshot = {"single"},
		arOpeningShot = {"single"}, ksShadowTwin = {"single"}, ksSeventhPalm = {"single"}, ksOverload = {"single"},
		-- the class sections of the Warrior, Ranger and Mystic lines (O449)
		ksUnbrokenLine = {"pack"}, ksOpenVeins = {"physical"}, ksLoneMark = {"physical"}, ksWolfbond = {"pack"},
		ksConvergence = {"pack"}, ksPhantomDouble = {"single"},
		-- the round 4 keystones (O450), each in themes that no Recommended role of a class that may hold it fills with (a role
		-- takes the keystones of its fill's theme, and no role may change): Momentum in single target and area clearing
		-- (not "mobility": the Shadowfist's Shadow Step fills with it), Attunement in four of the six element themes (not
		-- "death": the Necromancer's Death Mage fills with it; not "holy": Radiant Rebuke, Dawnchain and Sigil of Cinders
		-- already fill the three places of a Templar line holy build, and a fourth took Radiant Rebuke out of every build,
		-- which the coverage test refuses; "earth" and "energy" are the Thief line's and Ranger line's roles, which cannot hold
		-- it), Open Wounds in physical. The roles that would want them are listed in docs/BUILDS.md.
		arMomentum = {"single", "pack"}, arAttunement = {"fire", "ice", "energy", "earth"},
		arOpenWounds = {"physical"}
	},

	-- Focus themes. stats = {stat or group name = weight}; nodes = {[id] = score} for the nodes a theme names (they may
	-- be flagged nodes); classes = only these classes get the theme. text = the line under the name.
	themes = {
		{key = "damage", name = "Damage", text = "Raw damage: the damage nodes, your weapon or spell skill and the damage multipliers.",
			stats = {increments = 1, multiIncrement = 1.5}, skills = true, attributes = true},
		{key = "crit", name = "Critical strikes", text = "Critical hit chance and amount, with the skill and attributes that feed your hits.",
			stats = {criticalHitChance = 2, criticalHitAmount = 1.5, multiIncrement = 0.3}, skills = true, attributes = true},
		{key = "leech", name = "Life and mana leech", text = "Life and mana leech chance and amount, and healing spells, to sustain yourself from your own hits.",
			stats = {lifeLeechChance = 1.5, lifeLeechAmount = 1.5, manaLeechChance = 1, manaLeechAmount = 1,
				incrementLifeDrain = 0.4, incrementManaDrain = 0.4, incrementHealth = 0.5}},
		{key = "mana", name = "Mana", text = "A deeper mana pool and leech for it, mana drain damage and absorb, and magic level.",
			stats = {spirit = 1, manaLeechChance = 1.2, manaLeechAmount = 1.2, incrementManaDrain = 0.8, absorbMana = 1,
				magicSkill = 0.8, intelligence = 0.4}},
		{key = "defense", name = "Defense", text = "Health, resistances to every damage type and the shielding skill.",
			stats = {vitality = 1, absorbs = 1, skillShield = 1}, shield = true},
		{key = "mobility", name = "Speed", text = "Movement speed first; attack speed nodes and dexterity on the way.",
			stats = {speed = 3, attackSpeed = 2, dexterity = 0.5}, minNodes = 8},
		{key = "loot", name = "Loot", text = "Item find and item rarity: more drops, better drops.",
			stats = {loot = 1, rarityLoot = 1}, minNodes = 8},
		{key = "experience", name = "Experience", text = "Experience gained from monsters.",
			stats = {experience = 1}, minNodes = 8},
		{key = "physical", name = "Physical", text = "Physical damage, physical absorb and the melee or distance skills.",
			stats = {incrementPhysical = 1.5, absorbPhysical = 0.4, multiIncrement = 0.8}, skills = true},
		{key = "fire", name = "Fire", text = "Fire damage and fire resistance.",
			stats = {incrementFire = 1.5, absorbFire = 0.4, multiIncrement = 0.8}, skills = true},
		{key = "ice", name = "Ice", text = "Ice damage and ice resistance.",
			stats = {incrementIce = 1.5, absorbIce = 0.4, multiIncrement = 0.8}, skills = true},
		{key = "energy", name = "Energy", text = "Energy damage and energy resistance.",
			stats = {incrementEnergy = 1.5, absorbEnergy = 0.4, multiIncrement = 0.8}, skills = true},
		{key = "earth", name = "Earth", text = "Earth damage and earth resistance.",
			stats = {incrementEarth = 1.5, absorbEarth = 0.4, multiIncrement = 0.8}, skills = true},
		{key = "holy", name = "Holy", text = "Holy damage and holy resistance.",
			stats = {incrementHoly = 1.5, absorbHoly = 0.4, multiIncrement = 0.8}, skills = true},
		{key = "death", name = "Death", text = "Death damage and death resistance.",
			stats = {incrementDeath = 1.5, absorbDeath = 0.4, multiIncrement = 0.8}, skills = true},
		{key = "summons", name = "Summons", text = "The army and companion nodes of the class, with health and mana for the owner.",
			stats = {spirit = 0.6, vitality = 0.6, incrementDeath = 0.3},
			classes = {"necromancer", "lich", "bonelord", "beastmaster"},
			nodes = {[369] = 30, [642] = 12, [643] = 12, [644] = 30}, minNodes = 1,
			-- Pack Alpha (the Beastmaster's 624) and Hoarded Souls (641) are tagged in keystoneThemes. Node 624 itself was
			-- named here until O442, which gave the Necromancer line Reaper's Toll in this theme: a named node counts for
			-- every class that may hold it, and every class may hold 624.
			},
		{key = "hybrid", name = "Hybrid", text = "A balance of damage, health and resistances.",
			stats = {increments = 0.6, multiIncrement = 0.8, vitality = 0.6, absorbs = 0.5, criticalHitChance = 0.5,
				lifeLeechChance = 0.4, lifeLeechAmount = 0.4}, skills = true, attributes = true},
		-- O442: five themes that take the keystones the older themes could not name (keystoneThemes above). A theme build
		-- holds every keystone tagged for it that the class may hold, so a theme is kept to the few that belong together.
		{key = "snares", name = "Traps and mines", text = "Snare damage follows your weapon skill and damage nodes, with the keystone that arms more traps and mines.",
			stats = {increments = 0.6, multiIncrement = 1.2, criticalHitChance = 0.4}, skills = true, attributes = true,
			classes = {"ranger", "deadeye", "beastmaster", "thief", "ninja", "samurai"}},
		{key = "party", name = "Party support", text = "Mana, healing spells and magic level, with the keystones that buff and heal your party.",
			stats = {spirit = 0.8, incrementHealth = 1.2, magicSkill = 0.8, vitality = 0.5},
			classes = {"illusionist", "ironsage", "templar", "inquisitor", "sentinel"}},
		{key = "retaliation", name = "Retaliation", text = "Hold the line and hit back: health and resistances, with the keystones that reflect, counter and survive.",
			stats = {vitality = 1, absorbs = 0.8, skillShield = 0.8, incrementPhysical = 0.4}, shield = true},
		{key = "pack", name = "Area clearing", text = "Damage and attack speed, with the keystones that hit more than one enemy.",
			stats = {increments = 0.8, multiIncrement = 1.2, attackSpeed = 0.8}, skills = true, attributes = true,
			classes = {"warrior", "juggernaut", "berserker", "ranger", "beastmaster", "mystic", "elementalist", "illusionist",
				"necromancer", "lich", "bonelord", "monk", "shadowfist", "ironsage"}},
		{key = "single", name = "Single target", text = "Critical hits and damage multipliers, with the keystones that make one target die faster.",
			stats = {criticalHitChance = 1.2, criticalHitAmount = 1.2, multiIncrement = 1.2, increments = 0.8}, skills = true, attributes = true,
			classes = {"warrior", "juggernaut", "berserker", "ranger", "deadeye", "beastmaster", "mystic", "elementalist",
				"illusionist", "thief", "ninja", "samurai", "monk", "shadowfist", "inquisitor"}}
	},

	-- Text under a role build, by its kind (a role's own `text` replaces it in the list)
	kinds = {
		damage = "Damage first: the damage nodes of your class, then crit and skill.",
		tank = "Survivability first: health, resistances and the shielding skill.",
		sustain = "Staying power: leech and health on the way to the class keystones.",
		support = "Support: mana and the support keystones of the class.",
		summons = "Summons: the army or companion nodes, with health for the owner.",
		mobility = "Speed and evasion with enough damage to hunt.",
		crit = "Critical strikes: chance and amount on the class path.",
		elemental = "One element: its damage nodes and resistance.",
		area = "Area: keystones that hit the whole pack, with the damage nodes of your class.",
		single = "Single target: keystones that kill one enemy fast, with crit and skill.",
		dot = "Damage over time: poison, bleed and curses that keep working.",
		snares = "Traps and mines: set them, then set them off.",
		retaliation = "Retaliation: attackers pay for every hit."
	},

	-- Recommended builds (O442, build variety): three different ways to play per class, not three stat fills.
	-- roles[classKey] = list of {id, name, kind, text, targets = {node ids in order}, fill = theme key,
	-- masteries = {[node id] = choice} (a mastery node in targets without a choice takes the best effect of the fill)}.
	--   * `text` is the one line under the name in the Auto build list: what the build does and its price (the same
	--     English key is the pt-BR key in i18n_strings.lua). `kind` says what sort of build it is.
	--   * `targets` are the keystones the build walks to, nearest first; a fill whose theme has keystone tags
	--     (keystoneThemes) takes those too, so a role names 1 to 3 keystones in all (tests/passive_builds_test.lua: the
	--     three roles of a class never hold the same set).
	--   * The tank role of a class (fill defense) is the anchor of the survival model (a median over the role builds):
	--     it stays as it was. The ids of the other roles stay where the way to play stays.
	-- Not in any role: Open Hand Creed, Aether Edge, Hollow Vessel (a price for no gain, or a pool that does not hold: the
	-- audit of 2026-11-09), Sigil of Cinders for the Elementalist. Mines (Seeker Mine, Detonate Mines) are on the Thief line
	-- spell list only on this base (O455 returns them to the Ranger line), so no Ranger line role names Snarewright's Creed. Poison is a loss for the Samurai (measured), so the
	-- Samurai has none.
	-- The ids of the keystones: 621 / 624 (the variant of the class), 77 Thornbound, 78 Cascade Edge, 81 Sanguine, 82
	-- Stormstring, 99 Vigils, 102 Iron Tithe, 105 Snarewright, 106 Sigil of Cinders, 107 Contagion Rite, 108 Pyre Oath, 253
	-- Reliquary Vow, 262 Effigy, 369 / 376 / 383 / 390 the lines' second keystones, 409 Earthbreaker, 428 Executioner,
	-- 447 Hobbling, 466 Rampage, 523 Last Stand, 542 Barbed, 561 Longshot, 599 Opening Shot, 629-634 / 639-644 / 649-654 /
	-- 659-664 the class sections.
	roles = {
		warrior = {
			{id = "slayer", name = "Slayer", kind = "area", targets = {621, 409}, fill = "damage",
				text = "Two-hander cleaves and Earthbreaker slams for packs. Price: other melee hits are 10% weaker."},
			{id = "bulwark", name = "Bulwark", kind = "tank", targets = {624}, fill = "defense",
				text = "Shield, health and resistances: Bulwark blocks and reflects. Price: needs a shield, kills come slowly."},
			{id = "bloodied", name = "Bloodied", kind = "sustain", targets = {81, 466}, fill = "leech",
				text = "Sanguine leech and Rampage kill stacks. Price: you receive 30% less healing and take more damage per stack."}
		},
		juggernaut = {
			{id = "unbreakable", name = "Unbreakable", kind = "tank", targets = {621, 624}, fill = "defense",
				text = "Immovable and Bulwark: the toughest way to stand. Price: kills come slowly."},
			{id = "pyre_walker", name = "Pyre Walker", kind = "area", targets = {108, 624}, fill = "defense",
				text = "Pyre Oath burns the pack around you while you stand tough. Price: your other damage is 25% weaker and you burn too."},
			{id = "heavy_hitter", name = "Heavy Hitter", kind = "single", targets = {409, 428}, fill = "damage",
				text = "Earthbreaker slams and Executioner finishes. Price: most hits are 10% weaker and no tank keystone."}
		},
		berserker = {
			{id = "rage_engine", name = "Rage Engine", kind = "area", targets = {624, 621}, fill = "damage",
				text = "Cleaving Arc hits the pack, Undying Rage heals on every blow. Price: Cleaving Arc needs a two-hander."},
			{id = "bloodrunner", name = "Bloodrunner", kind = "sustain", targets = {81, 624}, fill = "leech",
				text = "Sanguine and Undying Rage: leech and heal on every hit. Price: healing from others is 30% lower."},
			{id = "crusher", name = "Crusher", kind = "crit", targets = {409}, fill = "crit",
				text = "Earthbreaker slams and Cascade Edge bursts on crits. Price: other hits 10% weaker, non-crits 5% weaker."}
		},
		ranger = {
			{id = "sharpshooter", name = "Sharpshooter", kind = "single", targets = {624, 561}, fill = "hybrid",
				text = "Deadeye crossbow shots and the Longshot range bonus for one target. Price: hits within 2 sqm are 15% weaker."},
			{id = "stormquiver", name = "Stormquiver", kind = "area", targets = {82, 621}, fill = "energy",
				text = "Stormstring arcs and Ricochet bounces clear packs from range. Price: the main bow hit is 10% weaker."},
			{id = "barbed_hunter", name = "Barbed Hunter", kind = "dot", targets = {542}, fill = "hybrid",
				text = "Barbed Quiver makes every shot bleed: strong in long fights. Price: the hit itself is 10% weaker."}
		},
		deadeye = {
			{id = "marked_target", name = "Marked Target", kind = "single", targets = {624, 621, 561}, fill = "hybrid",
				text = "Deadeye shots, Hunter's Focus stacks and Longshot: one target dies fast. Price: slow on packs."},
			{id = "stormquiver", name = "Stormquiver", kind = "area", targets = {82}, fill = "energy",
				text = "Stormstring arcs lightning through the pack. Price: the main bow hit is 10% weaker."},
			{id = "cascade_hunter", name = "Cascade Hunter", kind = "crit", targets = {78}, fill = "crit",
				text = "Cascade Edge bursts on the neighbours of every crit. Price: non-critical hits are 5% weaker."}
		},
		beastmaster = {
			{id = "pack_leader", name = "Pack Leader", kind = "summons", targets = {624, 82}, fill = "summons",
				text = "Pack Alpha wolves and Stormstring arcs. Price: the main bow hit is 10% weaker."},
			{id = "wild_volley", name = "Wild Volley", kind = "area", targets = {621, 561}, fill = "damage",
				text = "Ricochet and Longshot: the bow bounces through a pack. Price: the wolves are filler, close hits are 15% weaker."},
			{id = "hardy_warden", name = "Hardy Warden", kind = "tank", targets = {624}, fill = "defense",
				text = "Pack Alpha with health and resistances for safe solo hunts. Price: low damage."}
		},
		mystic = {
			{id = "arcanist", name = "Arcanist", kind = "area", targets = {621, 624}, fill = "damage",
				text = "Arcane Echo repeats area spells, Elemental Overload primes the next element. Price: Overload pays only if you change element."},
			{id = "mana_weaver", name = "Mana Weaver", kind = "support", targets = {99}, fill = "mana",
				text = "Covenant of Vigils: vigils for the party on a deep mana pool. Price: your own damage is 10% weaker."},
			{id = "warded_mage", name = "Warded Mage", kind = "tank", targets = {624}, fill = "defense",
				text = "Elemental Overload with health and resistances. Price: low damage."}
		},
		elementalist = {
			{id = "overloaded", name = "Overloaded", kind = "single", targets = {624}, fill = "damage",
				text = "Elemental Overload: a spell of a new element hits harder. Price: it pays only if you change element every cast."},
			{id = "effigy_caller", name = "Effigy Caller", kind = "area", targets = {262}, fill = "hybrid",
				text = "Cinder Effigies repeat your area spell every 2 seconds. Price: your spells are 25% weaker, one target gains nothing."},
			{id = "vigil_keeper", name = "Vigil Keeper", kind = "support", targets = {99}, fill = "mana",
				text = "Covenant of Vigils: vigils for the party on a deep mana pool. Price: your own damage is 10% weaker."}
		},
		illusionist = {
			{id = "support_weaver", name = "Support Weaver", kind = "support", targets = {621, 624}, fill = "party",
				text = "Shared Phantasm and Inspiring Illusion: your party hits harder and heals. Price: needs a party, little own damage."},
			{id = "vigil_keeper", name = "Vigil Keeper", kind = "support", targets = {99}, fill = "mana",
				text = "Covenant of Vigils: vigils for the party on a deep mana pool. Price: your own damage is 10% weaker."},
			{id = "illusory_striker", name = "Illusory Striker", kind = "area", targets = {262}, fill = "damage",
				text = "An area caster: Cinder Effigies repeat each cast. Price: your spells are 25% weaker, one target gains nothing."}
		},
		thief = {
			{id = "venomblade", name = "Venomblade", kind = "dot", targets = {383, 107, 624}, fill = "earth",
				text = "Poison on every attack that spreads when the pack dies. Price: evasion halved, weapon hits weaker."},
			{id = "cutthroat", name = "Cutthroat", kind = "crit", targets = {621}, fill = "crit",
				text = "Shadow Twin sometimes strikes twice, Cascade Edge bursts on crits. Price: you take 6% more damage, non-crits 5% weaker."},
			{id = "mine_layer", name = "Mine-layer", kind = "snares", targets = {105}, fill = "snares",
				text = "Traps and mines for the pack, set off by hand. Price: your other hits are 15% weaker and it needs set-up."}
		},
		ninja = {
			{id = "twin_fangs", name = "Twin Fangs", kind = "crit", targets = {631, 78}, fill = "crit",
				text = "Living Shadow opens a damage window after a dodge, Cascade Edge bursts on crits. Price: non-crits are 5% weaker."},
			{id = "phantom", name = "Phantom", kind = "single", targets = {630, 621}, fill = "hybrid",
				text = "Shadow Twin sometimes strikes twice, Fleet Shadow adds dodge. Price: you take 6% more damage."},
			{id = "plaguebearer", name = "Plaguebearer", kind = "dot", targets = {383, 107, 624}, fill = "earth",
				text = "Poison on every attack that spreads when the pack dies. Price: evasion halved, weapon hits weaker."}
		},
		samurai = {
			{id = "duelist", name = "Duelist", kind = "tank", targets = {633, 634}, fill = "defense",
				text = "Way of the Blade: Counter Stance parries every melee hit. Price: low damage."},
			{id = "iaido_striker", name = "Iaido Striker", kind = "crit", targets = {621}, fill = "crit",
				text = "Shadow Twin and Cascade Edge for crit duels. Price: you take 6% more damage, non-crits 5% weaker."},
			{id = "bloodblade", name = "Bloodblade", kind = "sustain", targets = {634, 81}, fill = "hybrid",
				text = "Way of the Blade parries, Sanguine leeches on every hit. Price: healing from others is 30% lower."}
		},
		necromancer = {
			{id = "grave_caller", name = "Grave Caller", kind = "summons", targets = {369}, fill = "summons",
				text = "Covenant of the Grave: minions hit harder and last longer. Price: your own spells are 25% weaker."},
			{id = "death_mage", name = "Death Mage", kind = "single", targets = {624, 621}, fill = "death",
				text = "Reaper's Toll doubles hits on weak monsters, Corpse Detonation blasts every kill. Price: your hits are weaker on healthy monsters."},
			{id = "grave_effigies", name = "Grave Effigies", kind = "area", targets = {262}, fill = "hybrid",
				text = "Cinder Effigies repeat your area spell every 2 seconds. Price: your spells are 25% weaker, one target gains nothing."}
		},
		lich = {
			{id = "rot_curser", name = "Rot Curser", kind = "dot", targets = {639, 640, 641}, fill = "damage",
				text = "Hoarded Souls with the rot and curse nodes: damage over time. Price: a slow start."},
			{id = "soul_reaper", name = "Soul Reaper", kind = "single", targets = {624, 621}, fill = "hybrid",
				text = "Reaper's Toll doubles hits on weak monsters, Corpse Detonation blasts every kill. Price: your hits are weaker on healthy monsters."},
			{id = "lifedrinker", name = "Lifedrinker", kind = "sustain", targets = {640}, fill = "leech",
				text = "Sanguine leech with Life Siphon. Price: healing from others is 30% lower."}
		},
		bonelord = {
			{id = "bone_army", name = "Bone Army", kind = "summons", targets = {642, 643, 644, 369}, fill = "summons",
				text = "Bone Colossus and Covenant of the Grave: a big army. Price: your own spells are 25% weaker."},
			{id = "bone_warden", name = "Bone Warden", kind = "tank", targets = {643, 644}, fill = "defense",
				text = "Bone Colossus with health and resistances. Price: low damage."},
			{id = "ossuary_fury", name = "Ossuary Fury", kind = "area", targets = {624, 621}, fill = "damage",
				text = "Reaper's Toll doubles hits on weak monsters, Corpse Detonation blasts every kill of your minions. Price: your hits are weaker on healthy monsters."}
		},
		monk = {
			{id = "iron_body", name = "Iron Body", kind = "tank", targets = {390}, fill = "defense",
				text = "Scarred Discipline: every hit you take builds chi and cuts damage. Price: no evasion."},
			{id = "fist_flurry", name = "Fist Flurry", kind = "single", targets = {621}, fill = "damage",
				text = "Seventh Palm: every 5th hit lands double and shocks its neighbours. Price: the other hits are 10% weaker."},
			{id = "palm_piercer", name = "Palm Piercer", kind = "area", targets = {624, 390}, fill = "hybrid",
				text = "Piercing Palm hits pass through to the next two enemies, Scarred Discipline cuts damage taken. Price: no evasion, each hit is 5% weaker."}
		},
		shadowfist = {
			{id = "hundred_fists", name = "Hundred Fists", kind = "crit", targets = {649, 650, 651}, fill = "crit",
				text = "Hundred Hands feeds chi from crits, Cascade Edge bursts on them. Price: non-crits are 5% weaker."},
			{id = "pressure_points", name = "Pressure Points", kind = "single", targets = {650, 621}, fill = "damage",
				text = "Seventh Palm: every 5th hit lands double. Price: the other hits are 10% weaker."},
			{id = "shadow_step", name = "Shadow Step", kind = "mobility", targets = {648, 651}, fill = "mobility",
				text = "Hundred Hands and Iron Tithe: vigils paid in health give speed. Price: part of your health is reserved."}
		},
		ironsage = {
			{id = "chi_healer", name = "Chi Healer", kind = "support", targets = {653, 654}, fill = "party",
				text = "Flowing Mercy and Overgrowth: your heals reach a second ally and keep healing. Price: little damage."},
			{id = "stone_sage", name = "Stone Sage", kind = "tank", targets = {653, 390}, fill = "defense",
				text = "Scarred Discipline: every hit you take builds chi and cuts damage. Price: no evasion."},
			{id = "healing_fist", name = "Healing Fist", kind = "sustain", targets = {654}, fill = "leech",
				text = "Flowing Mercy with Sanguine leech: a healer that fights. Price: healing you receive is 30% lower."}
		},
		templar = {
			{id = "zealot", name = "Zealot", kind = "damage", targets = {624, 376}, fill = "damage",
				text = "Dawnchain chains holy light, Penitent's Wrath answers every hit. Price: your spells are 10% weaker, your aura is halved."},
			{id = "shield_wall", name = "Shield Wall", kind = "tank", targets = {658}, fill = "defense",
				text = "Shield, resistances and the Templar aura. Price: little damage."},
			{id = "pyre_walker", name = "Pyre Walker", kind = "area", targets = {108}, fill = "defense",
				text = "Pyre Oath burns the pack around you. Price: your other damage is 25% weaker and you burn too."}
		},
		inquisitor = {
			{id = "judge", name = "Judge", kind = "area", targets = {661, 624}, fill = "hybrid",
				text = "Divine Verdict lets Radiant Strikes judge, Dawnchain chains holy light. Price: your spells are 10% weaker."},
			{id = "ember_brand", name = "Ember Brand", kind = "single", targets = {106}, fill = "hybrid",
				text = "Sigil of Cinders brands one target and burns its neighbours. Price: damage that is not fire or holy is 20% weaker."},
			{id = "rebuker", name = "Rebuker", kind = "tank", targets = {621}, fill = "defense",
				text = "Radiant Rebuke: a shield blocks one hit in five and answers with a holy nova. Price: weapon hits are 10% weaker."}
		},
		sentinel = {
			{id = "bastion", name = "Bastion", kind = "tank", targets = {662, 663, 664}, fill = "defense",
				text = "Bastion widens your aura and covers the party. Price: little damage."},
			{id = "reliquary_keeper", name = "Reliquary Keeper", kind = "support", targets = {253}, fill = "party",
				text = "A Reliquary Warden follows you: it heals and buffs the party and burns enemies. Price: your own damage is 10% weaker."},
			{id = "retributor", name = "Retributor", kind = "retaliation", targets = {624, 77}, fill = "retaliation",
				text = "Thorns, Thornbound Oath and Penitent's Wrath: attackers pay for every hit. Price: your damage is 10% weaker, your aura is halved."}
		}
	},

	-- the one-line summary of a build: its top three stats, "<label> +<value>" ({scale} = node value to shown value)
	statLabels = {
		strength = {"Strength", 1}, dexterity = {"Dexterity", 1}, intelligence = {"Intelligence", 1}, vitality = {"Vitality", 1},
		spirit = {"Spirit", 1}, speed = {"Speed", 0.1}, attackSpeed = {"Attack speed %", 1}, experience = {"Experience %", 0.1}, loot = {"Item find %", 0.2},
		rarityLoot = {"Item rarity %", 1}, criticalHitChance = {"Crit chance", 1}, criticalHitAmount = {"Crit amount", 1},
		lifeLeechChance = {"Life leech chance", 1}, lifeLeechAmount = {"Life leech amount", 1},
		manaLeechChance = {"Mana leech chance", 1}, manaLeechAmount = {"Mana leech amount", 1},
		multiIncrement = {"All damage", 1}, incrementHealth = {"Healing spells", 1}, skillShield = {"Shielding", 1},
		shieldingSkill = {"Shielding", 1}, swordSkill = {"Sword skill", 1}, axeSkill = {"Axe skill", 1},
		clubSkill = {"Club skill", 1}, distanceSkill = {"Distance skill", 1}, magicSkill = {"Magic level", 1},
		incrementPhysical = {"Physical damage", 1}, incrementFire = {"Fire damage", 1}, incrementIce = {"Ice damage", 1},
		incrementEnergy = {"Energy damage", 1}, incrementEarth = {"Earth damage", 1}, incrementHoly = {"Holy damage", 1},
		incrementDeath = {"Death damage", 1}, incrementArcane = {"Arcane damage", 1},
		incrementWater = {"Water damage", 1}, incrementLifeDrain = {"Life drain damage", 1},
		incrementManaDrain = {"Mana drain damage", 1}, absorbPhysical = {"Physical resist", 1},
		absorbFire = {"Fire resist", 1}, absorbIce = {"Ice resist", 1}, absorbEnergy = {"Energy resist", 1},
		absorbEarth = {"Earth resist", 1}, absorbHoly = {"Holy resist", 1}, absorbDeath = {"Death resist", 1},
		absorbArcane = {"Arcane resist", 1}, absorbWater = {"Water resist", 1},
		absorbLife = {"Life drain resist", 1}, absorbMana = {"Mana drain resist", 1}, absorbAllElements = {"All resists", 1}
	}
}

return ChaosPassiveBuildsConfig
