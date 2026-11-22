-- Inspect Monster settings (monster_inspect.lua, monster_inspect_core.lua; O721). Loaded with
--     Chaos.monsterInspectConfig = dofile("data/scripts/chaos/monster_inspect_config.lua")
-- No engine calls (also read by server/tests/monster_inspect_test.lua). Lua 5.1 / LuaJIT and Lua 5.3 compatible.

return {
	-- who may be inspected: a monster on the same floor, within this many tiles and in view of the player
	rangeX = 10,
	rangeY = 10,
	-- request budget per player (token bucket, ms): one request at most every cooldownMs, a burst of bucketSize, then one
	-- every 1 / bucketPerSecond seconds
	cooldownMs = 600,
	bucketSize = 8,
	bucketPerSecond = 0.5,
	-- a packet bigger than this goes through Chaos.sendChunked (the extended opcode limit is 8192)
	packetBytes = 8000,

	-- the bestiary stage of the player (0 unknown, 1 Discovered, 2 Studied, 3 Mastered, 4 Completed) that opens a part of
	-- the window. Everything the player may know about a living monster in view is open from stage 0 (owner 2026-11-22,
	-- "mostrando todas as informações dele"), except what the Bestiary sells as progress: the loot list and the places the
	-- monster lives follow the Bestiary stages of the player for that monster (the Bestiary window shows the same rows).
	reveal = {
		lootHighlights = 2, -- the rarest rows of the loot table (bestiary_config.lua lootHighlights)
		lootFull = 3, -- the whole loot table and the uniques
		areas = 2 -- where it lives
	},

	-- lists in the window are cut here (the packet stays small)
	maxAttacks = 12,
	maxAbilities = 10,
	maxMods = 6,
	maxLoot = 30,
	maxUniques = 8,
	maxAreas = 3,
	lootHighlights = 4, -- rows shown from stage `reveal.lootHighlights` up to `reveal.lootFull` (the rarest)

	-- loot rarity bands by chance in percent (the first band whose min the chance reaches; `key` is a window text key)
	lootBands = {
		{key = "Common", min = 10},
		{key = "Uncommon", min = 1},
		{key = "Rare", min = 0.1},
		{key = "Very rare", min = 0}
	},
	-- what a tier of monster adds to its corpse (loot.lua extraRolls and gear floors; a line of the loot section)
	lootTierText = {
		magic = "1 extra loot roll",
		rare = "1 extra loot roll, gear of Magic quality or better",
		legendary = "2 extra loot rolls, gear of Rare quality or better",
		boss = "2 extra loot rolls, gear of Rare quality or better"
	},

	-- the element an attack or a spell shows, by words of its name (first match wins; lower case, plain find)
	attackElements = {
		{"fire", "fire"}, {"flame", "fire"}, {"inferno", "fire"}, {"burn", "fire"}, {"lava", "fire"}, {"magma", "fire"},
		{"energy", "energy"}, {"lightning", "energy"}, {"thunder", "energy"}, {"electr", "energy"},
		{"poison", "earth"}, {"earth", "earth"}, {"venom", "earth"}, {"acid", "earth"},
		{"ice", "ice"}, {"frost", "ice"}, {"cold", "ice"}, {"freez", "ice"},
		{"holy", "holy"}, {"smite", "holy"}, {"divine", "holy"},
		{"death", "death"}, {"curse", "death"}, {"necro", "death"}, {"soul", "death"},
		{"drown", "drown"}, {"water", "drown"},
		{"lifedrain", "life drain"}, {"life drain", "life drain"},
		{"manadrain", "mana drain"}, {"mana drain", "mana drain"},
		{"physical", "physical"}, {"melee", "physical"}, {"bleed", "physical"}
	},
	-- conditions a monster can be immune to: the label, and the name of the engine constant that holds the bit
	conditionImmunities = {
		{"poison", "CONDITION_POISON"}, {"burning", "CONDITION_FIRE"}, {"shock", "CONDITION_ENERGY"},
		{"bleeding", "CONDITION_BLEEDING"}, {"paralysis", "CONDITION_PARALYZE"}, {"drunk", "CONDITION_DRUNK"},
		{"invisibility", "CONDITION_INVISIBLE"}, {"outfit change", "CONDITION_OUTFIT"}
	},
	-- a sentence for each modifier of monster_tiers.lua ChaosMods (the key is the mod's key); shown under its name
	modifiers = {
		blazing = "Its hits can set you on fire.",
		chilling = "Its hits can slow you down.",
		venomous = "Its hits can poison you.",
		shocking = "Its hits can shock you.",
		vampiric = "It heals itself with a part of the damage it deals.",
		berserker = "It hits much harder below half health.",
		brutal = "It hits harder.",
		stoneskin = "It takes less damage.",
		reflective = "It throws part of the damage back at you.",
		regenerating = "It slowly heals itself.",
		swift = "It moves faster.",
		explosive = "It explodes when it dies.",
		juggernaut = "It has much more health.",
		emberforged = "It resists fire and burns.",
		frostforged = "It resists ice and chills.",
		stormforged = "It resists energy and shocks.",
		plated = "It resists physical damage.",
		resistant = "It resists one more element.",
		ruthless = "Its attacks ignore a part of your armour.",
		bulwark = "It blocks some hits outright."
	}
}
