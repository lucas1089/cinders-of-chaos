-- Hideouts (data/scripts/chaos/hideout.lua; hideout.lua also creates these at startup when missing).
-- chaos_hideouts: one row per character that changed its hideout or was visited: theme, permission (0 private,
--   1 friends, 2 guild, 3 public), unique visits per day and likes (the showcase reads them).
-- chaos_hideout_decor: the placed decorations: decor_id (per hideout), the decoration key of hideout_config.lua, the
--   inner grid tile (x 1..15 / y 1..11; 0 = the west / north wall for wall decorations) and the rotation.
-- chaos_hideout_unlocks: unlocked decorations and themes ("theme:<key>"). Earned ones are per character (player_id),
--   bought ones per account (player_id 0); `source` = the source type that unlocked it.
-- chaos_hideout_visits: the day key (YYYYMMDD) of a character's last visit to a hideout (one visit a day counts).
-- chaos_hideout_likes: one like per account and hideout.

CREATE TABLE IF NOT EXISTS `chaos_hideouts` (`player_id` int(11) NOT NULL,
  `theme` varchar(32) NOT NULL DEFAULT '', `permission` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `visits` int(10) unsigned NOT NULL DEFAULT 0, `likes` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`), KEY `chaos_hideouts_perm` (`permission`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_hideout_decor` (`player_id` int(11) NOT NULL, `decor_id` smallint(5) unsigned NOT NULL,
  `decor` varchar(32) NOT NULL, `x` tinyint(3) unsigned NOT NULL, `y` tinyint(3) unsigned NOT NULL,
  `rot` tinyint(3) unsigned NOT NULL DEFAULT 1, PRIMARY KEY (`player_id`, `decor_id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_hideout_unlocks` (`account_id` int(11) NOT NULL, `player_id` int(11) NOT NULL,
  `unlock_key` varchar(40) NOT NULL, `source` varchar(16) NOT NULL DEFAULT '', `created_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `player_id`, `unlock_key`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_hideout_visits` (`owner_id` int(11) NOT NULL, `visitor_id` int(11) NOT NULL,
  `day` int(10) unsigned NOT NULL DEFAULT 0, `visited_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`owner_id`, `visitor_id`), KEY `chaos_hideout_visits_visitor` (`visitor_id`, `visited_at`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_hideout_likes` (`owner_id` int(11) NOT NULL, `account_id` int(11) NOT NULL,
  `liked_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`owner_id`, `account_id`),
  KEY `chaos_hideout_likes_account` (`account_id`, `liked_at`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;
