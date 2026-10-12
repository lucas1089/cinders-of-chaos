-- Seasonal Journey (data/scripts/chaos/season_journey.lua, season_journey_config.lua). Run after the stock TFS schema
-- (players):  mysql -u USER -p DB < chaos_season_journey.sql   (season_journey.lua also creates them at startup)

-- Journey counters of a season character, per season (stat = a key of season_journey_config.lua `stats`).
CREATE TABLE IF NOT EXISTS `chaos_season_journey_stats` (
  `season` smallint(5) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  `stat` varchar(32) NOT NULL,
  `value` bigint(20) NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`season`, `player_id`, `stat`),
  CONSTRAINT `chaos_season_journey_stats_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Done objectives ("o:<key>") and finished chapters ("c:<key>", rewards given) of a character, per season. A chapter
-- row exists once: it is written before the chapter's rewards are given.
CREATE TABLE IF NOT EXISTS `chaos_season_journey` (
  `season` smallint(5) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  `entry` varchar(40) NOT NULL,
  `done_at` int(10) unsigned NOT NULL,
  PRIMARY KEY (`season`, `player_id`, `entry`),
  CONSTRAINT `chaos_season_journey_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
