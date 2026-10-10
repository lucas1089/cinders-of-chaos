-- Orb Exchange (orbexchange.lua, orbexchange_core.lua, client game_orbexchange). Every number and rule of the
-- currency order book for the crafting orbs. Returned as a table, loaded as Chaos.orbExchangeConfig (and by
-- server/tests/orbexchange_test.lua). Data only, no engine calls. See server/README.md "Orb Exchange".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- DB tables (server/sql/chaos_orbx.sql; orbexchange.lua also creates them at startup when missing)
	tables = {
		orders = "chaos_orbx_orders", -- one row per order; the unfilled part of the offered amount is its escrow
		trades = "chaos_orbx_trades", -- one row per fill (the price history and "My fills")
		deliveries = "chaos_orbx_deliveries", -- what the exchange owes a character: orbs (inbox) or gold (bank)
		log = "chaos_orbx_log" -- every order, cancel, expiry, delivery, recovery and error worth keeping
	},

	-- player storages (inside the Chaos range; 7100950 - 7100954 reserved for the exchange). Saved in the same database
	-- transaction as the character's items, which makes placing an orb order and the deliveries crash safe (the
	-- market's method, market_config.lua storage).
	storage = {
		placeSeq = 7100950, -- id of the last order whose orbs left this character
		deliverSeq = 7100951 -- id of the last delivery row that reached this character
	},

	-- the orbs on the exchange: nil = every crafting orb (ChaosCrafting.config.orbs, orbs v2 included), else a list of
	-- orb keys; `exclude` removes keys from either
	orbs = nil,
	exclude = {},

	minLevel = 8, -- characters below this level cannot place orders

	-- the size of one order, per side (the amount offered and the amount wanted)
	min = {orb = 1, gold = 1000},
	max = {orb = 100000, gold = 2000000000},

	-- fees (gold sinks, never refunded):
	--   goldBps      the gold leg of every fill pays goldBps / 10000 (200 = 2%), rounded down, from the side that
	--                receives the gold
	--   orbPairGold  an orb-for-orb order pays this much gold from the bank when it is placed
	fees = {goldBps = 200, orbPairGold = 500},

	durations = {1, 3, 7, 14}, -- days an order stays on the book
	defaultDuration = 7,
	maxOpen = 20, -- open orders per character
	maxOpenPerAccount = 40, -- open orders per account (all its characters)
	selfTrade = false, -- false: an order never fills against an order of the same account (it is skipped)

	-- the matching engine
	matchBatch = 200, -- resting orders read for one new order (the best ones)
	scan = 256, -- smaller fills tried when the largest one would break the new order's limit by rounding

	-- the window
	bookDepth = 12, -- price levels shown per side
	bookRows = 600, -- active orders of a pair read for the book
	tradesShown = 20, -- last trades listed
	historyHours = 24, -- the volume, high / low and the chart
	mineRows = 30, -- closed orders and fills in My Orders

	-- rate limits per character (ms between two requests of the kind)
	rate = {open = 400, book = 150, place = 1000, cancel = 500, mine = 300},

	-- the expiry sweep (globalevent) and how many orders it closes at most per run
	sweepSeconds = 60,
	sweepBatch = 200,

	messages = {
		level = "You need level %d to use the Orb Exchange.",
		notSaved = "This character is not saved by the server, so it cannot use the Orb Exchange.",
		slow = "Slow down.",
		busy = "The exchange is busy, please try again.",
		asset = "Choose what you give and what you want: an orb or gold.",
		same = "Give and want must be two different currencies, at least one an orb.",
		tooSmall = "At least %s %s per order.",
		tooBig = "At most %s %s per order.",
		days = "Choose one of the order durations.",
		noOrbs = "You do not carry %s %s in your backpack (locked orbs do not count).",
		noGold = "You do not have %s gold in your bank account.",
		fee = "An orb-for-orb order costs %s gold from your bank; you do not have it.",
		maxOpen = "You already have %d open orders.",
		maxAccount = "Your account already has %d open orders.",
		gone = "That order is no longer open.",
		later = "The order is saved and goes on the book when you open the exchange again or at your next login."
	}
}
