-- Bot detection, event store and hourly scores (data/scripts/chaos/botdet.lua; server/README.md "Bot detection events and
-- scores (O722)"). botdet.lua also creates both tables at startup when they are missing. Nothing here punishes: the scores
-- are for staff to read (/botcheck, chaos-ctl.sh botcheck-top). Testers and staff are never collected.
-- Run once: mysql -u USER -p DB < chaos_botdet.sql

-- One row per kind of event and flush (every 5 minutes and at logout), packed: `data` is JSON, the lists inside are
-- strings of numbers ("dt,x,y,z;dt,x,y,z"), so a busy hour is a few rows, not thousands.
-- type: pos (position changes), walk (key steps, path commands), spell, heal, react (seconds a creature was in view before
-- the first attack), session (login / logout / idle gaps), integrity (client module hashes that differ from the official
-- list), tool (the short code of a known tool the client named), note (anything staff wrote). Purged after 7 days, daily.
CREATE TABLE IF NOT EXISTS `chaos_botdet_events` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `player_id` int unsigned NOT NULL,
  `type` varchar(16) NOT NULL,
  `data` mediumtext NOT NULL,
  `created_at` int unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_player_time` (`player_id`, `created_at`),
  KEY `idx_time` (`created_at`),
  KEY `idx_type` (`type`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- One row per character and hour (hour_ts = the hour's first second): the six heuristics 0-100, the weighted total,
-- the path bonus, the flag (total above flagAt) and the numbers behind every score in `notes`. Purged after 90 days.
CREATE TABLE IF NOT EXISTS `chaos_botdet_scores` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `player_id` int unsigned NOT NULL,
  `player_name` varchar(64) NOT NULL DEFAULT '',
  `hour_ts` int unsigned NOT NULL,
  `total` smallint unsigned NOT NULL DEFAULT 0,
  `route` smallint unsigned NOT NULL DEFAULT 0,
  `regularity` smallint unsigned NOT NULL DEFAULT 0,
  `reaction` smallint unsigned NOT NULL DEFAULT 0,
  `heal` smallint unsigned NOT NULL DEFAULT 0,
  `session` smallint unsigned NOT NULL DEFAULT 0,
  `bonus` smallint unsigned NOT NULL DEFAULT 0,
  `flagged` tinyint unsigned NOT NULL DEFAULT 0,
  `notes` varchar(1024) NOT NULL DEFAULT '',
  `created_at` int unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_player_hour` (`player_id`, `hour_ts`),
  KEY `idx_hour_total` (`hour_ts`, `total`),
  KEY `idx_flagged` (`flagged`, `hour_ts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
