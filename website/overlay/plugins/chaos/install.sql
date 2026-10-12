-- Cinders of Chaos plugin. Idempotent (run again on every update).
-- The class lock table of the game server (server/sql/chaos_class_unlocks.sql; the server also creates it at
-- startup). Created here too so the character creation check works before the server's first start.
CREATE TABLE IF NOT EXISTS `chaos_class_unlocks` (
  `account_id` int(11) NOT NULL,
  `class_key` varchar(32) NOT NULL,
  `source` varchar(32) NOT NULL DEFAULT '',
  `created` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `class_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Paid Chaos Coin orders (server/sql/chaos.sql; the game server also creates it at startup). The site writes 'paid'
-- rows through chaos_coin_order_paid (lib.php); the game server credits them (shop.lua).
CREATE TABLE IF NOT EXISTS `chaos_coin_orders` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `pack_key` varchar(32) NOT NULL,
  `provider` varchar(32) NOT NULL DEFAULT '',
  `provider_ref` varchar(128) NOT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'paid',
  `coins` int(11) NOT NULL DEFAULT 0,
  `bonus` int(11) NOT NULL DEFAULT 0,
  `first_bonus` int(11) NOT NULL DEFAULT 0,
  `note` varchar(255) NOT NULL DEFAULT '',
  `created` int(10) unsigned NOT NULL,
  `credited` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `chaos_coin_orders_ref` (`provider`, `provider_ref`),
  KEY `chaos_coin_orders_status` (`status`),
  KEY `chaos_coin_orders_account` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- The Pix / PayPal donation of an order (server/sql/chaos.sql; the game server also creates it at startup). Written by
-- the game server or the donation page, filled in by plugins/chaos/pay (worker and webhook).
CREATE TABLE IF NOT EXISTS `chaos_coin_payments` (
  `order_id` int(11) NOT NULL,
  `method` varchar(16) NOT NULL,
  `token` varchar(64) NOT NULL,
  `amount_cents` int(11) NOT NULL,
  `currency` char(3) NOT NULL,
  `source` varchar(8) NOT NULL DEFAULT 'client',
  `psp` varchar(16) NOT NULL DEFAULT '',
  `psp_id` varchar(128) NOT NULL DEFAULT '',
  `psp_ref` varchar(128) NOT NULL DEFAULT '',
  `psp_status` varchar(32) NOT NULL DEFAULT '',
  `qr_code` varchar(1024) NOT NULL DEFAULT '',
  `pay_url` varchar(1024) NOT NULL DEFAULT '',
  `qr_image` mediumtext NULL,
  `expires` int(10) unsigned NOT NULL DEFAULT 0,
  `attempts` int(11) NOT NULL DEFAULT 0,
  `claimed` int(10) unsigned NOT NULL DEFAULT 0,
  `checked` int(10) unsigned NOT NULL DEFAULT 0,
  `cancel_sent` tinyint(1) NOT NULL DEFAULT 0,
  `paid_at` int(10) unsigned NOT NULL DEFAULT 0,
  `reversal` varchar(16) NOT NULL DEFAULT '',
  `reversal_cents` int(11) NOT NULL DEFAULT 0,
  `reversal_done` tinyint(1) NOT NULL DEFAULT 0,
  `reversal_coins` int(11) NOT NULL DEFAULT 0,
  `reversal_at` int(10) unsigned NOT NULL DEFAULT 0,
  `note` varchar(255) NOT NULL DEFAULT '',
  `updated` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`order_id`),
  UNIQUE KEY `chaos_coin_payments_token` (`token`),
  KEY `chaos_coin_payments_psp` (`psp`, `psp_id`),
  KEY `chaos_coin_payments_ref` (`psp`, `psp_ref`),
  KEY `chaos_coin_payments_reversal` (`reversal_done`, `reversal`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Accounts created on the website per address (register_guard.php: the per-IP limit of account creation). Rows older
-- than a day are deleted by the site. Website only; the game server does not use it.
CREATE TABLE IF NOT EXISTS `chaos_web_registrations` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `ip` varchar(64) NOT NULL,
  `created` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `chaos_web_registrations_ip` (`ip`, `created`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Account recovery links (recovery_lib.php, README "Mail"): the SHA-256 of the one-time token, one row per account
-- (a new request replaces the older link), deleted when used or expired. Website only.
CREATE TABLE IF NOT EXISTS `chaos_password_resets` (
  `account_id` int(11) NOT NULL,
  `token_hash` char(64) NOT NULL,
  `created` int(10) unsigned NOT NULL,
  `expires` int(10) unsigned NOT NULL,
  PRIMARY KEY (`account_id`),
  UNIQUE KEY `chaos_password_resets_token` (`token_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Recovery requests per address and links mailed per account (the limits of recovery_lib.php). Rows older than a day
-- are deleted by the site. Website only.
CREATE TABLE IF NOT EXISTS `chaos_recovery_requests` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `ip` varchar(64) NOT NULL,
  `account_id` int(11) NOT NULL DEFAULT 0,
  `created` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `chaos_recovery_requests_ip` (`ip`, `created`),
  KEY `chaos_recovery_requests_account` (`account_id`, `created`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
