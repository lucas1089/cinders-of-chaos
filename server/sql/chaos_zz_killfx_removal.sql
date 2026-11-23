-- O715 (owner, 2026-11-22: the oldest kill effects "estao ruins, podem ser deletados"; server/README.md "Old kill effects
-- removed"): the five store kill effects of the first generation leave the game and every account that owns one is paid
-- back. The list is cosmetics_config.lua `retired` (id, key, store list price, kind killfx), held to this file by
-- tests/cosmetics_removal_test.lua. Same method as the Victory Emotes (chaos_zz_emote_removal.sql, O564).
--   kill_soulspark 200 (Soul Spark), kill_sunring 200 (Sun Ring), kill_shatter 200 (Frost Shatter),
--   kill_bloodbloom 200 (Blood Bloom), kill_radiant 200 (Radiant Ring)
-- What each owned row gets back, by where it came from (`chaos_cosmetics.source`):
--   store   the Chaos Coins it cost: the price the purchase log shows (chaos_shop_purchases, the last row of the offer
--           `unlock:cosmetic_<key>`, a sale price counts), else the list price. The coins go to chaos_shop_coins, with a
--           refund row (offer_key `refund:cosmetic_<key>`, negative price and list price, player 0) in the purchase log.
--   marks   the Pact Marks it cost (the list price; the shelf sold three of them for 200): balance + that (at most the 100000
--           cap of pact_config.lua marks.maxBalance), `spent` - that, a chaos_pact_log row `refund`.
--   mentor  (bought with Mentor Marks, a point balance of a character, not of the account): the account gets Windswept
--           (kill_windswept, a kept store kill effect) instead, if it does not own it.
--   other   (gm: a staff grant) nothing: it never cost the player anything.
-- Then every row of the five keys is deleted from chaos_cosmetics, and the chosen kill effect (player storage 7100940,
-- read as the cosmetic id) of a character that had one of the five chosen from player_storage.
-- One transaction; a second run finds no row, so nothing is paid twice. Nothing runs unless the five tables exist
-- (chaos_cosmetics, chaos_shop_coins, chaos_shop_purchases, chaos_pact_marks, chaos_pact_log): on a fresh install that is a no-op.
-- Run it with the server stopped (the install does): a running server holds the account's cosmetics in memory.
-- Named zz so the installer runs it after every other server/sql file.
SET @have = (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('chaos_cosmetics', 'chaos_shop_coins', 'chaos_shop_purchases', 'chaos_pact_marks', 'chaos_pact_log'));
SET @go = IF(@have = 5, 1, 0);

START TRANSACTION;
DROP TEMPORARY TABLE IF EXISTS `tmp_killfx_refund`;
CREATE TEMPORARY TABLE `tmp_killfx_refund` (
  `account_id` int(11) NOT NULL,
  `cosmetic` varchar(40) NOT NULL,
  `coins` int(11) NOT NULL DEFAULT 0,
  `marks` int(11) NOT NULL DEFAULT 0,
  `src` varchar(16) NOT NULL DEFAULT '',
  `list_price` int(11) NOT NULL DEFAULT 0,
  `title` varchar(60) NOT NULL,
  PRIMARY KEY (`account_id`, `cosmetic`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- what each owned row is worth back
SET @q = IF(@go = 1, 'INSERT INTO `tmp_killfx_refund` (`account_id`, `cosmetic`, `coins`, `marks`, `src`, `list_price`, `title`)
  SELECT c.`account_id`, c.`cosmetic`,
    IF(c.`source` = ''store'', COALESCE((SELECT p.`price` FROM `chaos_shop_purchases` p WHERE p.`account_id` = c.`account_id`
      AND p.`offer_key` = CONCAT(''unlock:cosmetic_'', c.`cosmetic`) AND p.`price` > 0 ORDER BY p.`id` DESC LIMIT 1), l.`price`), 0),
    IF(c.`source` = ''marks'', l.`price`, 0), c.`source`, l.`price`, l.`title`
  FROM `chaos_cosmetics` c JOIN (
    SELECT ''kill_soulspark'' AS `k`, 200 AS `price`, ''Soul Spark'' AS `title`
    UNION ALL SELECT ''kill_sunring'', 200, ''Sun Ring''
    UNION ALL SELECT ''kill_shatter'', 200, ''Frost Shatter''
    UNION ALL SELECT ''kill_bloodbloom'', 200, ''Blood Bloom''
    UNION ALL SELECT ''kill_radiant'', 200, ''Radiant Ring'') l ON l.`k` = c.`cosmetic`
  WHERE c.`source` IN (''store'', ''marks'', ''mentor'')', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- the coins back
SET @q = IF(@go = 1, 'INSERT INTO `chaos_shop_coins` (`account_id`, `coins`)
  SELECT t.`account_id`, SUM(t.`coins`) FROM `tmp_killfx_refund` t GROUP BY t.`account_id` HAVING SUM(t.`coins`) > 0
  ON DUPLICATE KEY UPDATE `coins` = `chaos_shop_coins`.`coins` + VALUES(`coins`)', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- the refund rows of the purchase log
SET @q = IF(@go = 1, 'INSERT INTO `chaos_shop_purchases` (`account_id`, `player_id`, `player_name`, `level`, `offer_key`, `category`,
    `title`, `price`, `list_price`, `gift_account`, `gift_player`, `created`)
  SELECT t.`account_id`, 0, '''', 0, CONCAT(''refund:cosmetic_'', t.`cosmetic`), ''Kill Effects'', CONCAT(''Refund: '', t.`title`),
    -t.`coins`, -t.`list_price`, 0, 0, UNIX_TIMESTAMP() FROM `tmp_killfx_refund` t WHERE t.`coins` > 0', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- the Marks back
SET @q = IF(@go = 1, 'INSERT INTO `chaos_pact_marks` (`account_id`, `balance`, `earned`, `spent`, `updated`)
  SELECT t.`account_id`, LEAST(SUM(t.`marks`), 100000), 0, 0, UNIX_TIMESTAMP() FROM `tmp_killfx_refund` t
  GROUP BY t.`account_id` HAVING SUM(t.`marks`) > 0
  ON DUPLICATE KEY UPDATE `balance` = LEAST(`chaos_pact_marks`.`balance` + VALUES(`balance`), 100000),
    `spent` = GREATEST(0, `chaos_pact_marks`.`spent` - VALUES(`balance`)), `updated` = VALUES(`updated`)', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

SET @q = IF(@go = 1, 'INSERT INTO `chaos_pact_log` (`account_id`, `player_id`, `action`, `detail`, `amount`, `at`)
  SELECT t.`account_id`, 0, ''refund'', t.`cosmetic`, t.`marks`, UNIX_TIMESTAMP() FROM `tmp_killfx_refund` t WHERE t.`marks` > 0', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- Mentor Marks buyers get Windswept (a kept kill effect) instead
SET @q = IF(@go = 1, 'INSERT IGNORE INTO `chaos_cosmetics` (`account_id`, `cosmetic`, `source`, `created`)
  SELECT DISTINCT t.`account_id`, ''kill_windswept'', ''mentor'', UNIX_TIMESTAMP() FROM `tmp_killfx_refund` t WHERE t.`src` = ''mentor''', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- the five cosmetics leave every account
SET @q = IF(@go = 1, 'DELETE FROM `chaos_cosmetics` WHERE `cosmetic` IN
  (''kill_soulspark'', ''kill_sunring'', ''kill_shatter'', ''kill_bloodbloom'', ''kill_radiant'')', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;
COMMIT;
DROP TEMPORARY TABLE IF EXISTS `tmp_killfx_refund`;

-- the chosen kill effect of a character that wore one of the five (the storage holds the cosmetic id 101 .. 105)
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'player_storage') = 1,
  'DELETE FROM `player_storage` WHERE `key` = 7100940 AND `value` IN (101, 102, 103, 104, 105)', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;
