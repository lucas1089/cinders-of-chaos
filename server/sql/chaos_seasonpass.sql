-- Season pass (data/scripts/chaos/seasonpass.lua, seasonpass_config.lua). Run after the stock TFS schema (accounts,
-- players):  mysql -u USER -p DB < chaos_seasonpass.sql   (CREATE TABLE IF NOT EXISTS: safe to run again; the
-- server also creates the tables at startup)

-- pass XP and the premium track, per account and season. premium_paid = Chaos Coins paid for the pass on its own
-- (0 = not bought, or included in a pack); premium_token = the purchase that won (a second one is refunded).
CREATE TABLE IF NOT EXISTS `chaos_seasonpass` (
  `account_id` int(11) NOT NULL,
  `season` smallint(5) unsigned NOT NULL,
  `xp` int(10) unsigned NOT NULL DEFAULT 0,
  `premium` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `premium_paid` int(10) unsigned NOT NULL DEFAULT 0,
  `premium_token` varchar(32) NOT NULL DEFAULT '',
  `premium_at` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `season`),
  CONSTRAINT `chaos_seasonpass_fk` FOREIGN KEY (`account_id`) REFERENCES `accounts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- one row per claimed reward; the primary key makes a second claim of the same tier and track impossible.
-- track 0 = free, 1 = premium. token = the claim that won (seasonpass.lua reads it back before giving anything).
CREATE TABLE IF NOT EXISTS `chaos_seasonpass_claims` (
  `account_id` int(11) NOT NULL,
  `season` smallint(5) unsigned NOT NULL,
  `tier` tinyint(3) unsigned NOT NULL,
  `track` tinyint(1) unsigned NOT NULL,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `claimed_at` int(10) unsigned NOT NULL,
  `token` varchar(32) NOT NULL DEFAULT '',
  PRIMARY KEY (`account_id`, `season`, `tier`, `track`),
  CONSTRAINT `chaos_seasonpass_claims_fk` FOREIGN KEY (`account_id`) REFERENCES `accounts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- per account, season and period (YYYYMMDD of the day, or of the Monday of the week): the daily source caps
-- ("cap:<source>") and the challenge progress ("ch:<challenge key>") and completions ("done:<challenge key>").
CREATE TABLE IF NOT EXISTS `chaos_seasonpass_periods` (
  `account_id` int(11) NOT NULL,
  `season` smallint(5) unsigned NOT NULL,
  `period` int(10) unsigned NOT NULL,
  `key` varchar(40) NOT NULL,
  `value` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `season`, `period`, `key`),
  CONSTRAINT `chaos_seasonpass_periods_fk` FOREIGN KEY (`account_id`) REFERENCES `accounts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- season packs bought: one row per account, season and pack (a pack can be bought once). paid = coins really paid
-- (the difference on an upgrade).
CREATE TABLE IF NOT EXISTS `chaos_seasonpass_packs` (
  `account_id` int(11) NOT NULL,
  `season` smallint(5) unsigned NOT NULL,
  `pack` tinyint(3) unsigned NOT NULL,
  `paid` int(10) unsigned NOT NULL DEFAULT 0,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `bought_at` int(10) unsigned NOT NULL,
  `token` varchar(32) NOT NULL DEFAULT '',
  PRIMARY KEY (`account_id`, `season`, `pack`),
  CONSTRAINT `chaos_seasonpass_packs_fk` FOREIGN KEY (`account_id`) REFERENCES `accounts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- event log: claim, premium, pack, tier, challenge, admin
CREATE TABLE IF NOT EXISTS `chaos_seasonpass_log` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `at` int(10) unsigned NOT NULL,
  `account_id` int(11) NOT NULL DEFAULT 0,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `season` smallint(5) unsigned NOT NULL,
  `event` varchar(16) NOT NULL,
  `detail` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `chaos_seasonpass_log_account` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
