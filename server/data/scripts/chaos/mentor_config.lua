-- Mentor system: every rule, number and text in one place. Read by mentor.lua (Chaos.mentorConfig), mentor_core.lua
-- (pure rules), server/tests/mentor_test.lua and the website (website/overlay/plugins/chaos/mentor_lib.php reads the
-- tables only). The engine also loads this file as a script because it lives under data/scripts; it only returns a
-- table. See server/README.md "Mentors". Lua 5.1 / LuaJIT and 5.3.
--
-- Nothing here gives power above what a new player can already get: the apprentice's bonus only works while the two
-- hunt together at the apprentice's level, Mentor Marks buy titles, cosmetics and supplies (the store's rule: no gear,
-- no orbs, no stats).
return {
	enabled = true,

	-- DB tables (server/sql/chaos_mentor.sql; mentor.lua creates them at startup too)
	tables = {
		mentors = "chaos_mentors", -- one row per registered mentor character: settings, marks, graduates, today's hunt
		links = "chaos_mentor_links", -- one row per mentor / apprentice link (active, dismissed, released, graduated)
		milestones = "chaos_mentor_milestones", -- one row per apprentice character and milestone (paid / unearned / ...)
		purchases = "chaos_mentor_purchases", -- the Mentor Marks shop log (also its weekly limits)
		log = "chaos_mentor_log" -- every registration, link, refusal, milestone, graduation, purchase
	},

	-- player storages, 7100360 - 7100369 reserved (chaos_constants.lua Chaos.storage.mentor): +0 "looking for a mentor"
	storage = {seeking = 7100360},

	-- who may register as a mentor: the ACCOUNT is a veteran (its best character, its total online time, its age);
	-- the mentoring character itself only needs minCharacterLevel, so a veteran can mentor with a character of the
	-- apprentice's level (the bonus needs that, see overLevel)
	mentor = {
		minAccountLevel = 150, -- a character of the account reached this level
		minOnlineHours = 100, -- players.onlinetime of every character of the account together
		minAccountDays = 30, -- account age (accounts.creation, else znote_accounts.created)
		minCharacterLevel = 20, -- the mentoring character
		maxApprentices = 3, -- active apprentices at a time
		monthlyLinks = 6, -- new apprentices per calendar month (server time)
		langMax = 24, hoursMax = 24, noteMax = 80 -- the free texts of the mentor card
	},

	-- who may pick a mentor: a new character on a new account
	apprentice = {
		maxLevel = 79, -- at most this level when the link is made
		maxAccountDays = 60, -- the account is at most this old
		maxMentors = 3, -- mentors one character may ever have (dismissed / released ones count)
		dismissCooldownHours = 24 -- after a dismiss or a release, before another mentor
	},
	graduationLevel = 200, -- the apprentice graduates: both get the graduation reward, the link ends
	inviteMinutes = 10, -- an invitation waits this long
	staffAccountType = 2, -- staff accounts (and characters of staffGroup or higher) take no part
	staffGroup = 2,

	-- the bonuses while grouped: same party, both online, the mentor within `range` tiles on the same floor, no shared
	-- IP right now, and the mentor not far over the content: mentor level <= max(apprentice level, monster level) x
	-- ratio + flat (the monster level: bounty_pool.lua, else estimated from experience and health)
	bonus = {
		exp = 0.10, -- apprentice: +10% experience from monsters (onGainExperience)
		damageTaken = 0.05, -- apprentice: 5% less damage from monsters (onHealthChange / onManaChange)
		range = 30
	},
	overLevel = {ratio = 1.5, flat = 20},

	-- Mentor Marks (per mentor character; earned, never bought)
	marks = {
		huntMinutes = 30, -- shared hunting time: one mark per this many minutes in a day (a minute counts when an
		--                   apprentice got experience with the bonus in it)
		dailyHuntMarks = 4, -- per mentor and day, all apprentices together
		monthlyCap = 300, -- marks a mentor can earn per calendar month (milestones and hunting); more are not paid
		milestoneMinShared = 30, -- a milestone pays only after this many shared minutes with that apprentice
		graduationMinShared = 120 -- the graduation pays (both sides) only after this many shared minutes
	},

	-- the apprentice's milestones; each pays once per apprentice character (another mentor never gets it again).
	-- kind "level": the level; "event": the first time (rift = a sealed rift, dungeon = a finished dungeon run,
	-- bounty = a bounty contract, worldboss = a world boss reward). Reached before the link: "before", no marks.
	milestones = {
		{key = "l25", kind = "level", level = 25, marks = 5, name = "Level 25"},
		{key = "l50", kind = "level", level = 50, marks = 10, name = "Level 50"},
		{key = "l100", kind = "level", level = 100, marks = 20, name = "Level 100"},
		{key = "rift", kind = "event", event = "rift", marks = 10, name = "First rift sealed"},
		{key = "dungeon", kind = "event", event = "dungeon", marks = 10, name = "First dungeon"},
		{key = "bounty", kind = "event", event = "bounty", marks = 5, name = "First bounty contract"},
		{key = "worldboss", kind = "event", event = "worldboss", marks = 5, name = "First world boss"}
	},

	-- graduation (graduationLevel, shown as the last milestone "Level 200: graduation")
	graduation = {
		marks = 50, -- to the mentor; the mentor's graduate count +1 (the Mentor achievements and the leaderboard)
		items = { -- to the apprentice (backpack, else the depot inbox)
			{id = 7618, count = 100, name = "health potions"},
			{id = 7620, count = 100, name = "mana potions"}
		}
		-- the titles of both sides come from achievements_data.lua (stats mentor_graduates and mentor_fledged)
	},

	-- the Mentor Marks shop. kind "title": a name plate title of this character (ChaosTitles source "mentor");
	-- "cosmetic": a cosmetic of cosmetics_config.lua, unlocked for the account (as the store does); "item": supplies
	-- (only ids of supplyIds), `weekly` = at most this many per character and week.
	-- The week: Monday weekResetHour (the bounty board's week, ChaosBounty.week). Until shopWeekGraceUntil the later of
	-- that and the old Monday 00:00 start counts (the one-time switch from Monday 00:00; mentor_core.lua shopWeekStart).
	weekResetHour = 6,
	shopWeekGraceUntil = os.time({year = 2026, month = 10, day = 19, hour = 6, min = 0, sec = 0}),
	shop = {
		{key = "title_lantern", kind = "title", cost = 40, name = "Lanternbearer", color = "#f0c060",
			desc = "A name plate title for those who light the way."},
		{key = "title_pathfinder", kind = "title", cost = 90, name = "Pathfinder", color = "#e0a040",
			desc = "A name plate title for a mentor who knows every road."},
		{key = "title_wayshower", kind = "title", cost = 160, name = "Wayshower", color = "#ffb85c",
			desc = "A name plate title for the patient guides of the realm."},
		{key = "cos_loot_ember", kind = "cosmetic", cost = 100, cosmetic = "loot_ember", name = "Ember Labels",
			desc = "Loot label accent (account-wide), the same as the store's."},
		{key = "cos_chat_cinder", kind = "cosmetic", cost = 140, cosmetic = "chat_cinder", name = "Cinder Name",
			desc = "Chat name colour (account-wide), the same as the store's."},
		{key = "cos_kill_soulspark", kind = "cosmetic", cost = 140, cosmetic = "kill_soulspark", name = "Soul Spark",
			desc = "Kill effect (account-wide), the same as the store's."},
		{key = "sup_health", kind = "item", cost = 6, item = 7618, count = 50, weekly = 3, name = "50 Health Potions",
			desc = "Supplies for a hunt with your apprentice."},
		{key = "sup_mana", kind = "item", cost = 6, item = 7620, count = 50, weekly = 3, name = "50 Mana Potions",
			desc = "Supplies for a hunt with your apprentice."}
	},
	-- the only items the shop may sell (potions); the test refuses anything else
	supplyIds = {7618, 7620},

	-- base classes for the browse filter (Chaos.classes.baseOf of the mentor's vocation)
	lines = {
		{key = "warrior", name = "Warrior", base = 4}, {key = "ranger", name = "Ranger", base = 3},
		{key = "mystic", name = "Mystic", base = 1}, {key = "thief", name = "Thief", base = 11},
		{key = "monk", name = "Monk", base = 17}, {key = "necromancer", name = "Necromancer", base = 20},
		{key = "templar", name = "Templar", base = 23}
	},
	listMax = 40, -- mentors in one browse answer
	topMax = 10, -- mentors on the graduates leaderboard

	-- Referral: a referred account's first character (the one the referral tracks) gets the referrer's mentor
	-- character at login when it has none and every check passes (the apprentice can dismiss it like any mentor)
	referral = {autoPick = true},

	messages = {
		disabled = "The mentor system is off.",
		staff = "Staff accounts take no part in the mentor system.",
		banned = "This account cannot take part right now.",
		mentorLevel = "To mentor, a character of your account must have reached level %d.",
		mentorHours = "To mentor, your account needs %d hours of play.",
		mentorAge = "To mentor, your account must be at least %d days old.",
		mentorCharLevel = "This character must be level %d to mentor.",
		isApprentice = "A character with a mentor cannot mentor.",
		registered = "This character is already a mentor.",
		notMentor = "This character is not a mentor.",
		hasApprentices = "Release your apprentices first.",
		apprenticeLevel = "Only characters up to level %d can pick a mentor.",
		apprenticeAge = "Only accounts up to %d days old can pick a mentor.",
		isMentor = "A mentor cannot pick a mentor.",
		hasMentor = "You already have a mentor.",
		graduated = "This character has graduated already.",
		maxMentors = "This character has had %d mentors already.",
		cooldown = "You can pick another mentor in %s.",
		noMentor = "That mentor is gone.",
		notAccepting = "This mentor takes no new apprentices right now.",
		full = "This mentor has no free place.",
		monthlyLinks = "This mentor has taken enough new apprentices this month.",
		sameAccount = "You cannot mentor your own account.",
		sameIp = "A mentor and an apprentice cannot share a connection.",
		sameEmail = "A mentor and an apprentice cannot share an e-mail domain.",
		pairBefore = "You were linked to this mentor before.",
		mentorBanned = "This mentor cannot take apprentices right now.",
		mentorStaff = "Staff characters cannot mentor.",
		offline = "That player is not online.",
		noInvite = "That invitation is gone.",
		noApprentice = "That apprentice is not yours.",
		notEnough = "Not enough Mentor Marks.",
		owned = "You own this already.",
		weekly = "Weekly limit reached for this offer.",
		noRoom = "No room for it: free some space first.",
		unknownOffer = "Unknown offer.",
		cosmeticOff = "Cosmetics are not available right now.",
		linked = "%s is now your mentor. Hunt together for the bonus: +%d%% experience and %d%% less damage taken.",
		linkedMentor = "%s is now your apprentice.",
		autoLinked = "Your referrer's character %s is now your mentor. You can dismiss them in Social > Mentors.",
		invited = "%s invites you to be their apprentice: Social > Mentors.",
		inviteSent = "Invitation sent to %s.",
		dismissed = "You dismissed your mentor %s.",
		dismissedMentor = "Your apprentice %s dismissed you.",
		released = "You released %s.",
		releasedApprentice = "Your mentor %s released you.",
		milestone = "Your apprentice %s: %s. +%d Mentor Marks.",
		milestoneUnearned = "Your apprentice %s: %s. No marks: hunt together first.",
		milestoneCapped = "Your apprentice %s: %s. Monthly marks limit reached.",
		huntMark = "+1 Mentor Mark for hunting with your apprentice (%d / %d today).",
		graduatedMentor = "Your apprentice %s graduated! +%d Mentor Marks.",
		graduatedApprentice = "You graduated from your mentor %s: %s.",
		graduatedUnearned = "%s reached level %d and leaves the mentorship (not enough time hunting together for a reward).",
		bought = "Bought: %s.",
		registeredOk = "You are a mentor now. New players can find you in Social > Mentors.",
		retired = "You are no longer a mentor.",
		saved = "Mentor card saved."
	}
}
