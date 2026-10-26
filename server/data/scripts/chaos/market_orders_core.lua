-- Chaos market buy orders: the rules without engine calls (tested by server/tests/market_test.lua with LuaJIT and Lua 5.3).
-- market.lua does the database, the escrow, the items and the protocol; market_config.lua (orders) has the numbers.
--   ChaosMarketOrders.checkFilter(f, cfg, known)          the item filter of an order (rarity, item level, the Browse
--                                                         modifier filter of market_core.lua C.modFilter), or nil, why
--   ChaosMarketOrders.checkOrder(cfg, d, known, stackable) quantity, price per unit, currency, days, total, fee, filter
--   ChaosMarketOrders.encodeFilter(f) / decodeFilter(text) the filter as one text column (no JSON needed)
--   ChaosMarketOrders.matches(filter, facts)               does an item (rarity, ilvl, MC.offerIndex of its tooltip) fit
--   ChaosMarketOrders.fillCount(order, have, want, stackable)  how many units one fill moves
--   ChaosMarketOrders.payment(cfg, cur, price, n)          total, tax, net of a fill
--   ChaosMarketOrders.ordersQuery(f, realm, now, cfg, esc, season, guid)  WHERE / ORDER BY of the Orders list
--   ChaosMarketOrders.rowView(r, now, guid)                one order as the client gets it
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosMarketCore then
	dofile("data/scripts/chaos/market_core.lua")
end

if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end

ChaosMarketOrders = ChaosMarketOrders or {}
local O = ChaosMarketOrders
local MC = ChaosMarketCore

local floor = math.floor
local int = MC.int

O.STATE = {active = 0, filled = 1, cancelled = 2, expired = 3}
O.STATE_NAME = {[0] = "active", [1] = "filled", [2] = "cancelled", [3] = "expired"}

local function ordersCfg(cfg)
	return cfg.orders or {}
end

-- ------------------------------------------------------------------ the filter
-- f = {rarity (lowest, 0 = any), ilvl (lowest item level, 0 = any), and the modifier filter fields of a Browse request:
-- mods = {{k, min, t}, ...}, need, sockets, quality, freeP, freeS, power, bound}. Returns {rarity, ilvl, mods, need,
-- sockets, quality, freePrefix, freeSuffix, power, bound} or nil, why
function O.checkFilter(f, cfg, known)
	f = type(f) == "table" and f or {}
	local mf, why = MC.modFilter(f, cfg, known)
	if not mf then
		return nil, why
	end
	mf.rarity = ChaosRarity.canon(MC.clampInt(f.rarity, 0, 15)) -- a stored id (an order saved with an old id maps)
	mf.ilvl = MC.clampInt(f.ilvl or f.ilvlMin, 0, ordersCfg(cfg).maxIlvl or 1000)
	return mf
end

-- d = {quantity, price (per unit), cur ("gold" | "coins"), days, filter}. Returns the checked order or nil, why
function O.checkOrder(cfg, d, known)
	d = type(d) == "table" and d or {}
	local oc = ordersCfg(cfg)
	local cur = d.cur == "coins" and "coins" or (d.cur == "gold" and "gold" or nil)
	if not cur then
		return nil, "Choose gold or Chaos Coins."
	end
	local qty = int(d.quantity)
	if not qty or qty < 1 then
		return nil, "Order at least one."
	end
	if qty > (oc.maxQuantity or 1000) then
		return nil, string.format("At most %s per order.", MC.money(oc.maxQuantity or 1000))
	end
	local price = int(d.price)
	local lim = cfg.price[cur]
	if not price or price < lim.min or price > lim.max then
		return nil, string.format("A %s price per item must be between %s and %s.", cur == "coins" and "coin" or "gold",
			MC.money(lim.min), MC.money(lim.max))
	end
	local total = price * qty
	local maxTotal = (oc.maxTotal or {})[cur] or lim.max
	if total > maxTotal then
		return nil, string.format(cur == "coins" and "An order may hold at most %s Chaos Coins." or "An order may hold at most %s gold.",
			MC.money(maxTotal))
	end
	local days = int(d.days) or cfg.defaultDuration
	local okDays = false
	for _, x in ipairs(cfg.durations) do
		if x == days then
			okDays = true
		end
	end
	if not okDays then
		return nil, "Choose one of the order durations."
	end
	local filter, why = O.checkFilter(d.filter, cfg, known)
	if not filter then
		return nil, why
	end
	local fee = MC.fee(cfg, cur == "gold" and total or 0, cur == "coins" and total or 0)
	return {quantity = qty, price = price, cur = cur, days = days, total = total, fee = fee, filter = filter}
end

-- "r=5;l=100;n=2;s=1;q=10;fp=1;fs=1;pw=1;bd=1;m=key:min:tier,key:min:tier" (keys are [a-z0-9_] after modFilter)
function O.encodeFilter(f)
	f = f or {}
	local parts = {}
	local function put(k, v)
		if v and v ~= 0 and v ~= false then
			parts[#parts + 1] = k .. "=" .. (v == true and "1" or tostring(v))
		end
	end
	put("r", f.rarity)
	put("l", f.ilvl)
	if f.mods and #f.mods > 0 and (f.need or #f.mods) < #f.mods then
		put("n", f.need)
	end
	put("s", f.sockets)
	put("q", f.quality)
	put("fp", f.freePrefix)
	put("fs", f.freeSuffix)
	put("pw", f.power)
	put("bd", f.bound)
	local mods = {}
	for _, m in ipairs(f.mods or {}) do
		mods[#mods + 1] = string.format("%s:%d:%d", m.key, m.min or 0, m.tier or 0)
	end
	if #mods > 0 then
		parts[#parts + 1] = "m=" .. table.concat(mods, ",")
	end
	return table.concat(parts, ";")
end

function O.decodeFilter(text)
	local f = {rarity = 0, ilvl = 0, mods = {}, need = 0, sockets = 0, quality = 0, freePrefix = false, freeSuffix = false,
		power = false, bound = false}
	for k, v in tostring(text or ""):gmatch("(%a+)=([^;]*)") do
		if k == "m" then
			for key, min, tier in v:gmatch("([%w_]+):(%d+):(%d+)") do
				f.mods[#f.mods + 1] = {key = key:lower(), min = tonumber(min), tier = tonumber(tier)}
			end
		elseif k == "r" then
			f.rarity = ChaosRarity.canon(tonumber(v) or 0)
		elseif k == "l" then
			f.ilvl = tonumber(v) or 0
		elseif k == "n" then
			f.need = tonumber(v) or 0
		elseif k == "s" then
			f.sockets = tonumber(v) or 0
		elseif k == "q" then
			f.quality = tonumber(v) or 0
		elseif k == "fp" then
			f.freePrefix = v == "1"
		elseif k == "fs" then
			f.freeSuffix = v == "1"
		elseif k == "pw" then
			f.power = v == "1"
		elseif k == "bd" then
			f.bound = v == "1"
		end
	end
	if f.need <= 0 or f.need > #f.mods then
		f.need = #f.mods
	end
	return f
end

-- the filter for the client (the Browse request's field names, so the window reads it like its own search)
function O.filterWire(f)
	local mods = {}
	for _, m in ipairs(f.mods or {}) do
		mods[#mods + 1] = {k = m.key, min = (m.min or 0) > 0 and m.min or nil, t = (m.tier or 0) > 0 and m.tier or nil}
	end
	return {rarity = (f.rarity or 0) > 0 and f.rarity or nil, ilvl = (f.ilvl or 0) > 0 and f.ilvl or nil,
		mods = #mods > 0 and mods or nil, need = #mods > 0 and (f.need or #mods) < #mods and f.need or nil,
		sockets = (f.sockets or 0) > 0 and f.sockets or nil, quality = (f.quality or 0) > 0 and f.quality or nil,
		freeP = f.freePrefix or nil, freeS = f.freeSuffix or nil, power = f.power or nil, bound = f.bound or nil}
end

-- does an item fit the filter? facts = {rarity, ilvl, index = MC.offerIndex(tooltip)}. Returns true, or false and why
function O.matches(f, facts)
	facts = facts or {}
	local idx = facts.index or {mods = {}, sockets = 0, quality = 0, freePrefix = 0, freeSuffix = 0, hasPower = 0, bound = 0}
	if (f.rarity or 0) > 0 and ChaosRarity.canon(facts.rarity) < ChaosRarity.canon(f.rarity) then
		return false, "Its rarity is too low."
	end
	if (f.ilvl or 0) > 0 and (tonumber(facts.ilvl) or 0) < f.ilvl then
		return false, "Its item level is too low."
	end
	local rows = f.mods or {}
	if #rows > 0 then
		local byKey = {}
		for _, m in ipairs(idx.mods or {}) do
			byKey[m.key] = m
		end
		local hit = 0
		for _, r in ipairs(rows) do
			local m = byKey[r.key]
			if m and m.value >= (r.min or 0) and m.tier >= (r.tier or 0) then
				hit = hit + 1
			end
		end
		local need = (f.need or 0) > 0 and math.min(f.need, #rows) or #rows
		if hit < need then
			return false, "Its modifiers do not match."
		end
	end
	if (f.sockets or 0) > 0 and (idx.sockets or 0) < f.sockets then
		return false, "Not enough sockets."
	end
	if (f.quality or 0) > 0 and (idx.quality or 0) < f.quality then
		return false, "Its quality is too low."
	end
	if f.freePrefix and (idx.freePrefix or 0) <= 0 then
		return false, "It has no free prefix."
	end
	if f.freeSuffix and (idx.freeSuffix or 0) <= 0 then
		return false, "It has no free suffix."
	end
	if f.power and (idx.hasPower or 0) <= 0 then
		return false, "It has no legendary power."
	end
	if f.bound and (idx.bound or 0) <= 0 then
		return false, "It has no bound modifier."
	end
	return true
end

-- units one fill moves: a stack gives what it has (or what the seller asked for) up to what the order still wants; a
-- single item gives one. 0 = nothing to fill
function O.fillCount(order, have, want, stackable)
	local remaining = (int(order.quantity) or 0) - (int(order.filled) or 0)
	if remaining <= 0 then
		return 0
	end
	have = int(have) or 0
	if not stackable then
		return have >= 1 and 1 or 0
	end
	local n = math.min(have, remaining)
	want = int(want)
	if want and want > 0 then
		n = math.min(n, want)
	end
	return math.max(0, n)
end

-- a fill of n units: what the buyer's escrow pays, the market's tax and what the seller receives
function O.payment(cfg, cur, price, n)
	local total = (int(price) or 0) * (int(n) or 0)
	local tax, net = MC.tax(cfg, cur, total)
	return total, tax, net
end

-- ------------------------------------------------------------------ the Orders list
local SORTS = {
	new = "`id` DESC",
	price = "`price` DESC, `id` ASC", -- the best paying first
	ending = "`expires` ASC, `id` ASC",
	name = "`name` ASC, `id` DESC"
}

-- f = {q, cat, cur, mine (only my orders, every state), sort, page}; guid = the viewer
function O.ordersQuery(f, realm, now, cfg, esc, season, guid)
	f = type(f) == "table" and f or {}
	local oc = ordersCfg(cfg)
	local w = {}
	if f.mine then
		w[#w + 1] = "`buyer_id` = " .. (int(guid) or 0)
		w[#w + 1] = "`state` = 0"
	else
		w[#w + 1] = "`state` = 0"
		w[#w + 1] = MC.realmClause(realm, season)
		w[#w + 1] = "`expires` > " .. (int(now) or 0)
	end
	local q = tostring(f.q or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if q ~= "" then
		w[#w + 1] = "`name` LIKE " .. esc("%" .. MC.likeEscape(q:sub(1, 40)) .. "%")
	end
	local cat = tostring(f.cat or "")
	for _, c in ipairs(cfg.categories) do
		if c == cat then
			w[#w + 1] = "`category` = " .. esc(cat)
		end
	end
	if f.cur == "gold" or f.cur == "coins" then
		w[#w + 1] = "`currency` = " .. esc(f.cur)
	end
	local item = int(f.item)
	if item and item > 0 then
		w[#w + 1] = "`item_id` = " .. item
	end
	local order = SORTS[tostring(f.sort or "new")] or SORTS.new
	local size = oc.pageSize or cfg.pageSize
	local page = int(f.page) or 1
	if page < 1 then
		page = 1
	end
	if page > 1000 then
		page = 1000
	end
	return table.concat(w, " AND "), order, page, (page - 1) * size, size
end

function O.rowView(r, now, guid)
	return {
		id = r.id, item = r.client_id, sid = r.item_id, name = r.name, cat = r.category, qty = r.quantity, filled = r.filled,
		price = r.price, cur = r.currency, buyer = r.buyer_name, left = math.max(0, (r.expires or 0) - (now or 0)),
		state = O.STATE_NAME[r.state] or "?", stack = (r.stackable or 0) == 1 or nil, escrow = r.escrow,
		refunded = (r.refunded or 0) > 0 and r.refunded or nil, filter = O.filterWire(O.decodeFilter(r.filter)),
		mine = (guid and r.buyer_id == guid) or nil, at = (r.closed_at or 0) ~= 0 and r.closed_at or r.created
	}
end

return O
