-- Achievements (data/scripts/chaos/achievements.lua; the list is achievements_data.lua). achievements.lua also creates
-- both tables at startup when they are missing. Run once: mysql -u USER -p DB < chaos_achievements.sql

-- one row per character and unlocked achievement (id of achievements_data.lua)
CREATE TABLE IF NOT EXISTS `chaos_achievements` (
  `player_id` int(11) NOT NULL,
  `achievement` varchar(48) NOT NULL,
  `unlocked_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `achievement`),
  CONSTRAINT `chaos_achievements_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- progress counters per character (kills_legendary, rift_tier, orbs_used, ...); values only go up
CREATE TABLE IF NOT EXISTS `chaos_achievement_stats` (
  `player_id` int(11) NOT NULL,
  `stat` varchar(48) NOT NULL,
  `value` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `stat`),
  CONSTRAINT `chaos_achievement_stats_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
