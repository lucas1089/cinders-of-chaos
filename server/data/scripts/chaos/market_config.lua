-- Chaos market (market.lua, market_core.lua, client game_market). Every number and rule of the player market.
-- Returned as a table, loaded as Chaos.marketConfig (and by server/tests/market_test.lua). Data only, no engine calls.
-- See server/README.md "Market".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- DB tables (server/sql/chaos_market.sql; market.lua also creates them at startup when missing)
	tables = {
		offers = "chaos_market_offers", -- one row per offer, the listed item kept in it (escrow) until it is delivered
		deliveries = "chaos_market_deliveries", -- what the market owes a character: an item, gold, or the notice of a coin sale
		log = "chaos_market_log" -- every listing, sale, cancel, expiry, delivery and refusal worth keeping
	},

	-- player storages (inside the Chaos range 7100000-7100999; 7100970-7100979 reserved for the market). They are saved
	-- in the same database transaction as the character's items, which is what makes listing and delivery crash safe.
	storage = {
		listSeq = 7100970, -- id of the last offer whose item left this character (the listing went through)
		deliverSeq = 7100971 -- id of the last delivery row whose item / gold reached this character
	},

	-- ------------------------------------------------------------------ prices and fees
	currencies = {"gold", "coins"}, -- gold: the bank balance; coins: the account's Chaos Coins (the store currency)
	price = {
		gold = {min = 100, max = 2000000000},
		coins = {min = 1, max = 100000}
	},
	-- listing fee, always in gold from the bank, not refunded (cancel, expiry): pct of the gold price (the coin price
	-- times coinFeeGold for a coins-only offer), at least minFee, at most maxFee
	listingFee = {pct = 1, minFee = 100, maxFee = 1000000, coinFeeGold = 100},
	-- sales tax taken from what the seller receives, rounded down (a coin price of 1-19 pays none)
	tax = {gold = 5, coins = 5},

	-- ------------------------------------------------------------------ offers
	durations = {1, 3, 7}, -- days a seller can choose
	defaultDuration = 3,
	maxActive = 20, -- active offers per character
	maxActivePerAccount = 40, -- active offers per account (all its characters)
	minLevel = 8, -- characters below this level cannot list or buy
	nameMax = 60, -- characters of an item name stored and searched

	-- items that are never listed: currency, store-bound items, and these ids
	blockedIds = {
		[2148] = true, [2152] = true, [2160] = true -- gold, platinum, crystal coins: the bank is the market for those
	},
	-- action ids a quest item carries (nil = only a unique id blocks); items with these action ids are refused
	blockedActionIds = {},

	-- ------------------------------------------------------------------ the window
	pageSize = 10, -- offers per Browse page (the window shows 10 rows without scrolling at 1280x720)
	historyRows = 40, -- rows in My Offers (sold / expired / cancelled) and History
	sellableMax = 120, -- items listed in the Sell tab's picker
	sorts = {"new", "price", "price_desc", "ilvl", "rarity", "name", "ending"},
	categories = {"weapon", "shield", "helmet", "armor", "legs", "boots", "jewel", "other", "orb", "gem", "key", "misc"},

	-- rate limits per character (ms between two requests of the kind)
	rate = {browse = 150, tip = 60, list = 1500, buy = 800, cancel = 800, mine = 400, sellable = 600},

	-- the expiry sweep (globalevent) and how many offers it closes at most per run
	sweepSeconds = 60,
	sweepBatch = 200,

	-- the stock market item in every depot locker (actions.xml `function="market"`, removed by
	-- tools/patch_market.py): using it opens this market instead
	marketItemId = 14405,

	messages = {
		level = "You need level %d to use the market.",
		notSaved = "This character is not saved by the server, so it cannot use the market.",
		slow = "Slow down.",
		notFound = "That offer is no longer on the market.",
		ownOffer = "That is your own offer.",
		ownAccount = "You cannot buy from a character of your own account.",
		realm = "That offer is not on your market.",
		noGold = "You do not have enough gold in your bank account.",
		noCoins = "You do not have enough Chaos Coins.",
		noCurrency = "That offer is not sold for that currency.",
		busy = "The market is busy, please try again.",
		maxActive = "You already have %d active offers.",
		maxAccount = "Your account already has %d active offers.",
		noItem = "That item is no longer where it was.",
		feeGold = "The listing fee is %s gold; you do not have it in your bank account."
	}
}
