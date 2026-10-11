-- Exclusives (data/scripts/chaos/exclusives.lua): the visual exclusives an account has unlocked (exclusives_config.lua
-- keys: outfits, addons, mounts, wings, auras, outfit shaders, plate frames and the boss drops of portal styles,
-- transmog sets, pets, footprints and outlines), from an achievement or a rare boss drop. Never sold, not tradeable.
-- exclusives.lua also creates the table at startup if it is missing. Safe to run again.
CREATE TABLE IF NOT EXISTS `chaos_exclusives` (
  `account_id` int(11) NOT NULL,
  `exclusive` varchar(40) NOT NULL,
  `source` varchar(16) NOT NULL DEFAULT '',
  `created` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `exclusive`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
