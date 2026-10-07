-- Chaos client-module tables for TFS 1.4.2 / Hellgrave Exodus (MySQL / MariaDB, InnoDB).
-- Safe to run more than once (CREATE TABLE IF NOT EXISTS). Table names must match
-- Chaos.tables in server/data/scripts/chaos/chaos_constants.lua.
-- Foreign keys reference players(id) as `int(11) NOT NULL`, the stock TFS schema.

-- game_bank: second currency ("star") balance. Gold uses the native players.balance column.
CREATE TABLE IF NOT EXISTS `chaos_bank` (
  `player_id` int(11) NOT NULL,
  `stars` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`),
  CONSTRAINT `chaos_bank_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- game_stash: one row per (player, item id) with the stored amount.
CREATE TABLE IF NOT EXISTS `chaos_stash` (
  `player_id` int(11) NOT NULL,
  `item_id` int(10) unsigned NOT NULL,
  `count` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `item_id`),
  CONSTRAINT `chaos_stash_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- game_stash: item types the player never wants auto/drag stashed.
CREATE TABLE IF NOT EXISTS `chaos_stash_block` (
  `player_id` int(11) NOT NULL,
  `item_id` int(10) unsigned NOT NULL,
  PRIMARY KEY (`player_id`, `item_id`),
  CONSTRAINT `chaos_stash_block_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- game_passivetree: saved allocation per preset (nodes = comma separated node ids, root excluded).
CREATE TABLE IF NOT EXISTS `chaos_passive_tree` (
  `player_id` int(11) NOT NULL,
  `preset` tinyint(3) unsigned NOT NULL,
  `name` varchar(32) NOT NULL DEFAULT 'Preset 1',
  `nodes` text NOT NULL,
  PRIMARY KEY (`player_id`, `preset`),
  CONSTRAINT `chaos_passive_tree_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- game_dungeons: highest unlocked difficulty (1..6) and completed challenge keys per dungeon.
CREATE TABLE IF NOT EXISTS `chaos_dungeon_progress` (
  `player_id` int(11) NOT NULL,
  `dungeon_id` int(10) unsigned NOT NULL,
  `difficulty` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `challenges` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`player_id`, `dungeon_id`),
  CONSTRAINT `chaos_dungeon_progress_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- game_dungeons: one row per completed run (names = member names separated by newlines).
CREATE TABLE IF NOT EXISTS `chaos_dungeon_runs` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `dungeon_id` int(10) unsigned NOT NULL,
  `difficulty` tinyint(3) unsigned NOT NULL,
  `time_ms` int(10) unsigned NOT NULL,
  `party_size` tinyint(3) unsigned NOT NULL,
  `names` varchar(255) NOT NULL,
  `finished_at` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `chaos_dungeon_runs_rank` (`dungeon_id`, `difficulty`, `party_size`, `time_ms`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_dungeon_run_players` (
  `run_id` int(10) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  PRIMARY KEY (`run_id`, `player_id`),
  KEY `chaos_dungeon_run_players_player` (`player_id`),
  CONSTRAINT `chaos_dungeon_run_players_run_fk` FOREIGN KEY (`run_id`) REFERENCES `chaos_dungeon_runs` (`id`) ON DELETE CASCADE,
  CONSTRAINT `chaos_dungeon_run_players_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- game_infinitytower: per season points, best floor/time, claimed milestone bitmask.
CREATE TABLE IF NOT EXISTS `chaos_tower_players` (
  `player_id` int(11) NOT NULL,
  `season` int(10) unsigned NOT NULL,
  `points` int(10) unsigned NOT NULL DEFAULT 0,
  `best_floor` int(10) unsigned NOT NULL DEFAULT 0,
  `best_time` int(10) unsigned NOT NULL DEFAULT 0,
  `claimed_mask` int(10) unsigned NOT NULL DEFAULT 0,
  `last_attempt` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `season`),
  KEY `chaos_tower_players_rank` (`season`, `best_floor`, `best_time`),
  CONSTRAINT `chaos_tower_players_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
