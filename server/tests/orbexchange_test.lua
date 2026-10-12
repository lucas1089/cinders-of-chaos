-- Run from the server/ folder: luajit tests/orbexchange_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The Orb Exchange rules (data/scripts/chaos/orbexchange_core.lua, numbers in orbexchange_config.lua): order checks,
-- pair keys, exact integer division, crossing and price-time priority, single fills at the maker's ratio (rounding up
-- for the maker, the taker's limit kept), whole matches (partial fills, several makers, self-trade skipped, fees on
-- the gold leg), the book levels, the price history, the makers query and the limits. Then randomized runs: thousands
-- of orders placed, matched and cancelled between a few traders while every orb and every gold coin is counted
-- (holdings + escrow + fees never change), no order ever trades worse than its ratio, what a maker gives while it
-- rests pays exactly its ratio rounded up once (a maker that never took gets exactly what it asked for), and no amount
-- goes negative.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/orbexchange_core.lua")
local C = ChaosOrbExchangeCore
local cfg = dofile("data/scripts/chaos/orbexchange_config.lua")
local ORBS = {fate = {id = 29857, name = "Orb of Fate"}, awakening = {id = 29851, name = "Orb of Awakening"},
	upheaval = {id = 29856, name = "Orb of Upheaval"}}

-- ====================================================================== config
ok(cfg.storage.placeSeq >= 7100950 and cfg.storage.deliverSeq <= 7100954, "storages in the reserved range")
ok(cfg.tables.orders:match("^chaos_orbx_"), "table names")
ok(cfg.max.orb * cfg.max.gold < 2 ^ 53, "products of one order stay exact")
ok(cfg.fees.goldBps >= 100 and cfg.fees.goldBps <= 200, "the gold fee is 1-2%")

-- ====================================================================== integer helpers
eq(C.idiv(10, 3), 3, "idiv")
eq(C.idiv(9, 3), 3, "idiv exact")
eq(C.ceilDiv(10, 3), 4, "ceil")
eq(C.ceilDiv(9, 3), 3, "ceil exact")
eq(C.ceilDiv(0, 7), 0, "ceil zero")
-- near 2^53: the float quotient rounds, the result must not
local big = 199999999999999
eq(C.idiv(big, 2000000000), 99999, "idiv large")
eq(C.ceilDiv(big, 2000000000), 100000, "ceil large")
eq(C.idiv(2000000000 * 99999 + 1999999999, 2000000000), 99999, "idiv just below")
eq(C.gcd(12, 18), 6, "gcd")

-- ====================================================================== orders
eq(C.pairKey("fate", "gold"), "fate/gold", "pair orb gold")
eq(C.pairKey("gold", "fate"), "fate/gold", "pair gold orb")
eq(C.pairKey("fate", "awakening"), "awakening/fate", "pair two orbs sorted")
eq(C.pairKey("awakening", "fate"), "awakening/fate", "pair two orbs either side")

local o, why = C.checkOrder(cfg, {give = "fate", giveQty = 10, want = "gold", wantQty = 50000, days = 7}, ORBS)
ok(o, "a fine order: " .. tostring(why))
eq(o.fee, 0, "no placing fee against gold")
eq(o.pair, "fate/gold", "its pair")
o = C.checkOrder(cfg, {give = "fate", giveQty = 3, want = "awakening", wantQty = 40, days = 1}, ORBS)
eq(o.fee, cfg.fees.orbPairGold, "an orb-for-orb order pays the placing fee")
o = C.checkOrder(cfg, {give = "gold", giveQty = 5000, want = "fate", wantQty = 1}, ORBS)
eq(o.days, cfg.defaultDuration, "default duration")
local function refused(d, what)
	local r, w = C.checkOrder(cfg, d, ORBS)
	ok(r == nil and type(w) == "string", what)
	return w
end
refused({give = "gold", giveQty = 5000, want = "gold", wantQty = 6000}, "gold for gold")
refused({give = "fate", giveQty = 5, want = "fate", wantQty = 6}, "same orb")
refused({give = "mirror", giveQty = 5, want = "gold", wantQty = 6000}, "unknown orb")
refused({give = "fate", giveQty = 0, want = "gold", wantQty = 6000}, "zero orbs")
refused({give = "fate", giveQty = -5, want = "gold", wantQty = 6000}, "negative orbs")
ok(refused({give = "fate", giveQty = 5, want = "gold", wantQty = 999}, "below the gold minimum"):find("1,000"), "names the minimum")
refused({give = "fate", giveQty = cfg.max.orb + 1, want = "gold", wantQty = 6000}, "above the orb maximum")
refused({give = "gold", giveQty = cfg.max.gold + 1, want = "fate", wantQty = 1}, "above the gold maximum")
refused({give = "fate", giveQty = 5, want = "gold", wantQty = 6000, days = 2}, "unknown duration")
refused({give = "fate", giveQty = "x", want = "gold", wantQty = 6000}, "not a number")
refused({give = "fate", giveQty = 0 / 0, want = "gold", wantQty = 6000}, "NaN")
refused({give = "fate", giveQty = math.huge, want = "gold", wantQty = 6000}, "infinite")
refused(nil, "no data")
o = C.checkOrder(cfg, {give = "fate", giveQty = 5.9, want = "gold", wantQty = 6000.7}, ORBS)
eq(o.giveQty, 5, "fractions are cut")

eq(C.fee(cfg, 10000), 200, "2% fee")
eq(C.fee(cfg, 49), 0, "fee rounds down")
eq(C.fee(cfg, 0), 0, "no fee on nothing")
eq(C.fee(cfg, 2000000000), 40000000, "fee of the largest order")

-- ====================================================================== crossing and priority
local function ord(id, give, giveQty, want, wantQty, account)
	return {id = id, give = give, giveQty = giveQty, want = want, wantQty = wantQty, given = 0, got = 0, account = account or id}
end
-- ask: 10 fate for 50,000 gold (5,000 each); bid: 30,000 gold for 6 fate (5,000 each)
local ask = ord(1, "fate", 10, "gold", 50000)
local bid = ord(2, "gold", 30000, "fate", 6)
ok(C.crosses(bid, ask), "same price crosses")
ok(C.crosses(ord(3, "gold", 30000, "fate", 5), ask), "a higher bid crosses")
ok(not C.crosses(ord(3, "gold", 30000, "fate", 7), ask), "a lower bid does not")
ok(not C.crosses(ord(3, "gold", 30000, "awakening", 6), ask), "another pair never crosses")
ok(C.makerBefore(ord(5, "fate", 10, "gold", 40000), ord(4, "fate", 10, "gold", 50000)), "cheaper first")
ok(C.makerBefore(ord(4, "fate", 10, "gold", 50000), ord(5, "fate", 2, "gold", 10000)), "same ratio: older first")
ok(not C.makerBefore(ord(5, "fate", 2, "gold", 10000), ord(4, "fate", 10, "gold", 50000)), "same ratio: newer after")

-- ====================================================================== single fills
local a, b = C.fillAmounts(ask, bid, cfg.scan)
eq(a, 6, "bid takes 6 fate")
eq(b, 30000, "for 30,000 gold")
-- the maker's ratio rounds up for the maker: 3 fate for 10 awakening (3.33 each)
local m = ord(1, "fate", 3, "awakening", 10)
a, b = C.fillAmounts(m, ord(2, "awakening", 4, "fate", 1), cfg.scan)
eq(a, 1, "one fate")
eq(b, 4, "costs ceil(3.33) = 4 awakening")
m.given, m.got = 1, 4
a, b = C.fillAmounts(m, ord(3, "awakening", 100, "fate", 1), cfg.scan)
eq(a, 2, "the rest of the maker")
eq(b, 6, "for exactly the rest of its 10")
-- a taker at the limit with a remainder that cannot buy a whole unit at its ratio
m = ord(1, "fate", 3, "awakening", 10)
local t = ord(2, "awakening", 7, "fate", 2)
ok(C.crosses(t, m), "3.5 per fate crosses 3.33")
a, b = C.fillAmounts(m, t, cfg.scan)
eq(a, 2, "two fate")
eq(b, 7, "for 7 awakening (within 3.5 each)")
-- the taker's limit is kept: exactly at the limit, a part fill would cost too much per unit
m = ord(1, "fate", 3, "awakening", 10)
t = ord(2, "awakening", 6, "fate", 2)
ok(not C.crosses(t, m), "3.0 per fate does not cross 3.33")
t = ord(2, "awakening", 10, "fate", 3)
a, b = C.fillAmounts(m, t, cfg.scan)
eq(a, 3, "all three at the exact ratio")
eq(b, 10, "for all ten")
t = ord(2, "awakening", 7, "fate", 2) -- 3.5 limit; can afford 2 (7)
a, b = C.fillAmounts(m, t, 0)
eq(a, 2, "no scan needed")
-- a maker that wants less than it gives: 10 awakening for 1 fate. A taker paying 1 fate gets all 10
m = ord(1, "awakening", 10, "fate", 1)
a, b = C.fillAmounts(m, ord(2, "fate", 1, "awakening", 5), cfg.scan)
eq(a, 10, "all ten awakening")
eq(b, 1, "for one fate")
-- the largest fill would break the taker's limit by rounding: a smaller one is found
m = ord(1, "fate", 7, "awakening", 10) -- 1.43 per fate
m.given, m.got = 1, 2 -- one fill already: owed(1) = ceil(10/7) = 2
t = ord(2, "awakening", 3, "fate", 2) -- 1.5 per fate, 3 to spend
a, b = C.fillAmounts(m, t, cfg.scan)
ok(a and b <= 3 and a * 3 >= b * 2, "a fill within the taker's limit: " .. tostring(a) .. " for " .. tostring(b))
eq(C.fillAmounts(ord(1, "fate", 1, "gold", 5000), ord(2, "gold", 4999, "fate", 1), cfg.scan), nil, "too little to buy one")
local full = ord(1, "fate", 1, "gold", 5000)
full.given = 1
eq(C.fillAmounts(full, ord(2, "gold", 5000, "fate", 1), cfg.scan), nil, "an empty maker gives nothing")

-- ====================================================================== whole matches
local makers = {
	ord(10, "fate", 5, "gold", 30000, 100), -- 6,000 each
	ord(11, "fate", 4, "gold", 20000, 101), -- 5,000 each, newer
	ord(9, "fate", 2, "gold", 10000, 102), -- 5,000 each, older
	ord(12, "fate", 3, "gold", 21000, 103), -- 7,000 each: beyond the taker's limit
	ord(13, "awakening", 50, "gold", 5000, 104) -- another pair
}
local taker = ord(20, "gold", 40000, "fate", 6, 200) -- up to 6,666 each, 40,000 to spend
local fills = C.match(taker, makers, cfg)
eq(#fills, 3, "three fills")
eq(fills[1].maker.id, 9, "the older of the cheapest first")
eq(fills[2].maker.id, 11, "then the newer of the cheapest")
eq(fills[3].maker.id, 10, "then the next price")
eq(fills[1].a, 2, "all of the first")
eq(fills[2].a, 4, "all of the second")
eq(fills[3].a, 1, "what is left buys one at 6,000")
eq(fills[3].b, 6000, "at the maker's price")
eq(taker.given, 36000, "the taker spent 36,000")
eq(taker.got, 7, "and got 7 fate: more than the 6 it asked, the price was better")
eq(fills[1].makerFee, 200, "the maker that receives gold pays 2%")
eq(fills[1].makerGets, 9800, "and gets the rest")
eq(fills[1].takerFee, 0, "the orb side pays no fee")
ok(not C.isDone(taker), "4,000 gold is left on the book")
eq(makers[4].given, 0, "the 7,000 ask is untouched")
eq(makers[5].given, 0, "the other pair is untouched")

-- self-trade: an order of the same account is skipped, the next one fills
makers = {ord(1, "fate", 5, "gold", 25000, 7), ord(2, "fate", 5, "gold", 30000, 8)}
taker = ord(3, "gold", 30000, "fate", 5, 7)
fills = C.match(taker, makers, cfg)
eq(#fills, 1, "one fill")
eq(fills[1].maker.id, 2, "the own account's order is skipped")
eq(makers[1].given, 0, "and left alone")
fills = C.match(ord(4, "gold", 25000, "fate", 5, 7), {ord(1, "fate", 5, "gold", 25000, 7)}, cfg, {selfTrade = true})
eq(#fills, 1, "with selfTrade it trades")

-- a bid that bought cheaper as a taker rests at its own price for the rest (found in the game test: it used to pay the
-- better price back as a maker). 62,400 gold for 12 fate (5,200 each) takes 10 at 5,000, then rests with 12,400.
local bidT = ord(30, "gold", 62400, "fate", 12, 300)
fills = C.match(bidT, {ord(31, "fate", 10, "gold", 50000, 301)}, cfg)
eq(bidT.given, 50000, "took 10 at 5,000")
eq(bidT.restGiven, 50000, "rests from there")
local seller = ord(32, "fate", 3, "gold", 15600, 302) -- 5,200 each
fills = C.match(seller, {bidT}, cfg)
eq(fills[1].b, 2, "the seller sells two")
eq(fills[1].a, 10400, "at the bid's 5,200 (not 6,200)")
eq(bidT.given, 60400, "2,000 gold left on the bid")
eq(bidT.got, 12, "the bid has its 12 fate")
local cheap = ord(33, "fate", 1, "gold", 5000, 303)
fills = C.match(cheap, {bidT}, cfg)
eq(#fills, 0, "2,000 gold cannot pay a 5,000 seller: no fill")
ok(C.isDust(bidT), "2,000 gold cannot buy one fate at 5,200: dust, the order closes")
ok(not C.isDust(ord(34, "gold", 62400, "fate", 12)), "a new order is never dust")
local oneLeft = ord(35, "fate", 10, "gold", 50000)
oneLeft.given = 9
ok(not C.isDust(oneLeft), "one orb left still sells")
ok(not C.isDust(full), "nothing left is not dust")

-- the orb seller takes a bid: the taker receives the gold and pays the fee
makers = {ord(1, "gold", 50000, "fate", 10, 1)}
taker = ord(2, "fate", 4, "gold", 16000, 2) -- 4,000 each; the bid pays 5,000
fills = C.match(taker, makers, cfg)
eq(fills[1].a, 20000, "the bid pays 5,000 each")
eq(fills[1].b, 4, "for four fate")
eq(fills[1].takerFee, 400, "the seller (taker) pays 2% of 20,000")
eq(fills[1].takerGets, 19600, "and gets the rest")
ok(C.isDone(taker), "the seller is done")

-- ====================================================================== the book
local orders = {
	{give = "fate", giveQty = 10, want = "gold", wantQty = 50000, given = 4}, -- ask 5,000, 6 left
	{give = "fate", giveQty = 2, want = "gold", wantQty = 10000, given = 0}, -- ask 5,000, 2
	{give = "fate", giveQty = 1, want = "gold", wantQty = 5500, given = 0}, -- ask 5,500
	{give = "gold", giveQty = 9000, want = "fate", wantQty = 2, given = 0}, -- bid 4,500, 2
	{give = "gold", giveQty = 48000, want = "fate", wantQty = 12, given = 8000}, -- bid 4,000, 10 left
	{give = "fate", giveQty = 1, want = "gold", wantQty = 5000, given = 1}, -- filled: not shown
	{give = "awakening", giveQty = 1, want = "gold", wantQty = 50, given = 0} -- another pair
}
local bk = C.book(orders, "fate", "gold", 10)
eq(#bk.asks, 2, "two ask levels")
eq(bk.asks[1].p, 5000, "best ask first")
eq(bk.asks[1].q, 8, "same price levels add up")
eq(bk.asks[1].n, 2, "two orders on it")
eq(bk.asks[1].t, 40000, "quote total")
eq(bk.asks[2].p, 5500, "then the next")
eq(#bk.bids, 2, "two bid levels")
eq(bk.bids[1].p, 4500, "best bid first")
eq(bk.bids[2].q, 10, "a bid's base left at its limit")
eq(bk.bids[2].t, 40000, "its gold left")
eq(bk.spread, 500, "spread")
-- the same book seen the other way round: fate per gold
local inv = C.book(orders, "gold", "fate", 10)
eq(#inv.asks, 2, "inverted asks are the bids")
ok(math.abs(inv.asks[1].p - 1 / 4500) < 1e-12, "inverted price")
eq(#C.book(orders, "fate", "gold", 1).asks, 1, "depth")

-- ====================================================================== history
local now = 1000000
local trades = {
	{id = 1, at = now - 30 * 3600, makerGive = "fate", a = 1, b = 4000}, -- before the window
	{id = 2, at = now - 5 * 3600, makerGive = "fate", a = 2, b = 9000}, -- 4,500; a taker bought
	{id = 3, at = now - 3600 - 5, makerGive = "gold", a = 15000, b = 3}, -- 5,000; a taker sold
	{id = 4, at = now - 60, makerGive = "fate", a = 1, b = 5500} -- 5,500
}
local h = C.history(trades, now, "fate", "gold", 24)
eq(h.last, 5500, "last price")
eq(h.open, 4500, "first price in the window")
eq(h.high, 5500, "high")
eq(h.low, 4500, "low")
eq(h.vol, 6, "base volume")
eq(h.volQuote, 29500, "quote volume")
ok(math.abs(h.change - 22.2222) < 0.01, "change in percent")
eq(#h.points, 3, "three hours with trades")
eq(h.points[1].h, 5, "oldest hour first")
eq(h.points[3].h, 0, "this hour last")
eq(#h.trades, 4, "every trade listed")
eq(h.trades[1].p, 5500, "newest first")
eq(h.trades[1].side, "buy", "a taker bought")
eq(h.trades[2].side, "sell", "a taker sold")
local h2 = C.history({}, now, "fate", "gold", 24)
eq(h2.last, nil, "no trades: no price")
eq(h2.vol, 0, "no volume")

eq(C.priceText(5000), "5,000", "price text thousands")
eq(C.priceText(4.5), "4.5", "price text small")
eq(C.priceText(0.333333), "0.3333", "price text fraction")
eq(C.priceText(125.26), "125.3", "price text hundreds")
eq(C.priceText(nil), "-", "no price")

-- ====================================================================== query and limits
local where, orderBy, limit = C.makersQuery({id = 7, give = "gold", want = "fate", giveQty = 40000, wantQty = 6}, 0, 3, now, 50)
ok(where:find("`give_asset` = 'fate'", 1, true), "makers give what the taker wants")
ok(where:find("`want_asset` = 'gold'", 1, true), "and want what it gives")
ok(where:find("`want_qty` * 6 <= `give_qty` * 40000", 1, true), "only the crossing ones")
ok(where:find("`realm` <> 3", 1, true), "a standard taker never meets the running season")
ok(where:find("`id` <> 7", 1, true), "never itself")
ok(orderBy:find("^`want_qty` / `give_qty` ASC, `id` ASC"), "cheapest and oldest first")
eq(limit, 50, "limit")
where = C.makersQuery({id = 7, give = "gold", want = "fate", giveQty = 1, wantQty = 1}, 3, 3, now, 50)
ok(where:find("`realm` = 3", 1, true), "a season taker meets its season only")
eq(C.realmOf(3, 3), 3, "a running season's order is on its book")
eq(C.realmOf(2, 3), 0, "an ended season's order is standard")
eq(C.limitRefusal(cfg, 19, 30), nil, "below the limits")
ok(C.limitRefusal(cfg, 20, 30):find("20"), "character limit")
ok(C.limitRefusal(cfg, 5, 40):find("40"), "account limit")
ok(C.limitRefusal(cfg, 5, 5, 5, 40), "a smaller limit passed in")
eq(C.pendingAction(10, 10), "activate", "crash: saved marker reached the order")
eq(C.pendingAction(10, 9), "drop", "crash: the orbs never left in a saved state")

-- ====================================================================== randomized: nothing is created or lost
local seed = 20261010
local function rnd(n)
	-- Park-Miller: exact in doubles and integers, so LuaJIT and Lua 5.3 run the same sequence
	seed = (seed * 16807) % 2147483647
	return math.floor(seed / 7) % n + 1
end
local ASSETS = {"gold", "fate", "awakening", "upheaval"}

local function run(rounds, traders)
	local hold, fees = {}, 0
	local total = {}
	for i = 1, traders do
		hold[i] = {gold = 2000000 + rnd(5000000), fate = 50 + rnd(500), awakening = 200 + rnd(3000), upheaval = 20 + rnd(300)}
	end
	for _, asset in ipairs(ASSETS) do
		total[asset] = 0
		for i = 1, traders do
			total[asset] = total[asset] + hold[i][asset]
		end
	end
	local book, nextId, fillsSeen, bad = {}, 1, 0, nil
	local function check(what)
		local sum = {gold = fees, fate = 0, awakening = 0, upheaval = 0}
		for i = 1, traders do
			for _, asset in ipairs(ASSETS) do
				if hold[i][asset] < 0 then
					bad = bad or (what .. ": negative holding")
				end
				sum[asset] = sum[asset] + hold[i][asset]
			end
		end
		for _, o in ipairs(book) do
			local left = C.left(o)
			if left < 0 or o.given > o.giveQty then
				bad = bad or (what .. ": escrow below zero")
			end
			sum[o.give] = sum[o.give] + left
			-- a maker never got less than its ratio for what it gave
			if o.got * o.giveQty < o.given * o.wantQty then
				bad = bad or (what .. ": order " .. o.id .. " below its ratio")
			end
		end
		for _, asset in ipairs(ASSETS) do
			if sum[asset] ~= total[asset] then
				bad = bad or string.format("%s: %s %s ~= %s", what, asset, tostring(sum[asset]), tostring(total[asset]))
			end
		end
	end
	for round = 1, rounds do
		local who = rnd(traders)
		if rnd(10) <= 2 and #book > 0 then
			-- cancel: the escrow left goes back
			local i = rnd(#book)
			local o = book[i]
			hold[o.trader][o.give] = hold[o.trader][o.give] + C.left(o)
			table.remove(book, i)
		else
			local give = ASSETS[rnd(4)]
			local want = ASSETS[rnd(4)]
			while want == give do
				want = ASSETS[rnd(4)]
			end
			-- around a fair price with noise, so the book crosses often
			local value = {gold = 1, fate = 5000, awakening = 40, upheaval = 900}
			local giveQty = give == "gold" and (1000 + rnd(200000)) or rnd(give == "awakening" and 400 or 40)
			local fair = giveQty * value[give] / value[want]
			local wantQty = math.max(1, math.floor(fair * (70 + rnd(60)) / 100))
			if want == "gold" and wantQty < 1000 then
				wantQty = 1000
			end
			local d = {give = give, giveQty = giveQty, want = want, wantQty = wantQty, days = 7}
			local checked = C.checkOrder(cfg, d, ORBS)
			if checked and hold[who][give] >= giveQty and hold[who].gold >= checked.fee + (give == "gold" and giveQty or 0) then
				hold[who][give] = hold[who][give] - giveQty -- escrow
				hold[who].gold = hold[who].gold - checked.fee
				fees = fees + checked.fee
				local tk = {id = nextId, trader = who, account = who, give = give, giveQty = giveQty, want = want,
					wantQty = wantQty, given = 0, got = 0}
				nextId = nextId + 1
				local fills = C.match(tk, book, cfg, {selfTrade = rnd(2) == 1})
				for _, f in ipairs(fills) do
					fillsSeen = fillsSeen + 1
					local mk = f.maker
					ok(f.a > 0 and f.b >= 0, "a fill moves something")
					-- the taker's limit, per fill
					if f.a * tk.giveQty < f.b * tk.wantQty then
						bad = bad or ("taker " .. tk.id .. " paid above its limit")
					end
					hold[tk.trader][tk.want] = hold[tk.trader][tk.want] + f.takerGets
					hold[mk.trader][mk.want] = hold[mk.trader][mk.want] + f.makerGets
					fees = fees + f.takerFee + f.makerFee
					if f.takerFee + f.makerFee > 0 and tk.want ~= "gold" and tk.give ~= "gold" then
						bad = bad or "a fee on an orb-for-orb fill"
					end
				end
				-- dust closes with a refund (orbexchange.lua does it in the matching transaction)
				for _, o in ipairs(book) do
					if C.isDust(o) then
						hold[o.trader][o.give] = hold[o.trader][o.give] + C.left(o)
						o.given, o.dust = o.giveQty, true
					end
				end
				if C.isDust(tk) then
					hold[tk.trader][tk.give] = hold[tk.trader][tk.give] + C.left(tk)
					tk.given, tk.dust = tk.giveQty, true
				end
				-- filled makers leave the book with exactly what they asked
				for i = #book, 1, -1 do
					local mk = book[i]
					if C.isDone(mk) and mk.dust then
						table.remove(book, i)
					elseif C.isDone(mk) then
						-- the part it gave while resting paid exactly its ratio, rounded up once (what it got as a
						-- taker before resting could be better)
						local restPart = mk.got - mk.gotAtRest
						if mk.restGiven ~= mk.givenAtRest
								or restPart ~= C.ceilDiv((mk.giveQty - mk.givenAtRest) * mk.wantQty, mk.giveQty) then
							bad = bad or ("filled maker " .. mk.id .. " got " .. restPart .. " while resting")
						end
						if mk.givenAtRest == 0 and mk.gotAtRest == 0 and mk.got ~= mk.wantQty then
							bad = bad or ("filled maker " .. mk.id .. " got " .. mk.got .. " of " .. mk.wantQty)
						end
						table.remove(book, i)
					end
				end
				if not C.isDone(tk) then
					tk.givenAtRest, tk.gotAtRest = tk.given, tk.got
					book[#book + 1] = tk
				end
				-- the taker's whole result is within its ratio
				if not tk.dust and tk.got * tk.giveQty < tk.given * tk.wantQty then
					bad = bad or ("taker " .. tk.id .. " below its ratio overall")
				end
			end
		end
		check("round " .. round)
		if bad then
			break
		end
	end
	-- everything cancelled at the end: every holding is back to the total minus the fees
	for _, o in ipairs(book) do
		hold[o.trader][o.give] = hold[o.trader][o.give] + C.left(o)
	end
	book = {}
	check("after cancelling everything")
	return bad, fillsSeen, fees
end

local bad, fillsSeen, feesTaken = run(4000, 6)
ok(bad == nil, "randomized run: " .. tostring(bad))
ok(fillsSeen > 500, "the random book trades a lot (" .. fillsSeen .. " fills)")
ok(feesTaken > 0, "fees were taken")
bad, fillsSeen = run(3000, 2)
ok(bad == nil, "randomized run, two traders: " .. tostring(bad))
-- tiny orders: the rounding cases are the common ones
local function tiny(rounds)
	local hold = {{fate = 1000, awakening = 1000}, {fate = 1000, awakening = 1000}, {fate = 1000, awakening = 1000}}
	local book, id = {}, 1
	for _ = 1, rounds do
		local who = rnd(3)
		local give, want = "fate", "awakening"
		if rnd(2) == 1 then
			give, want = want, give
		end
		local tk = {id = id, trader = who, account = who, give = give, giveQty = rnd(7), want = want, wantQty = rnd(7), given = 0, got = 0}
		id = id + 1
		if hold[who][give] >= tk.giveQty then
			hold[who][give] = hold[who][give] - tk.giveQty
			for _, f in ipairs(C.match(tk, book, cfg)) do
				hold[who][want] = hold[who][want] + f.a
				hold[f.maker.trader][f.maker.want] = hold[f.maker.trader][f.maker.want] + f.b
				if f.a * tk.giveQty < f.b * tk.wantQty then
					return "tiny: taker above its limit"
				end
			end
			for i = #book, 1, -1 do
				local mk = book[i]
				if C.isDone(mk) then
					if mk.got - mk.gotAtRest ~= C.ceilDiv((mk.giveQty - mk.givenAtRest) * mk.wantQty, mk.giveQty) then
						return "tiny: filled maker " .. mk.id .. " got " .. (mk.got - mk.gotAtRest) .. " while resting"
					end
					if mk.got * mk.giveQty < mk.given * mk.wantQty then
						return "tiny: maker below its ratio"
					end
					table.remove(book, i)
				end
			end
			if not C.isDone(tk) then
				tk.givenAtRest, tk.gotAtRest = tk.given, tk.got
				book[#book + 1] = tk
			end
		end
	end
	local sum = {fate = 0, awakening = 0}
	for i = 1, 3 do
		sum.fate, sum.awakening = sum.fate + hold[i].fate, sum.awakening + hold[i].awakening
	end
	for _, o in ipairs(book) do
		sum[o.give] = sum[o.give] + C.left(o)
	end
	if sum.fate ~= 3000 or sum.awakening ~= 3000 then
		return "tiny: totals " .. sum.fate .. " / " .. sum.awakening
	end
	return nil
end
local tinyBad = tiny(5000)
ok(tinyBad == nil, "randomized tiny orders: " .. tostring(tinyBad))

print(string.format("orbexchange_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
