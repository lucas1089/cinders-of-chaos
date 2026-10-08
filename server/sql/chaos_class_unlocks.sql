-- Class unlocks (data/scripts/chaos/class_unlocks.lua): the classes an account may play. One row per account and
-- unlocked class key ("necromancer", "monk", "templar"); every character of the account may then play that class.
-- `source` says how it was unlocked (store, level, quest, achievement, gm). class_unlocks.lua also creates this table
-- at startup if it is missing. A website that creates characters can read it to offer a locked vocation only to
-- accounts with a row here.
CREATE TABLE IF NOT EXISTS `chaos_class_unlocks` (
  `account_id` int(11) NOT NULL,
  `class_key` varchar(32) NOT NULL,
  `source` varchar(32) NOT NULL DEFAULT '',
  `created` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `class_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
