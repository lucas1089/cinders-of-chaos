-- Pets (data/scripts/chaos/pets.lua; species and numbers in pets_config.lua). pets.lua also creates the table at
-- startup when it is missing. Run once: mysql -u USER -p DB < chaos_pets.sql

-- one row per character and pet species it owns; xp is the pet's total XP (its level comes from pets_core.lua),
-- active = 1 for the pet that is out (it comes back after the next login), source = drop | store | achievement | staff
CREATE TABLE IF NOT EXISTS `chaos_pets` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL,
  `species` varchar(32) NOT NULL,
  `name` varchar(32) NOT NULL DEFAULT '',
  `xp` int(10) unsigned NOT NULL DEFAULT 0,
  `active` tinyint(1) NOT NULL DEFAULT 0,
  `source` varchar(16) NOT NULL DEFAULT '',
  `obtained_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `player_species` (`player_id`, `species`),
  CONSTRAINT `chaos_pets_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
