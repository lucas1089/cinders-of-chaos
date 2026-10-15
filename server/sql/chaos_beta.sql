-- Beta starter coins (data/scripts/chaos/beta.lua, beta_core.lua): one row per account that got its beta Chaos Coins,
-- so the grant is given once per account, across restarts. beta.lua also creates this table at startup if it is missing.
-- Wiped with the beta (docs/BETA.md section 9 truncates every chaos_* table but a few).
CREATE TABLE IF NOT EXISTS `chaos_beta_grants` (
  `account_id` int(11) NOT NULL,
  `kind` varchar(16) NOT NULL DEFAULT 'starter',
  `coins` int(11) NOT NULL DEFAULT 0,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `granted_at` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
