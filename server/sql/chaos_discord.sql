-- Discord announcements (data/scripts/chaos/discord.lua, discord_core.lua; server/README.md "Discord announcements").
-- The game writes one row per event; the website's worker (plugins/chaos/discord_worker.php) posts the rows to the
-- channel webhooks from the environment and marks them: status new -> sent | failed (after the worker's attempts) |
-- nohook (no webhook for its channel) | off (the event type is switched off in CHAOS_DISCORD_OFF). Sent rows are deleted
-- after 14 days. chaos_discord_state: the worker's cursors (the bazaar log id it read up to).
-- discord.lua creates the queue at startup too (ChaosDiscordCore.schemaSql; the test compares). Safe to run more than once.

CREATE TABLE IF NOT EXISTS `chaos_discord_queue` (`id` int unsigned NOT NULL AUTO_INCREMENT, `created_at` int unsigned NOT NULL, `kind` varchar(32) NOT NULL, `channel` varchar(32) NOT NULL DEFAULT 'default', `title` varchar(256) NOT NULL DEFAULT '', `body` text NOT NULL, `fields` text NOT NULL, `status` varchar(8) NOT NULL DEFAULT 'new', `attempts` int unsigned NOT NULL DEFAULT 0, `next_at` int unsigned NOT NULL DEFAULT 0, `sent_at` int unsigned NOT NULL DEFAULT 0, `error` varchar(255) NOT NULL DEFAULT '', PRIMARY KEY (`id`), KEY `status` (`status`, `next_at`, `id`), KEY `created` (`created_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `chaos_discord_state` (`k` varchar(32) NOT NULL, `v` bigint NOT NULL DEFAULT 0, PRIMARY KEY (`k`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
