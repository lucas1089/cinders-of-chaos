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

	-- shards per rarity at item level 1, in the order Common, Uncommon, Magic, Rare, Legendary, Divine (before the seven
	-- rarities: 1, 1, 2, 2, 3, 3, 4, 5, 6, 7, 8, 10, 12, 14, 18 for the 15; Legendary now covers old 5 .. 9, Divine old 10 .. 15)
	baseShards = {1, 1, 2, 3, 5, 12},
	-- the item level (chaos_item_mods.lua, 1 .. maxLevel) gives up to this share more: floor(base x (1 + levelBonus x
	-- level / maxLevel)), so Common and Uncommon stay at 1
	maxLevel = 150,
	levelBonus = 0.5,
	-- extra shards per modifier of tier highTier or better (T6+), and per empty socket
	highTier = 6,
	perHighTier = 1,
	perSocket = 1,

	-- chance (per 10000) of a whole orb on top of the shards, by rarity (same order; it was 50 .. 500 over the 15)
	orbChance = {50, 50, 75, 100, 150, 300},
	-- which orb (ChaosCrafting orb keys), by weight
	orbWeights = {
		{"transmutation", 35}, {"chaos", 25}, {"scouring", 12}, {"alchemy", 10}, {"annulment", 8}, {"divine", 5},
		{"sockets", 3}, {"exalted", 2},
		-- orbs v2: the cheap ones often, the gamble almost never
		{"whetstone", 14}, {"tempering", 12}, {"reforging", 4}, {"ember", 4}, {"excision", 3}, {"crown", 3}, {"binding", 2}, {"void", 1}, {"ruin", 1}
	},

	-- shards -> one orb, about 2.5 shards per Chaos Coin of a reference price: Awakening (transmutation) 5, Upheaval
	-- (chaos) 10, Erasure (scouring) 12, Gilding (alchemy) 15, Unmaking (annulment) 20, Fate (divine) 25, Sockets 25,
	-- Grafting (exalted) 40, Whetstone 2, Tempering 8, Reforging 20, Ember 20, Excision 25, Crown 40, Binding 30, Void 50,
	-- Ruin 60. The store
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
		{key = "ember", cost = 50},
		{key = "excision", cost = 60},
		{key = "crown", cost = 100},
		{key = "binding", cost = 75},
		{key = "void", cost = 125},
		{key = "ruin", cost = 150}
	},
	maxCombine = 10, -- orbs made by one click
	-- recycling (beta 2026-10-20: ~2000 orbs nobody could use): an orb back into shards at this share of its recipe cost
	-- (rounded down, at least 1); the loss keeps shards -> orb -> shards from being a free loop. Up to maxRecycle per click.
	recycleShare = 0.4,
	maxRecycle = 100,

	-- the base world's character-upgrade shards -> the crafting orb of the same name (beta 2026-10-21: "how do I combine
	-- the shards into an orb?"). Same action and limits as the rune shard recipes (combine {key, count}, maxCombine,
	-- combineIntervalMs), but the input is the shard item itself; no recycling back. The shards stay character-upgrade
	-- currency. input = the item id the recipe eats, orb = ChaosCrafting orb key, name / plural = the item's names after
	-- install_orbs.py (tests/salvage_test.lua checks them against chaos_orbs_config.lua renames).
	-- 1,000 of either shard for its orb: owner, 2026-10-21 ("pode deixar 1000 shards por orb"), down from the computed
	-- 1,500 / 1,750 (server/README.md "Salvage", "Ember and Crown Shards into orbs"): the shards drop only from the 30
	-- waystone monsters, ~400 Ember and ~210 Crown Shards an hour in tier 3-4 maps, so an Ember Orb every ~2.5 h and a
	-- Crown Orb every ~4.8 h of shard hunting there.
	shardRecipes = {
		{key = "embershard", orb = "ember", input = 29852, cost = 1000, name = "Ember Shard", plural = "Ember Shards"},
		{key = "crownshard", orb = "crown", input = 29853, cost = 1000, name = "Crown Shard", plural = "Crown Shards"}
	},

	-- uniques are not salvaged for their rarity (they have none) ...
	allowUniques = false,
	-- ... but item set pieces (data/lib/chaos_item_sets.lua): duplicates are common enough, each gives this many shards
	-- (about a Legendary drop; no orb chance beyond the Common one)
	setPieceShards = 8,
	-- ... and, with Conquest Tokens loaded (conquest.lua), every unique: a share of its Conquest vendor price in tokens
	-- (conquest_config.lua salvage: 10%, at least 25) plus uniqueShards rune shards (a set piece keeps setPieceShards)
	uniqueTokens = true,
	uniqueShards = 4,

	-- "salvage all": items of rarity <= maxRarity (a stored id: 1, 2, 3, 4, 5 or 10) directly inside one container (the backpack or one bag in it),
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
