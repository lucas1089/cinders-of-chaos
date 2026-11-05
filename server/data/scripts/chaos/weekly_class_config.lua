-- The weekly class boards (O409; weekly_class.lua, weekly_class_core.lua, tests/weekly_class_test.lua; server/README.md
-- "Weekly class ranking (O409)"). Plain table, loaded with
--     ChaosWeeklyClassConfig = dofile("data/scripts/chaos/weekly_class_config.lua")
-- A weekly leaderboard board ranked per class: the experience every character gains from monsters this week. It is a
-- board of leaderboard_config.lua (weekly_xp, classAwards: no overall title, no orbs); this file feeds it and closes its
-- week: at the leaderboard reset (Monday, leaderboard_config.lua resetHour) the top of every class tab gets Conquest
-- Tokens, a broadcast names the class winners and the Discord queue gets one "weekly_class" post with the podium of
-- every class. Fair: each class competes with itself, so a class that levels faster never takes every reward.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,

	-- the board (leaderboard_config.lua boards, key weekly_xp, mode "add", classAwards = true)
	board = "weekly_xp",

	-- ------------------------------------------------------------------ the experience
	-- an EventCallback onGainExperience at this index: after every bonus and the caps (xpcap 85, dungeons 90, rift 100,
	-- xp_rate_display 999, the hunt tracker 1000, the Ember Cache 1001), before the party diagnosis (2000). Only a
	-- monster kill counts (no quest, no store item, no staff command).
	expIndex = 1500,
	-- the experience gained is kept in memory and written to the board once a minute and at logout (one row update per
	-- active character a minute, as the Reputation board)
	flushSeconds = 60,

	-- ------------------------------------------------------------------ the week's end
	-- the 1st, 2nd and 3rd of every class tab (base class and its ascensions) get these Conquest Tokens (conquest.lua,
	-- log source "weekly_class"). The same amounts as the Weekly Challenge's class rewards: 7 classes x 60 = at most 420
	-- tokens a week on the whole server, 60 for one character.
	tokens = {30, 20, 10},
	rewardTop = 3,
	-- a character needs at least this much experience this week to be rewarded or posted (no reward for a quiet week)
	minValue = 1000,
	-- the Discord post (discord_core.lua D.weeklyClass; discord_config.lua events.weekly_class): the top 3 of each class
	discordTop = 3,
	-- one broadcast line with the 1st of every class
	broadcast = true,
	-- table of the podium (server/sql/chaos_weekly_class.sql): one row per week, board, class and rank. It also keeps
	-- the reset from paying twice (a /leaderboard reset of the same week finds its rows and skips)
	table = "chaos_weekly_class_podium",
	keepWeeks = 12
}
