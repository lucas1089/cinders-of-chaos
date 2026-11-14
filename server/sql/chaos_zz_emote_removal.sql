-- O564 (owner, 2026-11-14: the Victory Emotes "do not make sense, take them out"; server/README.md "Victory emotes
-- removed"): the five emote cosmetics leave the game and every account that owns one is paid back. The list is
-- cosmetics_config.lua `retired` (id, key, store list price), held to this file by tests/cosmetics_removal_test.lua.
--   emote_roar 200 (Victory Roar), emote_salute 200 (Warrior's Salute), emote_flourish 250 (Ember Flourish),
--   emote_halo 250 (Halo of Triumph), emote_shadow 200 (Shadow Bow)
-- What each owned row gets back, by where it came from (`chaos_cosmetics.source`):
--   store   the Chaos Coins it cost: the price the purchase log shows (chaos_shop_purchases, the last row of the offer
--           `unlock:cosmetic_<key>`, a sale price counts), else the list price. The coins go to chaos_shop_coins. A refund
--           row (offer_key `refund:cosmetic_<key>`, negative price and list price, player 0) goes to the purchase log, so
--           the sales dashboard shows the net and every refund can be found; it matches no offer, limit or starter pack.
--   marks   the Pact Marks it cost (the list price: the shelf sold the two of them for 200): balance + that (at most
--           the 100000 cap of pact_config.lua marks.maxBalance), `spent` - that, a chaos_pact_log row `refund`.
--   other   (gm: a staff grant) nothing: it never cost the player anything.
-- Then every row of the five keys is deleted from chaos_cosmetics, and the chosen emote (player storage 7102004, key kept
-- reserved, never reused) from player_storage.
-- One transaction: the refunds and the deletes are saved together or not at all, and a second run finds no row, so nothing
-- is paid twice. Nothing runs unless all five tables exist (chaos_cosmetics, chaos_shop_coins, chaos_shop_purchases,
-- chaos_pact_marks, chaos_pact_log): on a fresh install that is a no-op and the next run does the work once they exist.
-- Run it with the server stopped (the install does): a running server holds the account's cosmetics in memory.
-- Named zz so the installer runs it after every other server/sql file.
SET @have = (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('chaos_cosmetics', 'chaos_shop_coins', 'chaos_shop_purchases', 'chaos_pact_marks', 'chaos_pact_log'));
SET @go = IF(@have = 5, 1, 0);

START TRANSACTION;
DROP TEMPORARY TABLE IF EXISTS `tmp_emote_refund`;
CREATE TEMPORARY TABLE `tmp_emote_refund` (
  `account_id` int(11) NOT NULL,
  `cosmetic` varchar(40) NOT NULL,
  `coins` int(11) NOT NULL DEFAULT 0,
  `marks` int(11) NOT NULL DEFAULT 0,
  `list_price` int(11) NOT NULL DEFAULT 0,
  `title` varchar(60) NOT NULL,
  PRIMARY KEY (`account_id`, `cosmetic`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- what each owned row is worth back
SET @q = IF(@go = 1, 'INSERT INTO `tmp_emote_refund` (`account_id`, `cosmetic`, `coins`, `marks`, `list_price`, `title`)
  SELECT c.`account_id`, c.`cosmetic`,
    IF(c.`source` = ''store'', COALESCE((SELECT p.`price` FROM `chaos_shop_purchases` p WHERE p.`account_id` = c.`account_id`
      AND p.`offer_key` = CONCAT(''unlock:cosmetic_'', c.`cosmetic`) AND p.`price` > 0 ORDER BY p.`id` DESC LIMIT 1), l.`price`), 0),
    IF(c.`source` = ''marks'', l.`price`, 0), l.`price`, l.`title`
  FROM `chaos_cosmetics` c JOIN (
    SELECT ''emote_roar'' AS `k`, 200 AS `price`, ''Victory Roar'' AS `title`
    UNION ALL SELECT ''emote_salute'', 200, ''Warrior''''s Salute''
    UNION ALL SELECT ''emote_flourish'', 250, ''Ember Flourish''
    UNION ALL SELECT ''emote_halo'', 250, ''Halo of Triumph''
    UNION ALL SELECT ''emote_shadow'', 200, ''Shadow Bow'') l ON l.`k` = c.`cosmetic`
  WHERE c.`source` IN (''store'', ''marks'')', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- the coins back
SET @q = IF(@go = 1, 'INSERT INTO `chaos_shop_coins` (`account_id`, `coins`)
  SELECT t.`account_id`, SUM(t.`coins`) FROM `tmp_emote_refund` t GROUP BY t.`account_id` HAVING SUM(t.`coins`) > 0
  ON DUPLICATE KEY UPDATE `coins` = `chaos_shop_coins`.`coins` + VALUES(`coins`)', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- the refund rows of the purchase log
SET @q = IF(@go = 1, 'INSERT INTO `chaos_shop_purchases` (`account_id`, `player_id`, `player_name`, `level`, `offer_key`, `category`,
    `title`, `price`, `list_price`, `gift_account`, `gift_player`, `created`)
  SELECT t.`account_id`, 0, '''', 0, CONCAT(''refund:cosmetic_'', t.`cosmetic`), ''Victory Emotes'', CONCAT(''Refund: '', t.`title`),
    -t.`coins`, -t.`list_price`, 0, 0, UNIX_TIMESTAMP() FROM `tmp_emote_refund` t WHERE t.`coins` > 0', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- the Marks back
SET @q = IF(@go = 1, 'INSERT INTO `chaos_pact_marks` (`account_id`, `balance`, `earned`, `spent`, `updated`)
  SELECT t.`account_id`, LEAST(SUM(t.`marks`), 100000), 0, 0, UNIX_TIMESTAMP() FROM `tmp_emote_refund` t
  GROUP BY t.`account_id` HAVING SUM(t.`marks`) > 0
  ON DUPLICATE KEY UPDATE `balance` = LEAST(`chaos_pact_marks`.`balance` + VALUES(`balance`), 100000),
    `spent` = GREATEST(0, `chaos_pact_marks`.`spent` - VALUES(`balance`)), `updated` = VALUES(`updated`)', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

SET @q = IF(@go = 1, 'INSERT INTO `chaos_pact_log` (`account_id`, `player_id`, `action`, `detail`, `amount`, `at`)
  SELECT t.`account_id`, 0, ''refund'', t.`cosmetic`, t.`marks`, UNIX_TIMESTAMP() FROM `tmp_emote_refund` t WHERE t.`marks` > 0', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- the five cosmetics leave every account
SET @q = IF(@go = 1, 'DELETE FROM `chaos_cosmetics` WHERE `cosmetic` IN
  (''emote_roar'', ''emote_salute'', ''emote_flourish'', ''emote_halo'', ''emote_shadow'')', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;
COMMIT;
DROP TEMPORARY TABLE IF EXISTS `tmp_emote_refund`;

-- the chosen emote of every character (storage 7102004 stays reserved)
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'player_storage') = 1,
  'DELETE FROM `player_storage` WHERE `key` = 7102004', 'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;
