-- Founder Pack (O322, data/scripts/chaos/founder.lua; see server/README.md "Founder Pack"). Safe to run more than once;
-- founder.lua creates the same table at startup.
-- chaos_founder_revokes: one row per account and tier whose Founder Pack was taken back because the donation that paid for it
--   was refunded or charged back (shop_payments.lua processReversals). The unique key is the guard: a tier is taken back once.
--   pieces = exclusives removed, pact_days = Pact days removed, order_id = the donation, purchase_id = the store log row.

CREATE TABLE IF NOT EXISTS `chaos_founder_revokes` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `tier` varchar(32) NOT NULL,
  `order_id` int(11) NOT NULL DEFAULT 0,
  `purchase_id` int(11) NOT NULL DEFAULT 0,
  `pieces` int(11) NOT NULL DEFAULT 0,
  `pact_days` int(11) NOT NULL DEFAULT 0,
  `reason` varchar(64) NOT NULL DEFAULT '',
  `at` bigint(20) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `chaos_founder_revokes_tier` (`account_id`, `tier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
