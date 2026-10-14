-- Nemesis (data/scripts/chaos/nemesis.lua; settings nemesis_config.lua; see server/README.md "Nemesis"). Safe to run
-- more than once (CREATE TABLE IF NOT EXISTS); nemesis.lua creates the same table at startup when missing.
-- chaos_nemesis: the active nemesis of a character (player_id = the victim's guid). monster = the type name, name = the
--   generated name (the epithet is built from the kills and the victim's current name), base_level = the killer's
--   level, level = base + bump % + growth, traits = trait keys, comma separated, created / last_seen = os.time (a row
--   not seen for nemesis_config.lua expireDays is deleted at startup and every hour), hc = born on a Hardcore
--   character. A slain nemesis is deleted.

CREATE TABLE IF NOT EXISTS `chaos_nemesis` (`id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL, `monster` varchar(64) NOT NULL, `name` varchar(32) NOT NULL,
  `base_level` smallint(5) unsigned NOT NULL DEFAULT 1, `level` smallint(5) unsigned NOT NULL DEFAULT 1,
  `bump` tinyint(3) unsigned NOT NULL DEFAULT 0, `kills` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `traits` varchar(64) NOT NULL DEFAULT '', `created` int(10) unsigned NOT NULL DEFAULT 0,
  `last_seen` int(10) unsigned NOT NULL DEFAULT 0, `appearances` int(10) unsigned NOT NULL DEFAULT 0,
  `hc` tinyint(1) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `chaos_nemesis_player` (`player_id`),
  KEY `chaos_nemesis_seen` (`last_seen`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;
