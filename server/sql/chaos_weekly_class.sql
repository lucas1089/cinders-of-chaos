-- Weekly class ranking (O409; data/scripts/chaos/weekly_class.lua, weekly_class_core.lua; server/README.md "Weekly class
-- ranking (O409)"). The podium of every class tab of a class board (leaderboard_config.lua classAwards) at the weekly
-- reset: week = the week that ended (YYYYMMDD of its Monday), class_base = the base class id of the tab, tokens = the
-- Conquest Tokens given. The rows of a week also keep a second reset of the same week from paying twice. Rows older than
-- keepWeeks (weekly_class_config.lua) are deleted at the reset. weekly_class.lua creates the table at startup too
-- (ChaosWeeklyClassCore.schemaSql; the test compares). Safe to run more than once.

CREATE TABLE IF NOT EXISTS `chaos_weekly_class_podium` (`week` int unsigned NOT NULL, `board` varchar(16) NOT NULL, `class_base` smallint unsigned NOT NULL, `rank` tinyint unsigned NOT NULL, `player_id` int NOT NULL, `value` bigint unsigned NOT NULL DEFAULT 0, `tokens` smallint unsigned NOT NULL DEFAULT 0, `awarded_at` int unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`week`, `board`, `class_base`, `rank`), KEY `player` (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;
