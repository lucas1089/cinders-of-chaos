-- The battleground "Ember Wells" and the PvP seasons (data/scripts/chaos/battleground.lua, arena_season.lua; numbers in
-- battleground_config.lua; see server/README.md "Battleground and PvP seasons"). Safe to run more than once (CREATE TABLE
-- IF NOT EXISTS); both scripts create the same tables at startup when missing.
-- chaos_pvp_players: per character: honor (the PvP vendor's currency) and its total, the battleground record, this
--   week's honor from matches and first win (week = YYYYMMDD of the Monday), the deserter penalty and its log
--   (os.time of the desertions of the last day, comma separated).
-- chaos_pvp_ratings: the season rating of a character per season and bracket (1v1, 2v2, 3v3, bg): Glicko-lite rating
--   and deviation, record, peak and the last rated match (inactivity decay and rd growth).
-- chaos_pvp_season_rewards: what a character got at a season's end: the tier (1-6) of the best placed bracket, its
--   rating, honor, the title and plate frame, the cosmetics granted to the account.
-- chaos_bg_matches: one row per rated battleground match.
-- chaos_pvp_purchases: the honor vendor's log.

CREATE TABLE IF NOT EXISTS `chaos_pvp_players` (`player_id` int(11) NOT NULL, `honor` int(10) unsigned NOT NULL DEFAULT 0,
  `honor_total` int(10) unsigned NOT NULL DEFAULT 0, `matches` int(10) unsigned NOT NULL DEFAULT 0,
  `wins` int(10) unsigned NOT NULL DEFAULT 0, `losses` int(10) unsigned NOT NULL DEFAULT 0, `draws` int(10) unsigned NOT NULL DEFAULT 0,
  `kills` int(10) unsigned NOT NULL DEFAULT 0, `downs` int(10) unsigned NOT NULL DEFAULT 0, `captures` int(10) unsigned NOT NULL DEFAULT 0,
  `week` int(10) unsigned NOT NULL DEFAULT 0, `week_honor` int(10) unsigned NOT NULL DEFAULT 0, `week_win` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `deserter_until` int(10) unsigned NOT NULL DEFAULT 0, `deserter_log` varchar(255) NOT NULL DEFAULT '',
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_pvp_ratings` (`season` smallint(5) unsigned NOT NULL, `player_id` int(11) NOT NULL,
  `bracket` varchar(8) NOT NULL, `rating` int(11) NOT NULL, `rd` int(11) NOT NULL, `matches` int(10) unsigned NOT NULL DEFAULT 0,
  `wins` int(10) unsigned NOT NULL DEFAULT 0, `losses` int(10) unsigned NOT NULL DEFAULT 0, `draws` int(10) unsigned NOT NULL DEFAULT 0,
  `peak` int(11) NOT NULL DEFAULT 0, `last_match` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`season`, `player_id`, `bracket`),
  KEY `chaos_pvp_ratings_player` (`player_id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_pvp_season_rewards` (`season` smallint(5) unsigned NOT NULL, `player_id` int(11) NOT NULL,
  `account_id` int(11) NOT NULL DEFAULT 0, `tier` tinyint(3) unsigned NOT NULL, `bracket` varchar(8) NOT NULL DEFAULT '',
  `rating` int(11) NOT NULL DEFAULT 0, `honor` int(10) unsigned NOT NULL DEFAULT 0, `title` varchar(32) NOT NULL DEFAULT '',
  `frame` varchar(16) NOT NULL DEFAULT '', `cosmetics` varchar(128) NOT NULL DEFAULT '', `granted_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`season`, `player_id`), KEY `chaos_pvp_season_rewards_player` (`player_id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_bg_matches` (`id` int(11) NOT NULL AUTO_INCREMENT, `realm` int(11) NOT NULL DEFAULT 0,
  `bracket` varchar(8) NOT NULL DEFAULT '', `size` tinyint(3) unsigned NOT NULL DEFAULT 0, `slot` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `winner` tinyint(3) unsigned NOT NULL DEFAULT 0, `score1` int(10) unsigned NOT NULL DEFAULT 0, `score2` int(10) unsigned NOT NULL DEFAULT 0,
  `reason` varchar(16) NOT NULL DEFAULT '', `started_at` int(10) unsigned NOT NULL DEFAULT 0, `ended_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_pvp_purchases` (`id` int(11) NOT NULL AUTO_INCREMENT, `player_id` int(11) NOT NULL,
  `offer` varchar(16) NOT NULL, `cost` int(10) unsigned NOT NULL, `at` int(10) unsigned NOT NULL, PRIMARY KEY (`id`),
  KEY `chaos_pvp_purchases_player` (`player_id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;
