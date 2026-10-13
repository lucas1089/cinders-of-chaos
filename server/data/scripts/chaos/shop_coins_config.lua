-- shop_coins_config.lua: the Chaos Coin packs, read by shop.lua (crediting), shop_payments.lua (donations from the
-- client store) and by the website (plugin chaos: lib.php chaos_coin_packs reads the `packs` block with its Lua reader,
-- so keep one pack per line in this simple form: strings in double quotes, plain numbers).
--
-- Chaos Coins are a thank-you for a voluntary donation: the game is fully playable for free.
--
-- How coins reach an account: the payment side (the website's Pix / PayPal donation flow, its hook chaos_coin_order_paid,
-- or the admin panel's Store > "Record a donation") marks a row of chaos_coin_orders 'paid'; shop.lua credits
-- it within `pollSeconds` (pack coins + pack bonus + the first-purchase bonus) in one transaction and marks it
-- 'credited'. The server decides every number here; the website and the payment worker only read them.
--
-- usdCents: the base price of the pack in US dollar CENTS (PLACEHOLDERS, the owner sets them before launch).
-- Every other price is derived from it in code (ChaosPayCore.priceCents, lib.php chaos_pay_price_cents), so the two
-- can never drift: PayPal charges usdCents in USD, Pix charges usdCents * brlPerUsd in BRL.
-- bonusPct: extra coins of the pack in %. once = true: one per account (the starter pack).
-- firstPurchase.bonusPct: once per account, on top of the first pack credited (not the starter pack). 100 = double
-- coins (owner approval 2026-10-13). "First" = the account has no credited pack yet (status 'credited' stays after a
-- refund or chargeback after crediting, so a reversal never makes the next pack "first" again).
-- Pack ladder (PLACEHOLDERS, docs/OWNER_TODO.md): an entry pack for about R$ 10 by Pix (199 x brlPerUsd 5 = R$ 9,95),
-- the four packs, and the Vault as the anchor (+30%). Coins per US$ (with the pack bonus): 40, 50, 55, 58, 67, 72.
return {
	currency = "USD",
	pollSeconds = 30,
	packs = {
		{key = "coins80", name = "Handful of Coins", coins = 80, bonusPct = 0, usdCents = 199},
		{key = "coins250", name = "Pouch of Coins", coins = 250, bonusPct = 0, usdCents = 499},
		{key = "coins750", name = "Sack of Coins", coins = 750, bonusPct = 10, usdCents = 1499},
		{key = "coins1500", name = "Chest of Coins", coins = 1500, bonusPct = 15, usdCents = 2999},
		{key = "coins4000", name = "Hoard of Coins", coins = 4000, bonusPct = 25, usdCents = 7499},
		{key = "coins10000", name = "Vault of Coins", coins = 10000, bonusPct = 30, usdCents = 17999},
		-- one-time starter pack: 250 coins and 250 more for the price of a small pack
		{key = "starter", name = "Starter Coins", coins = 250, bonusCoins = 250, usdCents = 299, once = true, starter = true}
	},
	firstPurchase = {bonusPct = 100},

	-- Donations from the client store and the website (shop_payments.lua, website/README.md "Donations").
	-- methods: pix = Pix through Mercado Pago (BRL), paypal = PayPal Orders v2 with the donation category (USD). The
	-- website decides which provider serves a method (mercadopago / paypal / mock / off, in its git-ignored settings
	-- file); a method switched off here is hidden everywhere.
	payments = {
		brlPerUsd = 5,              -- Pix price = usdCents * brlPerUsd (integer cents)
		expireMinutes = 30,         -- a charge expires after this (Mercado Pago needs at least 30)
		maxOpenPerAccount = 1,      -- open (unpaid) orders per account at a time
		maxPerHour = 6,             -- orders an account may start per hour
		pollSeconds = 3,            -- how often the server looks for paid orders and refunds
		chargeWaitSeconds = 120,    -- an order without a charge after this is shown as "payment service unavailable"
		removeCoinsOnReversal = true, -- refund / chargeback after crediting: take back what is still unspent
		methods = {
			pix = {enabled = true, currency = "BRL", label = "Pix (BRL)"},
			paypal = {enabled = true, currency = "USD", label = "PayPal (USD)"}
		}
	}
}
