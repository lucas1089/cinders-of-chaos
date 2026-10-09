-- salvage_config.lua: every number of salvage (salvage.lua, salvage_core.lua; server/README.md "Salvage").
-- Plain table, loaded with  ChaosSalvageConfig = dofile("data/scripts/chaos/salvage_config.lua")
-- Lua 5.1 / LuaJIT compatible. Edit here, then /reload scripts (or restart). server/tools/install_salvage.py reads `shard`.
--
-- Economy (see the README for the reasoning): an item with a rarity gives a few Rune Shards, shards combine into the
-- existing orbs at about 2.5 shards per Chaos Coin of the orb's store price, and a small chance gives a whole orb. With
-- the stock rarity roll an average rolled drop is worth about 3.3 shards (~0.13 Chaos Orb) plus a 0.9% orb chance, so salvaging every rolled
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
			.. "(!craft, Salvage)."
	},

	-- shards per rarity 1..15 (Common .. Transcendent) at the bottom of the rarity's item level window
	baseShards = {1, 1, 2, 2, 3, 3, 4, 5, 6, 7, 8, 10, 12, 14, 18},
	-- the engine rolls rarity r with item level 10r-9 .. 10r; the top of that window gives up to this share more
	-- (floor, so Common and Uncommon stay at 1)
	levelWindow = 10,
	levelBonus = 0.5,
	-- extra shards per Chaos modifier (chaos_item_mods.lua) and per empty socket
	perChaosMod = 1,
	perSocket = 1,

	-- chance (per 10000) of a whole orb on top of the shards, by rarity 1..15
	orbChance = {50, 50, 75, 75, 100, 100, 150, 150, 200, 200, 250, 300, 350, 400, 500},
	-- which orb (ChaosCrafting orb keys), by weight
	orbWeights = {
		{"transmutation", 35}, {"chaos", 25}, {"scouring", 12}, {"alchemy", 10}, {"annulment", 8}, {"divine", 5},
		{"sockets", 3}, {"exalted", 2}
	},

	-- shards -> one orb. Store prices (shop_config.lua, Chaos Coins): Transmutation 5, Chaos 10, Scouring 12,
	-- Alchemy 15, Annulment 20, Divine 25, Sockets 25, Exalted 40.
	recipes = {
		{key = "transmutation", cost = 12},
		{key = "chaos", cost = 25},
		{key = "scouring", cost = 30},
		{key = "alchemy", cost = 40},
		{key = "annulment", cost = 50},
		{key = "divine", cost = 60},
		{key = "sockets", cost = 60},
		{key = "exalted", cost = 100}
	},
	maxCombine = 10, -- orbs made by one click

	-- uniques are never salvaged: they are chase items with their own drop table and no rarity tier to price them
	allowUniques = false,

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
