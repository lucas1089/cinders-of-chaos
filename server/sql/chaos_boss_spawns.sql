-- Boss spawns tracker (data/scripts/chaos/bossspawns.lua). bossspawns.lua also creates the table at startup when it
-- is missing. Run once: mysql -u USER -p DB < chaos_boss_spawns.sql

-- one row per boss of bossspawns_config.lua (boss_key = the entry's key): the last kill (unix time), the player with
-- the most damage (else the last hit) and the kills counted since the feature was installed
CREATE TABLE IF NOT EXISTS `chaos_boss_spawns` (
  `boss_key` varchar(48) NOT NULL,
  `last_kill` int(10) unsigned NOT NULL DEFAULT 0,
  `killer` varchar(64) NOT NULL DEFAULT '',
  `kills` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`boss_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
