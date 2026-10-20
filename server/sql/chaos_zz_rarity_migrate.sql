-- Rarity migration (owner item 87, 2026-10-18; server/README.md "Item rarities"). The game had 15 rarities and has seven now;
-- the stored id of a rarity is 1 Common, 2 Uncommon, 3 Magic (was Rare), 4 Rare (was Epic), 5 Legendary (was 5 .. 9: Legendary,
-- Exotic, Mythic, Chaos, Eternal) and 10 Divine (was 10 .. 15: Divine .. Transcendent). The Lua side reads every old id as the
-- rarity it became, so nothing waits for this file; it only makes the `rarity` columns hold the stored ids, so a filter or a
-- sort groups the rows right. Safe to run more than once (a stored id maps to itself). Named zz so the installer runs it after
-- every other server/sql file. The daily price history has the rarity in its primary key: a row whose new key is taken stays as it
-- is (UPDATE IGNORE), the history of the merged rarities is not added up.
UPDATE `chaos_market_offers` SET `rarity` = IF(`rarity` BETWEEN 6 AND 9, 5, 10) WHERE `rarity` BETWEEN 6 AND 15 AND `rarity` <> 10;
UPDATE `chaos_stash_items` SET `rarity` = IF(`rarity` BETWEEN 6 AND 9, 5, 10) WHERE `rarity` BETWEEN 6 AND 15 AND `rarity` <> 10;
UPDATE `chaos_market_history` SET `rarity` = IF(`rarity` BETWEEN 6 AND 9, 5, 10) WHERE `rarity` BETWEEN 6 AND 15 AND `rarity` <> 10;
UPDATE IGNORE `chaos_market_history_daily` SET `rarity` = IF(`rarity` BETWEEN 6 AND 9, 5, 10) WHERE `rarity` BETWEEN 6 AND 15 AND `rarity` <> 10;
