-- Bestiary and kill tasks (data/scripts/chaos/bestiary.lua; settings bestiary_config.lua). bestiary.lua also creates
-- both tables at startup when they are missing. Run once: mysql -u USER -p DB < chaos_bestiary.sql

-- kills per character and monster (lower-case monster name); the bestiary stages are worked out from it
CREATE TABLE IF NOT EXISTS `chaos_bestiary` (
  `player_id` int(11) NOT NULL,
  `monster` varchar(64) NOT NULL,
  `kills` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `monster`),
  CONSTRAINT `chaos_bestiary_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- accepted (status 0) and finished (status 1) kill tasks; finished rows feed the daily and weekly limits and are
-- deleted after five weeks. task = "h:<monster>" (hunt) or "f:<category>:<lo>-<hi>" (family); mc = 1: a kill was made
-- while multi-clienting (no reward); done_day / done_week = task day and week (YYYYMMDD) of the completion
CREATE TABLE IF NOT EXISTS `chaos_bestiary_tasks` (
  `player_id` int(11) NOT NULL,
  `task` varchar(80) NOT NULL,
  `accepted_at` int(10) unsigned NOT NULL,
  `kind` varchar(8) NOT NULL,
  `target` varchar(64) NOT NULL,
  `label` varchar(64) NOT NULL,
  `lo` int(11) NOT NULL DEFAULT 0,
  `hi` int(11) NOT NULL DEFAULT 0,
  `level` int(11) NOT NULL DEFAULT 0,
  `progress` int(11) NOT NULL DEFAULT 0,
  `required` int(11) NOT NULL DEFAULT 0,
  `status` tinyint(4) NOT NULL DEFAULT 0,
  `mc` tinyint(4) NOT NULL DEFAULT 0,
  `done_day` int(11) NOT NULL DEFAULT 0,
  `done_week` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `task`, `accepted_at`),
  KEY `done` (`player_id`, `status`, `done_week`),
  CONSTRAINT `chaos_bestiary_tasks_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
