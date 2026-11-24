-- Collection log (O753; data/scripts/chaos/collection_log.lua, collection_log_core.lua; server/README.md "Collection log
-- (O753)"). Safe to run more than once; collection_log.lua creates the same table at startup when it is missing.
-- chaos_collection_log: per character and item (a unique, a set piece, a raid unique) how many dropped for it, the first
--   and the last date.

CREATE TABLE IF NOT EXISTS `chaos_collection_log` (`player_id` int(11) NOT NULL, `item_id` int(10) unsigned NOT NULL,
  `count` int(10) unsigned NOT NULL DEFAULT 0, `first_at` int(10) unsigned NOT NULL DEFAULT 0,
  `last_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`, `item_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;
