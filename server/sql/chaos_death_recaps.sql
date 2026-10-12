-- Death recap (data/scripts/chaos/deathrecap.lua). deathrecap.lua also creates the table at startup when it is
-- missing (deathrecap_core.lua R.createSql, the same columns). Run once: mysql -u USER -p DB < chaos_death_recaps.sql

-- the last deaths of each character (deathrecap_config.lua keep = 5; older rows are deleted after each insert):
-- at = unix time of the death, seen = 1 once the client got it (at the next login the experience and levels lost
-- are filled into data first), data = the recap as JSON (deathrecap_core.lua, at most maxRecapBytes)
CREATE TABLE IF NOT EXISTS `chaos_death_recaps` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL,
  `at` int(10) unsigned NOT NULL DEFAULT 0,
  `seen` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `data` text NOT NULL,
  PRIMARY KEY (`id`),
  KEY `player_id` (`player_id`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
