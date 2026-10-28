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
	-- answered with autobuildError {retry = true} and the client asks again
	previewRateMs = 500,
	-- the caps of the stats the effects apply (passivetree_effects.lua charStatCap / maxSpeed / maxAbsorb, in node units)
	caps = {strength = 120, intelligence = 120, dexterity = 80, vitality = 100, spirit = 100, wisdom = 0,
		speed = 800, absorb = 75},
	-- the two-tier value curve of the character stats (passivetree_effects.lua charStatKnee / charStatMax /
	-- charStatKneeShare; the caps above): a node scores the value it adds where the build stands on the curve, so a point
	-- past the knee scores what it is worth there (strength 0.2 of a point before the knee's 0.8)
	statCurve = {knee = {strength = 60, intelligence = 60, dexterity = 20, vitality = 50, spirit = 50},
		max = {strength = 60, intelligence = 60, dexterity = 20, vitality = 50, spirit = 50}, kneeShare = 0.8},
	-- stats that never score (crafting, and the stat the engine gives nothing for)
	ignored = {"craftingSkill", "herbalistSkill", "woodcuttingSkill", "miningSkill", "armorsmithSkill", "jewelsmithSkill",
		"weaponsmithSkill", "wisdom"},

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
			nodes = {[369] = 30, [642] = 12, [643] = 12, [644] = 30, [624] = 20}, minNodes = 1,
			-- 624 is Pack Alpha for the Beastmaster only; the generator ignores a named node the class may not hold
			},
		{key = "hybrid", name = "Hybrid", text = "A balance of damage, health and resistances.",
			stats = {increments = 0.6, multiIncrement = 0.8, vitality = 0.6, absorbs = 0.5, criticalHitChance = 0.5,
				lifeLeechChance = 0.4, lifeLeechAmount = 0.4}, skills = true, attributes = true}
	},

	-- Text under a role build, by its kind
	kinds = {
		damage = "Damage first: the damage nodes of your class, then crit and skill.",
		tank = "Survivability first: health, resistances and the shielding skill.",
		sustain = "Staying power: leech and health on the way to the class keystones.",
		support = "Support: mana and the support keystones of the class.",
		summons = "Summons: the army or companion nodes, with health for the owner.",
		mobility = "Speed and evasion with enough damage to hunt.",
		crit = "Critical strikes: chance and amount on the class path.",
		elemental = "One element: its damage nodes and resistance."
	},

	-- Recommended builds. roles[classKey] = list of {id, name, kind, targets = {node ids in order}, fill = theme key,
	-- masteries = {[node id] = choice} (a mastery node in targets without a choice takes the best effect of the fill)}.
	-- The ids of the class keystones: 621 / 624 (the variant of the class), 330 Purity of Robustness, 383 / 369 / 390 / 376
	-- the lines' second keystones, 107 Contagion Rite, 629-634 / 639-644 / 649-654 / 659-664 the class sections.
	roles = {
		warrior = {
			{id = "slayer", name = "Slayer", kind = "damage", targets = {621}, fill = "damage"},
			{id = "bulwark", name = "Bulwark", kind = "tank", targets = {624}, fill = "defense"},
			{id = "bloodied", name = "Bloodied", kind = "sustain", targets = {330}, fill = "leech"}
		},
		juggernaut = {
			{id = "unbreakable", name = "Unbreakable", kind = "tank", targets = {621, 624}, fill = "defense"},
			{id = "retaliator", name = "Retaliator", kind = "sustain", targets = {624, 330}, fill = "leech"},
			{id = "heavy_hitter", name = "Heavy Hitter", kind = "damage", targets = {624}, fill = "damage"}
		},
		berserker = {
			{id = "rage_engine", name = "Rage Engine", kind = "damage", targets = {621, 624}, fill = "damage"},
			{id = "bloodrunner", name = "Bloodrunner", kind = "sustain", targets = {624, 330}, fill = "leech"},
			{id = "crusher", name = "Crusher", kind = "crit", targets = {621}, fill = "crit"}
		},
		ranger = {
			{id = "sharpshooter", name = "Sharpshooter", kind = "damage", targets = {624}, fill = "damage"},
			{id = "skirmisher", name = "Skirmisher", kind = "mobility", targets = {621}, fill = "mobility"},
			{id = "steady_aim", name = "Steady Aim", kind = "crit", targets = {621, 624}, fill = "crit"}
		},
		deadeye = {
			{id = "marked_target", name = "Marked Target", kind = "crit", targets = {621, 624}, fill = "crit"},
			{id = "hunters_focus", name = "Hunter's Focus", kind = "damage", targets = {621}, fill = "damage"},
			{id = "evasive_hunter", name = "Evasive Hunter", kind = "mobility", targets = {624}, fill = "mobility"}
		},
		beastmaster = {
			{id = "pack_leader", name = "Pack Leader", kind = "summons", targets = {624}, fill = "summons"},
			{id = "wild_volley", name = "Wild Volley", kind = "damage", targets = {621}, fill = "damage"},
			{id = "hardy_warden", name = "Hardy Warden", kind = "tank", targets = {624}, fill = "defense"}
		},
		mystic = {
			{id = "arcanist", name = "Arcanist", kind = "damage", targets = {621, 624}, fill = "damage"},
			{id = "mana_weaver", name = "Mana Weaver", kind = "support", targets = {621}, fill = "mana"},
			{id = "warded_mage", name = "Warded Mage", kind = "tank", targets = {624}, fill = "defense"}
		},
		elementalist = {
			{id = "overloaded", name = "Overloaded", kind = "damage", targets = {621, 624}, fill = "damage"},
			{id = "pyromancer", name = "Pyromancer", kind = "elemental", targets = {624}, fill = "fire"},
			{id = "channeler", name = "Channeler", kind = "support", targets = {621}, fill = "mana"}
		},
		illusionist = {
			{id = "support_weaver", name = "Support Weaver", kind = "support", targets = {621, 624}, fill = "mana"},
			{id = "lifeline", name = "Lifeline", kind = "sustain", targets = {621}, fill = "leech"},
			{id = "illusory_striker", name = "Illusory Striker", kind = "damage", targets = {624}, fill = "damage"}
		},
		thief = {
			{id = "venomblade", name = "Venomblade", kind = "damage", targets = {383}, fill = "damage"},
			{id = "shadow_dancer", name = "Shadow Dancer", kind = "mobility", targets = {626}, fill = "mobility"},
			{id = "cutthroat", name = "Cutthroat", kind = "crit", targets = {628}, fill = "crit"}
		},
		ninja = {
			{id = "twin_fangs", name = "Twin Fangs", kind = "damage", targets = {629, 631}, fill = "crit"},
			{id = "phantom", name = "Phantom", kind = "mobility", targets = {630, 631}, fill = "mobility"},
			{id = "plaguebearer", name = "Plaguebearer", kind = "damage", targets = {383, 107}, fill = "damage"}
		},
		samurai = {
			{id = "duelist", name = "Duelist", kind = "tank", targets = {633, 634}, fill = "defense"},
			{id = "iaido_striker", name = "Iaido Striker", kind = "crit", targets = {634, 383}, fill = "crit"},
			{id = "bloodblade", name = "Bloodblade", kind = "sustain", targets = {634, 330}, fill = "leech"}
		},
		necromancer = {
			{id = "grave_caller", name = "Grave Caller", kind = "summons", targets = {369}, fill = "summons"},
			{id = "soul_siphon", name = "Soul Siphon", kind = "sustain", targets = {638}, fill = "leech"},
			{id = "death_mage", name = "Death Mage", kind = "elemental", targets = {637}, fill = "death"}
		},
		lich = {
			{id = "rot_curser", name = "Rot Curser", kind = "damage", targets = {639, 640, 641}, fill = "death"},
			{id = "soul_hoarder", name = "Soul Hoarder", kind = "support", targets = {641}, fill = "mana"},
			{id = "lifedrinker", name = "Lifedrinker", kind = "sustain", targets = {640}, fill = "leech"}
		},
		bonelord = {
			{id = "bone_army", name = "Bone Army", kind = "summons", targets = {642, 643, 644, 369}, fill = "summons"},
			{id = "bone_warden", name = "Bone Warden", kind = "tank", targets = {643, 644}, fill = "defense"},
			{id = "ossuary_fury", name = "Ossuary Fury", kind = "damage", targets = {642}, fill = "damage"}
		},
		monk = {
			{id = "iron_body", name = "Iron Body", kind = "tank", targets = {390}, fill = "defense"},
			{id = "fist_flurry", name = "Fist Flurry", kind = "damage", targets = {648}, fill = "damage"},
			{id = "chi_surge", name = "Chi Surge", kind = "crit", targets = {390, 648}, fill = "crit"}
		},
		shadowfist = {
			{id = "hundred_fists", name = "Hundred Fists", kind = "crit", targets = {649, 650, 651}, fill = "crit"},
			{id = "pressure_points", name = "Pressure Points", kind = "damage", targets = {650, 390}, fill = "damage"},
			{id = "shadow_step", name = "Shadow Step", kind = "mobility", targets = {648, 651}, fill = "mobility"}
		},
		ironsage = {
			{id = "chi_healer", name = "Chi Healer", kind = "support", targets = {653, 654}, fill = "mana"},
			{id = "stone_sage", name = "Stone Sage", kind = "tank", targets = {653, 390}, fill = "defense"},
			{id = "healing_fist", name = "Healing Fist", kind = "sustain", targets = {654}, fill = "leech"}
		},
		templar = {
			{id = "zealot", name = "Zealot", kind = "damage", targets = {376}, fill = "holy"},
			{id = "shield_wall", name = "Shield Wall", kind = "tank", targets = {658}, fill = "defense"},
			{id = "penitent", name = "Penitent", kind = "sustain", targets = {376}, fill = "leech"}
		},
		inquisitor = {
			{id = "judge", name = "Judge", kind = "damage", targets = {659, 660, 661}, fill = "holy"},
			{id = "burning_zeal", name = "Burning Zeal", kind = "crit", targets = {660, 376}, fill = "crit"},
			{id = "purifier", name = "Purifier", kind = "sustain", targets = {661}, fill = "leech"}
		},
		sentinel = {
			{id = "bastion", name = "Bastion", kind = "tank", targets = {662, 663, 664}, fill = "defense"},
			{id = "beacon", name = "Beacon", kind = "support", targets = {664}, fill = "mana"},
			{id = "retributor", name = "Retributor", kind = "damage", targets = {624, 376}, fill = "hybrid"}
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
