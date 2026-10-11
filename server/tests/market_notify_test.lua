-- Run from the server/ folder: luajit tests/market_notify_test.lua (and lua5.3; CI runs both)
-- The market's sale notifications (data/scripts/chaos/market_notify_core.lua): the short money text, a sale from its
-- delivery row and offer row (price, fee, proceeds), the sale line, the batch (dedupe by offer, the cap on lines,
-- totals in gold and coins) and the summary the seller gets online or at the next login ("While you were away").
-- The flows (online seller, offline seller told once at login, a relog tells nothing twice) are in market_test.lua.

local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/market_notify_core.lua")
local N = ChaosMarketNotify

-- ---------------------------------------------------------------- short money
eq(N.short(0), "0", "zero")
eq(N.short(950), "950", "hundreds")
eq(N.short(9999), "9,999", "under ten thousand: grouped")
eq(N.short(10000), "10K", "ten thousand")
eq(N.short(950000), "950K", "thousands")
eq(N.short(12560), "12.5K", "one decimal, rounded down")
eq(N.short(4200000), "4.2M", "millions")
eq(N.short(4290000), "4.2M", "never rounded up")
eq(N.short(5000000), "5M", ".0 dropped")
eq(N.short(1300000000), "1.3B", "billions")
eq(N.short(-25000), "-25K", "negative")
eq(N.short(nil), "0", "nil")
eq(N.money(1234567), "1,234,567", "grouped money")

-- ---------------------------------------------------------------- a sale from its rows
local offer = {name = "plate armor", count = 1, buyer_name = "Buyer", paid_amount = 100000, tax = 5000, order_id = 0}
local s = N.saleOf({id = 7, offer_id = 31, kind = "gold", amount = 95000, reason = "sold"}, offer)
eq(s.key, "offer:31", "keyed by the offer")
eq(s.price .. "/" .. s.fee .. "/" .. s.net, "100000/5000/95000", "price, fee, proceeds")
eq(N.saleLine(s), "Buyer bought your plate armor for 100,000 gold (fee 5,000): +95,000 gold to your bank.", "gold line")
local c = N.saleOf({id = 8, offer_id = 32, kind = "coins", amount = 95, reason = "sold"},
	{name = "Orb of Upheaval", count = 20, buyer_name = "Buyer", paid_amount = 100, tax = 5})
eq(N.saleLine(c), "Buyer bought your 20x Orb of Upheaval for 100 Chaos Coins (fee 5): +95 Chaos Coins to your account.", "coins line")
local f = N.saleOf({id = 9, offer_id = 33, kind = "gold", amount = 1900, reason = "sold"},
	{name = "Orb of Upheaval", count = 2, buyer_name = "Orderer", paid_amount = 2000, tax = 100, order_id = 4})
eq(N.saleLine(f), "Orderer's buy order took your 2x Orb of Upheaval for 2,000 gold (fee 100): +1,900 gold to your bank.", "buy order fill")
local gone = N.saleOf({id = 10, offer_id = 34, kind = "gold", amount = 500, reason = "sold"}, nil)
eq(gone.price .. "/" .. gone.fee .. "/" .. gone.name, "500/0/an item", "offer row gone: the proceeds still told")
local odd = N.saleOf({id = 11, offer_id = 35, kind = "gold", amount = 900, reason = "sold"}, {paid_amount = 1000, tax = 3})
eq(odd.fee, 100, "the fee follows price - proceeds when the row disagrees")
eq(N.saleOf({id = 12, offer_id = 36, kind = "item", amount = 0, reason = "bought"}, offer), nil, "an item delivery is no sale")
eq(N.saleOf({id = 13, offer_id = -4, kind = "gold", amount = 300, reason = "refund"}, offer), nil, "a refund is no sale")
eq(N.saleOf(nil, offer), nil, "no row")

-- ---------------------------------------------------------------- the batch: dedupe and cap
local b = N.newBatch(2)
eq(N.summary(b, true), nil, "empty batch: nothing to say")
eq(N.add(b, s), true, "first sale added")
eq(N.add(b, s), false, "the same sale twice is deduped")
eq(N.add(b, N.saleOf({id = 99, offer_id = 31, kind = "gold", amount = 95000, reason = "sold"}, offer)), false,
	"another row of the same offer is deduped too")
eq(b.count, 1, "counted once")
local one = N.summary(b, false)
eq(one.title, "", "online: no title (the ITEM SOLD header says it)")
eq(one.text, N.saleLine(s), "online: the sale line")
eq(#one.lines, 1, "one chat line")
local oneAway = N.summary(b, true)
eq(oneAway.title, "While you were away", "login: While you were away")
eq(oneAway.text, N.saleLine(s), "login, one sale: its line")

N.add(b, c)
N.add(b, f)
N.add(b, gone)
eq(b.count, 4, "four sales")
eq(#b.sales, 2, "only cap sales kept for lines")
eq(b.more, 2, "the rest counted")
eq(b.gold, 95000 + 1900 + 500, "gold proceeds summed")
eq(b.coins, 95, "coin proceeds summed")
local many = N.summary(b, true)
eq(many.title, "While you were away", "away title")
eq(many.text, "4 items sold for 97.4K gold and 95 Chaos Coins: plate armor, 20x Orb of Upheaval and 2 more.", "summary text")
eq(#many.lines, 3, "two sale lines and the rest line")
eq(many.lines[3], "... and 2 more sales (see My Offers).", "the rest line")
eq(N.summary(b, false).title, "Market sales", "several sales online")

-- the example of the request: 3 items for 4.2M gold
local e = N.newBatch()
eq(e.cap, N.DEFAULT_CAP, "default cap")
for i, net in ipairs({1500000, 1400000, 1300000}) do
	N.add(e, N.saleOf({id = i, offer_id = 100 + i, kind = "gold", amount = net, reason = "sold"},
		{name = "Item " .. i, count = 1, buyer_name = "B", paid_amount = net, tax = 0}))
end
eq(N.summary(e, true).text, "3 items sold for 4.2M gold: Item 1, Item 2, Item 3.", "3 items sold for 4.2M gold")
eq(#N.summary(e, true).lines, 3, "no rest line under the cap")
local coinsOnly = N.newBatch(5)
N.add(coinsOnly, c)
N.add(coinsOnly, N.saleOf({id = 20, offer_id = 40, kind = "coins", amount = 1, reason = "sold"}, {name = "x", paid_amount = 1, tax = 0}))
eq(N.totalText(coinsOnly), "96 Chaos Coins", "coins only: no 0 gold")

-- a large queue stays bounded: 500 sales keep 5 lines
local big = N.newBatch(5)
for i = 1, 500 do
	N.add(big, N.saleOf({id = i, offer_id = i, kind = "gold", amount = 1000, reason = "sold"}, {name = "Orb", paid_amount = 1000, tax = 0}))
end
eq(#big.sales, 5, "kept lines capped")
eq(#N.summary(big, true).lines, 6, "five lines and the rest")
eq(N.summary(big, true).text, "500 items sold for 500K gold: Orb, Orb, Orb and 497 more.", "the total covers every sale")

-- ---------------------------------------------------------------- the Orb Exchange toast
local t1, x1, k1 = N.exchangeToast("+1,200 gold in your bank.", true, true)
eq(t1 .. "|" .. x1 .. "|" .. k1, "While you were away|your Orb Exchange orders traded: +1,200 gold in your bank.|sale", "orbs sold offline")
local t2, x2, k2 = N.exchangeToast("+1,200 gold in your bank.", true, false)
eq(t2 .. "|" .. x2 .. "|" .. k2, "Orb Exchange|your orders traded: +1,200 gold in your bank.|sale", "orbs sold online")
local t3, x3, k3 = N.exchangeToast("+5 Orb of Fate in your inbox.", false, true)
eq(t3 .. "|" .. x3 .. "|" .. k3, "Orb Exchange|+5 Orb of Fate in your inbox.|market", "a refund is no sale")

print(string.format("market_notify_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
