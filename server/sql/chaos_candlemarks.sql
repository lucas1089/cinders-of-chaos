-- Candlemarks (data/scripts/chaos/candlemarks.lua; numbers in candlemarks_config.lua; see server/README.md "Candlemarks").
-- Safe to run more than once (CREATE TABLE IF NOT EXISTS); candlemarks.lua creates the same tables at startup when missing.
-- chaos_candlemarks: one row per ACCOUNT: the balance every character of the account shares, earned and spent in all,
--   the day (YYYYMMDD, turning at dayResetHour) and the coins earned that day (the optional daily cap).
-- chaos_candlemark_progress: one row per character: seconds of online time toward its next coin. Written with every
--   coin (one transaction with the balance), every few minutes and at logout.
-- chaos_candlemark_purchases: one row per purchase: offer, limit_key and week (YYYYMMDD of the Monday) for the weekly
--   limits, price, what it delivers (`detail`: "items:id:count,..." or the kind), state 0 pending, 1 done, 2 refunded.
--   A pending row is settled at the character's next login against its delivery mark (storage 7102460).

CREATE TABLE IF NOT EXISTS `chaos_candlemarks` (`account_id` int(11) NOT NULL,
  `balance` int(11) NOT NULL DEFAULT 0, `earned` int(11) NOT NULL DEFAULT 0, `spent` int(11) NOT NULL DEFAULT 0,
  `day` int(11) NOT NULL DEFAULT 0, `today` int(11) NOT NULL DEFAULT 0, `updated` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_candlemark_progress` (`player_id` int(11) NOT NULL, `account_id` int(11) NOT NULL,
  `progress` int(11) NOT NULL DEFAULT 0, `updated` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_candlemark_purchases` (`id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL, `player_id` int(11) NOT NULL, `offer` varchar(64) NOT NULL,
  `limit_key` varchar(64) NOT NULL, `week` int(11) NOT NULL, `price` int(11) NOT NULL,
  `state` tinyint(3) unsigned NOT NULL DEFAULT 0, `detail` varchar(255) NOT NULL DEFAULT '',
  `created` int(10) unsigned NOT NULL, `done_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`), KEY `chaos_cm_week` (`account_id`, `week`, `limit_key`), KEY `chaos_cm_player` (`player_id`, `state`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;
