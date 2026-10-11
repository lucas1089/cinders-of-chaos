-- The Scorched Marches, the open-world PvP zone (data/scripts/chaos/pvpzone.lua; numbers in pvpzone_config.lua; see
-- server/README.md "The Scorched Marches (open-world PvP zone)"). Safe to run more than once (CREATE TABLE IF NOT
-- EXISTS); pvpzone.lua creates the same tables at startup when missing.
-- chaos_pvpzone_players: per character: banked embers and their total, counted defeats dealt, defeats taken, shrine
--   captures, the biggest haul banked at one exit, the faction pledge and when it was made, today's reputation from
--   Marches kills and embers taken from other players' piles (day = YYYYMMDD, from 06:00), this week's banked embers
--   (week = YYYYMMDD of the Monday). Carried embers are a player storage (7100522), not here.
-- chaos_pvpzone_control: the faction holding the Cinder Shrine per realm (0 = standard, else the season id) and until when.
-- chaos_pvpzone_purchases: the embers vendor's log (and the weekly limits).
CREATE TABLE IF NOT EXISTS `chaos_pvpzone_players` (
  `player_id` int(11) NOT NULL,
  `banked` int(10) unsigned NOT NULL DEFAULT 0,
  `banked_total` int(10) unsigned NOT NULL DEFAULT 0,
  `kills` int(10) unsigned NOT NULL DEFAULT 0,
  `defeats` int(10) unsigned NOT NULL DEFAULT 0,
  `captures` int(10) unsigned NOT NULL DEFAULT 0,
  `haul` int(10) unsigned NOT NULL DEFAULT 0,
  `pledge` varchar(16) NOT NULL DEFAULT '',
  `pledge_at` int(10) unsigned NOT NULL DEFAULT 0,
  `day` int(10) unsigned NOT NULL DEFAULT 0,
  `day_rep` int(10) unsigned NOT NULL DEFAULT 0,
  `day_picked` int(10) unsigned NOT NULL DEFAULT 0,
  `week` int(10) unsigned NOT NULL DEFAULT 0,
  `week_banked` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_pvpzone_control` (
  `realm` int(11) NOT NULL,
  `faction` varchar(16) NOT NULL DEFAULT '',
  `at` int(10) unsigned NOT NULL DEFAULT 0,
  `until_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`realm`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_pvpzone_purchases` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL,
  `offer` varchar(16) NOT NULL,
  `week` int(10) unsigned NOT NULL DEFAULT 0,
  `cost` int(10) unsigned NOT NULL,
  `at` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `chaos_pvpzone_purchases_player` (`player_id`, `week`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
