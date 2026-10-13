-- Creator codes (data/scripts/chaos/creator_codes.lua, creator_codes_config.lua; website plugins/chaos/creator_lib.php,
-- pages/creator.php; server/README.md "Creator codes"). Safe to run more than once; creator_codes.lua and the website's
-- install.sql create the same tables.
-- chaos_creator_codes: one row per code; account_id = the creator's account (paid there), pct = its own % (0 = the
--   config's sharePct), active = 0 switches it off (new picks refused, waiting shares void). Written by the website's
--   admin action (an admin panel account with a character of group 5 or higher).
-- chaos_creator_support: the code a donor account picked on the website and until when it covers its donations;
--   ip = the address of the pick (the same-connection check).
-- chaos_creator_uses: one row per donation that carried a code (order_id = chaos_coin_orders.id). state: pending,
--   wait (reason hold / cap / banned), paid (share = the Chaos Coins paid to the creator), void (reason self / sameIp /
--   samePayer / reversed / inactive / nocode / zero).
-- chaos_creator_log: code changes, picks, matches, payments and refusals.
-- chaos_pay_payers: the payer of a donation as a SHA-256 (never the e-mail or the payer id itself), written by the
--   donation service when it confirms a payment (website pay/Service.php; see website/README.md "Creator codes" for the
--   hook); read by the creator codes and the referral program (same payer = void).

CREATE TABLE IF NOT EXISTS `chaos_creator_codes` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `code` varchar(16) NOT NULL,
  `account_id` int(11) NOT NULL,
  `display_name` varchar(64) NOT NULL DEFAULT '',
  `pct` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `note` varchar(255) NOT NULL DEFAULT '',
  `created_at` int(10) unsigned NOT NULL DEFAULT 0,
  `created_by` varchar(64) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `chaos_creator_codes_code` (`code`),
  KEY `chaos_creator_codes_account` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_creator_support` (
  `account_id` int(11) NOT NULL,
  `code_id` int(11) NOT NULL,
  `set_at` int(10) unsigned NOT NULL,
  `expires_at` int(10) unsigned NOT NULL,
  `ip` varchar(64) NOT NULL DEFAULT '',
  PRIMARY KEY (`account_id`),
  KEY `chaos_creator_support_code` (`code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_creator_uses` (
  `order_id` int(11) NOT NULL,
  `code_id` int(11) NOT NULL,
  `creator_account_id` int(11) NOT NULL,
  `buyer_account_id` int(11) NOT NULL,
  `coins_base` int(11) NOT NULL DEFAULT 0,
  `share` int(11) NOT NULL DEFAULT 0,
  `state` varchar(8) NOT NULL DEFAULT 'pending',
  `reason` varchar(16) NOT NULL DEFAULT '',
  `created_at` int(10) unsigned NOT NULL DEFAULT 0,
  `credited_at` int(10) unsigned NOT NULL DEFAULT 0,
  `settled_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`order_id`),
  KEY `chaos_creator_uses_code` (`code_id`, `state`),
  KEY `chaos_creator_uses_creator` (`creator_account_id`, `state`, `settled_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_creator_log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `at` int(10) unsigned NOT NULL,
  `code_id` int(11) NOT NULL DEFAULT 0,
  `account_id` int(11) NOT NULL DEFAULT 0,
  `order_id` int(11) NOT NULL DEFAULT 0,
  `action` varchar(16) NOT NULL,
  `detail` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `chaos_creator_log_code` (`code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_pay_payers` (
  `order_id` int(11) NOT NULL,
  `account_id` int(11) NOT NULL,
  `payer_hash` char(64) NOT NULL,
  `created_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`order_id`),
  KEY `chaos_pay_payers_account` (`account_id`),
  KEY `chaos_pay_payers_hash` (`payer_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
