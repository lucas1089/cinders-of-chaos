-- salvage_config.lua: every number of salvage (salvage.lua, salvage_core.lua; server/README.md "Salvage").
-- Plain table, loaded with  ChaosSalvageConfig = dofile("data/scripts/chaos/salvage_config.lua")
-- Lua 5.1 / LuaJIT compatible. Edit here, then /reload scripts (or restart). server/tools/install_salvage.py reads `shard`.
--
-- Economy (see the README for the reasoning): an item with a rarity gives a few Rune Shards, shards combine into the
-- existing orbs at about 2.5 shards per Chaos Coin of the orb's store price, and a small chance gives a whole orb. With
-- the stock rarity roll an average rolled drop is worth about 3.3 shards (~0.13 Orb of Upheaval) plus a 0.9% orb chance, so salvaging every rolled
-- drop adds a modest share to the orb income of the loot layer instead of replacing it.

return {
	-- the shard item. A new items.otb node (install_salvage.py): a copy of the stock node sourceId (the violet crystal
	-- shard sprite, stackable) with the server id `id`; no client change is needed.
	shard = {
		id = 32051,
		sourceId = 18414,
		name = "rune shard",
		plural = "rune shards",
		article = "a",
		weight = 5,
		description = "A splinter of the power bound in salvaged gear. Combine shards into orbs at the crafting bench "
			.. "(Economy > Salvage)."
	},

	-- shards per rarity 1..15 (Common .. Transcendent) at item level 1
	baseShards = {1, 1, 2, 2, 3, 3, 4, 5, 6, 7, 8, 10, 12, 14, 18},
	-- the item level (chaos_item_mods.lua, 1 .. maxLevel) gives up to this share more: floor(base x (1 + levelBonus x
	-- level / maxLevel)), so Common and Uncommon stay at 1
	maxLevel = 150,
	levelBonus = 0.5,
	-- extra shards per modifier of tier highTier or better (T6+), and per empty socket
	highTier = 6,
	perHighTier = 1,
	perSocket = 1,

	-- chance (per 10000) of a whole orb on top of the shards, by rarity 1..15
	orbChance = {50, 50, 75, 75, 100, 100, 150, 150, 200, 200, 250, 300, 350, 400, 500},
	-- which orb (ChaosCrafting orb keys), by weight
	orbWeights = {
		{"transmutation", 35}, {"chaos", 25}, {"scouring", 12}, {"alchemy", 10}, {"annulment", 8}, {"divine", 5},
		{"sockets", 3}, {"exalted", 2},
		-- orbs v2: the cheap ones often, the gamble almost never
		{"whetstone", 14}, {"tempering", 12}, {"reforging", 4}, {"excision", 3}, {"binding", 2}, {"ruin", 1}
	},

	-- shards -> one orb, about 2.5 shards per Chaos Coin of a reference price: Awakening (transmutation) 5, Upheaval
	-- (chaos) 10, Erasure (scouring) 12, Gilding (alchemy) 15, Unmaking (annulment) 20, Fate (divine) 25, Sockets 25,
	-- Grafting (exalted) 40, Whetstone 2, Tempering 8, Reforging 20, Excision 25, Binding 30, Ruin 60. The store
	-- (shop_config.lua) sells only Whetstones, the Orb of Excision and the Orb of Binding, with weekly limits; the
	-- other prices are reference values for the shard costs, not store offers.
	recipes = {
		{key = "transmutation", cost = 12},
		{key = "chaos", cost = 25},
		{key = "scouring", cost = 30},
		{key = "alchemy", cost = 40},
		{key = "annulment", cost = 50},
		{key = "divine", cost = 60},
		{key = "sockets", cost = 60},
		{key = "exalted", cost = 100},
		{key = "whetstone", cost = 5},
		{key = "tempering", cost = 20},
		{key = "reforging", cost = 50},
		{key = "excision", cost = 60},
		{key = "binding", cost = 75},
		{key = "ruin", cost = 150}
	},
	maxCombine = 10, -- orbs made by one click

	-- uniques are not salvaged for their rarity (they have none) ...
	allowUniques = false,
	-- ... but item set pieces (data/lib/chaos_item_sets.lua): duplicates are common enough, each gives this many shards
	-- (about a Mythic drop; no orb chance beyond the Common one)
	setPieceShards = 8,
	-- ... and, with Conquest Tokens loaded (conquest.lua), every unique: a share of its Conquest vendor price in tokens
	-- (conquest_config.lua salvage: 10%, at least 25) plus uniqueShards rune shards (a set piece keeps setPieceShards)
	uniqueTokens = true,
	uniqueShards = 4,

	-- "salvage all": items of rarity <= maxRarity directly inside one container (the backpack or one bag in it),
	-- at most batchCap items per action
	batchCap = 50,
	batchDefaultMaxRarity = 2,

	-- ms between two actions of a player (single salvage / lock, a batch, a combine)
	singleIntervalMs = 300,
	batchIntervalMs = 2000,
	combineIntervalMs = 300,

	-- the item lock: a custom attribute; salvage and the auto seller never take a locked item
	lockAttr = "chaos_locked",

	logName = "Salvage" -- the `orb` column of chaos_crafting_log
}
