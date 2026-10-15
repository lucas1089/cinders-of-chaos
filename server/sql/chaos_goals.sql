-- Next Goals (server/data/scripts/chaos/goals.lua; server/README.md "Next Goals"). goals.lua also creates it at startup.
-- One row per character and entry: "g:<goal key>" a goal done (value 1 rewarded, 2 found done at the first load, no
-- reward), "s:<stat>" an own stat of goals_config.lua `own` (the other counters are the achievements').
CREATE TABLE IF NOT EXISTS `chaos_goals` (
	`player_id` int(11) NOT NULL,
	`entry` varchar(40) NOT NULL,
	`value` bigint(20) NOT NULL DEFAULT 0,
	`at` int(10) unsigned NOT NULL DEFAULT 0,
	PRIMARY KEY (`player_id`, `entry`),
	CONSTRAINT `chaos_goals_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
