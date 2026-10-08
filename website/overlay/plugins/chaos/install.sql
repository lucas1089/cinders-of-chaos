-- Project Chaos plugin. Idempotent (run again on every update).
-- The class lock table of the game server (server/sql/chaos_class_unlocks.sql; the server also creates it at
-- startup). Created here too so the character creation check works before the server's first start.
CREATE TABLE IF NOT EXISTS `chaos_class_unlocks` (
  `account_id` int(11) NOT NULL,
  `class_key` varchar(32) NOT NULL,
  `source` varchar(32) NOT NULL DEFAULT '',
  `created` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `class_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
