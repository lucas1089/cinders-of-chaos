-- Pocket bosses (data/scripts/chaos/pocketboss.lua). pocketboss.lua also creates the table at startup when it is
-- missing. Run once: mysql -u USER -p DB < chaos_pocketboss.sql

-- one row per character and pocket boss (boss_key = the Boss Spawns key: world_1 .. world_5, dreadscale, raid_moloveth,
-- ...): the pocket day (YYYYMMDD) of `used` daily charges, the bonus charges held (the online-time shop), the day and
-- number of bonus charges added that day (the daily cap), the pocket kills and when the boss's scheduled or contested
-- fight last rewarded the character (event_at: no pocket of that boss for noStackSeconds after it)
CREATE TABLE IF NOT EXISTS `chaos_pocketboss` (
  `player_id` int(11) NOT NULL,
  `boss_key` varchar(48) NOT NULL,
  `day` int(10) unsigned NOT NULL DEFAULT 0,
  `used` smallint(5) unsigned NOT NULL DEFAULT 0,
  `bonus` smallint(5) unsigned NOT NULL DEFAULT 0,
  `bonus_day` int(10) unsigned NOT NULL DEFAULT 0,
  `bonus_added` smallint(5) unsigned NOT NULL DEFAULT 0,
  `kills` int(10) unsigned NOT NULL DEFAULT 0,
  `event_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `boss_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
