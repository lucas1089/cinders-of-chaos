local mType = Game.createMonsterType("Overcharged Energy Elemental")
local monster = {}

monster.description = "an overcharged energy elemental"
monster.experience = 1300
monster.outfit = {
	lookType = 290,
	lookHead = 0,
	lookBody = 0,
	lookLegs = 0,
	lookFeet = 0,
	lookAddons = 0,
	lookMount = 0
}

monster.health = 1200
monster.maxHealth = 1200
monster.race = "undead"
monster.corpse = 8966
monster.speed = 300
monster.manaCost = 0
monster.maxSummons = 0

monster.changeTarget = {
	interval = 20000,
	chance = 15
}

monster.strategiesTarget = {
	nearest = 70,
	health = 10,
	damage = 10,
	random = 10,
}

monster.flags = {
	summonable = false,
	attackable = true,
	hostile = true,
	convinceable = false,
	pushable = false,
	rewardBoss = false,
	illusionable = false,
	canPushItems = true,
	canPushCreatures = false,
	staticAttackChance = 85,
	targetDistance = 1,
	runHealth = 0,
	healthHidden = false,
	isBlockable = false,
	canWalkOnEnergy = false,
	canWalkOnFire = false,
	canWalkOnPoison = false,
	pet = false
}

monster.light = {
	level = 0,
	color = 0
}

monster.voices = {
	interval = 5000,
	chance = 10,
	{text = "BZZZZZZZZZZ", yell = false}
}

monster.loot = {
	-- by id only: the base Loot():setId() takes no name, an entry without an id is dropped (check_content.py)
	{id = 2148, chance = 50000, maxCount = 100},	-- gold coin
	{id = 2148, chance = 50000, maxCount = 56},	-- gold coin
	{id = 2152, chance = 15000, maxCount = 2},	-- platinum coin
	{id = 2150, chance = 10000, maxCount = 2},	-- small amethyst
	{id = 7591, chance = 10000},	-- great health potion
	{id = 7590, chance = 5000},	-- great mana potion
	{id = 7439, chance = 2173},	-- berserk potion
	{id = 8920, chance = 730},	-- wand of starstorm
	{id = 7889, chance = 730},	-- lightning pendant
	{id = 7869, chance = 500},	-- energy spike sword
	{id = 10221, chance = 500},	-- shockwave amulet
	{id = 7895, chance = 150}	-- lightning legs
}

monster.attacks = {
	{name ="melee", interval = 2000, chance = 100, minDamage = 0, maxDamage = -200},
	{name ="combat", interval = 1000, chance = 11, type = COMBAT_ENERGYDAMAGE, minDamage = 0, maxDamage = -250, radius = 4, shootEffect = CONST_ANI_ENERGY, effect = CONST_ME_PURPLEENERGY, target = false},
	{name ="combat", interval = 1000, chance = 12, type = COMBAT_ENERGYDAMAGE, minDamage = 0, maxDamage = -300, range = 3, effect = CONST_ME_PURPLEENERGY, target = true},
	{name ="combat", interval = 1000, chance = 12, type = COMBAT_PHYSICALDAMAGE, minDamage = 0, maxDamage = -200, radius = 4, effect = CONST_ME_POFF, target = false}
}

monster.defenses = {
	defense = 35,
	armor = 35,
	{name ="combat", interval = 2000, chance = 15, type = COMBAT_HEALING, minDamage = 90, maxDamage = 150, effect = CONST_ME_MAGIC_BLUE, target = false}
}

monster.elements = {
	{type = COMBAT_PHYSICALDAMAGE, percent = 0},
	{type = COMBAT_ENERGYDAMAGE, percent = 100},
	{type = COMBAT_EARTHDAMAGE, percent = -20},
	{type = COMBAT_FIREDAMAGE, percent = 30},
	{type = COMBAT_LIFEDRAIN, percent = 0},
	{type = COMBAT_MANADRAIN, percent = 0},
	{type = COMBAT_DROWNDAMAGE, percent = 0},
	{type = COMBAT_ICEDAMAGE, percent = 100},
	{type = COMBAT_HOLYDAMAGE , percent = 0},
	{type = COMBAT_DEATHDAMAGE , percent = 0}
}

monster.immunities = {
	{type = "paralyze", condition = false},
	{type = "outfit", condition = false},
	{type = "invisible", condition = false},
	{type = "bleed", condition = false}
}

mType:register(monster)
