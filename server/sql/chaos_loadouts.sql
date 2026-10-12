-- Loadouts / Armory (data/scripts/chaos/loadouts.lua): one row per character and loadout slot (1..5); slot 0 is the
-- character's armory state (`serial` and `undo`: the crash-safe switch record). Columns of a loadout:
--   voc       vocation id it was saved with          tree      passive tree node ids "2,3,9"
--   paragon   "damage=3,health=4"                    supports  "spell:rune/rune/rune;..." (a summary: the runes
--   gear      "slot=itemid:iid:name|slot=empty"                 themselves are player storages, loadouts_config.lua)
-- The active slot (the live build) and the support runes of the other slots are player storages (7100570 - 7100579,
-- 7112000 - 7127999). loadouts.lua also creates the table at startup if it is missing. Safe to run again.
CREATE TABLE IF NOT EXISTS `chaos_loadouts` (
  `player_id` int(11) NOT NULL,
  `slot` tinyint(3) unsigned NOT NULL,
  `name` varchar(32) NOT NULL DEFAULT '',
  `icon` varchar(16) NOT NULL DEFAULT '',
  `voc` int(11) NOT NULL DEFAULT 0,
  `tree` text NOT NULL,
  `paragon` varchar(255) NOT NULL DEFAULT '',
  `supports` text NOT NULL,
  `gear` text NOT NULL,
  `serial` int(11) NOT NULL DEFAULT 0,
  `undo` text NOT NULL,
  `updated` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `slot`),
  CONSTRAINT `chaos_loadouts_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
