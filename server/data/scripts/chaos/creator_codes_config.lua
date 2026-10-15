-- Creator codes (creator_codes.lua, creator_codes_core.lua; website plugins/chaos/creator_lib.php, pages/creator.php).
-- Every number of the program in one place. Returned as a table, loaded as Chaos.creatorCodesConfig, by
-- server/tests/creator_codes_test.lua and by the website (it reads `enabled`, `sharePct`, `supportDays`, `holdDays`,
-- `monthlyCap`, `orderCap`, `adminGroup` with its small Lua reader). Data only, no engine calls. See server/README.md
-- "Creator codes" and website/README.md "Creator codes".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- A streamer or content creator gets a code from an administrator (website admin action, group adminGroup and up). A
-- donor picks the code on the website (Donate page, or page.php?plugin=chaos&p=creator); for supportDays every donation
-- of that account credits the creator with sharePct % of the donation's Chaos Coins (the pack's coins, not its bonus),
-- as in-game Chaos Coins to the creator's account, after holdDays (refunds and chargebacks first). Nothing is taken
-- from the donor: the donor gets the full pack. Owner decision 2026-10-13: paid in Chaos Coins in game (not money).
return {
	enabled = true,

	-- % of the donation's coins the creator earns (decided 2026-10-14, owner delegated; docs/PRICES.md): 10, so the
	-- Vault's 5000 coins reach orderCap exactly
	sharePct = 10,
	-- a code chosen by a donor applies to that account's donations for this many days (then the donor picks again)
	supportDays = 30,
	-- a share is paid this many days after the donation was credited, when it was not refunded or charged back
	holdDays = 14,
	-- caps: most coins one donation can earn its creator, and most coins one creator earns per calendar month (server
	-- time). A share over the month's room waits for the next month (state "wait"), it is never cut.
	orderCap = 500,
	monthlyCap = 5000,
	-- who may create, switch off or change a code on the website: the admin panel's accounts with a character of this
	-- group or higher (5 = god / administrator, docs/GM_HANDBOOK.md section 1)
	adminGroup = 5,
	-- the code a creator shares: 3-16 letters and digits, stored upper case
	code = {min = 3, max = 16},
	pollSeconds = 300, -- how often credited donations are matched to codes and due shares paid

	-- DB tables (server/sql/chaos_creator_codes.sql; the website's install.sql and creator_codes.lua create them too)
	tables = {
		codes = "chaos_creator_codes", -- one row per code: owner account, active, own % (0 = sharePct)
		support = "chaos_creator_support", -- the code a donor account picked, until when
		uses = "chaos_creator_uses", -- one row per donation that carried a code: share, state, reason
		log = "chaos_creator_log", -- every code change, pick, payment and refusal
		payers = "chaos_pay_payers" -- the payer of a donation (a hash written by the donation service; see README)
	},

	-- anti-abuse (creator_codes_core.lua C.decide): a share is void when the donor is the creator's own account, shares an
	-- IP (an IPv6 address by its /64) or a payer with it, when the donation was refunded or charged back, or when the
	-- code or the creator's account is switched off or banned
	antiAbuse = {
		selfUse = true,
		sameIp = true,
		samePayer = true
	},

	messages = {
		paid = "Creator code %s: %d Chaos Coins from a supporter's donation.",
		self = "the creator's own account",
		sameIp = "the same connection as the creator",
		samePayer = "the same payer as the creator",
		reversed = "the donation was refunded or charged back",
		inactive = "the code is switched off",
		banned = "the creator's account is banned",
		nocode = "the code no longer exists"
	}
}
