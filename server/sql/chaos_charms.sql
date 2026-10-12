-- Charms (server/data/scripts/chaos/charms.lua; README "Charms"). charms.lua runs the same statement at startup.
-- One row per charm placed in a character's charm grid. A placed charm exists only here: `data` is the item's
-- attributes (codec 'blob': the engine's own binary form, hex, engine patch 0017; codec 'attrs': the charm's attribute
-- list as JSON), `charm` the charm's summary (shape, rarity, item level, modifiers) the totals are read from.
-- state 0 placed, 9 being placed, 8 being taken out; `seq` = the place / take serial, settled at login against the
-- character's storage 7100470 (charms_core.lua C.recoverAction).
CREATE TABLE IF NOT EXISTS `chaos_charms` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL,
  `state` tinyint(3) unsigned NOT NULL DEFAULT 9,
  `seq` int(11) NOT NULL DEFAULT 0,
  `x` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `y` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `item_id` int(11) NOT NULL,
  `codec` varchar(8) NOT NULL DEFAULT 'attrs',
  `data` mediumtext NOT NULL,
  `charm` text NOT NULL,
  `placed_at` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `player_id` (`player_id`),
  CONSTRAINT `chaos_charms_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
