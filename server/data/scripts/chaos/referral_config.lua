-- Referral program: every rule, reward and text in one place. Read by referral.lua (Chaos.referralConfig),
-- referral_core.lua (pure rules), server/tests/referral_test.lua and the website (website/overlay/plugins/chaos/
-- referral.php reads `code`, `entryDays` and `enabled`). The engine also loads this file as a script because it lives
-- under data/scripts; it only returns a table. See server/README.md "Referral program". Lua 5.1 / LuaJIT and 5.3.
--
-- Nothing here gives power: the friend's gift is supplies and a title, the referrer's rewards are titles and a few
-- Chaos Coins (the store sells no gear and no orb with a random result).
return {
	enabled = true,

	-- DB tables (server/sql/chaos_referral.sql; referral.lua creates them at startup too)
	tables = {
		codes = "chaos_referral_codes", -- one row per account that has a code: account_id -> code
		links = "chaos_referrals", -- one row per referred account: who referred it, status, the tracked character
		rewards = "chaos_referral_rewards", -- one row per referred account and milestone: reached, paid / due / void
		log = "chaos_referral_log", -- every link, refusal, gift and payment
		tiers = "chaos_referral_tiers" -- one row per referrer and tier reward reached (3, 5, 10 friends)
	},

	-- the code an account shares: `length` characters of `alphabet` (no 0/O, 1/I/L), shown as XXXX-XXXX
	code = {length = 8, alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789", group = 4},
	minReferrerLevel = 20, -- an account gets its code once one of its characters reached this level
	-- the website link players can share (empty: only the code is shown). The site pre-fills the form from ?ref=CODE.
	shareUrl = "",

	-- a new account may enter a code at creation (website) or in game within this many days of its creation
	-- (accounts.creation; znote_accounts.created when that is 0). Accounts with no creation time cannot enter one.
	entryDays = 7,

	antiAbuse = {
		sameIp = true, -- refused when the new account and the referrer share an IP (login IPs of every character,
		--                the website registration IP of both; an IPv6 address counts by its /64 network)
		sameEmailDomain = true, -- refused when both e-mails have the same domain, unless it is a public one below
		publicDomains = {"gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "msn.com", "yahoo.com",
			"yahoo.com.br", "icloud.com", "me.com", "proton.me", "protonmail.com", "gmx.com", "gmx.de", "web.de", "mail.ru",
			"yandex.ru", "aol.com", "uol.com.br", "bol.com.br", "terra.com.br", "wp.pl", "o2.pl", "interia.pl", "onet.pl"},
		staffAccountType = 2, -- accounts of this type or higher (tutor and up) neither refer nor are referred
		staffGroup = 2, -- nor accounts with a character of this group or higher
		monthlyLinks = 10, -- new friends one referrer can sign up per calendar month (server time)
		monthlyRewards = 10, -- referrer rewards paid per calendar month; more wait for the next month
		-- checked again when a reward is due (owner rules 2026-10-13, docs/GM_HANDBOOK.md section 4 and the multi-client
		-- rule of Chaos.multiClient: one person, one side of a referral):
		minReferredAccountDays = 7, -- the referred account is at least this old (else the reward waits)
		sameIpAtPayout = true, -- void when the two accounts share a connection by then (an IPv6 address by its /64)
		samePayer = true, -- void when a donation of each account had the same payer (payersTable)
		payersTable = "chaos_pay_payers" -- the payer hash of each donation (server/sql/chaos_creator_codes.sql; may be empty)
	},
	retryMinutes = 30, -- how often waiting rewards are tried again (also at every login of the referrer and at startup)

	-- the friend's gift, given to the character that logs in once the link is accepted (also the one that entered the
	-- code in game). Items go to the backpack, else to the depot inbox. title: account-wide, on the name plate.
	starterGift = {
		items = {
			{id = 7618, count = 50, name = "health potions"},
			{id = 7620, count = 50, name = "mana potions"}
		},
		title = {key = "referral:kindled", text = "Kindled", color = "#d98a3a"}
	},

	-- the referrer's rewards, when the referred account's first character (the lowest character id of that account,
	-- fixed when the link is accepted) reaches the level. coins: Chaos Coins to the referrer's account; title: account-wide.
	-- l250: the main reward (owner decision 2026-10-13: a cosmetic when the friend's character reaches level X; X = 250
	-- decided 2026-10-14, owner delegated, docs/PRICES.md: with pack combat level 150 took 1.5-3 hours, 250 about 3-6, a
	-- friend who stayed; the referred account must be minReferredAccountDays old).
	milestones = {
		{key = "l50", level = 50, coins = 25, title = {key = "referral:torchbearer", text = "Torchbearer", color = "#e0a040"}},
		{key = "l250", level = 250, coins = 50, title = {key = "referral:emberherald", text = "Ember Herald", color = "#e06030"}}
	},

	-- tier rewards of the referrer: once `count` referred accounts reached the milestone `qualify` (paid, not void), a
	-- title for the whole account and a few coins, once each. Cosmetics only.
	qualify = "l250",
	tiers = {
		{key = "t3", count = 3, coins = 50, title = {key = "referral:flamecaller", text = "Flamecaller", color = "#f08a3a"}},
		{key = "t5", count = 5, coins = 100, title = {key = "referral:hearthwarden", text = "Hearthwarden", color = "#f0a050"}},
		{key = "t10", count = 10, coins = 200, title = {key = "referral:pyrelord", text = "Lord of the Pyre", color = "#ff5a2a"}}
	},

	messages = {
		disabled = "The referral program is off.",
		badCode = "That is not a referral code.",
		unknownCode = "No account has this referral code.",
		ownCode = "You cannot use your own referral code.",
		alreadyLinked = "This account already has a referrer.",
		tooOld = "Referral codes can only be entered in the first %d days of a new account.",
		noCreation = "This account has no creation date, so it cannot enter a referral code.",
		staff = "Staff accounts cannot take part in the referral program.",
		referrerStaff = "Staff accounts cannot refer players.",
		referrerBanned = "This referral code cannot be used right now.",
		sameIp = "This referral code cannot be used from the same connection as its owner.",
		sameEmail = "This referral code cannot be used by an account with the same e-mail domain as its owner.",
		cycle = "You cannot use the code of an account you referred.",
		monthlyLinks = "This referral code has reached its limit of new friends for this month.",
		noCodeYet = "Reach level %d with any character of this account to get your referral code.",
		linked = "Referral code accepted: you were referred by %s.",
		rejected = "The referral code entered at account creation was not accepted: %s",
		gift = "Welcome gift for joining with a referral code: %s and the title %s.",
		giftNoRoom = "Your welcome gift could not be given: log in again.",
		giftInbox = "Part of your welcome gift did not fit: it waits in your depot inbox.",
		paid = "Your friend %s reached level %d: you received %s.",
		waitingCap = "Your friend %s reached level %d. Monthly reward limit reached: the reward waits for next month.",
		void = "Your friend %s reached level %d, but the referral rules refused the reward (a banned account, a shared connection or a shared payer).",
		tier = "%d of your friends reached level %d: you received %s."
	}
}
