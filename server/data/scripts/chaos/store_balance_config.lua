-- Store balance rules (O140): the limits that tools/store_model.lua --check enforces on the coin packs, the store prices and the
-- boosts. Plain table, loaded with dofile; the engine loads it as a script and it only returns a table. Numbers are in
-- docs/PRICES.md ("Store balance (O140)"). Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- one Chaos Coin is worth this much gold: the rate the potion and rune packs are built on (shop_config.lua
	-- RUNE_GOLD_PER_COIN). Every gold alternative of a store item is measured against it.
	goldPerCoin = 1000,
	-- the store may be at most this many times cheaper than the gold way (premium never more than ~2x as efficient)
	maxCheaperThanGold = 2,

	packs = {
		coinsPerReal = 10,        -- the base rate: one coin is about R$ 0,10
		baseTolerancePct = 1.5,   -- the packs without a bonus differ at most this much in coins per real (R$ 9,90 vs 24,90 rounding)
		maxBonusPct = 20,         -- the biggest pack bonus ("modest bulk bonus")
		maxBulkMult = 1.25,       -- coins per real of the biggest pack / the base rate
		starterMaxMult = 3.5,     -- the one-time Starter pack, coins per real / the base rate
		firstMaxMult = 2.25,      -- the first donation doubling (at most +maxBonus coins), coins per real / the base rate
		usdCentsEnding = 98,      -- every USD price ends in .98 so that x brlPerUsd 5 gives R$ x9,90
		pixCentsEnding = 90
	},

	-- supplies sold in packs: gold value of a pack (NPC ask x count) per coin, any size. O317: the ceiling fell from 2000 to
	-- 1400 when the ultimate and supreme potion packs rose 30-40% (they sold at 1,400-1,850; the others at 800-1,400)
	supplies = {minGoldPerCoin = 700, maxGoldPerCoin = 1400, maxPackDiscountPct = 10},
	-- no item of the store may sell to an NPC for more than this many gold per coin it cost (half a coin's gold: no coin -> gold loop)
	maxSellGoldPerCoin = 500,

	boosts = {
		xpPotion = {itemId = 28095, maxHoursPerWeek = 14},   -- 4 singles + 2 packs of 5, hours of x2 per account and week
		xpPackMaxDiscountPct = 15,
		worldBuffMaxBonus = {xp = 0.25, loot = 0.25, skill = 0.25, hunt = 0.5},
		worldBuffMaxCapMinutes = 180,
		worldBuffMaxSpreadPct = 25,                           -- the hourly prices of xp / loot / skill differ at most this much
		xpCapMax = 4.0                                        -- xpcap_config.lua cap: every bonus together
	},

	services = {
		passiveResetMaxLevelAt2x = 800,   -- the flat price covers the in-window reset (level x 250 gold) up to this level
		blessingLevel = 120,              -- the level where one blessing reaches its mid price (gentledeath_config.lua)
		-- All Blessings by level (O317: 60 / 100 / 150 coins up to level 200 / 500 / above). Each tier is judged at a typical
		-- level of its band against the gold way (!bless, five blessings): `level` and the most the store may be cheaper than
		-- that gold. The ratio may grow with the level because gold comes faster there (loot_model.lua); it may not fall
		-- under the first tier's 2x. Tier prices must rise with the level.
		blessingTiers = {{level = 120, maxCheaper = 2.0}, {level = 350, maxCheaper = 2.5}, {level = 700, maxCheaper = 3.0}},
		-- the Eternal Blessing in All Blessings purchases: at most eternalMaxTimes of the first (cheapest) tier, at least
		-- eternalMinTimesTop of the dearest tier (a level 800 character still needs several deaths to get its money back)
		eternalMinTimes = 8, eternalMaxTimes = 15, eternalMinTimesTop = 4
	},

	premium = {minDiscountPct90 = 5, maxDiscountPct90 = 20, maxDiscountPct180 = 25},
	-- Pacto Completo (O317, owner 2026-10-29: players encouraged to pay about R$ 50 a month): the Pact and Premium together
	-- against buying both apart. The 30 day offer is the monthly target; every length is cheaper than apart by minDiscountPct
	-- to maxDiscountPct, and its discount beats the Premium offer of the same days by at least minOverPremiumPct points.
	complete = {monthlyCoins = 500, monthlyTolerancePct = 5, minDiscountPct = 10, maxDiscountPct = 25, minOverPremiumPct = 6,
		pactPartTolerancePct = 1},
	-- Pact Marks (O317): the shelf of cosmetics, never coins, services, boosts or supplies. A Mark is worth at least a coin of
	-- the same cosmetic and at most maxMarksPerCoin; a month of Marks (dailyMarks x 31) buys at most one shelf item.
	marks = {minMarksPerCoin = 1.0, maxMarksPerCoin = 1.5, maxMonthlyMarks = 160},
	-- Lasting Exercise weapons (O317): one weekly limit for all of them together (shop_config.lua weeklyGroup), 14,000+ charges
	lastingMinCharges = 10000, lastingMaxPerWeek = 2,
	-- per-character convenience bought for another character of the account (accountDiscount): at most this much off, and only
	-- for services and unlocks (the kinds that are per character and not giftable)
	accountDiscountMaxPct = 50,
	pactDayTolerancePct = 10,           -- the Pact days of a starter pack at the Pact's own price per day
	bundles = {maxStarterDiscountPct = 55, maxSetDiscountPct = 25},
	-- Everfull potion tiers (O245, O247: ten upgrades, 20 / 30 / 50 / 70 coins; potions_config.lua upgrade): the store sells the swap Veyra's task does. The task's gold
	-- way is `materials` stock potions at Veyra's price; the store may be at most maxCheaperThanGold times cheaper than
	-- it (checked with goldPerCoin), and a whole line (health, mana or spirit) costs at most maxLineCoins in all.
	-- Nothing a tier gives is for sale to an NPC (no coin -> gold loop).
	everfull = {maxLineCoins = 200},
	-- the stash (O316): the free tab is 30 entries; Stash Slot Expansions (pact_config.lua store, stash_config.lua slots) grow it,
	-- the affinity tabs (100 entries each) are bought one by one. tools/store_model.lua --check holds the prices to these.
	stash = {
		minCoinsPerSlot = 1, maxCoinsPerSlot = 3,   -- an expansion, per slot it adds
		maxPackDiscountPct = 15,                    -- the pack of expansions against the same number bought singly
		maxFullCapCoins = 1200,                     -- all expansions up to the cap bought singly
		maxAffinityCoinsPerEntry = 2.0,             -- a bought affinity tab, per entry: never dearer than an expansion slot (the specialised tab is the better deal)
		maxOldTabCoins = 150,                       -- an old tab (150 coins when it was sold) is worth this many coins of expansions, no more
		-- the Remote Stash Deposit (O317): bought once for the account, it is dearer than a month of the Chaos Pact that lends it
		-- (else one month of Pact would be enough for good) and no more than the Auto Seller, the other convenience the Pact lends
		remoteMinCoins = 300, remoteMaxCoins = 450
	},
	-- Founder Pack (O322, owner 2026-10-29): two time-limited packs of cosmetics that never return, about R$ 50 and R$ 100
	-- (one coin is about R$ 0,10). founder_config.lua tiers; store_model.lua --check holds them to these.
	founder = {
		anchors = {["founder:pack"] = 499, ["founder:grand"] = 999}, anchorTolerancePct = 1,
		ratioMin = 1.9, ratioMax = 2.1,   -- the grand pack against the first: about twice the price, more pieces
		pactSharePct = 35, maxPactDays = 30,   -- the Pact days are a gift on top of the cosmetics, at most this share of the price
		minPieces = 2                     -- cosmetic pieces in the first pack (the grand pack has more)
	},
	perCharacterConvenienceMax = 1550,  -- Loot Bag + Auto Seller + Rarity Autoloot + pouches (Orbs, Rift Key, Gem) + Ration for one character
	cosmetics = {min = 80, max = 800}  -- every cosmetic offer; a static plate frame costs no more than the cheapest wings
}
