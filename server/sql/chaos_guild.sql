-- Guild levels and guild halls (data/scripts/chaos/guild.lua, guild_hall.lua). Run after the stock TFS schema
-- (guilds, players): mysql -u USER -p DB < chaos_guild.sql. guild.lua also creates these tables at startup if missing.

-- One row per guild: guild XP (the level is derived from it with guild_config.lua's curve and kept for the website)
-- and the guild bank. No foreign key: a disbanded guild's bank and log stay for the staff.
CREATE TABLE IF NOT EXISTS `chaos_guild` (
  `guild_id` int(11) NOT NULL,
  `xp` bigint(20) unsigned NOT NULL DEFAULT 0,
  `level` smallint(5) unsigned NOT NULL DEFAULT 1,
  `bank` bigint(20) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`guild_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Contribution log: guild XP per member, week (Monday 06:00 key), day and source (exp, bounty, rift, worldboss,
-- siege, goblin, invasion..., siegeResult with player_id 0). Feeds the members list, the daily caps and the weekly board.
CREATE TABLE IF NOT EXISTS `chaos_guild_contrib` (
  `guild_id` int(11) NOT NULL,
  `player_id` int(11) NOT NULL,
  `week` int(10) unsigned NOT NULL,
  `day` int(10) unsigned NOT NULL,
  `source` varchar(24) NOT NULL,
  `amount` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`guild_id`, `player_id`, `week`, `day`, `source`),
  KEY `chaos_guild_contrib_week` (`week`, `guild_id`),
  KEY `chaos_guild_contrib_player` (`player_id`, `day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Staff-visible log of everything that moves gold or items, and of the hall: deposit, withdraw, hall, upgrade, rent,
-- put / take (guild depot), refund, level. amount = gold; item_id / count for the depot.
CREATE TABLE IF NOT EXISTS `chaos_guild_log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `guild_id` int(11) NOT NULL,
  `at` int(10) unsigned NOT NULL,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `player_name` varchar(64) NOT NULL DEFAULT '',
  `action` varchar(16) NOT NULL,
  `amount` bigint(20) NOT NULL DEFAULT 0,
  `item_id` int(11) NOT NULL DEFAULT 0,
  `count` int(11) NOT NULL DEFAULT 0,
  `text` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `chaos_guild_log_guild` (`guild_id`, `id`),
  KEY `chaos_guild_log_at` (`at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Trophy counters per guild: worldboss (participations), bounty, rift (runs), riftBest (highest tier), siegeWins,
-- sieges, invasion, goblin.
CREATE TABLE IF NOT EXISTS `chaos_guild_stats` (
  `guild_id` int(11) NOT NULL,
  `stat` varchar(24) NOT NULL,
  `value` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`guild_id`, `stat`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Guild halls: the slot of the runtime-built instance and the rent. Deleted with the guild (the slot is reused).
CREATE TABLE IF NOT EXISTS `chaos_guild_hall` (
  `guild_id` int(11) NOT NULL,
  `slot` smallint(5) unsigned NOT NULL,
  `bought_at` int(10) unsigned NOT NULL,
  `paid_until` int(10) unsigned NOT NULL,
  PRIMARY KEY (`guild_id`),
  UNIQUE KEY `chaos_guild_hall_slot` (`slot`),
  CONSTRAINT `chaos_guild_hall_guilds_fk` FOREIGN KEY (`guild_id`) REFERENCES `guilds` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_guild_upgrades` (
  `guild_id` int(11) NOT NULL,
  `upgrade` varchar(16) NOT NULL,
  `tier` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `bought_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`guild_id`, `upgrade`),
  CONSTRAINT `chaos_guild_upgrades_guilds_fk` FOREIGN KEY (`guild_id`) REFERENCES `guilds` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Guild depot: one row per item or stack. attrs = the item's attributes as text (guild_core.lua encodeAttrs).
-- No foreign key: the items of a disbanded guild stay for the staff.
CREATE TABLE IF NOT EXISTS `chaos_guild_depot` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `guild_id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL,
  `count` int(11) NOT NULL DEFAULT 1,
  `name` varchar(255) NOT NULL DEFAULT '',
  `attrs` text NOT NULL,
  `added_by` int(11) NOT NULL DEFAULT 0,
  `added_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `chaos_guild_depot_guild` (`guild_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
