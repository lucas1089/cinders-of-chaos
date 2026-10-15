-- Anti-bot behaviour detection, presence check and player reports: the numbers (antibot.lua, reports.lua; pure logic in
-- antibot_core.lua and reports_core.lua; tests/antibot_test.lua; server/README.md "Anti-bot and player reports").
-- Loaded as Chaos.antibotConfig. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Nothing here bans anyone. A high suspicion score asks the player for a presence check and writes a staff log entry;
-- staff decide.
return {
	enabled = true,
	staffGroup = 4, -- group id from which a character is staff: never scored or checked, may use /reports

	-- ------------------------------------------------------------------ sampling (antibot.lua)
	sampleMs = 2000, -- position sample of every online character (one getPosition per player)
	evalSeconds = 60, -- signals and score are recomputed this often per character
	keepOfflineMinutes = 30, -- the rolling stats of a character that logged out are kept this long (a relog keeps them)

	-- ------------------------------------------------------------------ the signals (antibot_core.lua)
	-- Every signal is 0 (human-like) .. 1 (bot-like) and needs a minimum of samples before it says anything.
	timing = {
		-- deliberate actions per kind: every spell (engine patch 0008, spell events on) and own heals (spells, runes,
		-- potions); the rhythm of each kind on its own, so a fixed-delay rotation shows through other actions
		ring = 32, -- intervals kept per kind
		maxKinds = 8, -- kinds kept per character (the one used longest ago is dropped)
		dedupeMs = 60, -- a spell event and its heal in the same moment are one action
		minIntervalMs = 300, maxIntervalMs = 20000, -- intervals outside are not rhythm (double events, breaks)
		readySlackMs = 150, -- a cast within this of its spell / group cooldown ending is a held hotkey: no interval
		cooldownMs = 1000, cooldownSlackMs = 120, -- without the engine's cooldowns (own heals): intervals within
		-- +-slack of a multiple of the group cooldown count as a held hotkey
		minSamples = 20,
		cvHuman = 0.15, cvBot = 0.05 -- robust spread (1.4826 x MAD / median): >= cvHuman scores 0, <= cvBot scores 1
	},
	reaction = {
		-- an own heal that is not part of a heal train (no own heal in isolateMs before it) and comes within windowMs of
		-- a hit taken: its latency (server side, so it includes the ping)
		ring = 24,
		windowMs = 1500,
		isolateMs = 2500,
		fastMs = 250, -- "instant" (ping + a reflex of a few ms)
		minSamples = 10,
		fastShareFrom = 0.5, fastShareTo = 0.9, -- share of instant reactions: 0 at From, 1 at To ...
		spreadBotMs = 40, spreadHumanMs = 90 -- ... times the tightness: standard deviation <= spreadBotMs 1, >= spreadHumanMs 0
	},
	loop = {
		-- coarse position cells: the map cut into cellSize x cellSize squares per floor; only changes of cell are kept,
		-- so the time a fight takes does not matter
		cellSize = 8,
		ring = 192, -- cell changes kept (a hunt of 20 - 60 minutes)
		minTransitions = 48,
		minPeriod = 4, maxPeriod = 60, -- loop length in cell changes
		minDistinct = 5, -- a loop must cover this many different cells (walking between two cells is no loop)
		minRepeats = 3, -- the history must hold the loop at least this many times
		minRepeatShare = 0.4, -- at least this share of the steps between cells must have been walked before
		matchFrom = 0.7, matchTo = 0.92, -- share of the repeated steps that come back after about 1, 2 or 3 laps
		fightMs = 4000, -- a hit taken or an action this recently: fighting, the cell is not stored
		everySeconds = 300 -- the loop search runs at most this often per character (the costliest signal)
	},
	loot = {
		-- items taken out of a corpse by hand (onItemMoved): the gaps between two moves of one looting burst
		ring = 32,
		burstMs = 2500, -- a longer gap starts a new burst (another corpse)
		minIntervalMs = 40,
		minSamples = 16,
		cvHuman = 0.22, cvBot = 0.08
	},
	nonstop = {
		breakMinutes = 20, -- this long without any activity (or offline) ends a streak
		streakFromHours = 8, streakToHours = 14, -- one streak without a break: 0 at From, 1 at To
		dayFromHours = 18, dayToHours = 22 -- active hours in the last 24: 0 at From, 1 at To
	},

	-- ------------------------------------------------------------------ the score
	-- add per evaluation = sum(weight x signal); fewer than `minElevated` signals at or over `elevatedAt` multiply the
	-- add by `singleFactor`. The score decays with `halfLifeMinutes`. With a 60 s evaluation and a 60 min half-life
	-- the steady score of a constant add is about 87 x add: one maxed signal alone (at most 1.2 x 0.35 = 0.42) stays
	-- near 37, under every threshold; two strong signals reach the check in about half an hour.
	weights = {timing = 1.2, reaction = 1.2, loop = 0.8, loot = 0.8, nonstop = 0.6},
	elevatedAt = 0.5,
	minElevated = 2,
	singleFactor = 0.35,
	halfLifeMinutes = 60,
	maxScore = 500,

	-- ------------------------------------------------------------------ the presence check
	check = {
		enabled = true,
		at = 60, -- score that asks for a check
		timeLimitSeconds = 75, -- 60 - 90
		retries = 1, -- one more picture after a wrong click or "Another picture" (accessibility)
		retrySeconds = 45, -- time for the retry (at least)
		minGapHours = 4, -- never two checks closer than this per character
		maxPerDay = 2,
		graceHours = 8, -- after a passed check no new one for this long
		successFactor = 0.4, -- a passed check multiplies the score by this
		failPenalty = 40, -- a failed check adds this
		-- "log" (default: log only, a signal for staff) or "temple" (teleport to the temple + log). Never a kick: the check
		-- only adds a signal for a manual review (server/README.md "Bot detection"); "kick" is treated as "log".
		failAction = "log",
		deferMaxMinutes = 30, -- a check deferred (PvP, boss) longer than this is dropped; the score asks again later
		pvpSeconds = 60, -- a hit from or on a player this recently: in PvP combat
		bossSeconds = 45, -- a hit from or on a boss this recently: in a boss fight
		choices = 4,
		-- the pictures (server item ids of stock items) and the word shown; items of one group never appear together
		pool = {
			{id = 2674, word = "Apple", group = "red"}, {id = 2685, word = "Tomato", group = "red"},
			{id = 2676, word = "Banana"}, {id = 2667, word = "Fish"}, {id = 2671, word = "Ham"},
			{id = 2684, word = "Carrot"}, {id = 2696, word = "Cheese"}, {id = 2689, word = "Bread"},
			{id = 2681, word = "Grapes"}, {id = 2683, word = "Pumpkin"}, {id = 2789, word = "Mushroom"},
			{id = 2230, word = "Bone"}, {id = 2120, word = "Rope"}, {id = 2554, word = "Shovel"},
			{id = 2580, word = "Fishing Rod"}, {id = 2050, word = "Torch"}, {id = 2148, word = "Gold Coin"},
			{id = 1987, word = "Bag", group = "bag"}, {id = 1988, word = "Backpack", group = "bag"},
			{id = 2509, word = "Shield"}, {id = 2376, word = "Sword"}, {id = 2386, word = "Axe"},
			{id = 2456, word = "Bow", group = "bow"}, {id = 2455, word = "Crossbow", group = "bow"},
			{id = 2457, word = "Helmet"}, {id = 2643, word = "Boots"},
			{id = 7618, word = "Health Potion", group = "potion"}, {id = 7620, word = "Mana Potion", group = "potion"}
		}
	},

	-- ------------------------------------------------------------------ the staff log (chaos_antibot_log)
	log = {
		at = 120, -- score that writes a "score" entry
		cooldownHours = 6, -- per character, unless the score doubled since the last entry
		-- true: a character with a "score" or "check_fail" entry holds its account off the leaderboards (weekly boards,
		-- class ladder, season ladder, the website boards) until staff clear it (/reports clear <name>). Off by default.
		holdLeaderboards = false
	},

	-- ------------------------------------------------------------------ player reports (reports.lua, reports_core.lua)
	reports = {
		enabled = true,
		reasons = {
			{key = "botting", label = "Botting"},
			{key = "cheating", label = "Cheating / exploiting"},
			{key = "harassment", label = "Harassment"},
			{key = "scam", label = "Scam"},
			{key = "name", label = "Offensive name"},
			{key = "other", label = "Other"}
		},
		noteMax = 200, -- characters of the reporter's note ("other" needs one)
		cooldownSeconds = 60, -- between two reports of one reporter
		perDay = 5, -- reports per reporter account per day
		sameTargetHours = 24, -- one report per reporter and target in this time
		minLevel = 8, -- reporters below this level cannot report (fresh throw-away characters)
		chatLines = 10, -- last lines of the target in public channels stored with the report
		chatLineMax = 160,
		chatKeepMinutes = 30, -- the lines of a character that logged out are kept this long
		-- Discord webhook for new reports: empty = off. Never put the URL in the repository; the environment variable
		-- CHAOS_REPORTS_WEBHOOK overrides this value. Only https://discord.com/api/webhooks/... URLs are accepted. The post
		-- carries the report id, reason and the two names, never the chat lines or the note.
		discordWebhook = "",
		listMax = 30, -- rows of /reports list
		-- bug reports: System > Report a Bug (the base client's dialog) -> Player:onReportBug (tools/patch_base_events.py
		-- step 12) -> reports.lua RP.reportBug: a chaos_reports row with reason "bug", for every account
		bugs = {
			enabled = true,
			textMin = 6, -- the dialog wants 6 characters too; a client without base patch 0040 sends only "0".."3"
			textMax = 240, -- note = "[category] text" in chaos_reports.note (varchar 255)
			rapidMs = 5000, -- Chaos.limited: one bug report per character in this time
			cooldownSeconds = 30, -- per account, survives a relog
			perDay = 10 -- per account
		}
	}
}
