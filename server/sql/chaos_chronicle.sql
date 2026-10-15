-- The Ashen Chronicle (data/scripts/chaos/chronicle.lua, chronicle_config.lua; server/README.md "The Ashen Chronicle").
-- chronicle.lua also creates the tables at startup when they are missing. Run once: mysql -u USER -p DB < chaos_chronicle.sql
-- The website reads these tables (read only): website/overlay/plugins/chaos/chronicle_lib.php.

-- one row per season with a Chronicle: its arc (chronicle_text.lua), the open chapter, how many chapters are written,
-- when it started and when the season ended (finished_at > 0: the record below is written)
CREATE TABLE IF NOT EXISTS `chaos_chronicle_state` (
  `season` smallint(5) unsigned NOT NULL,
  `arc` varchar(16) NOT NULL DEFAULT '',
  `chapter` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `done` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `started_at` int(10) unsigned NOT NULL DEFAULT 0,
  `finished_at` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`season`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- every chapter of the season: its key and title (en, pt), what it changed once written (en, pt) and when (the website)
CREATE TABLE IF NOT EXISTS `chaos_chronicle_chapters` (
  `season` smallint(5) unsigned NOT NULL,
  `chapter` tinyint(3) unsigned NOT NULL,
  `chapter_key` varchar(32) NOT NULL DEFAULT '',
  `title` varchar(96) NOT NULL DEFAULT '',
  `title_pt` varchar(96) NOT NULL DEFAULT '',
  `world` varchar(255) NOT NULL DEFAULT '',
  `world_pt` varchar(255) NOT NULL DEFAULT '',
  `done_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`season`, `chapter`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- every goal of every chapter: the server-wide count, the target, and when the chapter was written (done_at > 0)
CREATE TABLE IF NOT EXISTS `chaos_chronicle_progress` (
  `season` smallint(5) unsigned NOT NULL,
  `chapter` tinyint(3) unsigned NOT NULL,
  `goal` tinyint(3) unsigned NOT NULL,
  `label` varchar(64) NOT NULL DEFAULT '',
  `progress` int(11) NOT NULL DEFAULT 0,
  `target` int(11) NOT NULL DEFAULT 0,
  `done_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`season`, `chapter`, `goal`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- the points of each character in each chapter (aggregated: a total per chapter, no event log)
CREATE TABLE IF NOT EXISTS `chaos_chronicle_contrib` (
  `season` smallint(5) unsigned NOT NULL,
  `chapter` tinyint(3) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL DEFAULT '',
  `points` int(11) NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`season`, `chapter`, `player_id`),
  KEY `rank` (`season`, `chapter`, `points`),
  FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- the record written at the season's end: the top contributors of every chapter (chronicle_config.lua topRecorded)
CREATE TABLE IF NOT EXISTS `chaos_chronicle_record` (
  `season` smallint(5) unsigned NOT NULL,
  `chapter` tinyint(3) unsigned NOT NULL,
  `place` tinyint(3) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL DEFAULT '',
  `points` int(11) NOT NULL DEFAULT 0,
  `recorded_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`season`, `chapter`, `place`),
  KEY `player` (`player_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- the level goals: a character counts once per season and level
CREATE TABLE IF NOT EXISTS `chaos_chronicle_levels` (
  `season` smallint(5) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  `level` smallint(5) unsigned NOT NULL,
  PRIMARY KEY (`season`, `player_id`, `level`),
  FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
