-- Character Bazaar (website plugins/chaos/bazaar_lib.php, pages/bazaar.php; the game server's login lock
-- data/scripts/chaos/bazaar.lua; numbers in bazaar_config.lua; server/README.md "Character Bazaar"). Safe to run more
-- than once; bazaar.lua and the website's install.sql create the same tables.
-- chaos_bazaar_listings: one row per auction. status: active (bids open; the character cannot log in), settling (ended,
--   the transfer is being done; still locked), sold, expired (no bid), cancelled (seller before a bid, or an
--   administrator: every escrow refunded), failed (the transfer could not be done: escrow refunded, reason). fee_pct =
--   the fee when listed; fee = the coins kept by the house on a sale. player_name / level / vocation: as listed.
--   active_player_id: generated, player_id while active or settling, else NULL; its unique key allows one open
--   listing per character (two list requests at once). Existing tables get it from website/setup/chaos_setup.php.
--   seller_slot: 1..maxActivePerAccount, given by the website at listing; active_seller_id: generated, seller_account_id
--   while active or settling, else NULL; the unique key on both holds the per-seller auction limit (two characters of
--   one account listed at once). Existing tables get them from website/setup/chaos_setup.php.
-- chaos_bazaar_bids: every bid. escrow = the Chaos Coins taken from the bidder's balance and held (0 once refunded or
--   paid to the seller). state: leading, outbid (refunded), won (paid), refunded (cancel / failure), buyout = 1 for a
--   buyout. ip = the bidder's address (the shill-bidding check: never the seller's connection).
-- chaos_bazaar_log: list, bid, refund, buyout, sale, transfer, cancel, refusals and the game's login refusals.

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
  `active_player_id` int(11) GENERATED ALWAYS AS (CASE WHEN `status` IN ('active', 'settling') THEN `player_id` ELSE NULL END) STORED,
  `seller_slot` tinyint(3) unsigned DEFAULT NULL,
  `active_seller_id` int(11) GENERATED ALWAYS AS (CASE WHEN `status` IN ('active', 'settling') THEN `seller_account_id` ELSE NULL END) STORED,
  PRIMARY KEY (`id`),
  UNIQUE KEY `chaos_bazaar_listings_active` (`active_player_id`),
  UNIQUE KEY `chaos_bazaar_listings_seller_slot` (`active_seller_id`, `seller_slot`),
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
