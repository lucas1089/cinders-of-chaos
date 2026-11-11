-- O488 (owner, 2026-11-11: "You can remove this mechanic from the game, together with the items"; server/README.md
-- "Soul pit removed"): the soul cores, the exalted core, dust and sliver leave the players, and nothing else. The ids are
-- the 36 soul cores of the pit's table (28326 - 28342, 28346 - 28364), the exalted core (28345) and its two materials, dust
-- (28343) and sliver (28344; owner, 2026-11-11: "You can delete dust and sliver too"): patch_remove_soulpit.py SQL_IDS, held
-- to this list by tools/patch_remove_soulpit_test.py. They are not containers (items.otb group 0), so a row has no children.
--   base item tables   player_items, player_depotitems, player_inboxitems, player_storeinboxitems: the rows are deleted.
--   Chaos stash        chaos_stash (the stacks), chaos_stash_items (single items), chaos_stash_block (the never-stash list),
--                      chaos_guild_depot (the Guild Stash): deleted.
--   Chaos market       an active or pending offer of these items is deleted (the item sits in the offer's `data`: the way
--                      the server closes an offer, cancelled or expired, hands the item back to its seller and takes two
--                      statements, so it is not used); the item deliveries still owed (a closed offer's item going to the
--                      seller or the buyer) are deleted; a sold offer's gold delivery and the closed offer rows stay (history).
--                      A buy order of these items is not deleted: its `expires` is set to 1 and the server's own sweep
--                      (market.lua MK.sweepOrders, every 60 s and at start) closes it as expired and refunds the escrow.
--   base market        market_offers: a sell offer is deleted, a buy offer gets `created` = 0 so the engine's own expiry
--                      refunds it.
-- Not covered: tile_store (the items lying in houses are in a binary blob; they are inert), the map, the logs
-- (chaos_market_log, chaos_guild_log, shop_history), the histories (market_history, chaos_market_history*), the
-- look unlocks (chaos_transmog), chaos_conquest_seen, znote_shop_orders (an order of the website shop; none gives these
-- items), player_deaths. No compensation is paid. Every statement runs only when its table exists (a table that is not there
-- on an install is skipped, so nothing here can break the step). Safe to run more than once: after the first run nothing
-- matches. Named zz so the installer runs it after every other server/sql file (the tables exist by then).
SET @ids = '28326,28327,28328,28329,28330,28331,28332,28333,28334,28335,28336,28337,28338,28339,28340,28341,28342,28343,28344,28345,28346,28347,28348,28349,28350,28351,28352,28353,28354,28355,28356,28357,28358,28359,28360,28361,28362,28363,28364';

-- player_items
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('player_items')) = 1,
  CONCAT('DELETE FROM `player_items` WHERE `itemtype` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- player_depotitems
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('player_depotitems')) = 1,
  CONCAT('DELETE FROM `player_depotitems` WHERE `itemtype` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- player_inboxitems
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('player_inboxitems')) = 1,
  CONCAT('DELETE FROM `player_inboxitems` WHERE `itemtype` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- player_storeinboxitems
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('player_storeinboxitems')) = 1,
  CONCAT('DELETE FROM `player_storeinboxitems` WHERE `itemtype` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- base market: sell offers deleted
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('market_offers')) = 1,
  CONCAT('DELETE FROM `market_offers` WHERE `sale` = 1 AND `itemtype` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- base market: buy offers expire (the engine refunds them)
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('market_offers')) = 1,
  CONCAT('UPDATE `market_offers` SET `created` = 0 WHERE `sale` = 0 AND `itemtype` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- chaos_stash
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('chaos_stash')) = 1,
  CONCAT('DELETE FROM `chaos_stash` WHERE `item_id` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- chaos_stash_items
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('chaos_stash_items')) = 1,
  CONCAT('DELETE FROM `chaos_stash_items` WHERE `item_id` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- chaos_stash_block
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('chaos_stash_block')) = 1,
  CONCAT('DELETE FROM `chaos_stash_block` WHERE `item_id` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- chaos_guild_depot
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('chaos_guild_depot')) = 1,
  CONCAT('DELETE FROM `chaos_guild_depot` WHERE `item_id` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- chaos market: item deliveries still owed
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('chaos_market_deliveries', 'chaos_market_offers')) = 2,
  CONCAT('DELETE d FROM `chaos_market_deliveries` d JOIN `chaos_market_offers` o ON o.`id` = d.`offer_id` WHERE d.`kind` = ''item'' AND d.`delivered` = 0 AND o.`item_id` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- chaos market: the modifier rows of the active and pending offers
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('chaos_market_offer_mods', 'chaos_market_offers')) = 2,
  CONCAT('DELETE m FROM `chaos_market_offer_mods` m JOIN `chaos_market_offers` o ON o.`id` = m.`offer_id` WHERE o.`state` IN (0, 9) AND o.`item_id` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- chaos market: active and pending offers
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('chaos_market_offers')) = 1,
  CONCAT('DELETE FROM `chaos_market_offers` WHERE `state` IN (0, 9) AND `item_id` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;

-- chaos market: buy orders expire (the server refunds the escrow)
SET @q = IF((SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('chaos_market_orders')) = 1,
  CONCAT('UPDATE `chaos_market_orders` SET `expires` = 1 WHERE `state` = 0 AND `expires` > 1 AND `item_id` IN (', @ids, ')'),
  'DO 0');
PREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;
