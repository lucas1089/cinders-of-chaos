-- Market price history (data/scripts/chaos/market_history.lua; numbers in market_history_config.lua; see server/README.md
-- "Market", Price history). Safe to run more than once (CREATE TABLE IF NOT EXISTS); market_history.lua creates the same
-- tables at startup when missing.
-- chaos_market_history: one row per completed sale (a bought offer or a buy order fill; offer_id unique): the key (realm
--   = 0 standard or the season id, item type, rarity, item level band, currency), the price per unit, the units, when.
--   Kept for market_history_config.lua rawDays full days, then aggregated into chaos_market_history_daily.
-- chaos_market_history_daily: one row per key and day: sales, units, median, low, high and the trimmed mean of the day's
--   prices per unit; dropped after keepDays.

CREATE TABLE IF NOT EXISTS `chaos_market_history` (`id` int(11) NOT NULL AUTO_INCREMENT,
  `realm` int(11) NOT NULL DEFAULT 0, `item_id` int(11) NOT NULL, `rarity` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `band` int(11) NOT NULL DEFAULT 0, `currency` varchar(8) NOT NULL DEFAULT 'gold', `price` bigint(20) unsigned NOT NULL,
  `count` int(11) NOT NULL DEFAULT 1, `at` int(10) unsigned NOT NULL, `day` int(11) NOT NULL, `offer_id` int(11) NOT NULL,
  PRIMARY KEY (`id`), UNIQUE KEY `chaos_market_history_offer` (`offer_id`),
  KEY `chaos_market_history_key` (`realm`, `item_id`, `rarity`, `band`, `currency`, `at`), KEY `chaos_market_history_day` (`day`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_market_history_daily` (`realm` int(11) NOT NULL DEFAULT 0, `item_id` int(11) NOT NULL,
  `rarity` tinyint(3) unsigned NOT NULL DEFAULT 0, `band` int(11) NOT NULL DEFAULT 0, `currency` varchar(8) NOT NULL DEFAULT 'gold',
  `day` int(11) NOT NULL, `sales` int(11) NOT NULL DEFAULT 0, `units` int(11) NOT NULL DEFAULT 0,
  `median` bigint(20) unsigned NOT NULL DEFAULT 0, `low` bigint(20) unsigned NOT NULL DEFAULT 0,
  `high` bigint(20) unsigned NOT NULL DEFAULT 0, `mean` bigint(20) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`realm`, `item_id`, `rarity`, `band`, `currency`, `day`), KEY `chaos_market_history_daily_day` (`day`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;
