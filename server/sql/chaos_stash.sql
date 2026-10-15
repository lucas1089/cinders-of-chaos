-- The stash as the one item storage (data/scripts/chaos/stash.lua; numbers in stash_config.lua; see server/README.md
-- "Stash"). Safe to run more than once; stash.lua creates the same tables at startup. chaos_stash (plain stacks merged
-- by type) and chaos_stash_block (the never-stash list) are in chaos.sql; chaos_stash.tab in chaos_pact.sql.
--
-- chaos_stash_items: every other stored item, one row each, with every attribute: codec "blob" (the engine's own
--   binary form, item:serializeAttributes() of engine patch 0017, hex in `data`), "attrs" (a key list, without the
--   patch) or "plain" (a journal row of a plain stack). The row is also the journal of every deposit and withdrawal:
--   state 0 stored, 9 depositing, 8 taking, with the serial `seq` that the character's storage 7100011 is compared to
--   after a crash (stash_core.lua "The journal"). `classes` are the affinity tabs it matches ("weapons,"), `name` and
--   `info` its name and look text for the list, `source` "deposit" or "depot" (the depot migration; rows of
--   tools/migrate_depot_stash.py start with empty classes and name and are described at the next opening).
-- chaos_stash_log: the depot migration per character (moved, to the Old depot tab, kept in the depot) and the
--   offline tool's runs.

CREATE TABLE IF NOT EXISTS `chaos_stash_items` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL,
  `count` int(11) NOT NULL DEFAULT 1,
  `codec` varchar(8) NOT NULL DEFAULT 'blob',
  `data` mediumtext NOT NULL,
  `tab` smallint(5) unsigned NOT NULL DEFAULT 0,
  `classes` varchar(96) NOT NULL DEFAULT '',
  `name` varchar(96) NOT NULL DEFAULT '',
  `info` text NOT NULL,
  `rarity` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `state` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `seq` int(11) NOT NULL DEFAULT 0,
  `source` varchar(16) NOT NULL DEFAULT '',
  `created_at` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `player_state` (`player_id`, `state`),
  CONSTRAINT `chaos_stash_items_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_stash_log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL,
  `action` varchar(16) NOT NULL,
  `moved` int(11) NOT NULL DEFAULT 0,
  `overflow` int(11) NOT NULL DEFAULT 0,
  `kept` int(11) NOT NULL DEFAULT 0,
  `detail` varchar(255) NOT NULL DEFAULT '',
  `at` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `player_id` (`player_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
