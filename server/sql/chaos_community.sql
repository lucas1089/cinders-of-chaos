-- Community goals and the weekly world modifier (data/scripts/chaos/community.lua, community_config.lua). community.lua
-- also creates the tables at startup when they are missing. Run once: mysql -u USER -p DB < chaos_community.sql
-- The website reads these tables (read only): website/overlay/plugins/chaos/community_lib.php.

-- one row per goal period (YYYYMMDD of its first day) and realm (0 = everybody; a season id with goal.realms =
-- "separate"): the goal's name and target when it was written, the points so far, the highest stage reached, when the
-- period ends, and whether its rewards were handed out (finished = 1)
CREATE TABLE IF NOT EXISTS `chaos_community_goal` (
  `period` int(10) unsigned NOT NULL,
  `realm` int(11) NOT NULL DEFAULT 0,
  `name` varchar(64) NOT NULL DEFAULT '',
  `target` int(11) NOT NULL DEFAULT 0,
  `progress` bigint(20) NOT NULL DEFAULT 0,
  `stage` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `finish` int(10) unsigned NOT NULL DEFAULT 0,
  `finished` tinyint(1) NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`period`, `realm`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- the buff window a stage opened: from started_at to ends_at, for every character of the realm (kept after the period
-- ends: an open window outlives it)
CREATE TABLE IF NOT EXISTS `chaos_community_buffs` (
  `period` int(10) unsigned NOT NULL,
  `realm` int(11) NOT NULL DEFAULT 0,
  `stage` tinyint(3) unsigned NOT NULL,
  `name` varchar(64) NOT NULL DEFAULT '',
  `text` varchar(255) NOT NULL DEFAULT '',
  `started_at` int(10) unsigned NOT NULL DEFAULT 0,
  `ends_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`period`, `realm`, `stage`),
  KEY `ends_at` (`ends_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- one row per period and character: the points it gave (after the caps), the cap day's total and its points per source
-- ("kill:120,rift:300"), and after the period: its top place (0 = none), whether it earned the token and whether the
-- rewards were given (at the next login). Rows older than keepPeriods periods are deleted at startup.
CREATE TABLE IF NOT EXISTS `chaos_community_contrib` (
  `period` int(10) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  `realm` int(11) NOT NULL DEFAULT 0,
  `name` varchar(255) NOT NULL DEFAULT '',
  `points` int(11) NOT NULL DEFAULT 0,
  `day` int(10) unsigned NOT NULL DEFAULT 0,
  `day_points` int(11) NOT NULL DEFAULT 0,
  `day_src` varchar(255) NOT NULL DEFAULT '',
  `place` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `token` tinyint(1) NOT NULL DEFAULT 0,
  `rewarded` tinyint(1) NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`period`, `player_id`),
  KEY `rank` (`period`, `realm`, `points`),
  FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- the world modifiers of a week (YYYYMMDD of its Monday): keys, names and texts ("|" between them), whether the seed
-- drew them or staff set them (/community modifier), when the week ends. Written at the week's start and on an override.
CREATE TABLE IF NOT EXISTS `chaos_community_week` (
  `week` int(10) unsigned NOT NULL,
  `mods` varchar(128) NOT NULL DEFAULT '',
  `names` varchar(255) NOT NULL DEFAULT '',
  `texts` text,
  `source` varchar(8) NOT NULL DEFAULT 'seed',
  `finish` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`week`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- what happened: a stage reached, a period's end with its top contributors, a staff override (the website's news line)
CREATE TABLE IF NOT EXISTS `chaos_community_history` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `period` int(10) unsigned NOT NULL DEFAULT 0,
  `realm` int(11) NOT NULL DEFAULT 0,
  `kind` varchar(16) NOT NULL DEFAULT '',
  `text` varchar(255) NOT NULL DEFAULT '',
  `created_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
