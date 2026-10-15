-- Time-friendly progression (data/scripts/chaos/catchup.lua, catchup_config.lua). catchup.lua also creates the table at
-- startup when it is missing. Run once: mysql -u USER -p DB < chaos_catchup.sql

-- one row per account: the returning player boost runs until returning_until (unix time; 0 = never started), started at
-- returned_at, the first login after none of the account's characters was online for returning.awayDays
CREATE TABLE IF NOT EXISTS `chaos_catchup` (
  `account_id` int(11) NOT NULL,
  `returning_until` int(10) unsigned NOT NULL DEFAULT 0,
  `returned_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
