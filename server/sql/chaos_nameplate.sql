-- Name plates (data/scripts/chaos/nameplate.lua): the title each character chose with !title.
-- nameplate.lua also creates the table at startup when it is missing.
-- title_key: a key of ChaosTitles (e.g. "staff", "leaderboard:worldboss", "champion:siege") or "none" (hidden);
-- no row = the default title (staff first, then the most recently earned).
CREATE TABLE IF NOT EXISTS `chaos_player_titles` (
  `player_id` int(11) NOT NULL,
  `title_key` varchar(64) NOT NULL DEFAULT '',
  `updated` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
