-- Purge of old moderation records (moderation_purge.lua, moderation_purge_core.lua). Every number of it.
-- Returned as a table, loaded as Chaos.moderationPurgeConfig (and by server/tests/moderation_purge_test.lua). Data only.
-- See server/README.md "Moderation record purge".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,

	-- Days a record is kept. The Privacy Policy (docs/legal/privacy.pt-BR.md and privacy.en.md, section 4)
	-- names this period as [PRAZO DOS REGISTROS DE MODERAÇÃO]. When the owner fills that placeholder, set these numbers
	-- to the same period (docs/legal/README.md "Placeholders"). 730 = 2 years, the suggestion there. 0 = never purged.
	-- A closed report counts from the day it was closed; a cleared hold from the day it was cleared.
	days = {
		reports = 730, -- chaos_reports: player reports and bug reports, with their public chat lines
		antibotLog = 730, -- chaos_antibot_log: scores and presence checks
		antibotHolds = 730, -- chaos_antibot_holds: cleared leaderboard holds
		adminLog = 730 -- chaos_admin_log: every admin panel action and guarded staff command
	},

	-- Never purged, whatever their age:
	--   an open report and an uncleared hold (staff have not decided yet);
	--   any record about an account whose ban is active, or ended less than appealDays ago (an appeal on Discord may
	--   still be open; base tables account_bans and account_ban_history);
	--   the admin log line of an IP ban that is still active (or ended less than appealDays ago).
	appealDays = 30,

	tables = {
		reports = "chaos_reports",
		antibotLog = "chaos_antibot_log",
		antibotHolds = "chaos_antibot_holds",
		adminLog = "chaos_admin_log"
	},

	runEverySeconds = 86400, -- one purge a day
	checkSeconds = 3600, -- the globalevent looks every hour whether a day passed (server_config chaos_moderation_purge)
	batch = 500, -- candidate rows read per query
	maxBatches = 200, -- per table and run at most (the rest waits for the next day)
	ipBanWindowSeconds = 120 -- an IP ban row and its admin log line are written within this many seconds
}
