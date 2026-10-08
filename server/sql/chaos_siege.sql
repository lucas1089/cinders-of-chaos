-- Guild siege (data/scripts/chaos/siege.lua). Run after the stock TFS schema (guilds, players): mysql -u USER -p DB < chaos_siege.sql

-- Sign-ups: one row per guild and siege. siege_at = unix time of the scheduled start the sign-up belongs to (the rows of a
-- siege are deleted when it ends or is cancelled, and at startup when that start is more than an hour in the past).
CREATE TABLE IF NOT EXISTS `chaos_siege_signups` (
  `siege_at` int(10) unsigned NOT NULL,
  `guild_id` int(11) NOT NULL,
  `guild_name` varchar(255) NOT NULL,
  `signed_by` int(11) NOT NULL DEFAULT 0,
  `signed_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`siege_at`, `guild_id`),
  CONSTRAINT `chaos_siege_signups_guilds_fk` FOREIGN KEY (`guild_id`) REFERENCES `guilds` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Results: one row per guild and bracket (arena) of every siege that ended. winner = 1 for the bracket winner; the
-- champion title and the experience buff last titleDays after ended_at (loaded at startup).
CREATE TABLE IF NOT EXISTS `chaos_siege_results` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `siege_at` int(10) unsigned NOT NULL,
  `ended_at` int(10) unsigned NOT NULL,
  `bracket` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `guild_id` int(11) NOT NULL,
  `guild_name` varchar(255) NOT NULL,
  `place` tinyint(3) unsigned NOT NULL,
  `winner` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `score` int(10) unsigned NOT NULL DEFAULT 0,
  `kills` int(10) unsigned NOT NULL DEFAULT 0,
  `hold_seconds` int(10) unsigned NOT NULL DEFAULT 0,
  `members` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `chaos_siege_results_winner` (`winner`, `ended_at`),
  KEY `chaos_siege_results_guild` (`guild_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
