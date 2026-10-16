-- Test accounts of the Windows package (tools/windows/prepare_server.sh puts this last in sql-setup/).
-- For playing on your own computer only: the passwords are known. Never load this into a public server.
--   account chaos / password chaos: staff (god), character "Chaos Admin"
--   account test  / password test:  one level 8 character per base class
-- Test characters only (real characters come from the website or the client and are not touched): every one starts
-- in the temple of Cinderhold, the main city (town 2, temple 32369, 32241, 7: server/data/chaos_poi.lua, server/README.md
-- "Main city"), with the tutorial island marked as skipped (it is switched off since 2026-10-16 anyway), so its first
-- login gives the starter kit of its class and level (newplayer_config.lua kits, docs/CLASSES.md), the welcome and the
-- Helper. Chaos Admin is made at level 1: its first login raises it to level 8 (newplayer.lua NP.fixStats).
INSERT IGNORE INTO `accounts` (`name`, `password`, `type`, `creation`) VALUES
  ('chaos', SHA1('chaos'), 5, UNIX_TIMESTAMP()),
  ('test', SHA1('test'), 1, UNIX_TIMESTAMP());

-- lastlogin 0: a first login, which gives the kit (newplayer.lua NP.kitDueAtLogin)
INSERT IGNORE INTO `players` (`name`, `group_id`, `account_id`, `vocation`, `level`, `town_id`, `posx`, `posy`, `posz`, `lastlogin`)
SELECT 'Chaos Admin', 6, `id`, 4, 1, 2, 32369, 32241, 7, 0 FROM `accounts` WHERE `name` = 'chaos';

-- like the website and the client make a character: level 8 with its experience (4200) and the class's health, mana,
-- capacity and soul at that level (server/data/scripts/chaos/start_stats.lua: the level 1 row plus 7 levels of gains;
-- server/tests/start_stats_test.lua checks these rows against it) and the class look with both addons
-- (class_looks_core.lua, male). The game gives the full starter kit at the first login.
INSERT IGNORE INTO `players` (`name`, `group_id`, `account_id`, `vocation`, `level`, `experience`, `health`, `healthmax`,
  `mana`, `manamax`, `cap`, `soul`, `looktype`, `lookaddons`, `sex`, `town_id`, `posx`, `posy`, `posz`, `lastlogin`)
SELECT c.`name`, 1, a.`id`, c.`vocation`, c.`lvl`, 4200, c.`health`, c.`health`, c.`mana`, c.`mana`, c.`cap`, c.`soul`,
  c.`looktype`, 3, 1, 2, 32369, 32241, 7, 0
FROM `accounts` a
JOIN (SELECT '' AS `name`, 0 AS `vocation`, 0 AS `lvl`, 0 AS `health`, 0 AS `mana`, 0 AS `cap`, 0 AS `soul`, 0 AS `looktype`
      UNION ALL SELECT 'Test Warrior', 4, 8, 290, 70, 645, 100, 2073
      UNION ALL SELECT 'Test Ranger', 3, 8, 235, 165, 580, 100, 2163
      UNION ALL SELECT 'Test Mystic', 1, 8, 185, 300, 470, 100, 2060
      UNION ALL SELECT 'Test Thief', 11, 8, 259, 115, 609, 100, 2175) c
WHERE a.`name` = 'test' AND c.`name` <> '';

-- the tutorial stage storage (Chaos.storage.newPlayer 7100250 + stage offset 2) = 101, skipped (newplayer_config.lua
-- stageSkipped): the island does not take them; the kit comes at the first login instead
INSERT IGNORE INTO `player_storage` (`player_id`, `key`, `value`)
SELECT `id`, 7100252, 101 FROM `players`
WHERE `name` IN ('Chaos Admin', 'Test Warrior', 'Test Ranger', 'Test Mystic', 'Test Thief');
