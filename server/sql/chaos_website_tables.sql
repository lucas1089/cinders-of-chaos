-- The website's tables that the game server's own scripts use (server/README.md "Website tables in the game
-- database"). The website (website/install_site.sh, its pinned schema SQL/znote_schema.sql) makes them too, with the
-- same definitions copied here; its installer accepts tables that are already there. Without them a game database
-- that has no website yet printed SQL errors at every start and login (start log 2026-10-16):
--   znote_global_storage  the login service banner at startup (base scripts/customs/znote/znote_login.lua)
--   znote_players         the skill history row at login and logout (base scripts/customs/znote/player_history.lua)
--   znote_shop_orders     the shop orders talkaction, and the engine's migration 41 (its mountid column)
--   znote_accounts        store coins and the game store (base), the referral check (referral.lua)
--   znote_guild_wars      the frag limit of a guild war (base playerdeath.lua, guildwar.lua)
--   znote_player_reports  the report talkaction (base)
-- Empty tables: the website fills znote_accounts / znote_players for existing accounts and characters when it is
-- installed (its schema's INSERT ... SELECT runs on an empty table). CREATE TABLE IF NOT EXISTS: safe to repeat.

CREATE TABLE IF NOT EXISTS `znote_accounts` (
  `id` int NOT NULL AUTO_INCREMENT,
  `account_id` int NOT NULL,
  `ip` bigint UNSIGNED NOT NULL,
  `created` int NOT NULL,
  `points` int DEFAULT 0,
  `cooldown` int DEFAULT 0,
  `active` tinyint NOT NULL DEFAULT '0',
  `active_email` tinyint NOT NULL DEFAULT '0',
  `activekey` int NOT NULL DEFAULT '0',
  `flag` varchar(20) NOT NULL,
  `secret` char(16) DEFAULT NULL,
  `password_hash` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `znote_players` (
  `id` int NOT NULL AUTO_INCREMENT,
  `player_id` int NOT NULL,
  `created` int NOT NULL,
  `hide_char` tinyint NOT NULL,
  `comment` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `znote_global_storage` (
  `key` varchar(32) NOT NULL,
  `value` TEXT NOT NULL,
  UNIQUE (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `znote_shop_orders` (
  `id` int NOT NULL AUTO_INCREMENT,
  `account_id` int NOT NULL,
  `type` int NOT NULL,
  `itemid` int NOT NULL,
  `count` int NOT NULL,
  `time` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `znote_guild_wars` (
  `id` int NOT NULL AUTO_INCREMENT,
  `limit` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `znote_player_reports` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL,
  `posx` int NOT NULL,
  `posy` int NOT NULL,
  `posz` int NOT NULL,
  `report_description` varchar(255) NOT NULL,
  `date` int NOT NULL,
  `status` tinyint NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- the engine's migration 41 adds this column; a database whose db_version passed 41 while the table was missing
-- never got it (data/scripts/customs/znote/shopsystem_talkaction.lua reads it)
ALTER TABLE `znote_shop_orders` ADD COLUMN IF NOT EXISTS `mountid` TINYINT NULL AFTER `itemid`;
