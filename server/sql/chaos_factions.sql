-- Factions with reputation (data/scripts/chaos/factions.lua, factions_config.lua). factions.lua also creates the tables
-- at startup when they are missing. Run once: mysql -u USER -p DB < chaos_factions.sql

-- one row per character and faction: reputation, the faction day's and week's gains (the day sum feeds the diminishing
-- returns, the week sum the weekly cap, the bank what earlier weeks left of their cap), when the character first reached Exalted (0 = never) and every gain together
CREATE TABLE IF NOT EXISTS `chaos_factions` (
  `player_id` int(11) NOT NULL,
  `faction` varchar(16) NOT NULL,
  `rep` int(11) NOT NULL DEFAULT 0,
  `day` int(10) unsigned NOT NULL DEFAULT 0,
  `day_gain` int(11) NOT NULL DEFAULT 0,
  `week` int(10) unsigned NOT NULL DEFAULT 0,
  `week_gain` int(11) NOT NULL DEFAULT 0,
  `week_bank` int(11) NOT NULL DEFAULT 0, -- unused cap carried from earlier weeks (rolloverWeeks)
  `exalted_at` int(10) unsigned NOT NULL DEFAULT 0,
  `total` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `faction`),
  FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- contract progress of the current faction day ("d" + YYYYMMDD) and week ("w" + YYYYMMDD of its Monday); the contract
-- itself is generated again from (character, period, faction, slot, level), so only the level of the first look, the
-- progress and done are kept. Rows of older periods are deleted at the next look.
CREATE TABLE IF NOT EXISTS `chaos_faction_contracts` (
  `player_id` int(11) NOT NULL,
  `period` varchar(12) NOT NULL,
  `faction` varchar(16) NOT NULL,
  `slot` tinyint(3) unsigned NOT NULL,
  `level` int(11) NOT NULL DEFAULT 1,
  `progress` int(11) NOT NULL DEFAULT 0,
  `done` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `period`, `faction`, `slot`),
  FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- quartermaster purchases: week 0 = an unlock bought once (recipe, aura, mount), else the week key of an offer with a
-- weekly limit (orb bundles) and how many were bought that week
CREATE TABLE IF NOT EXISTS `chaos_faction_purchases` (
  `player_id` int(11) NOT NULL,
  `offer` varchar(32) NOT NULL,
  `week` int(10) unsigned NOT NULL DEFAULT 0,
  `count` int(11) NOT NULL DEFAULT 0,
  `at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `offer`, `week`),
  FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- tables made before 2026-10-15 (factions.lua also does this at startup)
ALTER TABLE `chaos_factions` ADD COLUMN IF NOT EXISTS `week_bank` int(11) NOT NULL DEFAULT 0;
