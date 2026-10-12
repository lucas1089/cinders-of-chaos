-- Professions (server/data/scripts/chaos/professions.lua; README "Professions"). professions.lua runs the same statements
-- at startup.
-- chaos_professions: one row per character and profession (delving, wortcunning, flaying, angling): level 1..100, the
-- experience inside the level and the materials gathered in total. A character without a row is level 1.
CREATE TABLE IF NOT EXISTS `chaos_professions` (
  `player_id` int(11) NOT NULL,
  `prof` varchar(16) NOT NULL,
  `level` smallint(5) unsigned NOT NULL DEFAULT 1,
  `xp` int(11) NOT NULL DEFAULT 0,
  `gathered` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `prof`),
  CONSTRAINT `chaos_professions_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- chaos_professions_sales: what a character sold to the Material Broker today, per material (server item id); `day` is
-- the server-local day key YYYYMMDD (days start at professions_config.lua rollHour). A row of an older day counts 0.
CREATE TABLE IF NOT EXISTS `chaos_professions_sales` (
  `player_id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL,
  `day` int(11) NOT NULL DEFAULT 0,
  `sold` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `item_id`),
  CONSTRAINT `chaos_professions_sales_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
