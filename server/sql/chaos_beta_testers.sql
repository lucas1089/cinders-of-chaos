-- Beta testers (data/scripts/chaos/beta_tester.lua, beta_core.lua): one row per account that logged in during a beta window
-- (beta_config.lua tester.windows). KEPT by the wipe (docs/BETA.md section 9 lists it with the tables that stay): at launch,
-- with the beta switch off, these accounts hold the cosmetic title "Beta Tester". beta_tester.lua also creates this table.
CREATE TABLE IF NOT EXISTS `chaos_beta_testers` (
  `account_id` int(11) NOT NULL,
  `first_at` bigint(20) NOT NULL DEFAULT 0,
  `player_id` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
