-- restock_core.lua: the pure rules of the Restock button (restock_config.lua; server/README.md "Restock"). No engine
-- calls; restock.lua is the engine side. Tests: server/tests/restock_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- used      {[id] = units used} (the hunt session's supplies: potions and spears count one each, a rune counts its
--           charges)
-- restocked {[id] = units already bought back in this session}
-- info(id)  {stack = true | false, charges = n} of the item type
-- prices    {[id] = NPC price of one item} (hunt_supplies.lua: a rune's price is for the rune with all its charges)

ChaosRestockCore = ChaosRestockCore or {}
local R = ChaosRestockCore

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local function num(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return v
end

-- the units still to buy back of each supply: {[id] = units}
function R.remaining(used, restocked)
	local out = {}
	for id, n in pairs(used or {}) do
		local left = floor(num(n)) - floor(num(restocked and restocked[id]))
		if left > 0 then
			out[id] = left
		end
	end
	return out
end

-- the purchase: list of {id, units, count (items to buy), each (gold per item), gold}, most gold first (ties by id),
-- within cfg.maxUnits. Supplies without a price are left out.
function R.plan(remaining, prices, info, cfg)
	local rows = {}
	local mult = num(cfg.priceMult)
	if mult <= 0 then
		mult = 1
	end
	for id, units in pairs(remaining or {}) do
		local price = num(prices[id])
		if price > 0 and units > 0 then
			local t = info(id) or {}
			local charges = (not t.stack and num(t.charges) > 1) and floor(num(t.charges)) or 1
			local count = ceil(units / charges)
			local each = max(1, floor(price * mult + 0.5))
			rows[#rows + 1] = {id = id, units = units, count = count, charges = charges, each = each, gold = each * count}
		end
	end
	table.sort(rows, function(a, b)
		if a.gold ~= b.gold then
			return a.gold > b.gold
		end
		return a.id < b.id
	end)
	local left = floor(num(cfg.maxUnits))
	local out = {}
	for _, r in ipairs(rows) do
		if left <= 0 then
			break
		end
		if r.units > left then
			r.units = left
			r.count = ceil(left / r.charges)
			r.gold = r.each * r.count
		end
		left = left - r.units
		out[#out + 1] = r
	end
	return out
end

-- what the money pays for: the rows cut to the gold (whole items), in plan order; returns rows, total
function R.afford(plan, money)
	money = max(0, floor(num(money)))
	local out, total = {}, 0
	for _, r in ipairs(plan) do
		local n = min(r.count, floor((money - total) / r.each))
		if n > 0 then
			out[#out + 1] = {id = r.id, count = n, charges = r.charges, each = r.each, gold = n * r.each,
				units = min(r.units, n * r.charges)}
			total = total + n * r.each
		end
	end
	return out, total
end

-- the convenience fee inside rows: what they cost over the plain NPC price
function R.fee(rows, prices)
	local f = 0
	for _, r in ipairs(rows or {}) do
		f = f + r.gold - floor(num(prices[r.id])) * r.count
	end
	return max(0, f)
end

-- the fee in percent of the NPC price (priceMult 1.10 -> 10)
function R.feePercent(cfg)
	return max(0, floor((num(cfg.priceMult) - 1) * 100 + 0.5))
end

function R.total(plan)
	local g = 0
	for _, r in ipairs(plan) do
		g = g + r.gold
	end
	return g
end

-- stacks of a stackable supply: list of counts of at most size
function R.stacks(count, size)
	local out = {}
	size = max(1, floor(num(size)))
	count = floor(num(count))
	while count > 0 do
		local n = min(size, count)
		out[#out + 1] = n
		count = count - n
	end
	return out
end

-- the same quote? (a purchase only goes through for the plan the player saw)
function R.sameQuote(a, b)
	if not a or not b or #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i].id ~= b[i].id or a[i].count ~= b[i].count or a[i].gold ~= b[i].gold then
			return false
		end
	end
	return true
end

return R
