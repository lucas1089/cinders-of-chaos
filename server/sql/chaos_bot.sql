-- Bot review (data/scripts/chaos/botreview.lua; server/README.md "Bot detection"). botreview.lua also creates the
-- tables at startup when they are missing. Nothing here punishes: staff review the flagged days.
-- Retention (botreview_config.lua retention): days 30, escalated days 90, staff actions 90; purged once a day.
-- Run once: mysql -u USER -p DB < chaos_bot.sql

-- one row per character and day, written only once the day's score reaches storeAt (25).
-- signals = "name=0.00;..." of the day's highest evaluation, reasons = its explanations (" | " between them),
-- timeline = "hour=score,..." (hourly means). status: none | new (flagged, not reviewed) | reviewed | false_positive |
-- escalated
CREATE TABLE IF NOT EXISTS `chaos_bot_daily` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `player_id` int unsigned NOT NULL,
  `account_id` int unsigned NOT NULL DEFAULT 0,
  `player_name` varchar(64) NOT NULL DEFAULT '',
  `day` int unsigned NOT NULL,
  `score` smallint unsigned NOT NULL DEFAULT 0,
  `peak` smallint unsigned NOT NULL DEFAULT 0,
  `flagged` tinyint unsigned NOT NULL DEFAULT 0,
  `signals` varchar(255) NOT NULL DEFAULT '',
  `reasons` varchar(1024) NOT NULL DEFAULT '',
  `timeline` varchar(255) NOT NULL DEFAULT '',
  `status` varchar(16) NOT NULL DEFAULT 'none',
  `reviewed_by` varchar(64) NOT NULL DEFAULT '',
  `reviewed_at` int unsigned NOT NULL DEFAULT 0,
  `note` varchar(255) NOT NULL DEFAULT '',
  `created_at` int unsigned NOT NULL,
  `updated_at` int unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_player_day` (`player_id`, `day`),
  KEY `idx_day` (`day`, `flagged`),
  KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- every staff action on a day (game: /botreview mark, admin panel; website: the staff page), and presence checks
-- requested from the website (action "check": done_at 0 until the server sent it; result sent | already running |
-- expired)
CREATE TABLE IF NOT EXISTS `chaos_bot_actions` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `created_at` int unsigned NOT NULL,
  `player_id` int unsigned NOT NULL,
  `player_name` varchar(64) NOT NULL DEFAULT '',
  `day` int unsigned NOT NULL DEFAULT 0,
  `action` varchar(16) NOT NULL,
  `staff` varchar(64) NOT NULL DEFAULT '',
  `staff_group` tinyint unsigned NOT NULL DEFAULT 0,
  `note` varchar(255) NOT NULL DEFAULT '',
  `done_at` int unsigned NOT NULL DEFAULT 0,
  `result` varchar(32) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_pending` (`action`, `done_at`),
  KEY `idx_player` (`player_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
