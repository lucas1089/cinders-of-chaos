-- The Gambler: pure logic (no engine calls), shared by gamble.lua and server/tests/gamble_test.lua.
-- Numbers: gamble_config.lua; overview: server/README.md "The Gambler".
--   ChaosGambleCore.validate(cfg)                         list of config problems (empty = fine)
--   .rng(seed)                                            a small deterministic generator (same numbers in 5.1 / 5.3)
--   .period / .offset / .window / .nextRefresh(cfg, t, offset)   the fixed 4-hour windows (server time or a fixed UTC offset)
--   .seed(cfg, guid, window, rerolls)                     the seed of one character's stock in one window
--   .interp(curve, x)                                     straight lines between {x, y} points
--   .price(cfg, ilvl, slot) / .rerollPrice(cfg, gate, done)   gold
--   .candidates(cfg, slot, level, canUse)                 the base types a character may get in a slot
--   .stock(cfg, ctx)                                      the whole stock: {{i, id, slot, lv, ilvl, price}, ...}
--   .isSold / .markSold / .unmarkSold(mask, i)            the sold slots as a bit mask (a player storage)
--   .odds(cfg, gear)                                      exact chance of every rarity place 0..6 (0 none, 1 Common .. 6 Divine, the
--                                                         ChaosRarity ranks; gear = ChaosLootConfig.gear)
--   .rollRarity(cfg, api)                                 the roll itself through the loot layer's API (ChaosLoot)
--   .checkBuy(cfg, s)                                     every refusal of a purchase, in order
--   .huntIncome(cfg, level) / .shareAt(cfg, level, gateFn) the price against hunting gold per hour
--   .payload(cfg, view)                                   the window state for the client
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosGambleCore = ChaosGambleCore or {}
local K = ChaosGambleCore
if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end

local floor, min, max = math.floor, math.min, math.max

K.SLOT_NAMES = {weapon = "Weapon", shield = "Shield", helmet = "Helmet", armor = "Armor", legs = "Legs", boots = "Boots",
	amulet = "Amulet", ring = "Ring", quiver = "Quiver"}

-- ---------------------------------------------------------------- generator
-- Park-Miller: exact in doubles (LuaJIT) and in 5.3 integers
function K.rng(seed)
	local m = 2147483647
	local state = floor(tonumber(seed) or 1) % (m - 1) + 1
	local function nextValue()
		state = (state * 48271) % m
		return state
	end
	for _ = 1, 3 do
		nextValue()
	end
	return function(a, b)
		local v = nextValue()
		if not a then
			return (v - 1) / (m - 1)
		end
		return a + v % (b - a + 1)
	end
end

-- ---------------------------------------------------------------- config check
function K.validate(cfg)
	local out = {}
	local function bad(text)
		out[#out + 1] = text
	end
	local h = cfg.refresh and cfg.refresh.hours
	if type(h) ~= "number" or h < 1 or 24 % h ~= 0 then
		bad("refresh.hours must divide 24")
	end
	if type(cfg.stock.size) ~= "number" or cfg.stock.size < 1 or cfg.stock.size > 30 then
		bad("stock.size must be 1..30 (the sold mask is one storage)")
	end
	local seen = {}
	for _, slot in ipairs(cfg.stock.order) do
		if not K.SLOT_NAMES[slot] then
			bad("unknown slot " .. tostring(slot))
		end
		if not cfg.price.slot[slot] then
			bad("no price multiplier for " .. slot)
		end
		for _, e in ipairs(cfg.pool[slot] or {}) do
			if type(e[1]) ~= "number" or type(e[2]) ~= "number" then
				bad("pool entry of " .. slot .. " needs {id, lv}")
			elseif seen[e[1]] then
				bad("item " .. e[1] .. " is in the pool twice")
			end
			seen[e[1]] = true
		end
	end
	for slot, w in pairs(cfg.stock.slots) do
		if not K.SLOT_NAMES[slot] or type(w) ~= "number" or w < 0 then
			bad("bad slot weight " .. tostring(slot))
		end
	end
	local prev
	for _, p in ipairs(cfg.price.curve) do
		if prev and (p[1] <= prev[1] or p[2] < prev[2]) then
			bad("price.curve must rise")
		end
		prev = p
	end
	if cfg.odds.floor < 0 or ChaosRarity.rank(cfg.odds.maxRarity) < ChaosRarity.rank(cfg.odds.floor) or cfg.odds.draws < 1 then
		bad("odds: draws >= 1, 0 <= floor <= maxRarity")
	end
	return out
end

-- ---------------------------------------------------------------- the 4-hour windows
function K.period(cfg)
	return floor((cfg.refresh.hours or 4) * 3600)
end

-- seconds east of UTC of the clock the windows follow: the fixed offset of the config, else the server's own zone at t
function K.offset(cfg, t)
	local h = cfg.refresh.utcOffsetHours
	if type(h) == "number" then
		return floor(h * 3600)
	end
	t = t or os.time()
	local u = os.date("!*t", t)
	u.isdst = false
	local l = os.date("*t", t)
	l.isdst = false
	return os.time(l) - os.time(u)
end

-- the number of the window t lies in (windows start at local 00:00, 04:00, ...)
function K.window(cfg, t, offset)
	return floor((t + (offset or 0)) / K.period(cfg))
end

-- os.time of the start of window w, and of the next refresh after t
function K.windowStart(cfg, w, offset)
	return w * K.period(cfg) - (offset or 0)
end

function K.nextRefresh(cfg, t, offset)
	return K.windowStart(cfg, K.window(cfg, t, offset) + 1, offset)
end

-- local clock time "HH:MM" of a window start (for the texts)
function K.clock(cfg, w)
	local s = (w * K.period(cfg)) % 86400
	return string.format("%02d:%02d", floor(s / 3600), floor(s % 3600 / 60))
end

-- the seed of one stock: the character, the window and the early refreshes bought in it
function K.seed(cfg, guid, window, rerolls)
	local s = (cfg.stock.seed or 1) * 1000003 + (floor(tonumber(guid) or 0) % 1000000007) * 7919 +
		floor(tonumber(window) or 0) * 31 + floor(tonumber(rerolls) or 0) * 104729
	return s % 2147483646 + 1
end

-- ---------------------------------------------------------------- prices
function K.interp(curve, x)
	x = tonumber(x) or 0
	if x <= curve[1][1] then
		return curve[1][2]
	end
	for i = 2, #curve do
		local a, b = curve[i - 1], curve[i]
		if x <= b[1] then
			return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
		end
	end
	return curve[#curve][2]
end

function K.price(cfg, ilvl, slot)
	local p = cfg.price
	local raw = K.interp(p.curve, ilvl) * (p.slot[slot] or 1)
	local r = p.round or 1
	return max(r, floor(raw / r + 1e-9) * r)
end

-- the price of the next early refresh after `done` of them in this window (nil: none left)
function K.rerollPrice(cfg, gate, done)
	local r = cfg.reroll
	done = done or 0
	if not r or (r.max or 0) <= 0 or done >= r.max then
		return nil
	end
	local round = cfg.price.round or 1
	local first = max(round, floor(K.price(cfg, gate, "armor") * (r.mult or 0.5) / round + 1e-9) * round)
	return floor(first * (r.growth or 2) ^ done + 1e-9)
end

-- ---------------------------------------------------------------- the stock
-- the base types of a slot a character may get: pool entries with lv <= level that canUse(id) allows, the
-- cfg.base.choices with the highest lv (ties by id)
function K.candidates(cfg, slot, level, canUse)
	local list = {}
	for _, e in ipairs(cfg.pool[slot] or {}) do
		if e[2] <= level and (not canUse or canUse(e[1], slot)) then
			list[#list + 1] = {id = e[1], lv = e[2]}
		end
	end
	table.sort(list, function(a, b)
		if a.lv ~= b.lv then
			return a.lv > b.lv
		end
		return a.id < b.id
	end)
	local n = cfg.base.choices or 4
	while #list > n do
		table.remove(list)
	end
	return list
end

local function pickSlot(cfg, rand, skip)
	local total = 0
	for _, slot in ipairs(cfg.stock.order) do
		if not skip[slot] then
			total = total + (cfg.stock.slots[slot] or 0)
		end
	end
	if total <= 0 then
		return nil
	end
	local roll, acc = rand(1, total), 0
	for _, slot in ipairs(cfg.stock.order) do
		if not skip[slot] then
			acc = acc + (cfg.stock.slots[slot] or 0)
			if roll <= acc then
				return slot
			end
		end
	end
	return nil
end

-- ctx = {guid, window, rerolls, level, gate (the item level gate), canUse(id, slot)}. Deterministic: the same ctx gives
-- the same stock. Returns entries sorted by the display order (slot, then the best first), each
-- {i, id, slot, lv, ilvl, price}; empty when the character can use nothing at all.
function K.stock(cfg, ctx)
	local rand = K.rng(K.seed(cfg, ctx.guid, ctx.window, ctx.rerolls))
	local level = max(1, floor(tonumber(ctx.level) or 1))
	local gate = max(1, floor(tonumber(ctx.gate) or 1))
	local cands, empty = {}, {}
	for _, slot in ipairs(cfg.stock.order) do
		cands[slot] = K.candidates(cfg, slot, level, ctx.canUse)
		if #cands[slot] == 0 then
			empty[slot] = true
		end
	end
	local used, out = {}, {}
	local spread = max(0, floor(cfg.itemLevel.spread or 0))
	for _ = 1, cfg.stock.size do
		local slot = pickSlot(cfg, rand, empty)
		if not slot then
			break
		end
		local list = cands[slot]
		local pick = list[rand(1, #list)]
		if cfg.base.dedupe and used[pick.id] then
			-- another base of the slot when one is left that this stock does not have yet (two tries)
			for _ = 1, 2 do
				local again = list[rand(1, #list)]
				if not used[again.id] then
					pick = again
					break
				end
			end
		end
		used[pick.id] = true
		local ilvl = max(1, gate - rand(0, spread))
		out[#out + 1] = {id = pick.id, slot = slot, lv = pick.lv, ilvl = ilvl, price = K.price(cfg, ilvl, slot)}
	end
	local order = {}
	for i, slot in ipairs(cfg.stock.order) do
		order[slot] = i
	end
	table.sort(out, function(a, b)
		if a.slot ~= b.slot then
			return order[a.slot] < order[b.slot]
		end
		if a.lv ~= b.lv then
			return a.lv > b.lv
		end
		if a.id ~= b.id then
			return a.id < b.id
		end
		return a.ilvl > b.ilvl
	end)
	for i, e in ipairs(out) do
		e.i = i
	end
	return out
end

-- ---------------------------------------------------------------- sold slots (bit i - 1 of a whole number)
local function bit(i)
	return floor(2 ^ (i - 1))
end

function K.isSold(mask, i)
	mask = max(0, floor(tonumber(mask) or 0))
	return floor(mask / bit(i)) % 2 == 1
end

function K.markSold(mask, i)
	mask = max(0, floor(tonumber(mask) or 0))
	if K.isSold(mask, i) then
		return mask
	end
	return floor(mask + bit(i))
end

function K.unmarkSold(mask, i)
	mask = max(0, floor(tonumber(mask) or 0))
	if not K.isSold(mask, i) then
		return mask
	end
	return floor(mask - bit(i))
end

function K.soldCount(mask, n)
	local c = 0
	for i = 1, n do
		if K.isSold(mask, i) then
			c = c + 1
		end
	end
	return c
end

-- ---------------------------------------------------------------- the rarity roll
local function stockHit(chance)
	-- loot.lua L.stockRarity: rnd(1, 100) <= chance, so a fraction counts as the whole number below it
	return min(100, max(0, floor(tonumber(chance) or 0))) / 100
end

local function pctHit(p)
	-- loot.lua pct(p): rnd(1, 1000000) <= p * 10000
	p = tonumber(p) or 0
	if p <= 0 then
		return 0
	end
	if p >= 100 then
		return 1
	end
	return min(1000000, floor(p * 10000 + 1e-9)) / 1000000
end

-- the stock roll's distribution (loot.lua L.stockRarity): index 0 (none) .. 6, the rarity places
function K.stockOdds(gear)
	local d = {}
	for r = 0, ChaosRarity.STORED do
		d[r] = 0
	end
	-- rnd(1, 100) > stockRollChance gives no rarity: the roll goes on stockRollChance times in 100
	local pass = min(100, max(0, floor(gear.stockRollChance or 70))) / 100
	local rest = pass
	for rank, chance in ipairs(gear.stockChances or {}) do
		local h = stockHit(chance)
		d[rank] = d[rank] + rest * h
		rest = rest * (1 - h)
	end
	d[0] = 1 - pass + rest
	return d
end

-- exact chance of every rarity place 0 .. 6 of one purchase (gear = ChaosLootConfig.gear); mirrors K.rollRarity and
-- loot.lua L.upgradeRarity, all in places (ChaosRarity ranks): the floor, the bonus steps up to gear.maxRarity, then the
-- Divine chance
function K.odds(cfg, gear)
	local o = cfg.odds
	local R = ChaosRarity
	local top = R.STORED
	local one = K.stockOdds(gear)
	-- best of `draws`: P(best <= r) = P(one <= r) ^ draws
	local cdf, acc = {}, 0
	for r = 0, top do
		acc = acc + one[r]
		cdf[r] = acc ^ o.draws
	end
	local best = {}
	for r = 0, top do
		best[r] = cdf[r] - (r > 0 and cdf[r - 1] or 0)
	end
	local tier = o.tier
	local cap = min(R.rank(o.maxRarity), top)
	local oFloor = R.rank(o.floor)
	local floorTier = R.rank((gear.minRarity or {})[tier] or 0)
	local ensure = pctHit((gear.ensureChance or {})[tier] or 0)
	local bonus = pctHit(((gear.bonusChance or {})[tier] or 0) * (o.find or 1))
	local divine = pctHit(((gear.divineChance or {})[tier] or 0) * (o.find or 1))
	local stepTotal = 0
	for _, s in ipairs(gear.bonusSteps or {}) do
		stepTotal = stepTotal + s[2]
	end
	local out = {}
	for r = 0, top do
		out[r] = 0
	end
	local function add(r, p)
		r = min(r, cap)
		out[r] = out[r] + p
	end
	local gearCap = R.rank(gear.maxRarity or 5)
	for r0 = 0, top do
		local p0 = best[r0]
		if p0 > 0 then
			local cur = max(r0, oFloor)
			-- L.upgradeRarity(tier, cur, find)
			local paths = {}
			if floorTier > 0 and cur < floorTier then
				paths[#paths + 1] = {floorTier, ensure}
				paths[#paths + 1] = {cur, 1 - ensure}
			else
				paths[#paths + 1] = {cur, 1}
			end
			for _, path in ipairs(paths) do
				local t, pp = path[1], path[2]
				if pp > 0 then
					local function final(v)
						if v > gearCap then
							v = max(gearCap, cur)
						end
						return max(v, cur)
					end
					-- the Divine chance lifts what is below Divine to Divine (L.upgradeRarity, after the steps)
					local function put(v, p)
						v = final(v)
						if v < top and divine > 0 then
							add(top, p * divine)
							add(v, p * (1 - divine))
						else
							add(v, p)
						end
					end
					put(t, p0 * pp * (1 - bonus))
					if bonus > 0 and stepTotal > 0 then
						for _, s in ipairs(gear.bonusSteps) do
							put(t + s[1], p0 * pp * bonus * s[2] / stepTotal)
						end
					end
				end
			end
		end
	end
	return out
end

-- P(rarity place >= r) from an odds table
function K.atLeast(odds, r)
	local s = 0
	for v = r, ChaosRarity.STORED do
		s = s + (odds[v] or 0)
	end
	return s
end

-- the roll: api = {stockRarity = fn(), upgradeRarity = fn(tier, current, find)} (ChaosLoot)
function K.rollRarity(cfg, api)
	local o = cfg.odds
	local r = 0
	for _ = 1, o.draws do
		r = max(r, tonumber(api.stockRarity()) or 0)
	end
	r = max(r, o.floor)
	r = tonumber(api.upgradeRarity(o.tier, r, o.find or 1)) or r
	return min(max(r, o.floor), o.maxRarity)
end

-- ---------------------------------------------------------------- buying
-- s = {enabled, stock, mask, slot, window (the current one), want = {w, id} (what the client saw), money, near,
-- busy}. Returns ok, text, entry.
function K.checkBuy(cfg, s)
	if not s.enabled then
		return false, "The Gambler has packed up his crates for now."
	end
	if s.busy then
		return false, "One crate at a time."
	end
	if not s.near then
		return false, "Buy from the Gambler in person: he waits in the Hall of Services (the portal beside the temple)."
	end
	local i = floor(tonumber(s.slot) or 0)
	local e = s.stock and s.stock[i]
	if not e then
		return false, "That crate is not on offer."
	end
	if s.want and ((s.want.w and tonumber(s.want.w) ~= s.window) or (s.want.id and tonumber(s.want.id) ~= e.id)) then
		return false, "The stock has changed. Look again."
	end
	if K.isSold(s.mask, i) then
		return false, "That crate is already sold."
	end
	if (tonumber(s.money) or 0) < e.price then
		return false, string.format("You need %s gold for that crate.", K.fmt(e.price))
	end
	return true, nil, e
end

-- 1234567 -> "1,234,567"
function K.fmt(n)
	n = floor(tonumber(n) or 0)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (n < 0 and "-" or "") .. out
end

-- ---------------------------------------------------------------- balance against hunting
function K.huntIncome(cfg, level)
	return K.interp(cfg.balance.hunting, level)
end

-- the price of an armour piece at the gate of `level`, as a share of an hour of hunting at that level
function K.shareAt(cfg, level, gateFn)
	local gate = gateFn(level)
	return K.price(cfg, gate, "armor") / K.huntIncome(cfg, level), gate
end

-- ---------------------------------------------------------------- the window
-- view = {stock, mask, window, now, offset, level, gate, rerolls, near, money, names = {id -> name}, cids = {id ->
-- client id}, odds, rarityNames, last}
function K.payload(cfg, view)
	local items = {}
	for _, e in ipairs(view.stock or {}) do
		items[#items + 1] = {i = e.i, id = e.id, c = view.cids and view.cids[e.id] or 0, n = view.names and view.names[e.id] or "",
			s = e.slot, sn = K.SLOT_NAMES[e.slot], l = e.ilvl, p = e.price, sold = K.isSold(view.mask, e.i) or nil}
	end
	local odds = {}
	if view.odds then
		for r = 1, ChaosRarity.rank(cfg.odds.maxRarity) do -- r = the rarity's place (1 Common .. 6 Divine)
			if (view.odds[r] or 0) > 0 then
				odds[#odds + 1] = {r = r, n = view.rarityNames and view.rarityNames[r] or tostring(r),
					p = floor(view.odds[r] * 100000 + 0.5) / 1000}
			end
		end
	end
	local nextAt = K.nextRefresh(cfg, view.now, view.offset)
	local w = K.window(cfg, view.now, view.offset)
	return {
		w = view.window, items = items, level = view.level, gate = view.gate, near = view.near and true or false,
		money = view.money or 0, left = max(0, nextAt - view.now), hours = cfg.refresh.hours,
		at = K.clock(cfg, w + 1), tz = type(cfg.refresh.utcOffsetHours) == "number" and
			string.format("UTC%+d", cfg.refresh.utcOffsetHours) or "server time",
		reroll = K.rerollPrice(cfg, view.gate, view.rerolls or 0), rerolls = view.rerolls or 0,
		rerollMax = cfg.reroll and cfg.reroll.max or 0, odds = odds, npc = cfg.npc.name, last = view.last
	}
end

return K
