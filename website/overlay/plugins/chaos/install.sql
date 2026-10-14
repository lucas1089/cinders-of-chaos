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

-- Acceptance of the Terms of Use and the Privacy Policy at account creation (legal_lib.php, README "Legal pages"):
-- the account, the version of the texts (the first 16 hex digits of the SHA-256 of the Portuguese texts) and the time.
-- No IP address. Website only.
CREATE TABLE IF NOT EXISTS `chaos_legal_acceptance` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `version` varchar(32) NOT NULL,
  `accepted_at` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `chaos_legal_acceptance_account` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- The client's account API (client_api_lib.php, README "Client API"). Website only.
-- Session tokens: the SHA-256 of the random token (never the token), the account, the mark of its password hash at
-- login (a password change ends the token), the address it came from, and when it ends.
CREATE TABLE IF NOT EXISTS `chaos_client_tokens` (
  `token_hash` char(64) NOT NULL,
  `account_id` int(11) NOT NULL,
  `pass_mark` varchar(96) NOT NULL,
  `ip` varchar(64) NOT NULL DEFAULT '',
  `created` int(10) unsigned NOT NULL,
  `expires` int(10) unsigned NOT NULL,
  PRIMARY KEY (`token_hash`),
  KEY `chaos_client_tokens_account` (`account_id`),
  KEY `chaos_client_tokens_expires` (`expires`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Requests per address (the per-minute limit) and characters created per account and address (the hourly limits).
-- Rows older than a day are deleted by the site.
CREATE TABLE IF NOT EXISTS `chaos_client_api_log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `ip` varchar(64) NOT NULL,
  `account_id` int(11) NOT NULL DEFAULT 0,
  `action` varchar(16) NOT NULL,
  `ok` tinyint(1) NOT NULL DEFAULT 0,
  `created` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `chaos_client_api_log_ip` (`ip`, `created`),
  KEY `chaos_client_api_log_account` (`account_id`, `action`, `created`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Nonces of login and create requests (a replayed request is refused), kept two hours.
CREATE TABLE IF NOT EXISTS `chaos_client_nonces` (
  `nonce` varchar(64) NOT NULL,
  `created` int(10) unsigned NOT NULL,
  PRIMARY KEY (`nonce`),
  KEY `chaos_client_nonces_created` (`created`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- A season join chosen when the character was created (server/sql/chaos_season.sql; the game server also creates it
-- at startup). The game server joins the character at its first login with the in-game join (season.lua) and deletes
-- the row.
CREATE TABLE IF NOT EXISTS `chaos_season_requests` (
  `player_id` int(11) NOT NULL,
  `season` smallint(5) unsigned NOT NULL,
  `mode` varchar(16) NOT NULL DEFAULT 'standard',
  `requested_at` int(10) unsigned NOT NULL,
  PRIMARY KEY (`player_id`),
  CONSTRAINT `chaos_season_requests_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Creator codes (server/sql/chaos_creator_codes.sql; the game server also creates them at startup): the codes (an
-- administrator creates them on page.php?plugin=chaos&p=creator), the donor's pick, the donations that carried a code
-- and their share, the log, and the payer hash of a donation. creator_lib.php, README "Creator codes".
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

-- Character Bazaar (server/sql/chaos_bazaar.sql; the game server also creates them at startup): listings, bids with
-- their escrow, the log. bazaar_lib.php, README "Character Bazaar".
CREATE TABLE IF NOT EXISTS `chaos_bazaar_listings` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL,
  `seller_account_id` int(11) NOT NULL,
  `min_price` int(11) NOT NULL,
  `buyout` int(11) NOT NULL DEFAULT 0,
  `current_bid` int(11) NOT NULL DEFAULT 0,
  `current_bid_id` int(11) NOT NULL DEFAULT 0,
  `bidder_account_id` int(11) NOT NULL DEFAULT 0,
  `bids` int(11) NOT NULL DEFAULT 0,
  `fee_pct` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `fee` int(11) NOT NULL DEFAULT 0,
  `status` varchar(10) NOT NULL DEFAULT 'active',
  `reason` varchar(64) NOT NULL DEFAULT '',
  `created_at` int(10) unsigned NOT NULL,
  `ends_at` int(10) unsigned NOT NULL,
  `settled_at` int(10) unsigned NOT NULL DEFAULT 0,
  `player_name` varchar(255) NOT NULL DEFAULT '',
  `level` int(11) NOT NULL DEFAULT 0,
  `vocation` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `chaos_bazaar_listings_player` (`player_id`, `status`),
  KEY `chaos_bazaar_listings_status` (`status`, `ends_at`),
  KEY `chaos_bazaar_listings_seller` (`seller_account_id`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_bazaar_bids` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `listing_id` int(11) NOT NULL,
  `account_id` int(11) NOT NULL,
  `amount` int(11) NOT NULL,
  `escrow` int(11) NOT NULL DEFAULT 0,
  `buyout` tinyint(1) NOT NULL DEFAULT 0,
  `state` varchar(10) NOT NULL DEFAULT 'leading',
  `created_at` int(10) unsigned NOT NULL,
  `ip` varchar(64) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `chaos_bazaar_bids_listing` (`listing_id`, `state`),
  KEY `chaos_bazaar_bids_account` (`account_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_bazaar_log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `at` int(10) unsigned NOT NULL,
  `listing_id` int(11) NOT NULL DEFAULT 0,
  `account_id` int(11) NOT NULL DEFAULT 0,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `action` varchar(16) NOT NULL,
  `detail` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `chaos_bazaar_log_listing` (`listing_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Discord announcements (discord_lib.php, discord_worker.php; the game server's server/sql/chaos_discord.sql creates the
-- same tables): the queue the game writes and the worker's cursors. Here too, so the worker runs before the server.
CREATE TABLE IF NOT EXISTS `chaos_discord_queue` (`id` int unsigned NOT NULL AUTO_INCREMENT, `created_at` int unsigned NOT NULL, `kind` varchar(32) NOT NULL, `channel` varchar(32) NOT NULL DEFAULT 'default', `title` varchar(256) NOT NULL DEFAULT '', `body` text NOT NULL, `fields` text NOT NULL, `status` varchar(8) NOT NULL DEFAULT 'new', `attempts` int unsigned NOT NULL DEFAULT 0, `next_at` int unsigned NOT NULL DEFAULT 0, `sent_at` int unsigned NOT NULL DEFAULT 0, `error` varchar(255) NOT NULL DEFAULT '', PRIMARY KEY (`id`), KEY `status` (`status`, `next_at`, `id`), KEY `created` (`created_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS `chaos_discord_state` (`k` varchar(32) NOT NULL, `v` bigint NOT NULL DEFAULT 0, PRIMARY KEY (`k`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
