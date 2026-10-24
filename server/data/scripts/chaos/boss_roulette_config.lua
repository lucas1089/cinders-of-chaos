-- Boss Roulette prize pool (server/README.md "Boss Roulette", O148). Data only, no engine calls. Returned as a table
-- and loaded as ChaosBossRouletteConfig (prizes.lua reads it for the prizes that are not a plain item); the install tool
-- tools/patch_roulette.py writes the `pool` lines into the prizePool of the base boss roulette script. Tests:
-- tests/boss_roulette_test.lua (luajit and lua5.3), tools/patch_roulette_test.py.
--
-- Beta 2026-10-23: "I spun it twice. One reward was the golden deck, the other a boat. The roulette also shows lots of card
-- rewards." The base pool was 9 Furious badges, 4 legendary level 6 cards and (until the prizes step of 2026-10-22) two
-- decks and a ship. Now every prize is something the loot models hand out: crafting orbs, gold that grows with the
-- level, sockets, badges and their catalysts, a unique now and then, and at most a few percent cards.
--
-- The base draw: every entry rolls its `chance` in 10000, one of the hits is picked at random, no hit rolls again
-- (ChaosPrizesCore.odds gives the exact share of each entry). `count` = {min, max} of the stack. `kind` groups the
-- entries for the tests (orb, material, gold, unique, badge, catalyst, card). `name` is for people.
-- One line per entry, in this exact shape: tools/patch_roulette.py reads the lines with a pattern.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- the roulette script's config.actionId (prizes.lua finds the config by it) and the name in its broadcasts
	actionIds = {18562},
	title = "boss",

	-- the token that pays a spin (the base script's playItem)
	token = 28033,
	tokenCount = 1,

	-- the base broadcasts a prize whose chance is at most this (rouletteOptions.rareItemChance_broadcastThreshold)
	rareThreshold = 120,

	pool = {
		-- crafting orbs and sockets: the currency the loot layer drops (loot_config.lua currency.entries), in stacks
		{id = 29851, name = "Orb of Awakening", count = {1, 3}, chance = 5200, kind = "orb"},
		{id = 32256, name = "Whetstone", count = {1, 3}, chance = 5200, kind = "orb"},
		{id = 29856, name = "Orb of Upheaval", count = {1, 2}, chance = 3000, kind = "orb"},
		{id = 32251, name = "Orb of Tempering", count = {1, 2}, chance = 2800, kind = "orb"},
		{id = 24691, name = "Orb of Gilding", count = {1, 2}, chance = 1800, kind = "orb"},
		{id = 24697, name = "Orb of Unmaking", count = {1, 2}, chance = 1800, kind = "orb"},
		{id = 24688, name = "Orb of Erasure", count = {1, 2}, chance = 1800, kind = "orb"},
		{id = 29857, name = "Orb of Fate", count = {1, 1}, chance = 900, kind = "orb"},
		{id = 29855, name = "Orb of Grafting", count = {1, 1}, chance = 500, kind = "orb"},
		{id = 32254, name = "Orb of Reforging", count = {1, 1}, chance = 350, kind = "orb"},
		{id = 32253, name = "Orb of Excision", count = {1, 1}, chance = 250, kind = "orb"},
		{id = 32252, name = "Orb of Binding", count = {1, 1}, chance = 180, kind = "orb"},
		{id = 32258, name = "Ember Orb", count = {1, 1}, chance = 200, kind = "orb"},
		{id = 32259, name = "Crown Orb", count = {1, 1}, chance = 100, kind = "orb"},
		{id = 32260, name = "Void Orb", count = {1, 1}, chance = 60, kind = "orb"},
		{id = 32255, name = "Orb of Ruin", count = {1, 1}, chance = 20, kind = "orb"},
		{id = 24692, name = "Orb of Sockets", count = {1, 3}, chance = 2000, kind = "material"},
		-- gold: the tile shows N crystal coins, the prize is N x gold.perUnit of an hour of hunting at the winner's level
		{id = 2160, name = "Crystal coin (small purse)", count = {1, 1}, chance = 4200, kind = "gold"},
		{id = 2160, name = "Crystal coin (purse)", count = {2, 2}, chance = 2800, kind = "gold"},
		{id = 2160, name = "Crystal coin (heavy purse)", count = {5, 5}, chance = 1000, kind = "gold"},
		-- a chest on the tile: a unique of the winner's level (unique.band), made like a drop
		{id = 1740, name = "Unique chest", count = {1, 1}, chance = 250, kind = "unique"},
		-- Furious badges (tier 2 of the nine lines) and the first amplifier catalyst of each line
		{id = 27804, name = "Furious Exiled Spirit Badge", count = {1, 1}, chance = 250, kind = "badge"},
		{id = 27808, name = "Furious Fury Badge", count = {1, 1}, chance = 250, kind = "badge"},
		{id = 27812, name = "Furious Moon Badge", count = {1, 1}, chance = 250, kind = "badge"},
		{id = 27817, name = "Furious Night Seeker Badge", count = {1, 1}, chance = 250, kind = "badge"},
		{id = 27822, name = "Furious Earthshade Badge", count = {1, 1}, chance = 250, kind = "badge"},
		{id = 27826, name = "Furious Reborn Badge", count = {1, 1}, chance = 250, kind = "badge"},
		{id = 27831, name = "Furious Chaosfiend Badge", count = {1, 1}, chance = 250, kind = "badge"},
		{id = 27835, name = "Furious Veins Badge", count = {1, 1}, chance = 250, kind = "badge"},
		{id = 27839, name = "Furious Daybreak Badge", count = {1, 1}, chance = 250, kind = "badge"},
		{id = 27843, name = "Exiled Amplifier Catalyst [1]", count = {1, 1}, chance = 200, kind = "catalyst"},
		{id = 27846, name = "Fury Amplifier Catalyst [1]", count = {1, 1}, chance = 200, kind = "catalyst"},
		{id = 27849, name = "Moon Amplifier Catalyst [1]", count = {1, 1}, chance = 200, kind = "catalyst"},
		{id = 27853, name = "Night Seeker Amplifier Catalyst [1]", count = {1, 1}, chance = 200, kind = "catalyst"},
		{id = 27857, name = "Earthshade Amplifier Catalyst [1]", count = {1, 1}, chance = 200, kind = "catalyst"},
		{id = 27860, name = "Reborn Amplifier Catalyst [1]", count = {1, 1}, chance = 200, kind = "catalyst"},
		{id = 27864, name = "Chaosfiend Amplifier Catalyst [1]", count = {1, 1}, chance = 200, kind = "catalyst"},
		{id = 27867, name = "Veins Amplifier Catalyst [1]", count = {1, 1}, chance = 200, kind = "catalyst"},
		{id = 27870, name = "Daybreak Amplifier Catalyst [1]", count = {1, 1}, chance = 200, kind = "catalyst"},
		-- cards: two of the four legendary level 6 cards of the old pool (a deck is sold by Veyra the Apothecary)
		{id = 27547, name = "Legendary Exotic Dawnpiercer Lv6", count = {1, 1}, chance = 200, kind = "card"},
		{id = 27571, name = "Legendary Exotic Soulreaver Lv6", count = {1, 1}, chance = 200, kind = "card"},
	},

	-- what the tests hold the pool to
	limits = {
		maxCardShare = 0.06, -- at most this share of the spins is a card
		minOrbShare = 0.40, -- at least this share is a crafting orb, socket orb or gold
		minGoldShare = 0.12,
		minUniqueShare = 0.003, -- a unique chest: about one spin in 150 at least ...
		maxUniqueShare = 0.02, -- ... and one in 50 at most
	},

	-- gold prizes: unit = the displayed crystal coins; each is perUnit of an hour of hunting gold at the winner's level
	-- (hunting = gamble_config.lua balance.hunting: {level, gold per hour}, linear between, flat beyond). Paid
	-- as coin stacks (at least one crystal coin).
	gold = {
		perUnit = 0.2,
		hunting = {{8, 19000}, {40, 83000}, {100, 358839}, {300, 881866}, {500, 5548330}, {1000, 9519711}},
	},

	-- the unique chest: a unique that no season holds back and that is not an Ascended or boss-only one, of an item level
	-- in [level x low, level x high] (the nearest below when none), picked at random, made with ChaosMakeUnique
	unique = {
		low = 0.5,
		high = 1.0,
	},

	-- ids that must never be in the pool (the tests and the install tool check): the decks and ships (belts and gloves
	-- too: tests/boss_roulette_test.lua, tools/patch_roulette_test.py read tools/patch_badges.py); nothing can wear
	-- them, or the prize duplicates what Veyra the Apothecary sells
	retired = {27632, 27633, 27634, 27796, 27797, 27798, 27799, 27800, 27801, 27802},
}
