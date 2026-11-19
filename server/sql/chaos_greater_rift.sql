-- Greater Rift ladder and rewards (data/scripts/chaos/greater_ladder.lua, greater_ladder_core.lua, rift_config.lua `greater`;
-- server/README.md "Greater Rift (O668)"). Run after the stock TFS schema (players):
--   mysql -u USER -p DB < chaos_greater_rift.sql

-- Best shown tier (16 and up), then least seconds, per season, character and mode (0 solo, 1 party of 2-5). voc = the
-- vocation id of the run that set the best (the class board). Tester bots are never written.
CREATE TABLE IF NOT EXISTS `chaos_greater_rift` (
  `season` int(10) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  `mode` tinyint(3) unsigned NOT NULL,
  `voc` int(11) NOT NULL DEFAULT 0,
  `best_tier` smallint(5) unsigned NOT NULL DEFAULT 0,
  `best_time` int(10) unsigned NOT NULL DEFAULT 0,
  `runs` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`season`, `player_id`, `mode`),
  KEY `chaos_greater_rift_rank` (`season`, `mode`, `best_tier`, `best_time`),
  CONSTRAINT `chaos_greater_rift_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Rewards waiting for delivery into the inbox (an online character gets them at once, an offline one at the next login).
-- kind 'pb' = personal best of a shown tier (slot = the tier, once per season and character over both modes), kind 'season'
-- = the season-end bracket (slot = the mode). rewarded is set before the items are made, so a failure never pays twice.
CREATE TABLE IF NOT EXISTS `chaos_greater_rift_rewards` (
  `season` int(10) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  `kind` varchar(8) NOT NULL,
  `slot` int(10) unsigned NOT NULL,
  `tier` smallint(5) unsigned NOT NULL DEFAULT 0,
  `place` int(10) unsigned NOT NULL DEFAULT 0,
  `label` varchar(48) NOT NULL DEFAULT '',
  `fate` int(10) unsigned NOT NULL DEFAULT 0,
  `upheaval` int(10) unsigned NOT NULL DEFAULT 0,
  `fragments` int(10) unsigned NOT NULL DEFAULT 0,
  `gold` bigint(20) unsigned NOT NULL DEFAULT 0,
  `rewarded` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `awarded_at` int(10) unsigned NOT NULL DEFAULT 0,
  `delivered_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`season`, `player_id`, `kind`, `slot`),
  KEY `chaos_greater_rift_rewards_pending` (`player_id`, `rewarded`),
  CONSTRAINT `chaos_greater_rift_rewards_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
