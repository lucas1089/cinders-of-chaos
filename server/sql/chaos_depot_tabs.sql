-- RETIRED (O316, 2026-10-29): the depot window and its tabs are gone; nothing reads or creates this table any more. It
-- stays for the rows that exist (nothing is dropped). Safe to leave as it is.
-- Depot tabs: the names and colours players gave their depot tabs (server/README.md "Depot (retired)"). One row per account and tab; a tab without a row had the default
-- name and colour.
-- name: at most 16 characters, printable ASCII and Latin-1 (the client draws Latin-1), "" = the default name.
-- color: a key of the old palette, "" = the default colour.

CREATE TABLE IF NOT EXISTS `chaos_depot_tabs` (
  `account_id` int(11) NOT NULL,
  `tab` tinyint(3) unsigned NOT NULL,
  `name` varchar(16) CHARACTER SET latin1 NOT NULL DEFAULT '',
  `color` varchar(16) NOT NULL DEFAULT '',
  PRIMARY KEY (`account_id`, `tab`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
