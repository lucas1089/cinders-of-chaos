-- Test accounts of the Windows package (tools/windows/prepare_server.sh puts this last in sql-setup/).
-- For playing on your own computer only: the passwords are known. Never load this into a public server.
--   account chaos / password chaos: staff (god), character "Chaos Admin"
--   account test  / password test:  one level 1 character per base class (the tutorial runs at the first login)
INSERT IGNORE INTO `accounts` (`name`, `password`, `type`, `creation`) VALUES
  ('chaos', SHA1('chaos'), 5, UNIX_TIMESTAMP()),
  ('test', SHA1('test'), 1, UNIX_TIMESTAMP());

INSERT IGNORE INTO `players` (`name`, `group_id`, `account_id`, `vocation`, `level`, `lastlogin`)
SELECT 'Chaos Admin', 6, `id`, 4, 1, UNIX_TIMESTAMP() FROM `accounts` WHERE `name` = 'chaos';

INSERT IGNORE INTO `players` (`name`, `group_id`, `account_id`, `vocation`, `level`, `lastlogin`)
SELECT c.`name`, 1, a.`id`, c.`vocation`, 1, 0
FROM `accounts` a
JOIN (SELECT 'Test Warrior' AS `name`, 4 AS `vocation`
      UNION ALL SELECT 'Test Ranger', 3
      UNION ALL SELECT 'Test Mystic', 1
      UNION ALL SELECT 'Test Thief', 11) c
WHERE a.`name` = 'test';
