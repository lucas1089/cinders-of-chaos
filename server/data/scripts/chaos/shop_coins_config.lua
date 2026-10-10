-- shop_coins_config.lua: the Chaos Coin packs sold for real money, read by shop.lua (crediting) and by the website
-- (plugin chaos, page "Chaos Coins": lib.php chaos_coin_packs reads the `packs` block with its Lua reader, so keep one
-- pack per line in this simple form: strings in double quotes, plain numbers).
--
-- How coins reach an account: the payment side (website hook chaos_coin_order_paid, or the admin panel's Store >
-- "Record a paid coin order") writes a row with status 'paid' into chaos_coin_orders; shop.lua credits it within
-- `pollSeconds` (pack coins + pack bonus + the first-purchase bonus) in one transaction and marks it 'credited'.
-- The server decides every number here; the website only shows them. No payment provider is connected: a provider's
-- confirmed-payment callback must call chaos_coin_order_paid (website/README.md "Chaos Coins").
--
-- price: what the website shows, in `currency` (PLACEHOLDERS, the owner sets them before launch).
-- bonusPct: extra coins of the pack in %. once = true: one per account (the starter pack).
-- firstPurchase.bonusPct: once per account, on top of the first pack credited (not the starter pack).
return {
	currency = "EUR",
	pollSeconds = 30,
	packs = {
		{key = "coins250", name = "Pouch of Coins", coins = 250, bonusPct = 0, price = 4.99},
		{key = "coins750", name = "Sack of Coins", coins = 750, bonusPct = 10, price = 14.99},
		{key = "coins1500", name = "Chest of Coins", coins = 1500, bonusPct = 15, price = 29.99},
		{key = "coins4000", name = "Hoard of Coins", coins = 4000, bonusPct = 25, price = 74.99},
		-- one-time starter pack: 250 coins and 250 more for the price of a small pack
		{key = "starter", name = "Starter Coins", coins = 250, bonusCoins = 250, price = 2.99, once = true, starter = true}
	},
	firstPurchase = {bonusPct = 20}
}
