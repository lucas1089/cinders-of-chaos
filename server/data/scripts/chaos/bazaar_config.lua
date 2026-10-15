-- Character Bazaar: player-to-player character auctions for Chaos Coins on the website (website plugins/chaos/
-- bazaar_lib.php, pages/bazaar.php) and the in-game lock of a listed character (bazaar.lua, bazaar_core.lua).
-- Every number in one place. Returned as a table, loaded as Chaos.bazaarConfig, by server/tests/bazaar_test.lua and by
-- the website (it reads the plain `key = number` fields below with its small Lua reader, so keep them one per line).
-- Data only, no engine calls. See server/README.md "Character Bazaar" and website/README.md "Character Bazaar".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Nothing here creates power: a character changes owner with what it has, paid with Chaos Coins that already exist
-- (the buyer's coins go to the seller, less the house fee, which leaves the economy).
return {
	enabled = true,

	-- the house fee in % of the final price, a coin sink (decided 2026-10-14, owner delegated, top of the approved 5-10
	-- range; docs/PRICES.md)
	feePct = 10,
	minDays = 1, -- an auction runs 1 to 7 days (the seller picks)
	maxDays = 7,
	minPrice = 100, -- the lowest minimum bid, in Chaos Coins
	maxPrice = 1000000,
	minStepPct = 5, -- a new bid beats the current one by at least this % ...
	minStep = 10, -- ... and at least this many coins
	minLevel = 50, -- a character below this level cannot be listed
	maxActivePerAccount = 2, -- listings one seller account may run at once
	maxBidsPerAccountHour = 20, -- bids one account may place per hour (all auctions)
	-- a bid in the last minutes moves the end so that the auction ends at least this many minutes after the last bid
	snipeMinutes = 5,
	-- a character with a chargeback on its account in this many days cannot be listed or bought for
	chargebackDays = 180,
	adminGroup = 5, -- the website's cancel action: an admin panel account with a character of this group or higher
	sweepSeconds = 60, -- how often the game server kicks a listed character that is online (a login during the listing)

	-- DB tables (server/sql/chaos_bazaar.sql; the website's install.sql creates them too)
	tables = {
		listings = "chaos_bazaar_listings", -- one row per auction: character, seller, prices, end, status
		bids = "chaos_bazaar_bids", -- every bid; escrow = coins held from the bidder (0 once refunded or spent)
		log = "chaos_bazaar_log" -- list, bid, outbid refund, buyout, sale, transfer, cancel, refusal
	},

	-- the statuses that lock the character in game (bazaar_core.lua B.locks)
	lockStatuses = {active = true, settling = true},

	messages = {
		locked = "This character is listed on the Character Bazaar until %s (server time). It cannot log in until the auction ends or the seller cancels it on the website.",
		kicked = "This character was listed on the Character Bazaar."
	}
}
