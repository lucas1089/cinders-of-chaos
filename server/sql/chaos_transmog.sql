-- Transmog wardrobe (data/scripts/chaos/transmog.lua): the looks an account has unlocked (server item ids; an item
-- carried or equipped once unlocks its look for every character of the account) and the appearance sets it owns
-- (transmog_config.lua `sets`: store, achievement, season or exclusive; their looks come from the config).
-- transmog.lua also creates both tables at startup if they are missing. Safe to run again.
CREATE TABLE IF NOT EXISTS `chaos_transmog` (
  `account_id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL,
  `created` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_transmog_sets` (
  `account_id` int(11) NOT NULL,
  `set_key` varchar(32) NOT NULL,
  `source` varchar(32) NOT NULL DEFAULT '',
  `created` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `set_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
