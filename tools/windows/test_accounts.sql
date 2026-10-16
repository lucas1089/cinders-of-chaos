-- Test accounts of the Windows package (tools/windows/prepare_server.sh puts this last in sql-setup/).
-- For playing on your own computer only: the passwords are known. Never load this into a public server.
--   account chaos / password chaos: staff (god), character "Chaos Admin"
--   account test  / password test:  one level 1 character per base class
-- Test characters only (real characters come from the website or the client and are not touched): every one starts
-- in the temple of Cinderhold, the main city (town 2, temple 32369, 32241, 7: server/data/chaos_poi.lua, server/README.md
-- "Main city"), with the tutorial island marked as skipped, so its first login gives the starter kit of its class and
-- level (newplayer_config.lua kits, docs/CLASSES.md) and the welcome at once. To try the island with one of them:
-- /newplayerkit <name>, reset then /newplayerkit <name>, tutorial (staff).
INSERT IGNORE INTO `accounts` (`name`, `password`, `type`, `creation`) VALUES
  ('chaos', SHA1('chaos'), 5, UNIX_TIMESTAMP()),
  ('test', SHA1('test'), 1, UNIX_TIMESTAMP());

-- lastlogin 0: a first login, which gives the kit (newplayer.lua NP.kitDueAtLogin)
INSERT IGNORE INTO `players` (`name`, `group_id`, `account_id`, `vocation`, `level`, `town_id`, `posx`, `posy`, `posz`, `lastlogin`)
SELECT 'Chaos Admin', 6, `id`, 4, 1, 2, 32369, 32241, 7, 0 FROM `accounts` WHERE `name` = 'chaos';

INSERT IGNORE INTO `players` (`name`, `group_id`, `account_id`, `vocation`, `level`, `town_id`, `posx`, `posy`, `posz`, `lastlogin`)
SELECT c.`name`, 1, a.`id`, c.`vocation`, 1, 2, 32369, 32241, 7, 0
FROM `accounts` a
JOIN (SELECT 'Test Warrior' AS `name`, 4 AS `vocation`
      UNION ALL SELECT 'Test Ranger', 3
      UNION ALL SELECT 'Test Mystic', 1
      UNION ALL SELECT 'Test Thief', 11) c
WHERE a.`name` = 'test';

-- the tutorial stage storage (Chaos.storage.newPlayer 7100250 + stage offset 2) = 101, skipped (newplayer_config.lua
-- stageSkipped): the island does not take them; the kit comes at the first login instead
INSERT IGNORE INTO `player_storage` (`player_id`, `key`, `value`)
SELECT `id`, 7100252, 101 FROM `players`
WHERE `name` IN ('Chaos Admin', 'Test Warrior', 'Test Ranger', 'Test Mystic', 'Test Thief');
