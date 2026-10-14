-- Run from the server/ folder: luajit tests/shop_payments_test.lua (and lua5.3; CI runs both)
-- Donations (Pix / PayPal): shop_payments_core.lua rules (prices derived from one USD table, money texts, limits,
-- reuse of an open order, starter once, views, the donation notice and thanks, the refund sentences before and after
-- the donation (the same as the website's legal_lib.php) with where the Donation Terms are, coins taken back after a
-- refund) and
-- shop_payments.lua against a mocked engine and database (pay_packs, pay_create, reuse, refusal, cancel, the thank-you
-- after crediting, a refund after crediting with and without unspent coins).
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function ok(v, m) if not v then error(m or "check failed", 2) end end

dofile("data/scripts/chaos/shop_core.lua")
dofile("data/scripts/chaos/shop_payments_core.lua")
local P = ChaosPayCore
local cfg = dofile("data/scripts/chaos/shop_coins_config.lua")
local packs = {}
for _, p in ipairs(cfg.packs) do packs[p.key] = p end

-- ------------------------------------------------------------------ prices: one USD table, Pix = USD x 5
eq(cfg.payments.brlPerUsd, 5, "BRL per USD")
for _, p in ipairs(cfg.packs) do
	ok(type(p.usdCents) == "number" and p.usdCents == math.floor(p.usdCents) and p.usdCents > 0, p.key .. " usdCents integer")
	eq(P.priceCents(p, "paypal", cfg), p.usdCents, p.key .. " PayPal in USD cents")
	eq(P.priceCents(p, "pix", cfg), p.usdCents * 5, p.key .. " Pix = USD x 5")
end
eq(P.priceCents({usdCents = 1000}, "pix", cfg), 5000, "10.00 USD is R$ 50,00")
eq(P.priceCents({usdCents = 4.5}, "pix", cfg), nil, "fractional cents refused")
eq(P.priceCents(packs.coins250, "card", cfg), nil, "no other method")
eq(P.priceCents(packs.coins250, "boleto", cfg), nil, "no other method 2")
local methods = P.methods(cfg)
eq(#methods, 2, "two methods"); eq(methods[1].key, "pix", "Pix first"); eq(methods[2].key, "paypal", "PayPal second")
eq(methods[1].label, "Pix (BRL)", "Pix label"); eq(methods[2].label, "PayPal (USD)", "PayPal label")
eq(methods[2].currency, "USD", "PayPal currency")

eq(P.money(2495, "BRL"), "R$ 24,95", "BRL text"); eq(P.money(499, "USD"), "US$ 4.99", "USD text")
eq(P.money(123456789, "BRL"), "R$ 1.234.567,89", "BRL thousands"); eq(P.money(100000, "USD"), "US$ 1,000.00", "USD thousands")
eq(P.money(5, "BRL"), "R$ 0,05", "cents only")

-- ------------------------------------------------------------------ donation wording
ok(P.NOTICE_EN:find("Voluntary donation", 1, true) and P.NOTICE_EN:find("fully playable for free", 1, true), "English notice")
ok(P.NOTICE_PT:find("Doação voluntária", 1, true) and P.NOTICE_PT:find("Ninguém é obrigado a doar", 1, true), "Portuguese notice")
local en, pt = P.thanks(975)
eq(en, "Thank you for your voluntary donation! You received 975 Chaos Coins as a thank-you.", "thanks en")
eq(pt, "Obrigado pela sua doação voluntária! Você recebeu 975 Chaos Coins como agradecimento.", "thanks pt")
local f = io.open("../website/overlay/plugins/chaos/legal_lib.php", "rb")
if f then
	local php = f:read("*a"); f:close()
	for key, s in pairs({BEFORE_EN = P.BEFORE_EN, BEFORE_PT = P.BEFORE_PT, AFTER_EN = P.AFTER_EN, AFTER_PT = P.AFTER_PT}) do
		eq(php:match("define%('CHAOS_LEGAL_DONATION_" .. key .. "', '([^']*)'%)"), s, key .. " = website")
	end
else
	print("note: website folder not found, refund sentences compared to the website skipped")
end
en, pt = P.terms()
eq(en, P.BEFORE_EN .. " Donation Terms on the website: page.php?plugin=chaos&p=legal&doc=donations", "terms before en")
eq(pt, P.BEFORE_PT .. " Termos de Doação no site: page.php?plugin=chaos&p=legal&doc=donations", "terms before pt")
eq(P.terms("open"), en, "an open order is before the donation")
en, pt = P.terms("credited")
ok(en:find("^This was a voluntary donation, not a purchase%.") and en:find("doc=donations$"), "terms after en")
ok(pt:find("^Esta foi uma doação voluntária, não uma compra%.") and pt:find("doc=donations$"), "terms after pt")
eq(P.terms("paid"), en, "paid is after the donation")

-- ------------------------------------------------------------------ decide
local now = 1800000000
local function decide(pack, method, orders, starter)
	return P.decide({coinsCfg = cfg, pack = pack, method = method, now = now, orders = orders or {}, starterCredited = starter})
end
local d = decide(packs.coins750, "pix")
eq(d.action, "create", "create"); eq(d.cents, 7495, "Pix cents of the order")
eq(decide(packs.coins750, "paypal").cents, 1499, "PayPal cents of the order")
eq(decide(nil, "pix").action, "refuse", "unknown pack")
eq(decide(packs.coins750, "bitcoin").action, "refuse", "unknown method")
eq(decide(packs.starter, "pix", {}, true).action, "refuse", "starter once")
eq(decide(packs.starter, "pix", {}, false).action, "create", "starter first time")
local open = {id = 9, pack_key = "coins750", method = "pix", status = "open", created = now - 60, expires = now + 600}
d = decide(packs.coins750, "pix", {open})
eq(d.action, "reuse", "same pack and method: the open order again"); eq(d.order.id, 9, "reused id")
d = decide(packs.coins1500, "pix", {open})
eq(d.action, "refuse", "one open order per account"); eq(d.order.id, 9, "the open order comes with the refusal")
eq(decide(packs.coins750, "paypal", {open}).action, "refuse", "other method also refused while one is open")
local expired = {id = 8, pack_key = "coins750", method = "pix", status = "open", created = now - 4000, expires = now - 5}
eq(decide(packs.coins1500, "pix", {expired}).action, "create", "an expired order does not block")
ok(P.isOpen({status = "pending", created = now}, now), "pending is open")
ok(not P.isOpen({status = "credited"}, now), "credited is not open")
local many = {}
for i = 1, 6 do many[i] = {id = i, pack_key = "coins250", method = "pix", status = "cancelled", created = now - 100 * i} end
eq(decide(packs.coins250, "pix", many).action, "refuse", "six an hour")
many[6].created = now - 4000
eq(decide(packs.coins250, "pix", many).action, "create", "older ones do not count")

-- ------------------------------------------------------------------ token, view
local t = P.token(77, now, function(a, b) return a end)
eq(t, "coc-77-" .. now .. "-000000000000", "token form"); ok(#P.token(77, now) <= 64, "token fits")
local v = P.view({id = 5, status = "open", method = "pix", pack_key = "coins750", amount_cents = 7495, currency = "BRL",
	qr_code = "000201", pay_url = "", expires = now + 90, created = now, coins = 750, bonus = 75, first_bonus = 150}, packs.coins750, now, cfg)
eq(v.price, "R$ 74,95", "view price"); eq(v.remaining, 90, "remaining"); eq(v.qrHex, "303030323031", "qr as hex"); eq(v.url, nil, "no url")
eq(v.coins, 975, "coins with bonuses"); eq(v.name, "Sack of Coins", "name")
v = P.view({id = 5, status = "open", method = "pix", pack_key = "coins750", amount_cents = 7495, currency = "BRL",
	qr_code = "x", pay_url = "", expires = now - 1, created = now}, packs.coins750, now, cfg)
eq(v.status, "expired", "past expiry shows as expired")
v = P.view({id = 5, status = "credited", method = "paypal", pack_key = "coins750", amount_cents = 1499, currency = "USD",
	coins = 750, bonus = 75, first_bonus = 0, created = now}, packs.coins750, now, cfg)
eq(v.text, "Thank you for your voluntary donation! You received 825 Chaos Coins as a thank-you.", "credited view thanks")
ok(v.textPt:find("Obrigado pela sua doação voluntária", 1, true), "credited view thanks pt")
v = P.view({id = 5, status = "pending", method = "pix", pack_key = "coins750", amount_cents = 7495, currency = "BRL", created = now - 500}, packs.coins750, now, cfg)
ok(v.text:find("slow", 1, true), "pending too long")

-- ------------------------------------------------------------------ reversal coins
eq(P.reversalCoins(975, 7495, 7495, 5000, true), 975, "full refund, all unspent")
eq(P.reversalCoins(975, 7495, 0, 5000, true), 975, "chargeback (no amount) takes all")
eq(P.reversalCoins(975, 7495, 7495, 300, true), 300, "only what is left")
eq(P.reversalCoins(1000, 10000, 2500, 5000, true), 250, "partial refund, its share")
eq(P.reversalCoins(975, 7495, 7495, 5000, false), 0, "switched off")
eq(P.reversalCoins(975, 7495, 7495, -3, true), 0, "never below zero")
eq(P.reversalRemaining(1000, 10000, 10000, 250, true), 750, "a second, full refund: the rest")
eq(P.reversalRemaining(1000, 10000, 2500, 250, true), 0, "nothing more for the same amount")
eq(P.reversalRemaining(1000, 10000, 5000, 600, true), 0, "never below zero")
eq(P.reversalRemaining(1000, 10000, 10000, 0, false), 0, "switched off")

-- ------------------------------------------------------------------ shop_payments.lua against a mocked engine
local n = 0
setmetatable(_G, {__index = function(tbl, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(tbl, k, n); return n end
end})
local registry, sent = {}, {}
local function event(kind)
	return function(name)
		local e = {name = name}
		function e:type() end
		function e:register() registry[name] = self end
		function e:interval(ms) self.ms = ms end
		function e:separator() end
		return e
	end
end
CreatureEvent, GlobalEvent = event("creature"), event("global")
json = {encode = function(tbl) sent[#sent + 1] = tbl; return "" end, decode = function(b) return b end}

-- the database: orders and payments as tables; the SQL the script writes is matched by its shape
local DB = {orders = {}, pay = {}, coins = {}}
local function field(q, name) return q:match("`" .. name .. "` = '([^']*)'") or q:match("`" .. name .. "` = (%-?%d+)") end
db = {
	escapeString = function(s) return "'" .. tostring(s) .. "'" end,
	query = function(q)
		local vals = q:match("^INSERT INTO `chaos_coin_orders` .- VALUES %((.*)%)$")
		if vals then
			local f = {}
			for x in (vals .. ","):gmatch("%s*('?[^,]*'?)%s*,") do f[#f + 1] = (x:gsub("^'(.*)'$", "%1")) end
			DB.orders[#DB.orders + 1] = {id = #DB.orders + 1, account_id = tonumber(f[1]), pack_key = f[2], provider = f[3],
				provider_ref = f[4], status = f[5], coins = tonumber(f[6]), bonus = tonumber(f[7]), first_bonus = tonumber(f[8]),
				created = tonumber(f[10])}
			return true
		end
		vals = q:match("^INSERT INTO `chaos_coin_payments` .- VALUES %((.*)%)$")
		if vals then
			local f = {}
			for x in (vals .. ","):gmatch("%s*('?[^,]*'?)%s*,") do f[#f + 1] = (x:gsub("^'(.*)'$", "%1")) end
			DB.pay[tonumber(f[1])] = {order_id = tonumber(f[1]), method = f[2], token = f[3], amount_cents = tonumber(f[4]),
				currency = f[5], qr_code = "", pay_url = "", expires = 0, reversal = "", reversal_cents = 0, reversal_done = 0}
			return true
		end
		if q:find("^UPDATE `chaos_coin_orders` SET `status` = 'cancelled'") then
			local o = DB.orders[tonumber(q:match("WHERE `id` = (%d+)"))]
			if o and o.account_id == tonumber(q:match("`account_id` = (%d+)")) and (o.status == "pending" or o.status == "open") then
				o.status = "cancelled"
			end
			return true
		end
		if q:find("^UPDATE `chaos_coin_orders` SET `status` = 'failed'") then
			local before = tonumber(q:match("`created` < (%d+)"))
			for _, o in ipairs(DB.orders) do if o.status == "pending" and o.created < before then o.status = "failed" end end
			return true
		end
		local take, acc = q:match("^UPDATE `chaos_shop_coins` SET `coins` = `coins` %- (%d+) WHERE `account_id` = (%d+)")
		if take then DB.coins[tonumber(acc)] = DB.coins[tonumber(acc)] - tonumber(take); return true end
		if q:find("^UPDATE `chaos_coin_payments` SET `reversal_done` = 1") then
			local p = DB.pay[tonumber(q:match("WHERE `order_id` = (%d+)"))]
			p.reversal_done, p.reversal_coins = 1, tonumber(field(q, "reversal_coins"))
			return true
		end
		return true
	end
}
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.decode = function(b) return b end
local function joined(o)
	local p = DB.pay[o.id] or {}
	local r = {}
	for k, x in pairs(o) do r[k] = x end
	for k, x in pairs(p) do if k ~= "order_id" then r[k] = x end end
	r.order_id = o.id
	return r
end
Chaos.select = function(q, cols)
	local out = {}
	if q:find("SELECT COUNT(*) AS `n` FROM `chaos_coin_orders`", 1, true) then
		local acc, c = tonumber(q:match("`account_id` = (%d+)")), 0
		local inl, notl = q:match(" `pack_key` IN %((.-)%)"), q:match("NOT IN %((.-)%)")
		for _, o in ipairs(DB.orders) do
			if o.account_id == acc and (o.status == "paid" or o.status == "credited") and
				(not inl or inl:find("'" .. o.pack_key .. "'", 1, true)) and (not notl or not notl:find("'" .. o.pack_key .. "'", 1, true)) then
				c = c + 1
			end
		end
		return {{n = c}}
	elseif q:find("p ON p.`order_id` = o.`id` WHERE o.`account_id`", 1, true) then
		local acc, id = tonumber(q:match("o.`account_id` = (%d+)")), tonumber(q:match("o.`id` = (%d+)"))
		for i = #DB.orders, 1, -1 do
			local o = DB.orders[i]
			if o.account_id == acc and (not id or o.id == id) and DB.pay[o.id] then out[#out + 1] = joined(o) end
		end
		return out
	elseif q:find("SELECT `id` FROM `chaos_coin_orders` WHERE `provider`", 1, true) then
		local ref = q:match("`provider_ref` = '([^']*)'")
		for _, o in ipairs(DB.orders) do if o.provider_ref == ref then return {{id = o.id}} end end
		return {}
	elseif q:find("SELECT `id` FROM `chaos_coin_orders` WHERE `status` = 'paid'", 1, true) then
		for _, o in ipairs(DB.orders) do if o.status == "paid" then return {{id = o.id}} end end
		return {}
	elseif q:find("WHERE p.`reversal_done` = 0", 1, true) then
		for _, o in ipairs(DB.orders) do
			local p = DB.pay[o.id]
			if p and p.reversal_done == 0 and p.reversal ~= "" and o.status == "credited" then out[#out + 1] = joined(o) end
		end
		return out
	elseif q:find("SELECT `reversal_cents`, `reversal_coins` FROM `chaos_coin_payments`", 1, true) then
		local p = DB.pay[tonumber(q:match("`order_id` = (%d+)"))]
		return (p and p.reversal_done == 0) and {{reversal_cents = p.reversal_cents, reversal_coins = p.reversal_coins or 0}} or {}
	elseif q:find("SELECT `coins` FROM `chaos_shop_coins`", 1, true) then
		local acc = tonumber(q:match("`account_id` = (%d+)"))
		return DB.coins[acc] and {{coins = DB.coins[acc]}} or {}
	end
	return out
end
ChaosShopCoinsConfig = cfg
local credited = 0
ChaosShop = {getCoins = function(acc) return DB.coins[acc] or 0 end, processOrders = function() credited = credited + 1 end}
local player = {acc = 77, id = 1}
function player:getAccountId() return self.acc end
function player:getId() return self.id end
function player:registerEvent() end
function player:sendExtendedOpcode(op, buf) end
Game = {getPlayers = function() return {player} end}
os.time = (function(real) return function(tt) if tt then return real(tt) end return now end end)(os.time)

dofile("data/scripts/chaos/shop_payments.lua")
local ext = registry.ChaosShopPayExtended
local function ask(action, data)
	sent = {}
	ext.onExtendedOpcode(player, ChaosOpcodes.shop, {action = action, data = data or {}})
	return sent[#sent]
end
ok(registry.ChaosShopPayPoll and registry.ChaosShopPayPoll.ms == 3000, "poll every 3 s")
eq(ask("buy", {}), nil, "the store's own actions are not answered here")

local r = ask("pay_packs")
eq(r.action, "pay_packs", "packs answer"); eq(r.data.notice, P.NOTICE_EN, "notice sent"); eq(r.data.noticePt, P.NOTICE_PT, "notice pt sent")
eq(r.data.terms, (P.terms()), "refund sentence sent"); eq(r.data.termsPt, select(2, P.terms()), "refund sentence pt sent")
eq(#r.data.packs, 7, "seven packs"); eq(r.data.packs[1].prices.pix.text, "R$ 9,95", "entry pack: about R$ 10 by Pix"); eq(r.data.packs[3].prices.pix.text, "R$ 74,95", "Pix price text")
eq(r.data.packs[3].prices.paypal.cents, 1499, "PayPal price"); eq(r.data.packs[3].total, 1575, "first donation bonus (double) in the preview")
eq(r.data.packs[3].prices.card, nil, "no third method"); ok(r.status, "balance sent")
eq(r.data.firstBonusMax, 1000, "the first bonus cap sent to the client"); eq(r.data.packs[7] and r.data.packs[7].key ~= nil, true, "packs listed")

r = ask("pay_create", {pack = "coins750", method = "pix"})
eq(r.action, "pay_order", "order answer"); eq(r.data.status, "pending", "pending"); eq(r.data.price, "R$ 74,95", "order price")
eq(DB.orders[1].status, "pending", "row written"); eq(DB.orders[1].provider, "pix", "provider = method")
eq(DB.pay[1].amount_cents, 7495, "amount from the server config"); eq(DB.pay[1].currency, "BRL", "currency")
eq(DB.orders[1].coins + DB.orders[1].bonus + DB.orders[1].first_bonus, 1575, "credit preview on the row (first donation: double)")
-- the client sends no price: a forged amount field changes nothing
ChaosRateLimit = nil
r = ask("pay_create", {pack = "coins750", method = "pix", amount = 1})
eq(r.data.id, 1, "same pack again: the open order"); eq(#DB.orders, 1, "no second row")
r = ask("pay_create", {pack = "coins4000", method = "paypal"})
eq(r.action, "pay_error", "second open order refused"); eq(r.data.order.id, 1, "refusal shows the open order")
-- a creator code sent with the donation (the website's pick, chaos_creator_support): refused codes stop the donation
do
	local realSelect, realQuery, creatorQ = Chaos.select, db.query, {}
	Chaos.select = function(q, cols)
		if q:find("FROM `chaos_creator_codes`", 1, true) then
			local code = q:match("`code` = '([^']*)'")
			if code == "STREAMER" then return {{id = 4, account_id = 900, active = 1, code = "STREAMER", display_name = "Streamer"}} end
			if code == "OFFCODE" then return {{id = 5, account_id = 900, active = 0, code = "OFFCODE", display_name = ""}} end
			if code == "MINE" then return {{id = 6, account_id = 77, active = 1, code = "MINE", display_name = ""}} end
			return {}
		end
		return realSelect(q, cols)
	end
	db.query = function(q)
		if q:find("chaos_creator_", 1, true) then creatorQ[#creatorQ + 1] = q return true end
		return realQuery(q)
	end
	eq(P.creatorCode(" stream-er "), "STREAMER", "code normalised like the website") eq(P.creatorCode("ab"), nil, "too short")
	local rows = #DB.orders
	r = ask("pay_create", {pack = "coins250", method = "pix", creator = "nope99"})
	eq(r.action .. ":" .. tostring(r.data.msg), "pay_error:That is not an active creator code.", "unknown code refused")
	r = ask("pay_create", {pack = "coins250", method = "pix", creator = "offcode"})
	eq(r.data.msg, "That is not an active creator code.", "switched off code refused")
	r = ask("pay_create", {pack = "coins250", method = "pix", creator = "MINE"})
	eq(r.data.msg, "You cannot support your own creator code.", "self-use refused")
	eq(#DB.orders, rows, "no order for a refused code")
	eq(#creatorQ, 0, "nothing written for a refused code")
	r = ask("pay_create", {pack = "coins750", method = "pix", creator = "streamer"})
	eq(r.data.id, 1, "a good code: the donation goes on (here: the open order)")
	ok(creatorQ[2] and creatorQ[2]:find("INSERT INTO `chaos_creator_support`", 1, true) and creatorQ[2]:find("(77, 4,", 1, true), "the pick saved")
	ok(creatorQ[3] and creatorQ[3]:find("'pick'", 1, true), "the pick logged")
	Chaos.select, db.query = realSelect, realQuery
end
-- the worker made the charge
DB.orders[1].status = "open"; DB.pay[1].qr_code = "00020126580014"; DB.pay[1].expires = now + 1800
r = ask("pay_status", {id = 1})
eq(r.data.qrHex, "3030303230313236353830303134", "Pix code sent as hex"); eq(r.data.remaining, 1800, "countdown")
eq(ask("pay_status", {id = 99}), nil, "unknown order: nothing")
player.acc = 78
eq(ask("pay_status", {id = 1}), nil, "another account's order: nothing")
r = ask("pay_cancel", {id = 1}); eq(DB.orders[1].status, "open", "another account cannot cancel")
player.acc = 77
r = ask("pay_cancel", {id = 1}); eq(DB.orders[1].status, "cancelled", "cancelled"); eq(r.data.status, "cancelled", "view cancelled")
r = ask("pay_create", {pack = "coins4000", method = "paypal"})
eq(r.data.status, "pending", "new order after the cancel"); eq(DB.pay[2].amount_cents, 7499, "PayPal amount"); eq(DB.pay[2].currency, "USD", "USD")

-- the poll: a paid row starts the crediting step at once; a pending row without a charge for 10 minutes fails
DB.orders[2].status = "paid"
ChaosShopPay.poll(); eq(credited, 1, "crediting step called")
DB.orders[2].status = "credited"; DB.orders[2].coins, DB.orders[2].bonus, DB.orders[2].first_bonus = 4000, 1000, 800
sent = {}
ChaosShopPay.onCredited(2, 77, {total = 5800}, packs.coins4000)
eq(sent[1].action, "pay_paid", "thank-you push"); eq(sent[1].data.coins, 5800, "coins in the push")
eq(sent[1].data.text, "Thank you for your voluntary donation! You received 5800 Chaos Coins as a thank-you.", "push thanks")
eq(sent[1].data.terms, (P.terms("credited")), "push receipt note"); eq(sent[1].data.termsPt, select(2, P.terms("credited")), "push receipt note pt")
ok(sent[1].status, "balance with the push")
DB.orders[#DB.orders + 1] = {id = 3, account_id = 77, pack_key = "coins250", provider = "pix", provider_ref = "x", status = "pending", created = now - 700}
ChaosShopPay.poll(); eq(DB.orders[3].status, "failed", "stale pending order failed")

-- refund after crediting: unspent coins taken back once
DB.coins[77] = 6000
DB.pay[2].reversal = "refunded"
sent = {}
ChaosShopPay.poll()
eq(DB.coins[77], 200, "5800 taken back"); eq(DB.pay[2].reversal_done, 1, "handled"); eq(DB.pay[2].reversal_coins, 5800, "logged")
eq(sent[#sent].action, "pay_reversal", "player told"); eq(sent[#sent].data.coins, 5800, "with the coins"); ok(sent[#sent].status, "and the new balance")
ChaosShopPay.poll(); eq(DB.coins[77], 200, "only once")
-- a chargeback when most coins were spent: only the rest
DB.orders[#DB.orders + 1] = {id = 4, account_id = 77, pack_key = "coins250", provider = "paypal", provider_ref = "y", status = "credited",
	coins = 250, bonus = 0, first_bonus = 0, created = now}
DB.pay[4] = {order_id = 4, method = "paypal", amount_cents = 499, currency = "USD", reversal = "charged_back", reversal_cents = 0, reversal_done = 0}
ChaosShopPay.poll()
eq(DB.coins[77], 0, "what was left"); eq(DB.pay[4].reversal_coins, 200, "200 of 250")

-- a chargeback after the coins were gifted on: taken back from the receiver (shop.lua's chaos_coin_gifts ledger)
DB.gifts = {{id = 1, from = 77, to = 88, amount = 300, order = 5, clawed = 0}}
DB.coins[88] = 1000
local baseSelect, baseQuery = Chaos.select, db.query
Chaos.select = function(q, cols)
	if q:find("FROM `chaos_coin_gifts` g", 1, true) then
		local from, since = tonumber(q:match("g.`from_account` = (%d+)")), tonumber(q:match("g.`order_id` >= (%d+)"))
		local out = {}
		for i = #DB.gifts, 1, -1 do
			local g = DB.gifts[i]
			if g.from == from and g.order >= since and g.clawed < g.amount then
				out[#out + 1] = {id = g.id, to_account = g.to, amount = g.amount, clawed = g.clawed, balance = DB.coins[g.to] or 0}
			end
		end
		return out
	end
	return baseSelect(q, cols)
end
db.query = function(q)
	local c, id = q:match("^UPDATE `chaos_coin_gifts` SET `clawed` = `clawed` %+ (%d+) WHERE `id` = (%d+)")
	if c then DB.gifts[tonumber(id)].clawed = DB.gifts[tonumber(id)].clawed + tonumber(c); return true end
	return baseQuery(q)
end
DB.orders[#DB.orders + 1] = {id = 5, account_id = 77, pack_key = "coins250", provider = "paypal", provider_ref = "z", status = "credited",
	coins = 250, bonus = 0, first_bonus = 0, created = now}
DB.pay[5] = {order_id = 5, method = "paypal", amount_cents = 499, currency = "USD", reversal = "charged_back", reversal_cents = 0, reversal_done = 0}
ChaosShopPay.poll()
eq(DB.coins[77], 0, "the donor had nothing left")
eq(DB.coins[88], 750, "250 taken back from the gift's receiver")
eq(DB.gifts[1].clawed, 250, "the ledger records the clawback")
ChaosShopPay.poll()
eq(DB.coins[88], 750, "only once")
Chaos.select, db.query = baseSelect, baseQuery

-- a partial refund after crediting, then a second, larger one (the website raises reversal_cents and resets
-- reversal_done): the second round takes back only the difference
DB.orders[#DB.orders + 1] = {id = 6, account_id = 77, pack_key = "coins250", provider = "pix", provider_ref = "w", status = "credited",
	coins = 1000, bonus = 0, first_bonus = 0, created = now}
DB.pay[6] = {order_id = 6, method = "pix", amount_cents = 10000, currency = "BRL", reversal = "refunded", reversal_cents = 2500, reversal_done = 0}
DB.coins[77] = 5000
ChaosShopPay.poll()
eq(DB.coins[77], 4750, "a quarter refunded: 250 taken back"); eq(DB.pay[6].reversal_coins, 250, "250 handled")
DB.pay[6].reversal_cents, DB.pay[6].reversal_done = 10000, 0
ChaosShopPay.poll()
eq(DB.coins[77], 4000, "then all of it: the other 750"); eq(DB.pay[6].reversal_coins, 1000, "1000 handled in all")
ChaosShopPay.poll(); eq(DB.coins[77], 4000, "only once")

print("shop_payments_test: ok")
