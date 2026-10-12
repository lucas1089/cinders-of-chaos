-- Chaos Pact and account storage (data/scripts/chaos/pact.lua; numbers in pact_config.lua; see server/README.md
-- "Chaos Pact and account storage"). Safe to run more than once; pact.lua creates the same tables at startup.
-- chaos_pact: one row per account. ends_at = end of the Pact (unix time; stacked purchases add 30 days to it),
--   started_at = start of the current unbroken run (the title's date), last_claim = YYYYMMDD of the last daily coins.
-- chaos_account_extras: one-time purchases per account (stashTabs, stashOrbs, stashGems, stashKeys, charSlots,
--   buildSlots) and the character slots given once to accounts that already had more characters (charSlotsLegacy).
--   The website reads charSlots + charSlotsLegacy for the character limit.
-- chaos_build_slots: saved passive tree builds (build codes of buildshare_core.lua) per account and slot.
-- chaos_pact_log: purchases, daily claims, legacy grants and staff changes.
-- chaos_stash.tab: the stash tab of each entry (0 = not placed yet; stash.lua places it at the next opening).

CREATE TABLE IF NOT EXISTS `chaos_pact` (
  `account_id` int(11) NOT NULL,
  `ends_at` bigint(20) NOT NULL DEFAULT 0,
  `started_at` bigint(20) NOT NULL DEFAULT 0,
  `total_days` int(11) NOT NULL DEFAULT 0,
  `last_claim` int(11) NOT NULL DEFAULT 0,
  `claimed_total` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_account_extras` (
  `account_id` int(11) NOT NULL,
  `extra_key` varchar(32) NOT NULL,
  `amount` int(11) NOT NULL DEFAULT 0,
  `updated` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `extra_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_build_slots` (
  `account_id` int(11) NOT NULL,
  `slot` tinyint(3) unsigned NOT NULL,
  `name` varchar(32) NOT NULL DEFAULT '',
  `code` varchar(600) NOT NULL DEFAULT '',
  `class_line` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `nodes` smallint(5) unsigned NOT NULL DEFAULT 0,
  `saved_by` varchar(64) NOT NULL DEFAULT '',
  `updated` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_pact_log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `action` varchar(16) NOT NULL,
  `detail` varchar(64) NOT NULL DEFAULT '',
  `amount` int(11) NOT NULL DEFAULT 0,
  `at` bigint(20) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `account_id` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- MariaDB (the game database): ADD COLUMN IF NOT EXISTS keeps this repeatable
ALTER TABLE `chaos_stash` ADD COLUMN IF NOT EXISTS `tab` smallint(5) unsigned NOT NULL DEFAULT 0;
