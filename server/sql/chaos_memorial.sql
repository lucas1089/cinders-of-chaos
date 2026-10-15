-- The Capital Memorial (data/scripts/chaos/memorial.lua, memorial_config.lua; server/README.md "The Capital Memorial").
-- memorial.lua also creates the tables at startup when they are missing. Run once: mysql -u USER -p DB < chaos_memorial.sql
-- The website reads these tables (read only): website/overlay/plugins/chaos/memorial_lib.php.

-- the character setting "Show me on the Memorial": records and realm firsts (on without a row), a Hardcore fall (off
-- without a row); asked = 0 while a fall waits for the question at the next login
CREATE TABLE IF NOT EXISTS `chaos_memorial_optin` (
  `player_id` int(11) NOT NULL,
  `records` tinyint(1) NOT NULL DEFAULT 1,
  `fallen` tinyint(1) NOT NULL DEFAULT 0,
  `asked` tinyint(1) NOT NULL DEFAULT 1,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`),
  FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- what the Memorial remembers, per season key ("s<id>", or the quarter "q<year><q>" outside a season): kind first |
-- record | fallen, one row per character and thing. shown follows the character's choice; only shown rows are read by
-- the plaza, the client and the website. Rows of past seasons stay (the website's archive).
CREATE TABLE IF NOT EXISTS `chaos_memorial_entries` (
  `season` varchar(16) NOT NULL,
  `kind` varchar(8) NOT NULL,
  `entry_key` varchar(64) NOT NULL,
  `player_id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL DEFAULT '',
  `title` varchar(96) NOT NULL DEFAULT '',
  `detail` varchar(160) NOT NULL DEFAULT '',
  `level` int(10) unsigned NOT NULL DEFAULT 0,
  `class` varchar(32) NOT NULL DEFAULT '',
  `at` int(10) unsigned NOT NULL DEFAULT 0,
  `ord` smallint(5) unsigned NOT NULL DEFAULT 0,
  `shown` tinyint(1) NOT NULL DEFAULT 0,
  `season_name` varchar(64) NOT NULL DEFAULT '',
  PRIMARY KEY (`season`, `kind`, `entry_key`, `player_id`),
  KEY `player` (`player_id`),
  FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
