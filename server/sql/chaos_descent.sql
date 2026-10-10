-- The Ember Descent (data/scripts/chaos/descent.lua; numbers in descent_config.lua; see server/README.md "The Ember Descent").
-- Safe to run more than once (CREATE TABLE IF NOT EXISTS); descent.lua creates the same tables at startup when missing.
-- chaos_descent_players: one row per character: the best depth ever and whether the boss was ever slain, the day key
--   (YYYYMMDD) of the last free normal run and the week key of the last free weekly run, the best depth of the weekly
--   seeded run in `week`, runs and full clears.
-- chaos_descent_runs: one row per character and run at its exit: seed, mode (daily / weekly), how it was paid (free /
--   sigil), the depth reached of the run's rooms, cleared (the boss slain), result (cleared, fallen, time, left, logout,
--   shutdown), party size, seconds, gold given, the unique given (server id or 0) and the boons held ("key x stacks").

CREATE TABLE IF NOT EXISTS `chaos_descent_players` (`player_id` int(11) NOT NULL,
  `best_depth` smallint(5) unsigned NOT NULL DEFAULT 0, `best_clear` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `free_day` int(10) unsigned NOT NULL DEFAULT 0, `free_week` int(10) unsigned NOT NULL DEFAULT 0,
  `week` int(10) unsigned NOT NULL DEFAULT 0, `week_best` smallint(5) unsigned NOT NULL DEFAULT 0,
  `runs` int(10) unsigned NOT NULL DEFAULT 0, `clears` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_descent_runs` (`id` int(11) NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL, `run` int(11) NOT NULL DEFAULT 0, `seed` int(10) unsigned NOT NULL DEFAULT 0,
  `mode` varchar(8) NOT NULL DEFAULT 'daily', `paid` varchar(8) NOT NULL DEFAULT 'free',
  `depth` smallint(5) unsigned NOT NULL DEFAULT 0, `rooms` smallint(5) unsigned NOT NULL DEFAULT 0,
  `cleared` tinyint(1) unsigned NOT NULL DEFAULT 0, `result` varchar(12) NOT NULL DEFAULT '',
  `party` tinyint(3) unsigned NOT NULL DEFAULT 1, `seconds` int(10) unsigned NOT NULL DEFAULT 0,
  `gold` bigint(20) unsigned NOT NULL DEFAULT 0, `unique_id` int(11) NOT NULL DEFAULT 0,
  `boons` varchar(255) NOT NULL DEFAULT '', `started_at` int(10) unsigned NOT NULL DEFAULT 0,
  `ended_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `chaos_descent_runs_player` (`player_id`, `id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;
