-- Spell ranks, the account echo (data/scripts/chaos/spell_ranks.lua; docs/SPELL_UPGRADES.md 1.7 and 7.2; server/README.md
-- "Spell ranks (O686 phase 2)"). spell_ranks.lua also creates the table at startup when it is missing (same columns). Run once:
--   mysql -u USER -p DB < chaos_spell_ranks.sql
--
-- The best rank any character of an account reached on a spell. A new or low character of the account gets a floor of
-- min(10, floor(0.5 x best_rank)) on that spell (spell_ranks_config.lua `echo`). Written when a rank rises, read at login.
-- Forms and awakening are never inherited. Tester bots are never written.
CREATE TABLE IF NOT EXISTS `chaos_spell_ranks` (
  `account_id` int(10) unsigned NOT NULL,
  `spell_id` smallint(5) unsigned NOT NULL,
  `best_rank` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `spell_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
