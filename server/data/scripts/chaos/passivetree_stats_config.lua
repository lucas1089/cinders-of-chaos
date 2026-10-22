-- passivetree_stats_config.lua: what every stat of the passive tree does, and which stats matter to which class.
-- Read by passivetree_stats.lua (the `statInfo` message of the tree window, opcode 65), passive_builds_core.lua (labels
-- and the order of the Focus builds) and the tests (tests/passivetree_stats_test.lua, tests/passivetree_paths_test.lua).
--
-- 1. stats[key] = {name, desc}: the English texts, with the numbers the game computes with
--    (passivetree_effects.lua: charStatCap, maxSpeed, maxAbsorb, maxDamagePercent, the experience / item find rates;
--    tests/passivetree_stats_test.lua checks the numbers against that file). Every stat key a node gives needs an
--    entry here and a pt-BR one in i18n_strings.lua (the test fails for a new stat without both). The flag stats of the
--    keystones and notables (`ar...`, `ks...`, `ct...`) have their text in the node's own tooltip and are not listed.
-- 2. classes[classKey] = {primary, secondary, irrelevant}: the stats that matter to the class (derived from the class
--    kits in docs/CLASSES.md), the next ones, and the stats that are wasted on it (weapon skills the class never uses).
--    A list may name a group ("@elements"). The tree window marks nodes that give a primary stat (gold) or a secondary
--    one (silver) and the paths test uses the lists to judge the routes to the class keystones.
-- Lua 5.1 / LuaJIT and Lua 5.3.

ChaosPassiveStatsConfig = {
	groups = {
		elements = {"incrementFire", "incrementIce", "incrementEnergy", "incrementEarth", "incrementDeath", "incrementHoly",
			"incrementArcane", "incrementWater"},
		elementResists = {"absorbFire", "absorbIce", "absorbEnergy", "absorbEarth", "absorbDeath", "absorbHoly", "absorbArcane",
			"absorbWater", "absorbAllElements"},
		meleeSkills = {"swordSkill", "axeSkill", "clubSkill"},
		leech = {"lifeLeechChance", "lifeLeechAmount"},
		manaLeech = {"manaLeechChance", "manaLeechAmount"},
		crit = {"criticalHitChance", "criticalHitAmount"},
		shield = {"shieldingSkill", "skillShield"},
		crafting = {"craftingSkill", "armorsmithSkill", "weaponsmithSkill", "jewelsmithSkill", "miningSkill", "woodcuttingSkill",
			"herbalistSkill"}
	},

	-- the name of a group in the Primary / Secondary header of the tree window
	-- The class lanes (tools/gen_class_lanes.lua, tests/passivetree_paths_test.lua): on the shortest legal route from the
	-- start to every keystone and notable a class can reach, no node may have a stat of the class's irrelevant list and at
	-- least `minShare` of the nodes must be primary / secondary (keystones, class and archetype nodes and masteries count as
	-- relevant). The generator aims at `goalShare` so there is room when the tree changes. `supplyFactor`: a lane never gives a
	-- class more than this times the tree's own total of a scarce stat (skills, critical hit, leech: a class cannot collect
	-- more magic levels than the tree has); `supplyFactorCommon` the same for the other stats.
	paths = {minShare = 0.70, goalShare = 0.75, supplyFactor = 1.5, supplyFactorCommon = 8},

	groupNames = {elements = "Elemental damage", elementResists = "Resists", meleeSkills = "Melee skills", leech = "Life leech",
		manaLeech = "Mana leech", crit = "Critical hits", shield = "Shielding", crafting = "Crafting skills"},

	-- Stats that no class is judged on: utility and crafting. They are never tagged primary or secondary, and never
	-- counted against a route.
	neutral = {"@crafting", "experience", "loot", "rarityLoot", "wisdom", "speed"},

	stats = {
		strength = {"Strength", "Physical damage x (1 + value / 230). Value: 0.8 per point up to 60 points (+21%), then 0.2 per point up to 120 points (+26%)."},
		intelligence = {"Intelligence", "Damage of every type but physical, and healing, x (1 + value / 230). Value: 0.8 per point up to 60 points (+21%), then 0.2 per point up to 120 points (+26%)."},
		dexterity = {"Dexterity", "Weapon hits (melee, distance, wand) deal 1 / (1 - value%) times the damage, like attacking faster. Value: 0.8 per point up to 20 points (+19%), then 1 per 15 points up to 80 points (+25%)."},
		vitality = {"Vitality", "+0.8 percent maximum health per point up to 50 points (+40%), then +0.2 per point up to 100 points (+50%)."},
		spirit = {"Spirit", "+0.8 percent maximum mana per point up to 50 points (+40%), then +0.2 per point up to 100 points (+50%)."},
		wisdom = {"Wisdom", "No effect yet: the game gives wisdom no use."},
		speed = {"Speed", "Walking speed. The tooltip shows the speed you gain; at most +80."},
		experience = {"Experience", "Experience from monsters, in the percent shown."},
		loot = {"Item find", "Item find +0.2 per point (shown as the percent): scales the chance of better item rarities, +300 percent at most with everything else."},
		rarityLoot = {"Item rarity", "Item find +1 per point (shown as the percent): scales the chance of better item rarities, +300 percent at most with everything else."},
		swordSkill = {"Sword skill", "+1 sword skill level per point: sword hit damage and accuracy."},
		axeSkill = {"Axe skill", "+1 axe skill level per point: axe hit damage and accuracy."},
		clubSkill = {"Club skill", "+1 club skill level per point: club hit damage and accuracy."},
		distanceSkill = {"Distance skill", "+1 distance skill level per point: bow, crossbow and throwing damage and accuracy."},
		magicSkill = {"Magic level", "+1 magic level per point: stronger spells, healing and runes."},
		shieldingSkill = {"Shielding", "+1 shielding skill level per point: you block more of the hits you take with a shield."},
		skillShield = {"Shielding", "+1 shielding skill level per point: you block more of the hits you take with a shield."},
		criticalHitChance = {"Crit chance", "Percent chance that a hit is critical, rolled once against the sum of tree, gear and gems."},
		criticalHitAmount = {"Crit amount", "A critical hit deals this many percent more damage."},
		lifeLeechChance = {"Life leech chance", "Percent chance on each hit that it also heals you."},
		lifeLeechAmount = {"Life leech amount", "A leeching hit heals you for this percent of the damage it dealt."},
		manaLeechChance = {"Mana leech chance", "Percent chance on each hit that it also refills your mana."},
		manaLeechAmount = {"Mana leech amount", "A leeching hit gives you this percent of the damage it dealt as mana."},
		multiIncrement = {"All elements", "+percent damage to every element at once (fire, ice, energy, earth, death, holy, water, arcane; not physical)."},
		incrementPhysical = {"Physical damage", "+percent physical damage, up to +150 percent together with every other source of the type."},
		incrementFire = {"Fire damage", "+percent fire damage, up to +150 percent together with all elements."},
		incrementIce = {"Ice damage", "+percent ice damage, up to +150 percent together with all elements."},
		incrementEnergy = {"Energy damage", "+percent energy damage, up to +150 percent together with all elements."},
		incrementEarth = {"Earth damage", "+percent earth damage, up to +150 percent together with all elements."},
		incrementDeath = {"Death damage", "+percent death damage, up to +150 percent together with all elements."},
		incrementHoly = {"Holy damage", "+percent holy damage, up to +150 percent together with all elements."},
		incrementArcane = {"Arcane damage", "+percent arcane damage, up to +150 percent together with all elements."},
		incrementWater = {"Water damage", "+percent water damage, up to +150 percent together with all elements."},
		incrementHealth = {"Healing", "+percent healing done by your heal spells and potions (mana potions too)."},
		incrementLifeDrain = {"Life drain damage", "+percent life drain damage."},
		incrementManaDrain = {"Mana drain damage", "+percent mana drain damage."},
		absorbPhysical = {"Physical resist", "Takes this percent less physical damage, at most 75 percent (gear adds on top)."},
		absorbFire = {"Fire resist", "Takes this percent less fire damage, at most 75 percent (gear adds on top)."},
		absorbIce = {"Ice resist", "Takes this percent less ice damage, at most 75 percent (gear adds on top)."},
		absorbEnergy = {"Energy resist", "Takes this percent less energy damage, at most 75 percent (gear adds on top)."},
		absorbEarth = {"Earth resist", "Takes this percent less earth damage, at most 75 percent (gear adds on top)."},
		absorbDeath = {"Death resist", "Takes this percent less death damage, at most 75 percent (gear adds on top)."},
		absorbHoly = {"Holy resist", "Takes this percent less holy damage, at most 75 percent (gear adds on top)."},
		absorbArcane = {"Arcane resist", "Takes this percent less arcane damage, at most 75 percent (gear adds on top)."},
		absorbWater = {"Water resist", "Takes this percent less water damage, at most 75 percent (gear adds on top)."},
		absorbLife = {"Life drain resist", "Takes this percent less life drain damage, at most 75%."},
		absorbMana = {"Mana drain resist", "Takes this percent less mana drain damage, at most 75%."},
		absorbAllElements = {"All resists", "Adds this percent to the resist of every element (fire, ice, energy, earth, death, holy, water, arcane), at most 75 percent each."},
		craftingSkill = {"Crafting skill", "Raises your crafting skill; no combat effect."},
		armorsmithSkill = {"Armorsmith skill", "Raises your armorsmith skill; no combat effect."},
		weaponsmithSkill = {"Weaponsmith skill", "Raises your weaponsmith skill; no combat effect."},
		jewelsmithSkill = {"Jewelsmith skill", "Raises your jewelsmith skill; no combat effect."},
		miningSkill = {"Mining skill", "Raises your mining skill; no combat effect."},
		woodcuttingSkill = {"Woodcutting skill", "Raises your woodcutting skill; no combat effect."},
		herbalistSkill = {"Herbalist skill", "Raises your herbalist skill; no combat effect."}
	},

	-- primary: what the class lives on; secondary: what supports it; irrelevant: wasted on it (route nodes with these
	-- are a flaw). classKey -> lists. The kits: docs/CLASSES.md.
	classes = {
		-- Warrior line: melee, heavy armour, most health
		warrior = {
			primary = {"strength", "vitality", "incrementPhysical", "@meleeSkills", "absorbPhysical"},
			secondary = {"@leech", "@crit", "@shield", "absorbAllElements", "dexterity"},
			irrelevant = {"magicSkill", "distanceSkill", "incrementManaDrain", "@manaLeech"}
		},
		juggernaut = {
			primary = {"vitality", "absorbPhysical", "absorbAllElements", "@shield", "strength"},
			secondary = {"incrementPhysical", "@meleeSkills", "@leech", "@elementResists"},
			irrelevant = {"magicSkill", "distanceSkill", "incrementManaDrain", "@manaLeech"}
		},
		berserker = {
			primary = {"strength", "incrementPhysical", "@meleeSkills", "@crit"},
			secondary = {"vitality", "@leech", "dexterity", "absorbPhysical"},
			irrelevant = {"magicSkill", "distanceSkill", "incrementManaDrain", "@manaLeech"}
		},
		-- Ranger line: bows and crossbows
		ranger = {
			primary = {"dexterity", "distanceSkill", "incrementPhysical", "@crit"},
			secondary = {"speed", "vitality", "@leech", "strength"},
			irrelevant = {"@meleeSkills", "magicSkill", "@shield"}
		},
		deadeye = {
			primary = {"dexterity", "distanceSkill", "@crit", "incrementPhysical"},
			secondary = {"@leech", "strength", "vitality", "speed"},
			irrelevant = {"@meleeSkills", "magicSkill", "@shield"}
		},
		beastmaster = {
			primary = {"distanceSkill", "dexterity", "incrementPhysical", "vitality", "spirit"},
			secondary = {"@crit", "@leech", "absorbPhysical", "speed"},
			irrelevant = {"@meleeSkills", "magicSkill", "@shield"}
		},
		-- Mystic line: spells, wands and rods
		mystic = {
			primary = {"intelligence", "magicSkill", "spirit", "multiIncrement", "@elements"},
			secondary = {"@manaLeech", "vitality", "absorbMana", "@crit"},
			irrelevant = {"@meleeSkills", "distanceSkill", "@shield"}
		},
		elementalist = {
			primary = {"intelligence", "magicSkill", "multiIncrement", "@elements"},
			secondary = {"spirit", "@crit", "@manaLeech", "vitality"},
			irrelevant = {"@meleeSkills", "distanceSkill", "@shield"}
		},
		illusionist = {
			primary = {"intelligence", "magicSkill", "spirit", "incrementHealth", "multiIncrement"},
			secondary = {"@manaLeech", "vitality", "absorbMana", "@elements"},
			irrelevant = {"@meleeSkills", "distanceSkill", "@shield"}
		},
		-- Thief line: fast light weapons, shurikens, evasion
		thief = {
			primary = {"dexterity", "swordSkill", "distanceSkill", "@crit", "speed"},
			secondary = {"incrementPhysical", "incrementEarth", "@leech", "absorbPhysical", "absorbAllElements"},
			irrelevant = {"axeSkill", "clubSkill", "magicSkill", "@shield"}
		},
		ninja = {
			primary = {"dexterity", "swordSkill", "@crit", "speed", "incrementPhysical"},
			secondary = {"distanceSkill", "strength", "incrementEarth", "@leech", "absorbAllElements"},
			irrelevant = {"axeSkill", "clubSkill", "magicSkill", "@shield"}
		},
		samurai = {
			primary = {"swordSkill", "strength", "@shield", "vitality", "absorbPhysical"},
			secondary = {"dexterity", "@crit", "@leech", "incrementPhysical"},
			irrelevant = {"axeSkill", "clubSkill", "magicSkill", "distanceSkill"}
		},
		-- Necromancer line: summoner, curses
		necromancer = {
			primary = {"magicSkill", "intelligence", "spirit", "incrementDeath", "vitality"},
			secondary = {"@manaLeech", "@leech", "absorbDeath", "incrementPhysical", "multiIncrement"},
			irrelevant = {"@meleeSkills", "distanceSkill", "@shield"}
		},
		lich = {
			primary = {"magicSkill", "intelligence", "incrementDeath", "spirit", "incrementLifeDrain"},
			secondary = {"@manaLeech", "@crit", "multiIncrement", "absorbDeath"},
			irrelevant = {"@meleeSkills", "distanceSkill", "@shield"}
		},
		bonelord = {
			primary = {"spirit", "vitality", "incrementDeath", "incrementPhysical", "absorbPhysical"},
			secondary = {"magicSkill", "intelligence", "@leech", "absorbDeath"},
			irrelevant = {"@meleeSkills", "distanceSkill", "@shield"}
		},
		-- Monk line: unarmed, chi, evasion
		monk = {
			primary = {"strength", "dexterity", "incrementPhysical", "vitality", "@crit"},
			secondary = {"speed", "absorbPhysical", "@leech", "spirit"},
			irrelevant = {"@meleeSkills", "distanceSkill", "magicSkill", "@shield"}
		},
		shadowfist = {
			primary = {"strength", "dexterity", "@crit", "incrementPhysical", "speed"},
			secondary = {"vitality", "@leech", "absorbPhysical"},
			irrelevant = {"@meleeSkills", "distanceSkill", "magicSkill", "@shield"}
		},
		ironsage = {
			primary = {"vitality", "incrementHealth", "spirit", "strength", "absorbPhysical"},
			secondary = {"incrementPhysical", "@elementResists", "dexterity", "@leech"},
			irrelevant = {"@meleeSkills", "distanceSkill", "magicSkill", "@shield"}
		},
		-- Templar line: holy melee, shield, party aura. Mana leech is secondary: Radiant Smite, Consecration, Vow of Mending,
		-- Lay on Hands and Aegis of Faith all cost mana and the melee hits can leech it (owner: it was marked wasted by mistake).
		templar = {
			primary = {"strength", "swordSkill", "clubSkill", "@shield", "vitality", "incrementHoly", "absorbPhysical"},
			secondary = {"magicSkill", "intelligence", "spirit", "@leech", "@manaLeech", "incrementPhysical"},
			irrelevant = {"axeSkill", "distanceSkill"}
		},
		inquisitor = {
			primary = {"incrementHoly", "magicSkill", "intelligence", "strength", "multiIncrement"},
			secondary = {"swordSkill", "clubSkill", "spirit", "@crit", "vitality"},
			irrelevant = {"axeSkill", "distanceSkill"}
		},
		sentinel = {
			primary = {"vitality", "@shield", "absorbPhysical", "absorbAllElements", "incrementHealth"},
			secondary = {"strength", "swordSkill", "clubSkill", "magicSkill", "spirit", "@manaLeech", "@elementResists"},
			irrelevant = {"axeSkill", "distanceSkill"}
		}
	}
}

return ChaosPassiveStatsConfig
