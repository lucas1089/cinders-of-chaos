-- Referral program (data/scripts/chaos/referral.lua; rules in referral_config.lua; see server/README.md "Referral
-- program"). Safe to run more than once; referral.lua creates the same tables at startup.
-- chaos_referral_codes: the code of an account (made when one of its characters reached minReferrerLevel).
-- chaos_referrals: one row per referred account. status: pending (entered on the website, checked at the first
--   login), active, rejected (reason = a key of referral_config.lua messages; the account may try another code while
--   it is new). player_id = the referred account's first character, whose levels count. gift_at = when the friend's
--   gift was given. reg_ip = the website registration IP ("a.b.c.d").
-- chaos_referral_rewards: one row per referred account and milestone. state: due (waits: banned referrer or monthly
--   cap), paid (coins = Chaos Coins paid), void (the referred account was banned). notified = the referrer was told.
-- chaos_referral_log: codes, links, refusals, gifts, milestones, payments, staff unlinks.

CREATE TABLE IF NOT EXISTS `chaos_referral_codes` (
  `account_id` int(11) NOT NULL,
  `code` varchar(16) NOT NULL,
  `created_at` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`),
  UNIQUE KEY `code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_referrals` (
  `referred_account_id` int(11) NOT NULL,
  `referrer_account_id` int(11) NOT NULL,
  `code` varchar(16) NOT NULL DEFAULT '',
  `source` varchar(8) NOT NULL DEFAULT 'game',
  `status` varchar(10) NOT NULL DEFAULT 'pending',
  `reason` varchar(32) NOT NULL DEFAULT '',
  `reg_ip` varchar(45) NOT NULL DEFAULT '',
  `created_at` bigint(20) NOT NULL DEFAULT 0,
  `linked_at` bigint(20) NOT NULL DEFAULT 0,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `gift_at` bigint(20) NOT NULL DEFAULT 0,
  `gift_player_id` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`referred_account_id`),
  KEY `referrer_account_id` (`referrer_account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_referral_rewards` (
  `referred_account_id` int(11) NOT NULL,
  `milestone` varchar(16) NOT NULL,
  `referrer_account_id` int(11) NOT NULL,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `reached_at` bigint(20) NOT NULL DEFAULT 0,
  `state` varchar(8) NOT NULL DEFAULT 'due',
  `paid_at` bigint(20) NOT NULL DEFAULT 0,
  `coins` int(11) NOT NULL DEFAULT 0,
  `notified` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`referred_account_id`, `milestone`),
  KEY `referrer_account_id` (`referrer_account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_referral_log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `at` bigint(20) NOT NULL,
  `account_id` int(11) NOT NULL DEFAULT 0,
  `other_account_id` int(11) NOT NULL DEFAULT 0,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `action` varchar(16) NOT NULL,
  `detail` varchar(128) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `account_id` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- chaos_referral_tiers: the referrer's tier rewards (referral_config.lua `tiers`: 3, 5 and 10 referred accounts whose
-- `qualify` milestone was paid): one row per referrer and tier, written once; qualified = the count when reached,
-- coins = the Chaos Coins paid with it. The title is shown from these rows (referral_core.lua R.titles).
CREATE TABLE IF NOT EXISTS `chaos_referral_tiers` (
  `referrer_account_id` int(11) NOT NULL,
  `tier` varchar(16) NOT NULL,
  `qualified` int(11) NOT NULL DEFAULT 0,
  `coins` int(11) NOT NULL DEFAULT 0,
  `paid_at` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`referrer_account_id`, `tier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
