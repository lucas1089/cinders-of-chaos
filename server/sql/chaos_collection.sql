-- Collection score (data/scripts/chaos/collection.lua): the wardrobe items, plate frames and titles an account has
-- owned ("w:<kind>:<look>", "f:<frame>", "t:<title key>") and the milestones it reached ("m:<milestone key>", `at` = when).
-- Cosmetics are read from chaos_cosmetics. collection.lua also creates the table at startup if it is missing.
-- Safe to run again.
CREATE TABLE IF NOT EXISTS `chaos_collection` (
  `account_id` int(11) NOT NULL,
  `entry` varchar(64) NOT NULL,
  `at` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
