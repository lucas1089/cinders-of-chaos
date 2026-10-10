-- Anti-bot and player reports (data/scripts/chaos/antibot.lua, reports.lua; server/README.md "Anti-bot and player
-- reports"). antibot.lua also creates the tables at startup when they are missing.
-- Run once: mysql -u USER -p DB < chaos_reports.sql

-- player reports: one row per report. chat = the target's last lines in PUBLIC channels only (one per line), never
-- private messages. suspicion = the target's anti-bot score when the report was made (0 offline / unknown).
CREATE TABLE IF NOT EXISTS `chaos_reports` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `created_at` int unsigned NOT NULL,
  `reporter_id` int unsigned NOT NULL,
  `reporter_account` int unsigned NOT NULL DEFAULT 0,
  `reporter_name` varchar(64) NOT NULL DEFAULT '',
  `target_id` int unsigned NOT NULL,
  `target_name` varchar(64) NOT NULL DEFAULT '',
  `reason` varchar(16) NOT NULL,
  `note` varchar(255) NOT NULL DEFAULT '',
  `pos_x` int unsigned NOT NULL DEFAULT 0,
  `pos_y` int unsigned NOT NULL DEFAULT 0,
  `pos_z` tinyint unsigned NOT NULL DEFAULT 0,
  `target_online` tinyint unsigned NOT NULL DEFAULT 0,
  `suspicion` int unsigned NOT NULL DEFAULT 0,
  `chat` text,
  `status` varchar(8) NOT NULL DEFAULT 'open', -- open | closed
  `closed_at` int unsigned NOT NULL DEFAULT 0,
  `closed_by` varchar(64) NOT NULL DEFAULT '',
  `staff_note` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_status` (`status`, `created_at`),
  KEY `idx_target` (`target_id`),
  KEY `idx_reporter` (`reporter_account`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- the anti-bot staff log: score thresholds, presence checks and their results. Nothing here bans; staff decide.
-- kind: score | check_pass | check_fail | check_retry | check_deferred | hold_cleared
CREATE TABLE IF NOT EXISTS `chaos_antibot_log` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `created_at` int unsigned NOT NULL,
  `player_id` int unsigned NOT NULL,
  `account_id` int unsigned NOT NULL DEFAULT 0,
  `player_name` varchar(64) NOT NULL DEFAULT '',
  `kind` varchar(16) NOT NULL,
  `score` int unsigned NOT NULL DEFAULT 0,
  `detail` varchar(512) NOT NULL DEFAULT '',
  `pos_x` int unsigned NOT NULL DEFAULT 0,
  `pos_y` int unsigned NOT NULL DEFAULT 0,
  `pos_z` tinyint unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_player` (`player_id`, `created_at`),
  KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- accounts held off the leaderboards pending review (only written with antibot_config.lua log.holdLeaderboards = true;
-- cleared_at > 0 = staff cleared it). The weekly boards, class ladder, season ladder and the website boards skip
-- accounts with an uncleared row.
CREATE TABLE IF NOT EXISTS `chaos_antibot_holds` (
  `account_id` int unsigned NOT NULL,
  `player_id` int unsigned NOT NULL DEFAULT 0,
  `created_at` int unsigned NOT NULL,
  `reason` varchar(64) NOT NULL DEFAULT '',
  `cleared_at` int unsigned NOT NULL DEFAULT 0,
  `cleared_by` varchar(64) NOT NULL DEFAULT '',
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
