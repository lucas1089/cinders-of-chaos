-- shop_payments_core.lua: rules of the donation flow (Pix / PayPal) without engine calls; tested by
-- tests/shop_payments_test.lua. The engine side is shop_payments.lua, the payment side the website's pay/ folder.
--
--   P.NOTICE_EN / P.NOTICE_PT                the voluntary donation notice shown before a pack is picked
--   P.terms(status)                          the refund sentence (before / after payment) and where the Donation Terms are
--   P.methods(coinsCfg)                      enabled methods {key, label, currency} in display order
--   P.priceCents(pack, method, coinsCfg)     integer cents in the method's currency (usdCents, x brlPerUsd for Pix)
--   P.money(cents, currency)                 "R$ 24,95" / "US$ 4.99"
--   P.isOpen(order, now, coinsCfg)           an order still waiting for the donation
--   P.decide(args)                           create / reuse / refuse a new order (limits, starter, open orders)
--   P.token(accountId, now, rnd)             the order's reference sent to the payment provider
--   P.view(order, pack, now, coinsCfg)       what the client shows for an order
--   P.reversalCoins(credited, amount, refunded, balance, enabled)  coins to take back after a refund / chargeback
--   P.reversalRemaining(credited, amount, refunded, already, enabled)  what is left to take back after an earlier round
-- Lua 5.1 / LuaJIT / Lua 5.3 compatible. Money is integer cents everywhere.

ChaosPayCore = ChaosPayCore or {}
local P = ChaosPayCore

P.NOTICE_EN = "Voluntary donation: it helps keep the server running. Nobody is required to donate; the game is fully playable for free."
P.NOTICE_PT = "Doação voluntária: ajuda a manter o servidor. Ninguém é obrigado a doar; o jogo é totalmente jogável de graça."
P.THANKS = "Chaos Coins are our thank-you for your donation."
-- the website's donation page says the same (legal_lib.php CHAOS_LEGAL_DONATION_*; the test checks they match)
P.BEFORE_EN = "A donation gives no right to a refund, except where the law requires one. It is not the purchase of a product: Chaos Coins are a thank-you and have no real-world value."
P.BEFORE_PT = "A doação não dá direito a reembolso, exceto quando a lei exigir. Ela não é a compra de um produto: as Chaos Coins são um agradecimento e não têm valor no mundo real."
P.AFTER_EN = "This was a voluntary donation, not a purchase. It gives no right to a refund, except where the law requires one."
P.AFTER_PT = "Esta foi uma doação voluntária, não uma compra. Ela não dá direito a reembolso, exceto quando a lei exigir."
P.TERMS_URL = "page.php?plugin=chaos&p=legal&doc=donations"
P.TERMS_EN = "Donation Terms on the website: " .. P.TERMS_URL
P.TERMS_PT = "Termos de Doação no site: " .. P.TERMS_URL

-- the refund sentence and where the Donation Terms are; the "after" sentence once the order is paid or credited
function P.terms(status)
	local after = status == "paid" or status == "credited"
	return (after and P.AFTER_EN or P.BEFORE_EN) .. " " .. P.TERMS_EN, (after and P.AFTER_PT or P.BEFORE_PT) .. " " .. P.TERMS_PT
end

-- after the donation (toast, payment window, in-game message, website return page)
function P.thanks(coins)
	return string.format("Thank you for your voluntary donation! You received %d Chaos Coins as a thank-you.", coins),
		string.format("Obrigado pela sua doação voluntária! Você recebeu %d Chaos Coins como agradecimento.", coins)
end

P.ORDER = {"pix", "paypal"}
-- texts of the statuses of chaos_coin_orders used by the donation flow (the crediting step adds 'credited' / 'rejected')
P.OPEN = {pending = true, open = true}
P.FINAL_TEXT = {
	paid = "Donation received. Your Chaos Coins arrive in a few seconds.",
	expired = "This donation expired before it was paid. Nothing was charged.",
	cancelled = "This donation was cancelled. Nothing was charged.",
	failed = "The payment service is not available right now. Nothing was charged; try again later.",
	refunded = "This donation was refunded.",
	rejected = "This order could not be credited. Staff can see why in the Store log."
}

local function payCfg(coinsCfg)
	return (coinsCfg and coinsCfg.payments) or {}
end

function P.methods(coinsCfg)
	local out, methods = {}, payCfg(coinsCfg).methods or {}
	for _, key in ipairs(P.ORDER) do
		local m = methods[key]
		if m and m.enabled ~= false then
			out[#out + 1] = {key = key, label = m.label or key, currency = m.currency or ""}
		end
	end
	return out
end

local function isInt(n)
	return type(n) == "number" and n == n and n > 0 and math.floor(n) == n
end

function P.priceCents(pack, method, coinsCfg)
	local pc = payCfg(coinsCfg)
	local m = (pc.methods or {})[method]
	if not pack or not m or m.enabled == false or not isInt(pack.usdCents) then
		return nil
	end
	if method == "pix" then
		local rate = pc.brlPerUsd
		if not isInt(rate) then
			return nil
		end
		return pack.usdCents * rate
	end
	return pack.usdCents
end

local function group(n, sep)
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
	return (out:gsub("^%" .. sep, ""))
end

function P.money(cents, currency)
	cents = math.floor(tonumber(cents) or 0)
	local whole, frac = math.floor(cents / 100), cents % 100
	if currency == "BRL" then
		return string.format("R$ %s,%02d", group(whole, "."), frac)
	elseif currency == "USD" then
		return string.format("US$ %s.%02d", group(whole, ","), frac)
	end
	return string.format("%s.%02d %s", group(whole, ","), frac, tostring(currency or ""))
end

-- pending: waiting for its charge; open: charge made, waiting for the donation until `expires`
function P.isOpen(o, now)
	if o.status == "pending" then
		return true
	end
	return o.status == "open" and ((tonumber(o.expires) or 0) == 0 or tonumber(o.expires) > now)
end

-- args: {coinsCfg, pack, method, now, orders = {{id, pack_key, method, status, created, expires}}, starterCredited}
-- returns {action = "create"} | {action = "reuse", order = o} | {action = "refuse", reason = text}
function P.decide(a)
	local pc = payCfg(a.coinsCfg)
	if not a.pack then
		return {action = "refuse", reason = "Unknown pack."}
	end
	local cents = P.priceCents(a.pack, a.method, a.coinsCfg)
	if not cents then
		return {action = "refuse", reason = "This donation method is not available."}
	end
	if a.pack.once and a.starterCredited then
		return {action = "refuse", reason = (a.pack.name or a.pack.key) .. " is once per account and was already received."}
	end
	local open, lastHour = {}, 0
	for _, o in ipairs(a.orders or {}) do
		if P.isOpen(o, a.now) then
			open[#open + 1] = o
		end
		if (tonumber(o.created) or 0) > a.now - 3600 then
			lastHour = lastHour + 1
		end
	end
	for _, o in ipairs(open) do
		if o.pack_key == a.pack.key and o.method == a.method then
			return {action = "reuse", order = o}
		end
	end
	if #open >= (pc.maxOpenPerAccount or 1) then
		return {action = "refuse", reason = "You already have an open donation. Finish or cancel it first.", order = open[1]}
	end
	if lastHour >= (pc.maxPerHour or 6) then
		return {action = "refuse", reason = "Too many donations started in the last hour. Please wait a little."}
	end
	return {action = "create", cents = cents}
end

local HEX = "0123456789abcdef"
function P.token(accountId, now, rnd)
	rnd = rnd or math.random
	local t = {}
	for i = 1, 12 do
		local k = rnd(1, 16)
		t[i] = HEX:sub(k, k)
	end
	return string.format("coc-%d-%d-%s", accountId, now, table.concat(t))
end

-- order: {id, status, method, pack_key, amount_cents, currency, qr_code, pay_url, expires, created, coins, bonus,
-- first_bonus}; credit: ChaosShopCore.packCredit preview (nil once credited: the row has the real numbers)
function P.view(o, pack, now, coinsCfg, credit)
	local pc = payCfg(coinsCfg)
	local total = credit and credit.total or ((tonumber(o.coins) or 0) + (tonumber(o.bonus) or 0) + (tonumber(o.first_bonus) or 0))
	local v = {
		id = o.id, status = o.status, method = o.method, pack = o.pack_key, name = pack and pack.name or o.pack_key,
		coins = total, amount = o.amount_cents, currency = o.currency, price = P.money(o.amount_cents, o.currency),
		now = now
	}
	if o.status == "open" then
		-- hex: the client converts UTF-8 server text to cp1252, which must not touch the Pix code
		v.qrHex = (o.qr_code and o.qr_code ~= "") and (o.qr_code:gsub(".", function(c) return string.format("%02x", c:byte()) end)) or nil
		v.url = (o.pay_url ~= "" and o.pay_url) or nil
		v.expires = tonumber(o.expires) or 0
		v.remaining = math.max(0, v.expires - now)
		if v.expires > 0 and v.remaining == 0 then
			v.status = "expired"
		end
	elseif o.status == "pending" then
		local waited = now - (tonumber(o.created) or now)
		v.text = waited > (pc.chargeWaitSeconds or 120) and "The payment service is slow to answer. Please wait or cancel." or
			"Preparing your donation..."
	end
	if v.status == "credited" then
		v.text, v.textPt = P.thanks(total)
	end
	v.text = v.text or P.FINAL_TEXT[v.status]
	return v
end

-- coins to take back: the share of the credited coins that was refunded, never more than the balance
function P.reversalCoins(credited, amountCents, refundedCents, balance, enabled)
	if not enabled then
		return 0
	end
	credited, balance = math.max(0, math.floor(tonumber(credited) or 0)), math.max(0, math.floor(tonumber(balance) or 0))
	amountCents, refundedCents = tonumber(amountCents) or 0, tonumber(refundedCents) or 0
	local share = credited
	if amountCents > 0 and refundedCents > 0 and refundedCents < amountCents then
		share = math.floor(credited * refundedCents / amountCents)
	end
	return math.min(share, balance)
end

-- coins still to take back for a reversal, when `already` were taken back by an earlier round of the same order (a
-- second, larger refund raises the refunded amount): the share of the new amount minus what was handled, never below 0
function P.reversalRemaining(credited, amountCents, refundedCents, already, enabled)
	local share = P.reversalCoins(credited, amountCents, refundedCents, 2 ^ 31, enabled)
	return math.max(0, share - math.max(0, math.floor(tonumber(already) or 0)))
end

return P
