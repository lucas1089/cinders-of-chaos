-- Chaos client-module tables for TFS 1.4.2 / the base server (MySQL / MariaDB, InnoDB).
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

-- Paragon track (paragon.lua): points per stat key (damage, critDamage, health, reduction, speed, mana, goldFind,
-- itemFind); rows with 0 points are not kept.
CREATE TABLE IF NOT EXISTS `chaos_paragon` (
  `player_id` int(11) NOT NULL,
  `stat` varchar(32) NOT NULL,
  `points` smallint(5) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `stat`),
  CONSTRAINT `chaos_paragon_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
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

-- Chaos store (data/scripts/chaos/shop.lua): coins per account and purchase history
CREATE TABLE IF NOT EXISTS `chaos_shop_coins` (
  `account_id` int(11) NOT NULL,
  `coins` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_shop_history` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `player_id` int(11) NOT NULL,
  `title` varchar(100) NOT NULL,
  `cost` int(11) NOT NULL,
  `created` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `chaos_shop_history_account` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Store purchase log (shop.lua; also created at startup): one row per purchase or gift, read by the weekly limits,
-- the once-per-account starter packs and the admin panel's Store tab
CREATE TABLE IF NOT EXISTS `chaos_shop_purchases` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `player_id` int(11) NOT NULL,
  `player_name` varchar(255) NOT NULL DEFAULT '',
  `level` int(11) NOT NULL DEFAULT 0,
  `offer_key` varchar(64) NOT NULL,
  `category` varchar(64) NOT NULL DEFAULT '',
  `title` varchar(100) NOT NULL,
  `price` int(11) NOT NULL,
  `list_price` int(11) NOT NULL,
  `gift_account` int(11) NOT NULL DEFAULT 0,
  `gift_player` int(11) NOT NULL DEFAULT 0,
  `created` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `chaos_shop_purchases_account` (`account_id`, `offer_key`),
  KEY `chaos_shop_purchases_created` (`created`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Store gifts to characters that were offline (shop.lua): status 0 waiting, 1 delivered at login, 2 refunded
CREATE TABLE IF NOT EXISTS `chaos_shop_gifts` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `target_player` int(11) NOT NULL,
  `offer_key` varchar(64) NOT NULL,
  `title` varchar(100) NOT NULL,
  `price` int(11) NOT NULL,
  `from_account` int(11) NOT NULL,
  `from_name` varchar(255) NOT NULL DEFAULT '',
  `status` tinyint(4) NOT NULL DEFAULT 0,
  `created` int(10) unsigned NOT NULL,
  `done` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `chaos_shop_gifts_target` (`target_player`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Paid Chaos Coin orders (written by the website hook chaos_coin_order_paid or the admin panel; credited by shop.lua
-- with the bonuses of shop_coins_config.lua): status paid -> credited | rejected
CREATE TABLE IF NOT EXISTS `chaos_coin_orders` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `pack_key` varchar(32) NOT NULL,
  `provider` varchar(32) NOT NULL DEFAULT '',
  `provider_ref` varchar(128) NOT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'paid',
  `coins` int(11) NOT NULL DEFAULT 0,
  `bonus` int(11) NOT NULL DEFAULT 0,
  `first_bonus` int(11) NOT NULL DEFAULT 0,
  `note` varchar(255) NOT NULL DEFAULT '',
  `created` int(10) unsigned NOT NULL,
  `credited` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `chaos_coin_orders_ref` (`provider`, `provider_ref`),
  KEY `chaos_coin_orders_status` (`status`),
  KEY `chaos_coin_orders_account` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- The Pix / PayPal donation of an order (data/scripts/chaos/shop_payments.lua; the website's plugins/chaos/pay/ worker
-- and webhook fill in the charge). Money in integer cents of `currency`. reversal: a refund or chargeback after crediting
-- (refunded / charged_back / disputed), handled by the game server (reversal_done, reversal_coins taken back).
CREATE TABLE IF NOT EXISTS `chaos_coin_payments` (
  `order_id` int(11) NOT NULL,
  `method` varchar(16) NOT NULL,
  `token` varchar(64) NOT NULL,
  `amount_cents` int(11) NOT NULL,
  `currency` char(3) NOT NULL,
  `source` varchar(8) NOT NULL DEFAULT 'client',
  `psp` varchar(16) NOT NULL DEFAULT '',
  `psp_id` varchar(128) NOT NULL DEFAULT '',
  `psp_ref` varchar(128) NOT NULL DEFAULT '',
  `psp_status` varchar(32) NOT NULL DEFAULT '',
  `qr_code` varchar(1024) NOT NULL DEFAULT '',
  `pay_url` varchar(1024) NOT NULL DEFAULT '',
  `qr_image` mediumtext NULL,
  `expires` int(10) unsigned NOT NULL DEFAULT 0,
  `attempts` int(11) NOT NULL DEFAULT 0,
  `claimed` int(10) unsigned NOT NULL DEFAULT 0,
  `checked` int(10) unsigned NOT NULL DEFAULT 0,
  `cancel_sent` tinyint(1) NOT NULL DEFAULT 0,
  `paid_at` int(10) unsigned NOT NULL DEFAULT 0,
  `reversal` varchar(16) NOT NULL DEFAULT '',
  `reversal_cents` int(11) NOT NULL DEFAULT 0,
  `reversal_done` tinyint(1) NOT NULL DEFAULT 0,
  `reversal_coins` int(11) NOT NULL DEFAULT 0,
  `reversal_at` int(10) unsigned NOT NULL DEFAULT 0,
  `note` varchar(255) NOT NULL DEFAULT '',
  `updated` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`order_id`),
  UNIQUE KEY `chaos_coin_payments_token` (`token`),
  KEY `chaos_coin_payments_psp` (`psp`, `psp_id`),
  KEY `chaos_coin_payments_ref` (`psp`, `psp_ref`),
  KEY `chaos_coin_payments_reversal` (`reversal_done`, `reversal`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Bounty board (data/scripts/chaos/bounty.lua; table name in bounty_config.lua): one row per accepted contract. day = bounty day (YYYYMMDD, the day
-- starts at the roll hour), contract = "<band>-<slot>" of that day's board, status 0 active / 1 completed,
-- mc = 1 when a kill was made while multi-clienting (no reward). Unfinished rows of past days and rows older than
-- two weeks are deleted at login; completed rows of the current week count for the weekly bonus.
CREATE TABLE IF NOT EXISTS `chaos_bounty` (
  `player_id` int(11) NOT NULL,
  `day` int(10) unsigned NOT NULL,
  `contract` varchar(16) NOT NULL,
  `monster` varchar(64) NOT NULL,
  `progress` int(10) unsigned NOT NULL DEFAULT 0,
  `required` int(10) unsigned NOT NULL,
  `status` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `mc` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `accepted_at` int(10) unsigned NOT NULL,
  `completed_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `day`, `contract`),
  KEY `chaos_bounty_week` (`player_id`, `status`, `day`),
  CONSTRAINT `chaos_bounty_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Leaderboards (data/scripts/chaos/leaderboard.lua; table names in leaderboard_config.lua). Weekly scores: one row per
-- board ("worldboss", "bounty", "rift"), week (YYYYMMDD of the Monday the week starts, at the reset hour) and player.
-- value = damage / contracts / highest tier, count = kills / contracts / runs recorded, updated_at = when the value last
-- changed (the earlier one wins a tie). Rows older than keepWeeks are deleted at the weekly reset.
CREATE TABLE IF NOT EXISTS `chaos_leaderboard` (
  `board` varchar(16) NOT NULL,
  `week` int(10) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  `value` bigint(20) unsigned NOT NULL DEFAULT 0,
  `count` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`board`, `week`, `player_id`),
  KEY `chaos_leaderboard_rank` (`board`, `week`, `value`),
  CONSTRAINT `chaos_leaderboard_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Leaderboards: the top 3 of every weekly board of an ended week (week = the week that was scored). They hold the title
-- during the week after; rewarded = 1 once the orbs were put in the inbox (at the reset, or at the next login).
-- The last processed reset week is the server_config row `chaos_leaderboard_reset`.
CREATE TABLE IF NOT EXISTS `chaos_leaderboard_titles` (
  `week` int(10) unsigned NOT NULL,
  `board` varchar(16) NOT NULL,
  `rank` tinyint(3) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  `value` bigint(20) unsigned NOT NULL DEFAULT 0,
  `title` varchar(48) NOT NULL,
  `rewarded` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `awarded_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`week`, `board`, `rank`),
  KEY `chaos_leaderboard_titles_player` (`player_id`, `rewarded`),
  CONSTRAINT `chaos_leaderboard_titles_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Crafting bench (data/scripts/chaos/crafting.lua): one row per orb used (bench or use-with). The bench shows the last
-- few; rows older than historyKeepDays (data/lib/chaos_crafting.lua) are deleted at startup.
CREATE TABLE IF NOT EXISTS `chaos_crafting_log` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL,
  `created_at` int(10) unsigned NOT NULL,
  `orb` varchar(32) NOT NULL,
  `item` varchar(80) NOT NULL,
  `result` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `chaos_crafting_log_player` (`player_id`, `id`),
  CONSTRAINT `chaos_crafting_log_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Arena (data/scripts/chaos/arena.lua; table names in arena_config.lua). Rating per player and mode ("1v1", "2v2"),
-- Elo starting at 1000; best = highest rating reached. Seasonal reset columns are not there yet.
CREATE TABLE IF NOT EXISTS `chaos_arena_ratings` (
  `player_id` int(11) NOT NULL,
  `mode` varchar(4) NOT NULL,
  `rating` int(11) NOT NULL DEFAULT 1000,
  `wins` int(10) unsigned NOT NULL DEFAULT 0,
  `losses` int(10) unsigned NOT NULL DEFAULT 0,
  `draws` int(10) unsigned NOT NULL DEFAULT 0,
  `best` int(11) NOT NULL DEFAULT 1000,
  `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `mode`),
  KEY `chaos_arena_ratings_rank` (`mode`, `rating`),
  CONSTRAINT `chaos_arena_ratings_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Arena: one row per rated match. winner = 1 / 2 (team) or 0 (draw); reason = defeat / timeout.
CREATE TABLE IF NOT EXISTS `chaos_arena_matches` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `mode` varchar(4) NOT NULL,
  `slot` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `winner` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `reason` varchar(16) NOT NULL DEFAULT '',
  `started_at` int(10) unsigned NOT NULL,
  `ended_at` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Arena: every player of a rated match (the window's recent matches). result = win / loss / draw; reason = how this
-- player's match ended (defeat / timeout, or defeated / left / secure / mc when the player was out before the end).
CREATE TABLE IF NOT EXISTS `chaos_arena_match_players` (
  `match_id` int(10) unsigned NOT NULL,
  `player_id` int(11) NOT NULL,
  `mode` varchar(4) NOT NULL,
  `team` tinyint(3) unsigned NOT NULL,
  `result` varchar(4) NOT NULL,
  `rating_before` int(11) NOT NULL,
  `rating_after` int(11) NOT NULL,
  `opponents` varchar(100) NOT NULL DEFAULT '',
  `partner` varchar(64) NOT NULL DEFAULT '',
  `reason` varchar(16) NOT NULL DEFAULT '',
  `ended_at` int(10) unsigned NOT NULL,
  PRIMARY KEY (`match_id`, `player_id`),
  KEY `chaos_arena_match_players_player` (`player_id`, `match_id`),
  CONSTRAINT `chaos_arena_match_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Daily reward and login streaks (data/scripts/chaos/daily.lua): one claim a day per account. streak = consecutive
-- claim days, best = best streak ever (login streak titles), grace = grace charges, last_claim = YYYYMMDD of the last
-- claim. Rows are created at the first login after the update from the old per-character storages (the best one).
CREATE TABLE IF NOT EXISTS `chaos_daily_account` (
  `account_id` int(11) NOT NULL,
  `streak` int(11) NOT NULL DEFAULT 0,
  `best` int(11) NOT NULL DEFAULT 0,
  `grace` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `last_claim` int(11) NOT NULL DEFAULT 0,
  `claims` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
