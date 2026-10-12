-- Cosmetics (data/scripts/chaos/cosmetics.lua): the cosmetics an account has unlocked (cosmetics_config.lua keys:
-- spell effect skins, kill effects, loot label accents, chat name colours, footprints, outlines), from the store, an
-- achievement, PvP or a boss drop (exclusives.lua).
-- What a character shows is chosen per character (player storages 7100940 - 7100949, 7102000 - 7102001).
-- cosmetics.lua also creates the table at startup if it is missing. Safe to run again.
CREATE TABLE IF NOT EXISTS `chaos_cosmetics` (
  `account_id` int(11) NOT NULL,
  `cosmetic` varchar(40) NOT NULL,
  `source` varchar(16) NOT NULL DEFAULT 'store',
  `created` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `cosmetic`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
