-- Depot tabs: the names and colours players give their depot tabs (data/scripts/chaos/depot.lua; see server/README.md
-- "Depot tabs"). One row per account and tab; a tab without a row has the default name and colour. Safe to run more
-- than once; depot.lua creates the same table at startup.
-- name: at most 16 characters, printable ASCII and Latin-1 (the client draws Latin-1), "" = the default name.
-- color: a key of depot_config.lua `palette`, "" = the default colour.

CREATE TABLE IF NOT EXISTS `chaos_depot_tabs` (
  `account_id` int(11) NOT NULL,
  `tab` tinyint(3) unsigned NOT NULL,
  `name` varchar(16) CHARACTER SET latin1 NOT NULL DEFAULT '',
  `color` varchar(16) NOT NULL DEFAULT '',
  PRIMARY KEY (`account_id`, `tab`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
