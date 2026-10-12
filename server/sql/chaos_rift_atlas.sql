-- Rift Atlas (data/scripts/chaos/atlas.lua). atlas.lua also creates the table at startup when it is missing.
-- Run once: mysql -u USER -p DB < chaos_rift_atlas.sql

-- one row per character: `done` = the completed cells of the completion grid (comma list of cell keys: c<theme>.<tier>,
-- f<tier> flawless, s<tier> swift, o<kind> omen guardian), `nodes` = the allocated node ids of atlas_config.lua
-- (comma list; the start node is implied). Season characters are characters of their own, so each realm has its own rows.
CREATE TABLE IF NOT EXISTS `chaos_rift_atlas` (
  `player_id` int(11) NOT NULL,
  `done` text NOT NULL,
  `nodes` varchar(1024) NOT NULL DEFAULT '',
  `updated` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`),
  CONSTRAINT `chaos_rift_atlas_player_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
