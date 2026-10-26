-- Sale notifications of the market (market.lua) without engine calls (tested by server/tests/market_notify_test.lua
-- with LuaJIT and Lua 5.3). The persistent queue is the market's own chaos_market_deliveries: a sale writes a "sold"
-- row for the seller, MK.deliver applies it when the seller is online (at once, or at the next login) and marks it
-- delivered, and the storage deliverSeq stops a row from being applied twice. This file turns the rows applied in one
-- delivery into what the seller is told: one line per sale (capped) and one toast.
--   ChaosMarketNotify.short(n)                   4200000 -> "4.2M", 950000 -> "950K", 1234 -> "1,234"
--   ChaosMarketNotify.saleOf(row, offer)         a "sold" delivery row and its offer row -> sale, or nil
--   ChaosMarketNotify.saleLine(sale)             "Buyer bought your 2x Sword for 100,000 gold (fee 5,000): +95,000 gold to your bank."
--   ChaosMarketNotify.newBatch(cap)              the sales of one delivery; at most `cap` are kept for the lines
--   ChaosMarketNotify.add(batch, sale)           false when the same sale was added before (deduped by its key)
--   ChaosMarketNotify.summary(batch, away)       {title, text, lines} for the toast and the chat, or nil
--   ChaosMarketNotify.totalText(batch)           "4.2M gold and 95 Chaos Coins"
--   ChaosMarketNotify.exchangeToast(gains, traded, away)  the Orb Exchange delivery toast: title, text, kind
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosMarketNotify = ChaosMarketNotify or {}
local N = ChaosMarketNotify

local floor = math.floor

-- the text in `lang` (ChaosI18n when it is loaded, English otherwise); the engine passes Chaos.lang(player)
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

N.DEFAULT_CAP = 5

local function int(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return floor(v)
end

local function grouped(n)
	local s = tostring(int(n))
	local sign = ""
	if s:sub(1, 1) == "-" then
		sign, s = "-", s:sub(2)
	end
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return sign .. out
end
N.money = grouped

-- one decimal, rounded down (4,290,000 -> 4.2M: never more than was paid), ".0" dropped
local function scaled(n, unit, suffix)
	local tenths = floor(n * 10 / unit)
	local whole, part = floor(tenths / 10), tenths % 10
	return (part == 0 and tostring(whole) or (whole .. "." .. part)) .. suffix
end

function N.short(n)
	n = int(n)
	local a = n < 0 and -n or n
	local sign = n < 0 and "-" or ""
	if a >= 1000000000 then
		return sign .. scaled(a, 1000000000, "B")
	elseif a >= 1000000 then
		return sign .. scaled(a, 1000000, "M")
	elseif a >= 10000 then
		return sign .. scaled(a, 1000, "K")
	end
	return sign .. grouped(a)
end

local function curName(cur, n)
	if cur == "coins" then
		return n == 1 and "Chaos Coin" or "Chaos Coins"
	end
	return "gold"
end
N.curName = curName

-- "1,200 gold", "1 Chaos Coin", "95 Chaos Coins" in `lang`
local function amountText(cur, n, lang)
	if cur == "coins" then
		return T(lang, n == 1 and "%s Chaos Coin" or "%s Chaos Coins", grouped(n))
	end
	return T(lang, "%s gold", grouped(n))
end

-- row = {id, offer_id, kind = "gold" | "coins", amount = net, reason = "sold"}; offer = the offer row (name, count,
-- buyer_name, paid_currency, paid_amount, tax, order_id) or nil when it is gone. A row that is not a sale -> nil.
function N.saleOf(row, offer)
	if type(row) ~= "table" or row.reason ~= "sold" or (row.kind ~= "gold" and row.kind ~= "coins") then
		return nil
	end
	offer = type(offer) == "table" and offer or {}
	local net = int(row.amount)
	local price = int(offer.paid_amount)
	if price < net then
		price = net
	end
	local fee = int(offer.tax)
	if fee <= 0 or price - fee ~= net then
		fee = price - net
	end
	local count = int(offer.count)
	return {
		key = "offer:" .. int(row.offer_id),
		row = int(row.id),
		name = tostring(offer.name or "an item"),
		count = count > 0 and count or 1,
		buyer = tostring(offer.buyer_name or "Someone"),
		order = int(offer.order_id) > 0,
		currency = row.kind,
		price = price,
		fee = fee,
		net = net
	}
end

local function itemText(sale)
	return (sale.count > 1 and (sale.count .. "x ") or "") .. sale.name
end
N.itemText = itemText

function N.saleLine(sale, lang)
	local cur = sale.currency
	local key
	if sale.order then
		key = cur == "coins" and "%s's buy order took your %s for %s (fee %s): +%s to your account." or
			"%s's buy order took your %s for %s (fee %s): +%s to your bank."
	else
		key = cur == "coins" and "%s bought your %s for %s (fee %s): +%s to your account." or
			"%s bought your %s for %s (fee %s): +%s to your bank."
	end
	return T(lang, key, sale.buyer, itemText(sale), amountText(cur, sale.price, lang), grouped(sale.fee),
		amountText(cur, sale.net, lang))
end

function N.newBatch(cap)
	cap = int(cap)
	if cap <= 0 then
		cap = N.DEFAULT_CAP
	end
	return {cap = cap, seen = {}, sales = {}, count = 0, units = 0, gold = 0, coins = 0, more = 0}
end

-- adds a sale; the same key (one offer) is counted once. Only the first `cap` sales are kept as lines; the rest only
-- count in the totals
function N.add(batch, sale)
	if type(sale) ~= "table" or not sale.key or batch.seen[sale.key] then
		return false
	end
	batch.seen[sale.key] = true
	batch.count = batch.count + 1
	batch.units = batch.units + sale.count
	if sale.currency == "coins" then
		batch.coins = batch.coins + sale.net
	else
		batch.gold = batch.gold + sale.net
	end
	if #batch.sales < batch.cap then
		batch.sales[#batch.sales + 1] = sale
	else
		batch.more = batch.more + 1
	end
	return true
end

function N.totalText(batch, lang)
	local parts = {}
	if batch.gold > 0 or batch.coins == 0 then
		parts[#parts + 1] = T(lang, "%s gold", N.short(batch.gold))
	end
	if batch.coins > 0 then
		parts[#parts + 1] = T(lang, batch.coins == 1 and "%s Chaos Coin" or "%s Chaos Coins", N.short(batch.coins))
	end
	if #parts == 2 then
		return T(lang, "%s and %s", parts[1], parts[2])
	end
	return parts[1]
end

-- away = the seller was offline when it sold (the login delivery). Returns nil for an empty batch, else
--   title  the toast's first words: "" for one sale online (the ITEM SOLD header says it), "While you were away" at
--          login, "Market sales" for several online
--   text   one sale: its line; more: "3 items sold for 4.2M gold: Sword, 20x Orb and 1 more." (net, after the fee)
--   lines  the chat lines: one per kept sale, plus "... and N more sales (My Offers > Closed)."
function N.summary(batch, away, lang)
	if not batch or batch.count == 0 then
		return nil
	end
	local lines = {}
	for _, s in ipairs(batch.sales) do
		lines[#lines + 1] = N.saleLine(s, lang)
	end
	if batch.more > 0 then
		lines[#lines + 1] = T(lang, batch.more == 1 and "... and %d more sale (see My Offers)." or
			"... and %d more sales (see My Offers).", batch.more)
	end
	if batch.count == 1 then
		return {title = away and "While you were away" or "", text = lines[1], lines = lines}
	end
	local names = {}
	local shown = math.min(#batch.sales, 3)
	for i = 1, shown do
		names[i] = itemText(batch.sales[i])
	end
	local rest = batch.count - shown
	local list = table.concat(names, ", ")
	if rest > 0 then
		list = T(lang, "%s and %d more", list, rest)
	end
	local text = T(lang, "%d items sold for %s: %s.", batch.count, N.totalText(batch, lang), list)
	return {title = away and "While you were away" or "Market sales", text = text, lines = lines}
end

-- The Orb Exchange (orbexchange.lua) delivers with the same rows-and-deliverSeq method (chaos_orbx_deliveries). gains =
-- "+1,200 gold in your bank, +3 Orb of Fate in your inbox"; traded = a row of this delivery was a fill (an order of the
-- player traded: a sale), else only refunds (cancel, expiry). Returns title, text, kind for ChaosNotify.send.
function N.exchangeToast(gains, traded, away)
	gains = tostring(gains or "")
	if not traded then
		return "Orb Exchange", gains, "market"
	end
	if away then
		return "While you were away", "your Orb Exchange orders traded: " .. gains, "sale"
	end
	return "Orb Exchange", "your orders traded: " .. gains, "sale"
end

return N
