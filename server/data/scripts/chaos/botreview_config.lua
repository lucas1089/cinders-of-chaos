-- Bot review: daily suspicion score per character for GM review (botreview.lua, pure logic botreview_core.lua,
-- tests/botreview_test.lua, tests/botreview_load_test.lua; server/README.md "Bot detection"). Loaded as
-- Chaos.botReviewConfig. Data only. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Nothing here punishes. A high daily score only puts the character on the review list (website staff page
-- page.php?plugin=chaos&p=botreview, /botreview, admin panel Accounts & Security). Staff decide with the GM handbook.
--
-- Two families of signals, each 0 (human-like) .. 1 (bot-like):
--   automation  what the allowed client helper also does: regular action timing, instant heals, heals at one HP
--               threshold, instant retargeting, regular looting. Never enough on its own.
--   unattended  signs that nobody is at the keyboard: no break for many hours, no human "noise" (chat, looks, turns,
--               inventory clicks, short pauses), the same route hour after hour, a missed presence check while still
--               fighting, actions in lockstep with another character of the same connection or party.
-- score = 100 x U x (automationBase + (1 - automationBase) x A), U cut by unattendedSingleFactor while fewer than
-- unattendedMinElevated unattended signals are at elevatedAt or more. A helper user (A high, U low) stays low; a human
-- without the helper who plays long and silent (A low) stays under flagAt; an unattended bot (both high) is flagged.
return {
	enabled = true,
	staffGroup = 4, -- never scored (as antibot_config.lua)
	evalSeconds = 300, -- one evaluation per character every 5 minutes
	keepOfflineMinutes = 30, -- the state of a character that logged out is kept this long (a relog keeps it)

	-- ------------------------------------------------------------------ automation signals
	heal = {
		-- HP % at an own heal (spell, rune, potion) that follows a hit: the interval [HP now, HP before the hits of the
		-- last lookbackMs) must hold the healer's threshold. A threshold healer fits one threshold almost every time.
		ring = 40,
		lookbackMs = 700,
		maxPct = 96, -- a heal at this HP % or more is a top-up, not a threshold
		minSamples = 15,
		shareFrom = 0.6, shareTo = 0.9 -- share of heals that fit the best threshold: 0 at From, 1 at To
	},
	retarget = {
		-- a kill, then the first attack on another monster within windowMs: the latency. Stands in for "a target
		-- appeared": tracking every monster that walks into view would cost a call per step.
		ring = 32,
		windowMs = 5000,
		minMs = 30,
		minSamples = 15,
		cvHuman = 0.35, cvBot = 0.12 -- robust spread of the latencies
	},

	-- ------------------------------------------------------------------ unattended signals
	silence = {
		-- human noise per active hour over the last 24 h: public chat lines, looks, turns on the spot, item moves that
		-- are not looting, pauses of idleSeconds .. 20 min. A bot makes almost none; a human with the helper still does.
		idleSeconds = 120,
		minActiveHours = 3, -- says nothing before this many active hours
		weights = {chat = 1, look = 1, turn = 0.5, inv = 0.5, idle = 2},
		rateHuman = 6, rateBot = 1 -- weighted noise per active hour: >= rateHuman 0, <= rateBot 1
	},
	route = {
		-- position samples (from antibot.lua, every 2 s) cut to cellSize cells; three cells in a row make a key; the
		-- keys of one hour form a set. The same route for hours gives nearly the same set every hour.
		cellSize = 4,
		maxPerHour = 400, -- keys kept per hour (bounded memory)
		minPerHour = 30, -- an hour with fewer keys (town, depot, a quiet hour) breaks a run
		simAt = 0.55, -- Jaccard similarity of two consecutive hours that counts as "the same route"
		fromHours = 3, toHours = 6 -- the longest run of same-route hours in the last 24: 0 at From, 1 at To
	},
	presence = {
		-- the presence check of antibot.lua: a failure while the character kept acting is the strongest sign
		windowHours = 24,
		ignoredActive = 1.0, -- missed or wrong while still fighting / walking
		ignoredIdle = 0.4, -- missed while idle: maybe away from the keyboard, maybe asleep in town
		passFactor = 0.5, -- a passed check in the window multiplies U by this
		-- random checks: rare, the same small modal, the same PvP / boss / rift deferral and daily limits as antibot.lua
		random = {
			enabled = true,
			afterHours = 2, -- only in a streak of at least this many active hours
			everyActiveHours = 8, -- about one per this many active hours
			minGapHours = 20 -- never two random checks closer than this per character
		}
	},
	cluster = {
		-- characters of one IP or one party: share of A's actions within windowMs of one of B's, over what chance
		-- gives at B's rate. Two people (or one person on two clients) do not act in the same 120 ms again and again.
		ring = 64,
		windowMs = 120,
		minActions = 24,
		everySeconds = 300,
		pairsPerTick = 100, -- pairs compared per 10 s tick (a pass of 800 pairs takes 80 s; no tick stalls the loop)
		maxGroup = 10, -- parties larger than this are checked by their first members only
		from = 0.25, to = 0.6 -- excess synchrony: 0 at From, 1 at To
	},

	-- ------------------------------------------------------------------ the score
	automation = {timing = 0.8, reaction = 0.6, loot = 0.6, heal = 0.7, retarget = 0.6},
	unattended = {nonstop = 0.8, silence = 0.8, route = 0.6, loop = 0.5, presence = 0.9, cluster = 0.6},
	elevatedAt = 0.5,
	unattendedMinElevated = 2,
	unattendedSingleFactor = 0.5,
	automationBase = 0.55,

	-- ------------------------------------------------------------------ the day
	minEvalsPerHour = 6, -- an hour counts with at least 30 minutes of evaluations
	storeAt = 25, -- a day is written to chaos_bot_daily once its score reaches this (less data kept)
	flagAt = 50, -- the day is on the review list
	-- the daily score is the second highest hourly mean (one odd hour never flags); a day with one hour: half of it

	-- ------------------------------------------------------------------ tables and retention
	tables = {daily = "chaos_bot_daily", actions = "chaos_bot_actions"},
	retention = {
		days = 30, -- chaos_bot_daily rows
		escalatedDays = 90, -- an escalated day stays this long (the case may become a ban and an appeal)
		actionDays = 90 -- chaos_bot_actions (who marked what)
	},
	purgeEverySeconds = 86400,
	requestPollSeconds = 60 -- presence checks requested from the website panel are picked up this often
}
