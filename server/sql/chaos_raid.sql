-- The Ashen Sepulchre, the weekly raid (data/scripts/chaos/raid.lua; numbers in raid_config.lua; see server/README.md
-- "The Ashen Sepulchre (weekly raid)"). Safe to run more than once (CREATE TABLE IF NOT EXISTS); raid.lua creates the
-- same tables at startup when missing. `week` is the lockout week: the YYYYMMDD of the day it started (raid_config.lua
-- resetDay / resetHour; Monday 06:00 by default, like the other weekly resets).
-- chaos_raid_lockouts: one row per character, week and boss key the character looted (the personal loot lockout).
-- chaos_raid_instances: one row per raid opened: its week, the opener, the bosses slain (bit i-1 = boss i), the
--   corridors cleared of trash (same bits) and whether every boss is slain. A raid of this week can be continued.
-- chaos_raid_members: the characters that were in a raid (they may continue or join it).
-- chaos_raid_players: per character: Sepulchre Marks (the vendor's currency), bosses looted, full clears, the best
--   full clear in seconds.
-- chaos_raid_purchases: the vendor purchases of a character per week and offer (the weekly limits).

CREATE TABLE IF NOT EXISTS `chaos_raid_lockouts` (`player_id` int(11) NOT NULL,
  `week` int(10) unsigned NOT NULL, `boss` varchar(16) NOT NULL, `instance_id` int(11) NOT NULL DEFAULT 0,
  `at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`, `week`, `boss`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_raid_instances` (`id` int(11) NOT NULL AUTO_INCREMENT,
  `week` int(10) unsigned NOT NULL, `leader_id` int(11) NOT NULL, `leader_name` varchar(255) NOT NULL DEFAULT '',
  `killed` int(10) unsigned NOT NULL DEFAULT 0, `trash` int(10) unsigned NOT NULL DEFAULT 0,
  `cleared` tinyint(1) unsigned NOT NULL DEFAULT 0, `created_at` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `chaos_raid_instances_week` (`week`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_raid_members` (`instance_id` int(11) NOT NULL, `player_id` int(11) NOT NULL,
  PRIMARY KEY (`instance_id`, `player_id`), KEY `chaos_raid_members_player` (`player_id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_raid_players` (`player_id` int(11) NOT NULL,
  `marks` int(10) unsigned NOT NULL DEFAULT 0, `kills` int(10) unsigned NOT NULL DEFAULT 0,
  `clears` int(10) unsigned NOT NULL DEFAULT 0, `best_clear` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_raid_purchases` (`player_id` int(11) NOT NULL,
  `week` int(10) unsigned NOT NULL, `offer` varchar(24) NOT NULL, `count` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `week`, `offer`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8;
