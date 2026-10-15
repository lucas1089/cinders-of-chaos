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
-- usdCents: the base price of the pack in US dollar CENTS (decided 2026-10-14, owner delegated; docs/PRICES.md).
-- Every other price is derived from it in code (ChaosPayCore.priceCents, lib.php chaos_pay_price_cents), so the two
-- can never drift: PayPal charges usdCents in USD, Pix charges usdCents * brlPerUsd in BRL.
-- bonusPct: extra coins of the pack in %. once = true: one per account (the starter pack).
-- firstPurchase.bonusPct: once per account, on top of the first pack credited (not the starter pack). 100 = double
-- coins (owner approval 2026-10-13); maxBonus caps it ("Limite a 1000", 2026-10-13): double up to +1000 extra, a pack of
-- more than 1000 coins gets +1000 flat. "First" = the account has no credited pack yet (status 'credited' stays after a
-- refund or chargeback after crediting, so a reversal never makes the next pack "first" again).
-- Pack ladder (decided 2026-10-14, owner delegated; docs/PRICES.md): one coin is about R$ 0,10. Every USD price ends in
-- .98 so that x brlPerUsd 5 gives a round Pix price: R$ 9,90, 24,90, 49,90, 99,90, 249,90, 499,90 and the Starter
-- R$ 14,90. Bonus 0 / 0 / 5 / 10 / 15 / 20%: coins per R$ (with the bonus) 10.1, 10.0, 10.5, 11.0, 11.5, 12.0.
return {
	currency = "USD",
	pollSeconds = 30,
	packs = {
		{key = "coins100", name = "Handful of Coins", coins = 100, bonusPct = 0, usdCents = 198},
		{key = "coins250", name = "Pouch of Coins", coins = 250, bonusPct = 0, usdCents = 498},
		{key = "coins500", name = "Sack of Coins", coins = 500, bonusPct = 5, usdCents = 998},
		{key = "coins1000", name = "Chest of Coins", coins = 1000, bonusPct = 10, usdCents = 1998},
		{key = "coins2500", name = "Hoard of Coins", coins = 2500, bonusPct = 15, usdCents = 4998},
		{key = "coins5000", name = "Vault of Coins", coins = 5000, bonusPct = 20, usdCents = 9998},
		-- one-time starter pack: 250 coins and 250 more for a little more than a small pack
		{key = "starter", name = "Starter Coins", coins = 250, bonusCoins = 250, usdCents = 298, once = true, starter = true}
	},
	firstPurchase = {bonusPct = 100, maxBonus = 1000},

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
