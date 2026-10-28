-- Exercise Roulette prize pool (server/README.md "Roulette prizes against token drops", O151). Data only, no engine calls.
-- Loaded as one of ChaosRoulettePools (prizes.lua, by the script's actionId); tools/patch_roulette.py writes the `pool` lines
-- into the prizePool of the base exercise roulette script. Tests: tests/roulette_pools_test.lua (luajit and lua5.3),
-- tools/patch_roulette_test.py; the numbers: tools/roulette_model.lua.
--
-- What it was: 21 prizes, all exercise weapon chests, 7 of each of three charge tiers (500 / 1800 / 14400). Of the seven
-- kinds six are the sword, axe and club chests, which are one melee weapon since 2026-10-23 (the axe and club chests are
-- retired: the shop lists dropped them), and a class can use only the kinds of its line, so most spins gave a chest the
-- winner could not use, worth 100,000 to 2.8M gold against an Exercise Token that costs about 80 minutes of boss
-- hunting. Now the roulette keeps the chests as its theme but never gives a dead one (an exercise chest of a kind the
-- winner's class cannot train with becomes the chest of the same tier of a kind it can: prizes_core.lua K.classChest), and
-- most spins are the same level-scaled prizes the loot layer hands out: crafting orbs, sockets, gold that grows with the
-- level and a unique chest of the level.
--
-- The base draw: every entry rolls its `chance` in 10000, one of the hits is picked at random, no hit rolls again
-- (ChaosPrizesCore.odds gives the exact share of each entry). `count` = {min, max} of the stack. For `gold` the count is
-- the crystal coins the tile shows (units of boss_roulette_config.lua gold). `kind` groups the entries for the tests (orb,
-- material, gold, unique, chest). One line per entry, in this exact shape: tools/patch_roulette.py reads them by pattern.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
local boss = dofile("data/scripts/chaos/boss_roulette_config.lua")

return {
	actionIds = {18563},
	title = "exercise",

	-- the token that pays a spin (the base script's playItem)
	token = 28058,
	tokenCount = 1,

	-- the base broadcasts a prize whose chance is at most this
	rareThreshold = 160,

	pool = {
		-- exercise chests: the three tiers of the six kinds (the fist chest is the Monk's); the class rule below turns a dead one into a usable one
		{id = 27761, name = "Exercise Melee Chest (500)", count = {1, 1}, chance = 450, kind = "chest"},
		{id = 27762, name = "Exercise Fist Chest (500)", count = {1, 1}, chance = 450, kind = "chest"},
		{id = 27764, name = "Exercise Bow Chest (500)", count = {1, 1}, chance = 450, kind = "chest"},
		{id = 27765, name = "Exercise Rod Chest (500)", count = {1, 1}, chance = 450, kind = "chest"},
		{id = 27766, name = "Exercise Wand Chest (500)", count = {1, 1}, chance = 450, kind = "chest"},
		{id = 27767, name = "Exercise Shield Chest (500)", count = {1, 1}, chance = 450, kind = "chest"},
		{id = 27768, name = "Durable Exercise Melee Chest (1800)", count = {1, 1}, chance = 300, kind = "chest"},
		{id = 27769, name = "Durable Exercise Fist Chest (1800)", count = {1, 1}, chance = 300, kind = "chest"},
		{id = 27771, name = "Durable Exercise Bow Chest (1800)", count = {1, 1}, chance = 300, kind = "chest"},
		{id = 27772, name = "Durable Exercise Rod Chest (1800)", count = {1, 1}, chance = 300, kind = "chest"},
		{id = 27773, name = "Durable Exercise Wand Chest (1800)", count = {1, 1}, chance = 300, kind = "chest"},
		{id = 27774, name = "Durable Exercise Shield Chest (1800)", count = {1, 1}, chance = 300, kind = "chest"},
		{id = 27775, name = "Lasting Exercise Melee Chest (14400)", count = {1, 1}, chance = 120, kind = "chest"},
		{id = 27776, name = "Lasting Exercise Fist Chest (14400)", count = {1, 1}, chance = 120, kind = "chest"},
		{id = 27778, name = "Lasting Exercise Bow Chest (14400)", count = {1, 1}, chance = 120, kind = "chest"},
		{id = 27779, name = "Lasting Exercise Rod Chest (14400)", count = {1, 1}, chance = 120, kind = "chest"},
		{id = 27780, name = "Lasting Exercise Wand Chest (14400)", count = {1, 1}, chance = 120, kind = "chest"},
		{id = 27781, name = "Lasting Exercise Shield Chest (14400)", count = {1, 1}, chance = 120, kind = "chest"},
		-- crafting orbs and sockets the loot layer drops (loot_config.lua currency.entries), in stacks
		{id = 29851, name = "Orb of Awakening", count = {2, 5}, chance = 2500, kind = "orb"},
		{id = 32256, name = "Whetstone", count = {2, 5}, chance = 2500, kind = "orb"},
		{id = 29856, name = "Orb of Upheaval", count = {2, 4}, chance = 2200, kind = "orb"},
		{id = 32251, name = "Orb of Tempering", count = {1, 3}, chance = 1800, kind = "orb"},
		{id = 29857, name = "Orb of Fate", count = {1, 2}, chance = 1000, kind = "orb"},
		{id = 24691, name = "Orb of Gilding", count = {1, 2}, chance = 700, kind = "orb"},
		{id = 24697, name = "Orb of Unmaking", count = {1, 2}, chance = 700, kind = "orb"},
		{id = 24688, name = "Orb of Erasure", count = {1, 2}, chance = 700, kind = "orb"},
		{id = 29855, name = "Orb of Grafting", count = {1, 1}, chance = 400, kind = "orb"},
		{id = 32254, name = "Orb of Reforging", count = {1, 1}, chance = 300, kind = "orb"},
		{id = 32253, name = "Orb of Excision", count = {1, 1}, chance = 150, kind = "orb"},
		{id = 24692, name = "Orb of Sockets", count = {2, 5}, chance = 1800, kind = "material"},
		-- gold: the tile shows N crystal coins, the prize is N x gold.perUnit of an hour of hunting gold at the winner's level
		{id = 2160, name = "Crystal coin (small purse)", count = {1, 1}, chance = 2000, kind = "gold"},
		{id = 2160, name = "Crystal coin (purse)", count = {2, 2}, chance = 2500, kind = "gold"},
		{id = 2160, name = "Crystal coin (heavy purse)", count = {5, 5}, chance = 3500, kind = "gold"},
		{id = 2160, name = "Crystal coin (strongbox)", count = {10, 10}, chance = 2600, kind = "gold"},
		-- a chest on the tile: a unique of the winner's level (unique.band), made like a drop
		{id = 1740, name = "Unique chest", count = {1, 1}, chance = 200, kind = "unique"},
	},

	-- the exercise chests of a tier, by kind (exercise_config.lua kinds): the chest a class cannot use becomes the one of the
	-- same tier of a kind it can (the club chests are retired and not in the pool). The fist chest (27762, 27769, 27776, the
	-- ids of the old axe chests) is the Monk's: a Monk's melee chest becomes a fist or a shield chest
	chests = {
		kinds = {"melee", "fist", "ranged", "rod", "wand", "shield"},
		tiers = {
			{melee = 27761, fist = 27762, ranged = 27764, rod = 27765, wand = 27766, shield = 27767},
			{melee = 27768, fist = 27769, ranged = 27771, rod = 27772, wand = 27773, shield = 27774},
			{melee = 27775, fist = 27776, ranged = 27778, rod = 27779, wand = 27780, shield = 27781},
		},
	},

	-- what the tests hold the pool to
	limits = {
		maxChestShare = 0.18, -- the theme, never the bulk
		minOrbShare = 0.40, -- at least this share is a crafting orb, socket orb or gold
		minGoldShare = 0.12,
		minUniqueShare = 0.003,
		maxUniqueShare = 0.02,
	},

	-- shared with the Boss Roulette: the gold per unit (the hunting gold curve) and the unique chest's level band
	gold = boss.gold,
	unique = boss.unique,
	-- never in the pool: decks, ships, belts, gloves, and the retired club chests
	retired = {27632, 27633, 27634, 27796, 27797, 27798, 27799, 27800, 27801, 27802, 27763, 27770, 27777},
}
