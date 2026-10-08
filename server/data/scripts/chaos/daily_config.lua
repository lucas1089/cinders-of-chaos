-- Daily reward login streaks (daily.lua, daily_core.lua, client game_daily). Returned as a table, loaded as
-- Chaos.dailyStreak. The 7 daily rewards, the week bonus and openOnLogin stay in Chaos.daily (chaos_constants.lua).
-- See server/README.md "Daily reward and login streaks". Lua 5.1 / LuaJIT compatible.
return {
	-- the daily reward and the streak are per account (all characters share one claim a day); DB table, sql/chaos.sql
	table = "chaos_daily_account",

	-- grace: one charge per `graceEvery` claimed days of a streak, `graceMax` stored at most; a charge covers one
	-- missed day, and at most `graceMaxMissed` missed days in a row can be covered
	graceEvery = 7,
	graceMax = 2,
	graceMaxMissed = 1,

	-- milestones: paid together with the daily reward of the day the streak reaches `days` (all or nothing with it),
	-- every time a streak gets there. `title`: shown in the look text of every character of the account while its
	-- best streak ever is at least `days` (the highest one wins). Server item ids: 29856 Chaos Orb, 29857 Divine Orb,
	-- 29855 Exalted Orb, 2160 crystal coin.
	milestones = {
		{days = 7, items = {{itemId = 29856, count = 2}, {itemId = 29857, count = 1}}},
		{days = 14, items = {{itemId = 29856, count = 3}, {itemId = 29857, count = 2}}},
		{days = 30, items = {{itemId = 29856, count = 5}, {itemId = 29857, count = 3}, {itemId = 29855, count = 1}},
			title = "the Devoted"},
		{days = 60, items = {{itemId = 29856, count = 8}, {itemId = 29857, count = 5}, {itemId = 29855, count = 2}}},
		{days = 100, items = {{itemId = 29856, count = 12}, {itemId = 29857, count = 8}, {itemId = 29855, count = 3},
			{itemId = 2160, count = 10}}, title = "the Relentless"},
		{days = 180, items = {{itemId = 29856, count = 20}, {itemId = 29857, count = 12}, {itemId = 29855, count = 5},
			{itemId = 2160, count = 25}}, title = "the Undying"}
	},

	-- login windows (ChaosLoginWindows in daily.lua): the order of the windows that open by themselves at login
	-- (low first) and how long to wait for the client to report one closed before the next is sent anyway
	loginOrder = {daily = 20},
	loginWindowMaxWaitMs = 90000
}
