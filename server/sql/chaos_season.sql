-- Seasons (data/scripts/chaos/season.lua, season_config.lua). Run after the stock TFS schema (accounts, players):
--   mysql -u USER -p DB < chaos_season.sql

-- The season flag: one row per character that joined a season. migrated_at = 0 while it is a season character,
-- the unix time it became a standard character (season end) afterwards. A character joins at most one season.
CREATE TABLE IF NOT EXISTS `chaos_season_players` (
  `player_id` int(11) NOT NULL,
  `account_id` int(11) NOT NULL,
  `season` smallint(5) unsigned NOT NULL,
  `joined_at` int(10) unsigned NOT NULL,
  `migrated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`),
  KEY `chaos_season_players_season` (`season`, `migrated_at`),
  KEY `chaos_season_players_account` (`account_id`),
  CONSTRAINT `chaos_season_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Season-long stats of a season character (stat = a leaderboard board key: bounty, rift, worldboss, goblin).
CREATE TABLE IF NOT EXISTS `chaos_season_progress` (
  `season` smallint(5) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  `stat` varchar(24) NOT NULL,
  `value` bigint(20) NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`season`, `player_id`, `stat`),
  CONSTRAINT `chaos_season_progress_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Reward track milestones reached, per account and kept forever (also when the character that reached it is deleted).
CREATE TABLE IF NOT EXISTS `chaos_season_rewards` (
  `account_id` int(11) NOT NULL,
  `season` smallint(5) unsigned NOT NULL,
  `milestone` varchar(32) NOT NULL,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `player_name` varchar(255) NOT NULL DEFAULT '',
  `reached_at` int(10) unsigned NOT NULL,
  PRIMARY KEY (`account_id`, `season`, `milestone`),
  CONSTRAINT `chaos_season_rewards_fk` FOREIGN KEY (`account_id`) REFERENCES `accounts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Event log: join, migrate, milestone, admin (start / end).
CREATE TABLE IF NOT EXISTS `chaos_season_log` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `at` int(10) unsigned NOT NULL,
  `season` smallint(5) unsigned NOT NULL,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `event` varchar(16) NOT NULL,
  `detail` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `chaos_season_log_player` (`player_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Season modes (season_modes.lua): the mode a season character picked at the join. Kept after the season (history,
-- the fallen graves of the ladder). ssf / hc = Self-Found / Hardcore; fallen_at = the unix time a Hardcore character
-- died (0 = alive), with its level and the cause; reset_at = when the end of the season reset the mode (0 = running).
CREATE TABLE IF NOT EXISTS `chaos_season_modes` (
  `player_id` int(11) NOT NULL,
  `season` smallint(5) unsigned NOT NULL,
  `ssf` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `hc` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `chosen_at` int(10) unsigned NOT NULL,
  `fallen_at` int(10) unsigned NOT NULL DEFAULT 0,
  `fallen_level` int(10) unsigned NOT NULL DEFAULT 0,
  `fallen_cause` varchar(64) NOT NULL DEFAULT '',
  `reset_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`),
  KEY `chaos_season_modes_season` (`season`, `fallen_at`),
  CONSTRAINT `chaos_season_modes_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- A season join chosen when the character was created (the client's character creation on the website,
-- website/README.md "Client API"; the website's plugin creates the table too). season.lua joins the character at its
-- first login with the in-game join (S.applyRequest) and deletes the row; mode = a key of season_config.lua modes.list.
CREATE TABLE IF NOT EXISTS `chaos_season_requests` (
  `player_id` int(11) NOT NULL,
  `season` smallint(5) unsigned NOT NULL,
  `mode` varchar(16) NOT NULL DEFAULT 'standard',
  `requested_at` int(10) unsigned NOT NULL,
  PRIMARY KEY (`player_id`),
  CONSTRAINT `chaos_season_requests_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
