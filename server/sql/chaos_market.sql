-- Chaos market (data/scripts/chaos/market.lua; numbers in market_config.lua; see server/README.md "Market").
-- Safe to run more than once (CREATE TABLE IF NOT EXISTS); market.lua creates the same tables at startup when missing.
-- chaos_market_offers: one row per offer; `data` holds the listed item (escrow: codec "blob" = hex of the engine's
--   own attribute serialization, engine patch 0017; "attrs" = key list), `tip` the tooltip snapshot (JSON).
--   state 0 active, 1 sold, 2 cancelled, 3 expired, 9 pending (a listing being written; resolved at login / startup).
-- chaos_market_deliveries: what the market owes a character (the item of an offer, gold from a sale, or the notice of a
--   coin sale: the coins are moved in the purchase transaction), applied in
--   id order when the character is online; the storage 7100971 (deliverSeq) makes it crash safe.
-- chaos_market_log: every listing, sale, cancel, expiry, delivery, recovery and error.
-- chaos_market_offer_mods: the modifiers of each active / pending offer (key, value, tier) for the Browse modifier
--   filter; written with the offer, removed when the offer closes. The offers' columns sockets, quality, free_prefix,
--   free_suffix, has_power, bound_mods are the other filters; mods_indexed = 1 once the offer's rows are written (the
--   offers listed before this existed are indexed from their tooltip snapshot at startup, recorded in server_config).

CREATE TABLE IF NOT EXISTS `chaos_market_offers` (`id` int(11) NOT NULL AUTO_INCREMENT,
  `realm` int(11) NOT NULL DEFAULT 0, `state` tinyint(3) unsigned NOT NULL DEFAULT 9,
  `seller_id` int(11) NOT NULL, `seller_account` int(11) NOT NULL, `seller_name` varchar(64) NOT NULL DEFAULT '',
  `item_id` int(11) NOT NULL, `client_id` int(11) NOT NULL DEFAULT 0, `count` int(11) NOT NULL DEFAULT 1,
  `name` varchar(100) NOT NULL DEFAULT '', `category` varchar(16) NOT NULL DEFAULT 'misc',
  `rarity` tinyint(3) unsigned NOT NULL DEFAULT 0, `ilvl` int(11) NOT NULL DEFAULT 0,
  `unique_item` tinyint(1) NOT NULL DEFAULT 0, `mods` varchar(1000) NOT NULL DEFAULT '',
  `price_gold` bigint(20) unsigned NOT NULL DEFAULT 0, `price_coins` int(11) unsigned NOT NULL DEFAULT 0,
  `fee` bigint(20) unsigned NOT NULL DEFAULT 0, `codec` varchar(8) NOT NULL DEFAULT 'blob', `data` mediumtext NOT NULL,
  `tip` mediumtext NOT NULL, `created` int(10) unsigned NOT NULL, `expires` int(10) unsigned NOT NULL,
  `buyer_id` int(11) NOT NULL DEFAULT 0, `buyer_name` varchar(64) NOT NULL DEFAULT '',
  `paid_currency` varchar(8) NOT NULL DEFAULT '', `paid_amount` bigint(20) unsigned NOT NULL DEFAULT 0,
  `tax` bigint(20) unsigned NOT NULL DEFAULT 0, `closed_at` int(10) unsigned NOT NULL DEFAULT 0,
  `sockets` tinyint(3) unsigned NOT NULL DEFAULT 0, `quality` smallint(5) unsigned NOT NULL DEFAULT 0,
  `free_prefix` tinyint(3) unsigned NOT NULL DEFAULT 0, `free_suffix` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `has_power` tinyint(1) NOT NULL DEFAULT 0, `bound_mods` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `mods_indexed` tinyint(1) NOT NULL DEFAULT 0, PRIMARY KEY (`id`),
  KEY `chaos_market_browse` (`state`, `realm`, `expires`), KEY `chaos_market_seller` (`seller_id`, `state`),
  KEY `chaos_market_buyer` (`buyer_id`), KEY `chaos_market_account` (`seller_account`, `state`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_market_deliveries` (`id` int(11) NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL, `offer_id` int(11) NOT NULL, `kind` varchar(8) NOT NULL DEFAULT 'item',
  `amount` bigint(20) unsigned NOT NULL DEFAULT 0, `reason` varchar(16) NOT NULL DEFAULT '',
  `created` int(10) unsigned NOT NULL, `delivered` tinyint(1) NOT NULL DEFAULT 0,
  `delivered_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`),
  UNIQUE KEY `chaos_market_delivery_once` (`offer_id`, `kind`), KEY `chaos_market_owed` (`player_id`, `delivered`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_market_log` (`id` int(11) NOT NULL AUTO_INCREMENT, `at` int(10) unsigned NOT NULL,
  `action` varchar(12) NOT NULL, `offer_id` int(11) NOT NULL DEFAULT 0, `player_id` int(11) NOT NULL DEFAULT 0,
  `other_id` int(11) NOT NULL DEFAULT 0, `item_id` int(11) NOT NULL DEFAULT 0, `count` int(11) NOT NULL DEFAULT 0,
  `name` varchar(100) NOT NULL DEFAULT '', `currency` varchar(8) NOT NULL DEFAULT '',
  `amount` bigint(20) NOT NULL DEFAULT 0, `fee` bigint(20) NOT NULL DEFAULT 0, `text` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`), KEY `chaos_market_log_offer` (`offer_id`), KEY `chaos_market_log_player` (`player_id`, `id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- the modifier filter (added after the first version: safe on a database that has the tables already; MariaDB's
-- ADD COLUMN IF NOT EXISTS)
ALTER TABLE `chaos_market_offers` ADD COLUMN IF NOT EXISTS `sockets` tinyint(3) unsigned NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `quality` smallint(5) unsigned NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `free_prefix` tinyint(3) unsigned NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `free_suffix` tinyint(3) unsigned NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `has_power` tinyint(1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `bound_mods` tinyint(3) unsigned NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `mods_indexed` tinyint(1) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS `chaos_market_offer_mods` (`offer_id` int(11) NOT NULL, `mod_key` varchar(48) NOT NULL,
  `value` int(11) NOT NULL DEFAULT 0, `tier` tinyint(3) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`offer_id`, `mod_key`),
  KEY `chaos_market_mod_value` (`mod_key`, `value`), KEY `chaos_market_mod_tier` (`mod_key`, `tier`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- buy orders (market_orders_core.lua; see server/README.md "Market", Buy orders): what a buyer wants (item kind, a filter
--   in the Browse modifier filter's language as text, quantity, price per unit in gold OR coins), the escrowed payment
--   (`escrow`: price x the units not bought yet), the fee, and on close what went back (`refunded`).
--   state 0 active, 1 filled, 2 cancelled, 3 expired. A fill is a chaos_market_offers row with `order_id` = the order
--   (state 1 sold, 9 while it is written); a refund is a chaos_market_deliveries row with `offer_id` = -order id.
CREATE TABLE IF NOT EXISTS `chaos_market_orders` (`id` int(11) NOT NULL AUTO_INCREMENT,
  `realm` int(11) NOT NULL DEFAULT 0, `state` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `buyer_id` int(11) NOT NULL, `buyer_account` int(11) NOT NULL, `buyer_name` varchar(64) NOT NULL DEFAULT '',
  `item_id` int(11) NOT NULL, `client_id` int(11) NOT NULL DEFAULT 0, `name` varchar(100) NOT NULL DEFAULT '',
  `category` varchar(16) NOT NULL DEFAULT 'misc', `stackable` tinyint(1) NOT NULL DEFAULT 0,
  `quantity` int(11) NOT NULL DEFAULT 1, `filled` int(11) NOT NULL DEFAULT 0, `currency` varchar(8) NOT NULL DEFAULT 'gold',
  `price` bigint(20) unsigned NOT NULL DEFAULT 0, `escrow` bigint(20) unsigned NOT NULL DEFAULT 0,
  `refunded` bigint(20) unsigned NOT NULL DEFAULT 0, `fee` bigint(20) unsigned NOT NULL DEFAULT 0,
  `filter` varchar(1000) NOT NULL DEFAULT '', `created` int(10) unsigned NOT NULL, `expires` int(10) unsigned NOT NULL,
  `closed_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`),
  KEY `chaos_market_orders_list` (`state`, `realm`, `expires`), KEY `chaos_market_orders_buyer` (`buyer_id`, `state`),
  KEY `chaos_market_orders_account` (`buyer_account`, `state`), KEY `chaos_market_orders_item` (`item_id`, `state`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

ALTER TABLE `chaos_market_offers` ADD COLUMN IF NOT EXISTS `order_id` int(11) NOT NULL DEFAULT 0,
  ADD INDEX IF NOT EXISTS `chaos_market_offer_order` (`order_id`);
