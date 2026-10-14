-- Orb Exchange: the rules without engine calls (tested by server/tests/orbexchange_test.lua with LuaJIT and Lua 5.3).
-- orbexchange.lua does the database, the escrow, the items and the protocol; orbexchange_config.lua has the numbers.
--
-- An order gives `giveQty` of one asset and wants at least `wantQty` of another (assets: "gold" = the bank balance, or
-- the key of a crafting orb; orb for orb or orb for gold, never gold for gold). Its limit ratio is wantQty / giveQty
-- (what it wants per unit it gives). The whole offered amount is escrowed in the order row when it is placed; the order
-- is done once it has given all of it (a better price only means it receives more).
--
-- Matching (price-time priority): a new order (the taker) meets the resting orders (makers) that give what it wants and
-- want what it gives, cheapest ratio first, the older first at the same ratio. Every fill is at the maker's ratio: the
-- maker's cumulative receipt since it went on the book is ceil(given there x wantQty / giveQty), so a maker never gets
-- less than its ratio and gets exactly wantQty once it has given everything (an order that traded as a taker first
-- keeps the better price it got then; restGiven marks where it went on the book). The taker's own limit is checked on every fill (what it gets per unit
-- it pays is never worse than its ratio). Nothing is created: a fill moves `a` from the maker's escrow to the taker
-- and `b` from the taker's escrow to the maker; the gold leg pays the fee (goldBps of it, rounded down), which leaves
-- the game. All numbers are integers; products stay below 2^53 (orb amounts up to 1e5, gold up to 2e9 per order).
--
--   ChaosOrbExchangeCore.checkOrder(cfg, d, orbs)        the checked order {give, giveQty, want, wantQty, days, fee, pair}
--   ChaosOrbExchangeCore.pairKey(a, b)                   one key per pair, whatever the side ("fate/gold", "awakening/fate")
--   ChaosOrbExchangeCore.crosses(taker, maker)           would the two trade?
--   ChaosOrbExchangeCore.makerBefore(m1, m2)             price-time priority of the resting orders
--   ChaosOrbExchangeCore.fillAmounts(maker, taker, scan) a (maker gives), b (taker gives) of one fill, or nil
--   ChaosOrbExchangeCore.match(taker, makers, cfg, opts)  the fills of a new order (changes the order tables it gets)
--   ChaosOrbExchangeCore.isDone(o) / isDust(o)           all given / the rest cannot buy one unit (closed, refunded)
--   ChaosOrbExchangeCore.fee(cfg, gold)                  the fee of a gold leg
--   ChaosOrbExchangeCore.book(orders, base, quote, depth)  price levels on both sides of a pair as the viewer sees it
--   ChaosOrbExchangeCore.history(trades, now, base, quote, hours)  last price, 24h volume, high / low, hourly points
--   ChaosOrbExchangeCore.makersQuery(taker, realm, season, now, limit)  WHERE / ORDER BY / LIMIT of the makers to read
--   ChaosOrbExchangeCore.limitRefusal(cfg, char, account, maxChar, maxAccount)
-- The crash-safety plans and the realm rules are the market's (ChaosMarketCore.pendingAction, deliveryPlan,
-- realmOf, realmClause), re-exported here.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosMarketCore then
	dofile("data/scripts/chaos/market_core.lua")
end

ChaosOrbExchangeCore = ChaosOrbExchangeCore or {}
local C = ChaosOrbExchangeCore
local MC = ChaosMarketCore

local floor = math.floor

C.GOLD = "gold"
C.STATE = {active = 0, filled = 1, cancelled = 2, expired = 3, pending = 9}
C.STATE_NAME = {[0] = "active", [1] = "filled", [2] = "cancelled", [3] = "expired", [9] = "pending"}

-- the market's helpers (crash safety, seasons, money text)
C.pendingAction = MC.pendingAction
C.deliveryPlan = MC.deliveryPlan
C.realmOf = MC.realmOf
C.realmClause = MC.realmClause
C.money = MC.money

local function int(v)
	v = tonumber(v)
	-- beyond +-2^53 no exact integer: "%d" in an SQL string fails (Lua 5.3) or reads -2^63 (LuaJIT)
	if not v or v ~= v or v > 9007199254740992 or v < -9007199254740992 then
		return nil
	end
	return floor(v)
end
C.int = int

-- floor(x / d) for non-negative integers, exact even where the float quotient rounds (x, d below 2^53)
function C.idiv(x, d)
	local q = floor(x / d)
	while q * d > x do
		q = q - 1
	end
	while (q + 1) * d <= x do
		q = q + 1
	end
	return q
end

function C.ceilDiv(x, d)
	local q = C.idiv(x, d)
	if q * d < x then
		q = q + 1
	end
	return q
end

local function gcd(a, b)
	while b ~= 0 do
		a, b = b, a % b
	end
	return a
end
C.gcd = gcd

-- ------------------------------------------------------------------ orders
function C.isGold(asset)
	return asset == C.GOLD
end

-- "fate/gold" (an orb against gold), "awakening/fate" (two orbs, sorted): the same key for both sides of a pair
function C.pairKey(a, b)
	a, b = tostring(a or ""), tostring(b or "")
	if a == C.GOLD then
		return b .. "/" .. a
	end
	if b == C.GOLD then
		return a .. "/" .. b
	end
	if a > b then
		a, b = b, a
	end
	return a .. "/" .. b
end

local function assetName(asset, orbs)
	if asset == C.GOLD then
		return "gold"
	end
	local o = orbs and orbs[asset]
	return o and o.name or tostring(asset)
end
C.assetName = assetName

-- d = {give, giveQty, want, wantQty, days}; orbs = {key -> {id, name}} (the orbs on the exchange).
-- Returns {give, giveQty, want, wantQty, days, fee (gold, at placing), pair} or nil, why
function C.checkOrder(cfg, d, orbs)
	d = type(d) == "table" and d or {}
	orbs = orbs or {}
	local give, want = tostring(d.give or ""), tostring(d.want or "")
	local function known(a)
		return a == C.GOLD or orbs[a] ~= nil
	end
	if not known(give) or not known(want) then
		return nil, cfg.messages.asset
	end
	if give == want then
		return nil, cfg.messages.same
	end
	if give == C.GOLD and want == C.GOLD then
		return nil, cfg.messages.same
	end
	local giveQty, wantQty = int(d.giveQty), int(d.wantQty)
	local function bad(asset, qty)
		local kind = asset == C.GOLD and "gold" or "orb"
		local lo, hi = cfg.min[kind], cfg.max[kind]
		if not qty or qty < lo then
			return string.format(cfg.messages.tooSmall, C.money(lo), assetName(asset, orbs))
		end
		if qty > hi then
			return string.format(cfg.messages.tooBig, C.money(hi), assetName(asset, orbs))
		end
		return nil
	end
	local why = bad(give, giveQty) or bad(want, wantQty)
	if why then
		return nil, why
	end
	local days = int(d.days) or cfg.defaultDuration
	local okDays = false
	for _, x in ipairs(cfg.durations) do
		if x == days then
			okDays = true
		end
	end
	if not okDays then
		return nil, cfg.messages.days
	end
	local fee = 0
	if give ~= C.GOLD and want ~= C.GOLD then
		fee = cfg.fees.orbPairGold or 0
	end
	return {give = give, giveQty = giveQty, want = want, wantQty = wantQty, days = days, fee = fee, pair = C.pairKey(give, want)}
end

-- the fee of a gold leg: goldBps / 10000 of it, rounded down (it leaves the game)
function C.fee(cfg, gold)
	gold = int(gold) or 0
	if gold <= 0 then
		return 0
	end
	return C.idiv(gold * (cfg.fees.goldBps or 0), 10000)
end

-- what is still in escrow
function C.left(o)
	return math.max(0, (o.giveQty or 0) - (o.given or 0))
end

-- what an order resting on the book is owed after giving `given` in all: its ratio applied to what it gave since it
-- went on the book (restGiven = what it had given as a taker before), rounded up: never below its ratio. What it got
-- as a taker at a better price stays its own; the rest of its escrow is priced at its ratio again.
function C.owed(o, given)
	return C.ceilDiv((given - (o.restGiven or 0)) * o.wantQty, o.giveQty)
end

-- the maker gives what the taker wants, wants what the taker gives, and the two ratios meet:
-- (maker.want / maker.give) x (taker.want / taker.give) <= 1
function C.crosses(taker, maker)
	if maker.give ~= taker.want or maker.want ~= taker.give then
		return false
	end
	return maker.wantQty * taker.wantQty <= maker.giveQty * taker.giveQty
end

-- price-time priority among the makers of one side: the lowest ratio (want per give) first, then the oldest
function C.makerBefore(m1, m2)
	local l, r = m1.wantQty * m2.giveQty, m2.wantQty * m1.giveQty
	if l ~= r then
		return l < r
	end
	return (m1.id or 0) < (m2.id or 0)
end

-- one fill between a maker and a taker: the most the maker can give (its escrow) that the taker can pay for (its
-- escrow), at the maker's ratio, and that keeps the taker within its own limit. nil = no fill possible.
-- The largest fill can break the taker's limit by the rounding up (< 1 unit of what the taker pays); then smaller fills
-- are tried, `scan` steps over what the maker gives and `scan` steps over what the taker pays (whichever unit is the
-- coarse one), and the largest that keeps the limit is taken.
function C.fillAmounts(maker, taker, scan)
	local mLeft, tLeft = C.left(maker), C.left(taker)
	if mLeft <= 0 or tLeft <= 0 then
		return nil
	end
	scan = scan or 256
	local G, W = maker.giveQty, maker.wantQty
	local g = maker.given or 0
	local d = g - (maker.restGiven or 0)
	local base = C.owed(maker, g)
	-- the most the maker gives for a payment of b: (d + a) x W <= (base + b) x G
	local function aFor(b)
		return math.min(mLeft, C.idiv((base + b) * G, W) - d)
	end
	local function fits(a, b)
		return a >= 1 and b <= tLeft and a * taker.giveQty >= b * taker.wantQty
	end
	local aMax = aFor(tLeft)
	if aMax < 1 then
		return nil
	end
	local bestA, bestB
	for a = aMax, math.max(1, aMax - scan), -1 do
		local b = C.owed(maker, g + a) - base
		if fits(a, b) then
			bestA, bestB = a, b
			break
		end
	end
	local bTop = C.owed(maker, g + aMax) - base
	for b = bTop, math.max(0, bTop - scan), -1 do
		local a = aFor(b)
		if a < 1 or (bestA and a <= bestA) then
			break
		end
		local b2 = C.owed(maker, g + a) - base
		if fits(a, b2) then
			bestA, bestB = a, b2
			break
		end
	end
	return bestA, bestB
end

-- taker = {id, account, give, giveQty, want, wantQty, given, got}; makers = list of the same (+ player, restGiven). Makers of the
-- taker's account are skipped unless opts.selfTrade. Changes given / got of the taker and of every maker that trades.
-- Returns the fills: {maker (the table), a, b, takerFee, makerFee, takerGets, makerGets}; a goes maker -> taker in the
-- maker's asset, b taker -> maker in the taker's asset; the fee is on whichever side receives gold. Sets
-- taker.restGiven (the order rests from there).
function C.match(taker, makers, cfg, opts)
	opts = opts or {}
	local list = {}
	for _, m in ipairs(makers or {}) do
		if m.give == taker.want and m.want == taker.give and C.left(m) > 0 then
			list[#list + 1] = m
		end
	end
	table.sort(list, C.makerBefore)
	local fills = {}
	for _, m in ipairs(list) do
		if C.left(taker) <= 0 then
			break
		end
		if not C.crosses(taker, m) then
			break -- sorted: no later maker crosses either
		end
		if opts.selfTrade or m.account == nil or m.account ~= taker.account then
			local a, b = C.fillAmounts(m, taker, cfg.scan)
			if a then
				m.given = (m.given or 0) + a
				m.got = (m.got or 0) + b
				taker.given = (taker.given or 0) + b
				taker.got = (taker.got or 0) + a
				local takerFee = taker.want == C.GOLD and C.fee(cfg, a) or 0
				local makerFee = m.want == C.GOLD and C.fee(cfg, b) or 0
				fills[#fills + 1] = {maker = m, a = a, b = b, takerFee = takerFee, makerFee = makerFee, takerGets = a - takerFee,
					makerGets = b - makerFee}
			end
		end
	end
	-- what is left rests on the book from here, at the order's own ratio
	taker.restGiven = taker.given or 0
	return fills
end

function C.isDone(o)
	return (o.given or 0) >= (o.giveQty or 0)
end

-- what is left cannot buy one whole unit at the order's own ratio (a buyer that got a better price earlier keeps a few
-- coins): the order closes as filled and the rest goes back
function C.isDust(o)
	local left = C.left(o)
	return left > 0 and left * o.wantQty < o.giveQty
end

-- ------------------------------------------------------------------ the database read of the makers
-- taker = the order row (give, want, giveQty, wantQty); returns the WHERE, ORDER BY and LIMIT of the makers that cross
-- it (the exact order is made again by C.match: the float ratio of ORDER BY only picks the candidates)
function C.makersQuery(taker, realm, season, now, limit, esc)
	esc = esc or function(s) return "'" .. tostring(s):gsub("[^%w_]", "") .. "'" end
	local w = {
		"`state` = 0",
		"`give_asset` = " .. esc(taker.want),
		"`want_asset` = " .. esc(taker.give),
		"`expires` > " .. (int(now) or 0),
		"`id` <> " .. (int(taker.id) or 0),
		C.realmClause(realm, season),
		string.format("`want_qty` * %d <= `give_qty` * %d", int(taker.wantQty) or 0, int(taker.giveQty) or 0)
	}
	return table.concat(w, " AND "), "`want_qty` / `give_qty` ASC, `id` ASC", int(limit) or 200
end

-- why one more order is refused (nil = fine)
function C.limitRefusal(cfg, char, account, maxChar, maxAccount)
	maxChar, maxAccount = maxChar or cfg.maxOpen, maxAccount or cfg.maxOpenPerAccount
	if (char or 0) >= maxChar then
		return string.format(cfg.messages.maxOpen, maxChar)
	end
	if (account or 0) >= maxAccount then
		return string.format(cfg.messages.maxAccount, maxAccount)
	end
	return nil
end

-- ------------------------------------------------------------------ the book as a viewer sees it
-- "ask": the order gives the base and wants the quote; "bid": gives the quote, wants the base; nil: another pair
function C.side(o, base, quote)
	if o.give == base and o.want == quote then
		return "ask"
	end
	if o.give == quote and o.want == base then
		return "bid"
	end
	return nil
end

-- the price of an order in quote per base, as a reduced fraction (num, den) and a number
function C.priceOf(o, base)
	local n, d
	if o.give == base then
		n, d = o.wantQty, o.giveQty
	else
		n, d = o.giveQty, o.wantQty
	end
	local g = gcd(n, d)
	n, d = n / g, d / g
	return n / d, n, d
end

-- what is left of an order in base units (an ask: its escrow; a bid: what its escrow buys at its limit)
function C.baseLeft(o, base)
	local left = C.left(o)
	if o.give == base then
		return left
	end
	return C.idiv(left * o.wantQty, o.giveQty)
end

-- orders = rows {give, giveQty, want, wantQty, given}; returns {asks = levels, bids = levels}; a level = {p (quote per
-- base), q (base left), n (orders), t (quote, about p x q)}. Asks lowest first, bids highest first, `depth` each.
function C.book(orders, base, quote, depth)
	local levels = {ask = {}, bid = {}}
	local index = {ask = {}, bid = {}}
	for _, o in ipairs(orders or {}) do
		local side = C.side(o, base, quote)
		if side and C.left(o) > 0 then
			local p, n, d = C.priceOf(o, base)
			local key = string.format("%.0f/%.0f", n, d)
			local lv = index[side][key]
			if not lv then
				lv = {p = p, q = 0, n = 0, t = 0, num = n, den = d}
				index[side][key] = lv
				levels[side][#levels[side] + 1] = lv
			end
			local q = C.baseLeft(o, base)
			lv.q = lv.q + q
			lv.n = lv.n + 1
			lv.t = lv.t + (side == "ask" and C.idiv(q * n, d) or C.left(o))
		end
	end
	local function cmp(x, y)
		return x.num * y.den < y.num * x.den
	end
	table.sort(levels.ask, cmp)
	table.sort(levels.bid, function(x, y) return cmp(y, x) end)
	local out = {asks = {}, bids = {}}
	depth = depth or 10
	for i = 1, math.min(depth, #levels.ask) do
		local lv = levels.ask[i]
		out.asks[i] = {p = lv.p, q = lv.q, n = lv.n, t = lv.t}
	end
	for i = 1, math.min(depth, #levels.bid) do
		local lv = levels.bid[i]
		out.bids[i] = {p = lv.p, q = lv.q, n = lv.n, t = lv.t}
	end
	out.spread = (out.asks[1] and out.bids[1]) and (out.asks[1].p - out.bids[1].p) or nil
	return out
end

-- ------------------------------------------------------------------ trades
-- t = {makerGive (asset the maker gave), a (maker gave), b (taker gave), at}: base and quote amounts for this view
function C.tradeAmounts(t, base)
	if t.makerGive == base then
		return t.a, t.b
	end
	return t.b, t.a
end

-- trades of one pair (any order); returns {last, open, high, low, change (percent), vol (base), volQuote, points =
-- {{h (hours ago, 0 = this hour), p (average price), v (base)}}, trades = newest first {at, p, q, side}}
function C.history(trades, now, base, quote, hours)
	hours = hours or 24
	local since = now - hours * 3600
	local sorted = {}
	for _, t in ipairs(trades or {}) do
		sorted[#sorted + 1] = t
	end
	table.sort(sorted, function(x, y)
		if x.at ~= y.at then
			return x.at < y.at
		end
		return (x.id or 0) < (y.id or 0)
	end)
	local out = {vol = 0, volQuote = 0, points = {}, trades = {}}
	local buckets = {}
	for _, t in ipairs(sorted) do
		local q, v = C.tradeAmounts(t, base)
		if q > 0 then
			local p = v / q
			out.last = p
			if t.at >= since then
				out.open = out.open or p
				out.high = math.max(out.high or p, p)
				out.low = math.min(out.low or p, p)
				out.vol = out.vol + q
				out.volQuote = out.volQuote + v
				local h = math.max(0, math.min(hours - 1, floor((now - t.at) / 3600)))
				local bk = buckets[h]
				if not bk then
					bk = {h = h, q = 0, v = 0}
					buckets[h] = bk
				end
				bk.q = bk.q + q
				bk.v = bk.v + v
			end
		end
	end
	for h = hours - 1, 0, -1 do
		local bk = buckets[h]
		if bk then
			out.points[#out.points + 1] = {h = h, p = bk.v / bk.q, v = bk.q}
		end
	end
	if out.open and out.last and out.open > 0 then
		out.change = (out.last - out.open) / out.open * 100
	end
	for i = #sorted, 1, -1 do
		local t = sorted[i]
		local q, v = C.tradeAmounts(t, base)
		if q > 0 then
			-- "buy": the taker bought the base (it gave the quote); "sell": the taker sold it
			out.trades[#out.trades + 1] = {at = t.at, p = v / q, q = q, side = t.makerGive == base and "buy" or "sell"}
		end
	end
	return out
end

-- a price for people: 4 significant digits at most, thousands separated
function C.priceText(p)
	p = tonumber(p)
	if not p then
		return "-"
	end
	if p >= 1000 then
		return C.money(floor(p + 0.5))
	end
	local s
	if p >= 100 then
		s = string.format("%.1f", p)
	elseif p >= 1 then
		s = string.format("%.2f", p)
	elseif p >= 0.01 then
		s = string.format("%.4f", p)
	else
		s = string.format("%.6f", p)
	end
	s = s:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
	return s
end

return C
