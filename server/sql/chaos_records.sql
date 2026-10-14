-- Competitive records (data/scripts/chaos/records.lua; settings records_config.lua; see server/README.md
-- "Competitive records"). Safe to run more than once (CREATE TABLE IF NOT EXISTS); records.lua creates the same tables
-- at startup when missing.
-- chaos_records: the best result of a character per board slot ("board|variant|size") and period: "w<YYYYMMDD>" (the
--   week of that Monday), the season ("s<id>" of season.lua, else "q<YYYY><quarter>") and "all". value: seconds (fastest
--   boards), a floor, tier, depth, rating, wins or a share in 1/100 %; at: when that value was reached (a tie goes to the
--   earlier at); party / members: the group of that result. Weekly rows older than keepWeeks are deleted.
-- chaos_records_firsts: the realm firsts, one row per season and boss (target); guids = the group, comma separated.
-- chaos_records_awards: the weekly top 3 of every slot (titles and the badge for the week after).
-- chaos_records_boards: the board catalogue, rewritten by the server at startup (the website reads names from it).

CREATE TABLE IF NOT EXISTS `chaos_records` (`slot` varchar(64) NOT NULL, `period` varchar(16) NOT NULL,
  `player_id` int(11) NOT NULL, `value` bigint(20) NOT NULL DEFAULT 0, `at` int(10) unsigned NOT NULL DEFAULT 0,
  `voc` smallint(5) NOT NULL DEFAULT 0, `party` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `members` varchar(160) NOT NULL DEFAULT '', `count` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`slot`, `period`, `player_id`), KEY `chaos_records_view` (`period`, `slot`, `value`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_records_firsts` (`season` varchar(16) NOT NULL, `target` varchar(64) NOT NULL,
  `board` varchar(48) NOT NULL DEFAULT '', `name` varchar(48) NOT NULL DEFAULT '', `members` varchar(160) NOT NULL DEFAULT '',
  `guids` varchar(120) NOT NULL DEFAULT '', `value` bigint(20) NOT NULL DEFAULT 0, `at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`season`, `target`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_records_awards` (`week` int(10) unsigned NOT NULL, `slot` varchar(64) NOT NULL,
  `rank` tinyint(3) unsigned NOT NULL, `player_id` int(11) NOT NULL, `cat` varchar(16) NOT NULL DEFAULT '',
  `value` bigint(20) NOT NULL DEFAULT 0, PRIMARY KEY (`week`, `slot`, `rank`),
  KEY `chaos_records_awards_player` (`player_id`, `week`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_records_boards` (`key` varchar(48) NOT NULL, `cat` varchar(16) NOT NULL,
  `name` varchar(64) NOT NULL, `mode` varchar(4) NOT NULL, `format` varchar(8) NOT NULL DEFAULT '',
  `label` varchar(32) NOT NULL DEFAULT '', `variants` text NOT NULL, `sizes` varchar(64) NOT NULL DEFAULT '',
  `ord` smallint(5) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`key`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;
