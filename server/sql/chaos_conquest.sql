-- Conquest Tokens (data/scripts/chaos/conquest.lua; numbers in conquest_config.lua; see server/README.md "Conquest
-- Tokens, the Conquest vendor and bad-luck protection"). Safe to run more than once (CREATE TABLE IF NOT EXISTS);
-- conquest.lua creates the same tables at startup when missing.
-- chaos_conquest: per character the token balance, everything earned and spent.
-- chaos_conquest_log: every grant (source, amount) and purchase (source "buy", a negative amount), the balance after
--   it; rows older than conquest_config.lua logKeepDays are deleted at startup.
-- chaos_conquest_seen: the uniques and set pieces that dropped for a character (the vendor offers them at any level).

CREATE TABLE IF NOT EXISTS `chaos_conquest` (`player_id` int(11) NOT NULL,
  `balance` int(10) unsigned NOT NULL DEFAULT 0, `earned` int(10) unsigned NOT NULL DEFAULT 0,
  `spent` int(10) unsigned NOT NULL DEFAULT 0, `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_conquest_log` (`id` int(11) NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL, `source` varchar(32) NOT NULL, `amount` int(11) NOT NULL DEFAULT 0,
  `balance` int(10) unsigned NOT NULL DEFAULT 0, `detail` varchar(80) NOT NULL DEFAULT '',
  `at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `chaos_conquest_log_player` (`player_id`, `at`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_conquest_seen` (`player_id` int(11) NOT NULL,
  `item_id` int(10) unsigned NOT NULL, `at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `item_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;
