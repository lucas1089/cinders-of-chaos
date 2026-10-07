-- Project Chaos admin panel: audit log of every admin action (allowed, failed and denied).
CREATE TABLE IF NOT EXISTS `chaos_admin_log` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `created_at` int unsigned NOT NULL,
  `account_id` int unsigned NOT NULL DEFAULT 0,
  `player_id` int unsigned NOT NULL DEFAULT 0,
  `player_name` varchar(64) NOT NULL DEFAULT '',
  `group_id` int unsigned NOT NULL DEFAULT 0,
  `ip` int unsigned NOT NULL DEFAULT 0,
  `action` varchar(64) NOT NULL,
  `target` varchar(128) NOT NULL DEFAULT '',
  `params` text,
  `status` varchar(16) NOT NULL DEFAULT 'ok', -- ok | fail | denied | invalid
  `message` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_created_at` (`created_at`),
  KEY `idx_player_id` (`player_id`),
  KEY `idx_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
