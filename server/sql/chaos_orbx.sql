-- Orb Exchange (data/scripts/chaos/orbexchange.lua; numbers in orbexchange_config.lua; see server/README.md "Orb Exchange").
-- Safe to run more than once (CREATE TABLE IF NOT EXISTS); orbexchange.lua creates the same tables at startup when missing.
-- chaos_orbx_orders: one row per order: gives `give_qty` of `give_asset` ("gold" or an orb key), wants at least
--   `want_qty` of `want_asset`; `given` / `got` so far (the escrow is give_qty - given), `rest_given` what it had given
--   as a taker before it went on the book (its ratio prices the rest from there), `refunded` on close, `fee` the gold
--   paid when placing (orb-for-orb), `pair` the pair key (orbexchange_core.lua pairKey).
--   state 0 active, 1 filled, 2 cancelled, 3 expired, 9 pending (orbs leaving the character; resolved at login / startup).
-- chaos_orbx_trades: one row per fill: the maker gave `a` of `maker_give`, the taker gave `b` of `taker_give`; the fees
--   of the gold leg (maker_fee: the maker received gold, taker_fee: the taker did).
-- chaos_orbx_deliveries: what the exchange owes a character (`asset` "gold" -> bank, an orb -> inbox, `item_id`), applied
--   in id order when the character is online; the storage 7100951 (deliverSeq) makes it crash safe. One row per
--   (order, trade, reason): reason "fill" (trade_id = the trade) or "refund" (trade_id = 0, cancel / expiry).
-- chaos_orbx_log: every order, cancel, expiry, delivery, recovery and error.

CREATE TABLE IF NOT EXISTS `chaos_orbx_orders` (`id` int(11) NOT NULL AUTO_INCREMENT,
  `realm` int(11) NOT NULL DEFAULT 0, `state` tinyint(3) unsigned NOT NULL DEFAULT 9,
  `player_id` int(11) NOT NULL, `account_id` int(11) NOT NULL, `player_name` varchar(64) NOT NULL DEFAULT '',
  `pair` varchar(40) NOT NULL, `give_asset` varchar(16) NOT NULL, `give_qty` bigint(20) unsigned NOT NULL,
  `want_asset` varchar(16) NOT NULL, `want_qty` bigint(20) unsigned NOT NULL,
  `given` bigint(20) unsigned NOT NULL DEFAULT 0, `got` bigint(20) unsigned NOT NULL DEFAULT 0,
  `rest_given` bigint(20) unsigned NOT NULL DEFAULT 0,
  `refunded` bigint(20) unsigned NOT NULL DEFAULT 0, `fee` bigint(20) unsigned NOT NULL DEFAULT 0,
  `created` int(10) unsigned NOT NULL, `expires` int(10) unsigned NOT NULL, `closed_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`), KEY `chaos_orbx_book` (`state`, `pair`, `give_asset`, `realm`), KEY `chaos_orbx_player` (`player_id`, `state`),
  KEY `chaos_orbx_account` (`account_id`, `state`), KEY `chaos_orbx_expiry` (`state`, `expires`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_orbx_trades` (`id` int(11) NOT NULL AUTO_INCREMENT,
  `realm` int(11) NOT NULL DEFAULT 0, `pair` varchar(40) NOT NULL, `at` int(10) unsigned NOT NULL,
  `maker_order` int(11) NOT NULL, `taker_order` int(11) NOT NULL, `maker_id` int(11) NOT NULL, `taker_id` int(11) NOT NULL,
  `maker_give` varchar(16) NOT NULL, `taker_give` varchar(16) NOT NULL,
  `a` bigint(20) unsigned NOT NULL, `b` bigint(20) unsigned NOT NULL,
  `maker_fee` bigint(20) unsigned NOT NULL DEFAULT 0, `taker_fee` bigint(20) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`), KEY `chaos_orbx_trades_pair` (`pair`, `realm`, `at`), KEY `chaos_orbx_trades_maker` (`maker_id`, `id`),
  KEY `chaos_orbx_trades_taker` (`taker_id`, `id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_orbx_deliveries` (`id` int(11) NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL, `order_id` int(11) NOT NULL, `trade_id` int(11) NOT NULL DEFAULT 0,
  `reason` varchar(8) NOT NULL DEFAULT 'fill', `asset` varchar(16) NOT NULL, `item_id` int(11) NOT NULL DEFAULT 0,
  `amount` bigint(20) unsigned NOT NULL DEFAULT 0, `created` int(10) unsigned NOT NULL,
  `delivered` tinyint(1) NOT NULL DEFAULT 0, `delivered_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`),
  UNIQUE KEY `chaos_orbx_delivery_once` (`order_id`, `trade_id`, `reason`), KEY `chaos_orbx_owed` (`player_id`, `delivered`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_orbx_log` (`id` int(11) NOT NULL AUTO_INCREMENT, `at` int(10) unsigned NOT NULL,
  `action` varchar(12) NOT NULL, `order_id` int(11) NOT NULL DEFAULT 0, `player_id` int(11) NOT NULL DEFAULT 0,
  `asset` varchar(16) NOT NULL DEFAULT '', `amount` bigint(20) NOT NULL DEFAULT 0, `text` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`), KEY `chaos_orbx_log_order` (`order_id`), KEY `chaos_orbx_log_player` (`player_id`, `id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;
