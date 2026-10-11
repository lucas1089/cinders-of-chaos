-- Guild wars in game and the weekly guild boss (data/scripts/chaos/guildwar.lua, guildboss.lua; numbers in
-- guildwar_config.lua / guildboss_config.lua; see server/README.md "Guild wars in game" and "The weekly guild boss").
-- Safe to run more than once (CREATE TABLE IF NOT EXISTS); the scripts create the same tables at startup when missing.
-- An accepted war is also a row of the base server's `guild_wars` (status 1; ended: status 4), which the engine reads
-- for the war emblems and skull rules; these tables hold what the base one has no room for.
-- chaos_guildwar: one row per declaration: the guilds, the realm, the terms (frag limit, hours, stake per side), the
--   status (pending, active, ended, declined, cancelled, expired), the score (counted kills), the winner (0 = draw),
--   the end reason, the gold held (escrow1 / escrow2) and paid out (payout) or burnt (fee). war_id = guild_wars.id.
-- chaos_guildwar_kills: every war kill with its verdict (counted, or the anti-farming reason it did not count).
-- chaos_guildboss_week: per guild and week (YYYYMMDD of the Monday): the Summoning Stone's fuel (embers), the summons
--   used, the kill (killed_at, best_seconds, players) and the damage of every attempt (the weekly board).
-- chaos_guildboss_contrib: per guild, week and member: the gold given and the embers it and the materials made.
-- chaos_guildboss_runs: one row per attempt (players, result, seconds, damage).

CREATE TABLE IF NOT EXISTS `chaos_guildwar` (`id` int(11) NOT NULL AUTO_INCREMENT, `war_id` int(11) NOT NULL DEFAULT 0,
  `guild1` int(11) NOT NULL, `guild2` int(11) NOT NULL, `name1` varchar(255) NOT NULL DEFAULT '',
  `name2` varchar(255) NOT NULL DEFAULT '', `realm` int(11) NOT NULL DEFAULT 0, `frag_limit` int(10) unsigned NOT NULL DEFAULT 0,
  `hours` int(10) unsigned NOT NULL DEFAULT 0, `stake` bigint(20) unsigned NOT NULL DEFAULT 0,
  `status` varchar(12) NOT NULL DEFAULT 'pending', `declared_by` int(11) NOT NULL DEFAULT 0,
  `declared_at` int(10) unsigned NOT NULL DEFAULT 0, `expires_at` int(10) unsigned NOT NULL DEFAULT 0,
  `started_at` int(10) unsigned NOT NULL DEFAULT 0, `ends_at` int(10) unsigned NOT NULL DEFAULT 0,
  `ended_at` int(10) unsigned NOT NULL DEFAULT 0, `kills1` int(10) unsigned NOT NULL DEFAULT 0,
  `kills2` int(10) unsigned NOT NULL DEFAULT 0, `winner` int(11) NOT NULL DEFAULT 0, `reason` varchar(12) NOT NULL DEFAULT '',
  `escrow1` bigint(20) unsigned NOT NULL DEFAULT 0, `escrow2` bigint(20) unsigned NOT NULL DEFAULT 0,
  `payout` bigint(20) unsigned NOT NULL DEFAULT 0, `fee` bigint(20) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`),
  KEY `chaos_guildwar_status` (`status`), KEY `chaos_guildwar_guild1` (`guild1`), KEY `chaos_guildwar_guild2` (`guild2`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_guildwar_kills` (`id` int(11) NOT NULL AUTO_INCREMENT, `war_id` int(11) NOT NULL,
  `at` int(10) unsigned NOT NULL, `killer_id` int(11) NOT NULL DEFAULT 0, `killer_name` varchar(255) NOT NULL DEFAULT '',
  `killer_guild` int(11) NOT NULL DEFAULT 0, `victim_id` int(11) NOT NULL DEFAULT 0, `victim_name` varchar(255) NOT NULL DEFAULT '',
  `victim_guild` int(11) NOT NULL DEFAULT 0, `victim_level` int(10) unsigned NOT NULL DEFAULT 0,
  `counted` tinyint(1) unsigned NOT NULL DEFAULT 0, `reason` varchar(16) NOT NULL DEFAULT '', PRIMARY KEY (`id`),
  KEY `chaos_guildwar_kills_war` (`war_id`, `id`), KEY `chaos_guildwar_kills_victim` (`war_id`, `victim_id`, `counted`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_guildboss_week` (`guild_id` int(11) NOT NULL, `week` int(10) unsigned NOT NULL,
  `fuel` int(10) unsigned NOT NULL DEFAULT 0, `attempts` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `killed_at` int(10) unsigned NOT NULL DEFAULT 0, `best_seconds` int(10) unsigned NOT NULL DEFAULT 0,
  `damage` bigint(20) unsigned NOT NULL DEFAULT 0, `players` smallint(5) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`guild_id`, `week`), KEY `chaos_guildboss_week_week` (`week`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_guildboss_contrib` (`guild_id` int(11) NOT NULL, `week` int(10) unsigned NOT NULL,
  `player_id` int(11) NOT NULL, `name` varchar(255) NOT NULL DEFAULT '', `gold` bigint(20) unsigned NOT NULL DEFAULT 0,
  `embers` int(10) unsigned NOT NULL DEFAULT 0, `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`guild_id`, `week`, `player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_guildboss_runs` (`id` int(11) NOT NULL AUTO_INCREMENT, `guild_id` int(11) NOT NULL,
  `week` int(10) unsigned NOT NULL, `started_at` int(10) unsigned NOT NULL DEFAULT 0, `ended_at` int(10) unsigned NOT NULL DEFAULT 0,
  `players` smallint(5) unsigned NOT NULL DEFAULT 0, `result` varchar(12) NOT NULL DEFAULT '', `seconds` int(10) unsigned NOT NULL DEFAULT 0,
  `damage` bigint(20) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `chaos_guildboss_runs_guild` (`guild_id`, `week`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;
