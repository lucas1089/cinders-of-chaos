-- Professions: pure logic (no engine calls), shared by professions.lua and server/tests/professions_test.lua.
-- Numbers: professions_config.lua; overview: server/README.md "Professions".
--   ChaosProfessionsCore.validate(cfg)                       list of config problems (empty = fine)
--   .index(cfg)                                              lookups: prof, mat, matOf[prof][tier], node, nodeOf, area, tool
--   .xpNeed(cfg, level) / .addXp(cfg, entry, xp) / .percent(cfg, entry)   the level curve ({level, xp} entries)
--   .profTier / .charTier / .gatherTier(cfg, placeTier, profLevel, charLevel)   which material tier a gather gives
--   .gatherXp(cfg, matTier, profLevel)                       profession experience of a gather
--   .extraChance / .avgYield / .yieldCount(cfg, tier, profLevel, rand)   how many units a gather gives
--   .resolve(cfg, idx, g, rand)                              a whole gather: {tier, mat, count, xp}
--   .charXp(cfg, level)                                      character experience of a gather
--   .bonusPct(cfg, levels) / .applyBonus(exp, pct)           the passive experience bonus
--   .demand(cfg, week)                                       material id -> this week's price multiplier (seeded)
--   .unitPrice / .quote(cfg, mat, mult, sold, count)         the broker's price with the daily diminishing price and cap
--   .day(t, rollHour) / .week(t, rollHour) / .nextDay / .nextWeek   server-local days and weeks
--   .huntIncome / .gathersPerHour / .goldPerHour / .balance  the gold per hour model against hunting
--   .inArea(area, pos) / .fishingPlace(cfg, pos) / .flayTier(cfg, level)   places and tiers
--   .pickSpots(area, cfg, idx, isFree, rand)                 node tiles of an area (deterministic for a given rand)
--   .rng(seed)                                               a small deterministic generator (same numbers in 5.1 / 5.3)
--   .payload(cfg, idx, view)                                 the window state for the client
-- O395 (feeding the base crafting, perks, nodes in the hunts):
--   .perks(cfg, prof, level) -> totals {channel, byproduct, lucky, flay}, the perks reached
--   .channelMs / .flayChance / .byproductChance(cfg, prof, level)    the gather numbers with the perks
--   .byproductId(cfg, prof, tier, rand)                      the base crafting material of a by-product
--   .huntAreas(cfg, entries)                                 gathering areas for the hunts of the teleport hall
--   .refineRows(cfg, idx) / .refineProblems(cfg, idx, priceOf) / .recipes(cfg, idx, book, nameOf)   refining recipes
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosProfessionsCore = ChaosProfessionsCore or {}
local K = ChaosProfessionsCore
local floor, min, max = math.floor, math.min, math.max

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

-- ---------------------------------------------------------------- index and checks
function K.index(cfg)
	local idx = {list = {}, prof = {}, mat = {}, matOf = {}, node = {}, nodeOf = {}, area = {}, tool = {}, ids = {}}
	for i, p in ipairs(cfg.professions) do
		idx.list[i] = p
		idx.prof[p.key] = p
		p.index = i
		idx.matOf[p.key] = {}
		idx.nodeOf[p.key] = {}
		for _, t in ipairs(p.tools or {}) do
			idx.tool[t] = idx.tool[t] or {}
			idx.tool[t][#idx.tool[t] + 1] = p.key
		end
	end
	for _, m in ipairs(cfg.materials) do
		idx.mat[m.id] = m
		if idx.matOf[m.prof] then
			idx.matOf[m.prof][m.tier] = m
		end
		idx.ids[#idx.ids + 1] = m.id
	end
	for _, n in ipairs(cfg.nodes or {}) do
		idx.node[n.id] = n
		if idx.nodeOf[n.prof] then
			idx.nodeOf[n.prof][n.tier] = n
		end
	end
	for _, a in ipairs(cfg.areas or {}) do
		idx.area[a.key] = a
	end
	return idx
end

function K.validate(cfg)
	local out = {}
	local function bad(text)
		out[#out + 1] = text
	end
	local idx = K.index(cfg)
	local nt = #cfg.tiers
	if nt < 1 then
		bad("no tiers")
	end
	for t = 2, nt do
		local a, b = cfg.tiers[t - 1], cfg.tiers[t]
		if not (b.profLevel > a.profLevel and b.charLevel > a.charLevel and b.price > a.price and b.xp >= a.xp) then
			bad("tier " .. t .. " must need more and pay more than tier " .. (t - 1))
		end
	end
	if cfg.tiers[1] and cfg.tiers[1].profLevel ~= 1 then
		bad("tier 1 must open at profession level 1")
	end
	local seen, keys = {}, {}
	for _, p in ipairs(cfg.professions) do
		if keys[p.key] then
			bad("profession " .. p.key .. " twice")
		end
		keys[p.key] = true
		if #(p.tools or {}) == 0 then
			bad("profession " .. p.key .. " has no tool")
		end
		for t = 1, nt do
			if not idx.matOf[p.key][t] then
				bad("profession " .. p.key .. " has no material of tier " .. t)
			end
		end
	end
	for _, list in ipairs({cfg.materials, cfg.nodes or {}}) do
		for _, it in ipairs(list) do
			if seen[it.id] then
				bad("item id " .. it.id .. " twice")
			end
			seen[it.id] = true
			if not keys[it.prof] then
				bad("item " .. it.id .. ": unknown profession " .. tostring(it.prof))
			end
			if not (it.tier >= 1 and it.tier <= nt) then
				bad("item " .. it.id .. ": tier out of range")
			end
			if not (it.sourceId and it.sourceId > 0 and it.name and it.name ~= "") then
				bad("item " .. it.id .. " incomplete")
			end
		end
	end
	for _, a in ipairs(cfg.areas or {}) do
		if not (a.tier >= 1 and a.tier <= nt) then
			bad("area " .. a.key .. ": tier out of range")
		end
		for prof, n in pairs(a.nodes or {}) do
			if not idx.nodeOf[prof] or not idx.nodeOf[prof][a.tier] then
				bad("area " .. a.key .. ": no " .. tostring(prof) .. " node of tier " .. a.tier)
			end
			if not (n >= 0) then
				bad("area " .. a.key .. ": node count")
			end
		end
	end
	if #cfg.demand.slots ~= nt then
		bad("demand slots: one per tier (" .. nt .. ")")
	end
	if not (cfg.broker.fullPerDay > 0 and cfg.broker.capPerDay >= cfg.broker.fullPerDay) then
		bad("broker: 0 < fullPerDay <= capPerDay")
	end
	if not (cfg.broker.lateMult > 0 and cfg.broker.lateMult <= 1) then
		bad("broker: 0 < lateMult <= 1")
	end
	if not (cfg.bonus.cap > 0 and cfg.bonus.perLevel > 0) then
		bad("bonus: perLevel and cap")
	end
	local kinds = {channel = true, byproduct = true, lucky = true, flay = true}
	for prof, list in pairs(cfg.perks or {}) do
		if not keys[prof] then
			bad("perks: unknown profession " .. tostring(prof))
		end
		local last = 0
		for _, pk in ipairs(list) do
			if not kinds[pk.kind] then
				bad("perk " .. tostring(pk.name) .. ": kind " .. tostring(pk.kind))
			end
			if not (pk.level > last and pk.level <= cfg.maxLevel) then
				bad("perks of " .. prof .. ": levels must rise and stay within the max level")
			end
			last = pk.level
			if pk.kind == "channel" and not (pk.value > 0 and pk.value < 1) then
				bad("perk " .. tostring(pk.name) .. ": a channel perk shortens (0 < value < 1)")
			elseif pk.kind ~= "channel" and not (pk.value > 0 and pk.value < 0.5) then
				bad("perk " .. tostring(pk.name) .. ": value out of range")
			end
			if type(pk.name) ~= "string" or type(pk.pt) ~= "string" then
				bad("perk of " .. prof .. ": name and pt")
			end
		end
	end
	for prof, list in pairs(cfg.byproducts and cfg.byproducts.ids or {}) do
		if #list ~= nt then
			bad("byproducts of " .. prof .. ": one list per tier (" .. nt .. ")")
		end
		if not (cfg.byproducts.chance[prof] and cfg.byproducts.chance[prof] > 0) then
			bad("byproducts of " .. prof .. ": no chance")
		end
	end
	local refineSeen = {}
	for _, r in ipairs(cfg.refine or {}) do
		local k = tostring(r.prof) .. ":" .. tostring(r.tier)
		if refineSeen[k] then
			bad("refine " .. k .. " twice")
		end
		refineSeen[k] = true
		if not (idx.matOf[r.prof] and idx.matOf[r.prof][r.tier]) then
			bad("refine " .. k .. ": no such material")
		end
		if not (r.ins >= 1 and r.count >= 1 and r.out > 0 and r.cost >= 0 and r.level >= 1 and type(r.book) == "string") then
			bad("refine " .. k .. " incomplete")
		end
	end
	return out
end

-- ---------------------------------------------------------------- levels
function K.xpNeed(cfg, level)
	level = floor(tonumber(level) or 1)
	if level >= cfg.maxLevel then
		return nil
	end
	local c = cfg.curve
	return floor(c.base + c.linear * level + c.square * level * level)
end

function K.totalXp(cfg, level)
	local n = 0
	for l = 1, min(level, cfg.maxLevel) - 1 do
		n = n + K.xpNeed(cfg, l)
	end
	return n
end

-- adds xp to an entry {level, xp}; returns the levels gained
function K.addXp(cfg, e, xp)
	e.level = max(1, floor(tonumber(e.level) or 1))
	e.xp = max(0, floor(tonumber(e.xp) or 0))
	if e.level >= cfg.maxLevel then
		e.level, e.xp = cfg.maxLevel, 0
		return 0
	end
	e.xp = e.xp + max(0, floor(xp or 0))
	local gained = 0
	while e.level < cfg.maxLevel do
		local need = K.xpNeed(cfg, e.level)
		if e.xp < need then
			break
		end
		e.xp = e.xp - need
		e.level = e.level + 1
		gained = gained + 1
	end
	if e.level >= cfg.maxLevel then
		e.xp = 0
	end
	return gained
end

function K.percent(cfg, e)
	local need = K.xpNeed(cfg, e.level or 1)
	if not need then
		return 100
	end
	return min(99, floor((e.xp or 0) * 100 / need))
end

-- ---------------------------------------------------------------- tiers
function K.profTier(cfg, profLevel)
	local t = 1
	for i, tier in ipairs(cfg.tiers) do
		if (profLevel or 1) >= tier.profLevel then
			t = i
		end
	end
	return t
end

-- tier 1 is open from level 1: a character below its charLevel still gathers tier 1
function K.charTier(cfg, charLevel)
	local t = 1
	for i, tier in ipairs(cfg.tiers) do
		if (charLevel or 1) >= tier.charLevel then
			t = i
		end
	end
	return t
end

function K.gatherTier(cfg, placeTier, profLevel, charLevel)
	return max(1, min(placeTier or 1, K.profTier(cfg, profLevel), K.charTier(cfg, charLevel)))
end

function K.gatherXp(cfg, matTier, profLevel)
	local tier = cfg.tiers[matTier]
	local below = max(0, K.profTier(cfg, profLevel) - matTier)
	local mult = cfg.greyXp[min(below, 2)] or 1
	return max(1, floor(tier.xp * mult + 0.5))
end

function K.extraChance(cfg, tier, profLevel)
	local over = max(0, (profLevel or 1) - cfg.tiers[tier].profLevel)
	return min(cfg.yield.extraMax, over / cfg.yield.extraPerLevel)
end

-- luckyAdd: the perks' extra lucky chance (K.perks lucky; default 0)
function K.avgYield(cfg, tier, profLevel, luckyAdd)
	return 1 + K.extraChance(cfg, tier, profLevel) + cfg.yield.lucky + (luckyAdd or 0)
end

function K.yieldCount(cfg, tier, profLevel, rand, luckyAdd)
	local n = 1
	if rand() < K.extraChance(cfg, tier, profLevel) then
		n = n + 1
	end
	if rand() < cfg.yield.lucky + (luckyAdd or 0) then
		n = n + 1
	end
	return n
end

-- g = {prof, placeTier, profLevel, charLevel, chance (optional: a roll that can miss, flaying), lucky (optional: the
-- perks' extra lucky chance), byChance (optional: the by-product chance, O395)}
-- -> {tier, mat, count (0 = a miss: half the experience), xp, extra (a base crafting material id or nil)}
function K.resolve(cfg, idx, g, rand)
	local tier = K.gatherTier(cfg, g.placeTier, g.profLevel, g.charLevel)
	local mat = idx.matOf[g.prof][tier]
	local xp = K.gatherXp(cfg, tier, g.profLevel)
	if g.chance and rand() >= g.chance then
		return {tier = tier, mat = mat, count = 0, xp = max(1, floor(xp / 2))}
	end
	local r = {tier = tier, mat = mat, count = K.yieldCount(cfg, tier, g.profLevel, rand, g.lucky), xp = xp}
	if g.byChance and g.byChance > 0 and rand() < g.byChance then
		r.extra = K.byproductId(cfg, g.prof, tier, rand)
	end
	return r
end

-- ---------------------------------------------------------------- O395: perks and by-products
-- totals of the perks a profession has at `level`: {channel (multiplier), byproduct, lucky, flay}, and the list
function K.perks(cfg, prof, level)
	local tot = {channel = 1, byproduct = 0, lucky = 0, flay = 0}
	local got = {}
	for _, pk in ipairs((cfg.perks or {})[prof] or {}) do
		if (tonumber(level) or 1) >= pk.level then
			got[#got + 1] = pk
			if pk.kind == "channel" then
				tot.channel = tot.channel * pk.value
			elseif tot[pk.kind] then
				tot[pk.kind] = tot[pk.kind] + pk.value
			end
		end
	end
	return tot, got
end

-- the perks a level up from `from` to `to` reaches
function K.newPerks(cfg, prof, from, to)
	local out = {}
	for _, pk in ipairs((cfg.perks or {})[prof] or {}) do
		if pk.level > (tonumber(from) or 1) and pk.level <= (tonumber(to) or 1) then
			out[#out + 1] = pk
		end
	end
	return out
end

function K.channelMs(cfg, prof, level)
	local p
	for _, q in ipairs(cfg.professions) do
		if q.key == prof then
			p = q
		end
	end
	return floor((p and p.channelMs or 0) * K.perks(cfg, prof, level).channel + 0.5)
end

function K.flayChance(cfg, level)
	return min(1, cfg.flaying.chance + K.perks(cfg, "flaying", level).flay)
end

function K.byproductChance(cfg, prof, level)
	local b = cfg.byproducts
	local base = b and b.chance and b.chance[prof]
	if not base then
		return 0
	end
	return min(1, base + K.perks(cfg, prof, level).byproduct)
end

function K.byproductId(cfg, prof, tier, rand)
	local list = cfg.byproducts and cfg.byproducts.ids and cfg.byproducts.ids[prof]
	local ids = list and (list[tier] or list[#list])
	if not ids or #ids == 0 then
		return nil
	end
	if #ids == 1 then
		return ids[1]
	end
	return ids[rand(1, #ids)]
end

-- experience the stock engine wants for a level (Player::getExpForLevel)
function K.expForLevel(level)
	local l = level - 1
	return floor((50 * l * l * l - 150 * l * l + 400 * l) / 3)
end

function K.charXp(cfg, level)
	level = max(1, floor(tonumber(level) or 1))
	local need = K.expForLevel(level + 1) - K.expForLevel(level)
	return max(1, floor(need * cfg.charXpShare))
end

-- ---------------------------------------------------------------- the experience bonus
-- levels: {key -> level} or a number (the sum of (level - 1) over the professions)
function K.earnedLevels(levels)
	if type(levels) == "number" then
		return max(0, levels)
	end
	local n = 0
	for _, l in pairs(levels or {}) do
		n = n + max(0, (tonumber(l) or 1) - 1)
	end
	return n
end

function K.bonusPct(cfg, levels)
	local pct = K.earnedLevels(levels) * cfg.bonus.perLevel
	pct = min(cfg.bonus.cap, pct)
	return floor(pct * 100 + 0.5) / 100
end

function K.applyBonus(exp, pct)
	if not pct or pct <= 0 then
		return exp
	end
	return floor(exp * (1 + pct / 100))
end

-- ---------------------------------------------------------------- days and weeks (server local time)
local function dayKeyOf(t)
	return tonumber(os.date("%Y%m%d", t))
end

function K.day(t, rollHour)
	return dayKeyOf(t - (rollHour or 0) * 3600)
end

function K.week(t, rollHour)
	local d = os.date("*t", t - (rollHour or 0) * 3600)
	local back = (d.wday + 5) % 7 -- Monday -> 0, Sunday -> 6
	return dayKeyOf(os.time({year = d.year, month = d.month, day = d.day - back, hour = 12}))
end

function K.nextDay(t, rollHour)
	local d = os.date("*t", t - (rollHour or 0) * 3600)
	return os.time({year = d.year, month = d.month, day = d.day + 1, hour = rollHour or 0, min = 0, sec = 0})
end

function K.nextWeek(t, rollHour)
	local d = os.date("*t", t - (rollHour or 0) * 3600)
	local back = (d.wday + 5) % 7
	return os.time({year = d.year, month = d.month, day = d.day - back + 7, hour = rollHour or 0, min = 0, sec = 0})
end

-- ---------------------------------------------------------------- demand and prices
-- material id -> multiplier for a week key (YYYYMMDD of its Monday): per profession the tiers get the demand slots in
-- an order drawn from the week (Fisher-Yates)
function K.demand(cfg, week, idx)
	idx = idx or K.index(cfg)
	local out = {}
	local slots = cfg.demand.slots
	for pi, p in ipairs(idx.list) do
		local seed = (cfg.demand.seed * 1000003 + floor(tonumber(week) or 0) * 31 + pi * 1009) % 2147483646 + 1
		local rand = K.rng(seed)
		local order = {}
		for i = 1, #slots do
			order[i] = i
		end
		for i = #order, 2, -1 do
			local j = rand(1, i)
			order[i], order[j] = order[j], order[i]
		end
		for tier = 1, #cfg.tiers do
			local mat = idx.matOf[p.key][tier]
			if mat then
				out[mat.id] = slots[order[tier]] or 1
			end
		end
	end
	return out
end

function K.maxDemand(cfg)
	local m = 0
	for _, s in ipairs(cfg.demand.slots) do
		m = max(m, s)
	end
	return m
end

function K.unitPrice(cfg, mat, mult)
	return max(1, floor(cfg.tiers[mat.tier].price * (mult or 1) + 0.5))
end

function K.latePrice(cfg, mat, mult)
	return max(1, floor(K.unitPrice(cfg, mat, mult) * cfg.broker.lateMult + 0.5))
end

-- what selling `count` units brings when `sold` were already sold today: {units, gold, full, late, price, latePrice,
-- left (what can still be sold today after this)}
function K.quote(cfg, mat, mult, sold, count)
	local b = cfg.broker
	sold = max(0, floor(tonumber(sold) or 0))
	count = max(0, floor(tonumber(count) or 0))
	local price, late = K.unitPrice(cfg, mat, mult), K.latePrice(cfg, mat, mult)
	local units = min(count, max(0, b.capPerDay - sold))
	local full = min(units, max(0, b.fullPerDay - sold))
	local atLate = units - full
	return {units = units, gold = full * price + atLate * late, full = full, late = atLate, price = price, latePrice = late,
		left = max(0, b.capPerDay - sold - units)}
end

-- ---------------------------------------------------------------- the gold per hour model
function K.huntIncome(cfg, level)
	local pts = cfg.balance.hunting
	if level <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

-- the nodes of a tier a character can work in one hour: the busiest single area of that tier (O395: with nodes in every
-- hunt of the hall a tier's nodes are spread over many hunts; walking from one hunt to the next takes minutes, so the
-- model keeps a gatherer in one area, as it always assumed: "one area of 10 nodes")
function K.nodesOfTier(cfg, prof, tier, areas)
	local best = 0
	for _, a in ipairs(areas or cfg.areas or {}) do
		if a.tier == tier then
			best = max(best, ((a.nodes or {})[prof] or 0) + #((a.pos or {})[prof] or {}))
		end
	end
	return best
end

-- gathers (rolls that can give a material) per hour at the best pace the model allows (profession 100, every perk)
function K.gathersPerHour(cfg, prof, tier)
	local bal = cfg.balance
	local channel = K.channelMs(cfg, prof, cfg.maxLevel) / 1000
	if prof == "flaying" then
		return 3600 / (channel + bal.killSec) * K.flayChance(cfg, cfg.maxLevel)
	elseif prof == "angling" then
		return 3600000 / cfg.angling.rollMs * cfg.angling.chance
	end
	local nodes = K.nodesOfTier(cfg, prof, tier)
	if nodes == 0 then
		return 0
	end
	return min(3600 / (channel + bal.walkSec), nodes * 60 / cfg.respawnMin)
end

-- gold of the by-products per hour (O395): gathers x the chance with every perk x the item price table's price
function K.byproductGold(cfg, prof, tier)
	return K.gathersPerHour(cfg, prof, tier) * K.byproductChance(cfg, prof, cfg.maxLevel) * ((cfg.byproducts or {}).price or 0)
end

function K.goldPerHour(cfg, prof, tier)
	local idx = K.index(cfg)
	local mat = idx.matOf[prof][tier]
	local lucky = K.perks(cfg, prof, cfg.maxLevel).lucky
	return K.gathersPerHour(cfg, prof, tier) * K.avgYield(cfg, tier, cfg.maxLevel, lucky)
		* K.unitPrice(cfg, mat, K.maxDemand(cfg)) + K.byproductGold(cfg, prof, tier)
end

-- one row per profession and tier: {prof, tier, perHour, gold (by-products included), by (their part), hunt, share}
function K.balance(cfg)
	local rows = {}
	for _, p in ipairs(cfg.professions) do
		for t, tier in ipairs(cfg.tiers) do
			local gold = K.goldPerHour(cfg, p.key, t)
			local hunt = K.huntIncome(cfg, tier.charLevel)
			rows[#rows + 1] = {prof = p.key, tier = t, perHour = K.gathersPerHour(cfg, p.key, t), gold = gold,
				by = K.byproductGold(cfg, p.key, t), hunt = hunt, share = gold / hunt}
		end
	end
	return rows
end

-- ---------------------------------------------------------------- O395: refining recipes for the base crafting books
-- rows {prof, tier, book, mat, ins, out, count, level, cost, inValue (the inputs at the broker's base price + gold)}
function K.refineRows(cfg, idx)
	idx = idx or K.index(cfg)
	local out = {}
	for _, r in ipairs(cfg.refine or {}) do
		local mat = idx.matOf[r.prof] and idx.matOf[r.prof][r.tier]
		if mat then
			out[#out + 1] = {prof = r.prof, tier = r.tier, book = r.book, mat = mat, ins = r.ins, out = r.out, count = r.count,
				level = r.level, cost = r.cost, inValue = r.ins * cfg.tiers[r.tier].price + r.cost}
		end
	end
	return out
end

-- priceOf(id) -> the item price table's gold for one; a recipe whose product is worth more than its inputs is a problem
function K.refineProblems(cfg, idx, priceOf)
	local out = {}
	for _, r in ipairs(K.refineRows(cfg, idx)) do
		local worth = (tonumber(priceOf(r.out)) or 0) * r.count
		if worth > r.inValue then
			out[#out + 1] = string.format("refine %s tier %d: %d x %d is worth %d, the inputs only %d", r.prof, r.tier,
				r.count, r.out, worth, r.inValue)
		end
	end
	return out
end

-- the base recipe tables of one book (the base books' format: id, name, level, cost, count, storage, storageText,
-- materials); nameOf(id) -> the product's name. Every recipe carries chaosProfession = true.
function K.recipes(cfg, idx, book, nameOf)
	local out = {}
	for _, r in ipairs(K.refineRows(cfg, idx)) do
		if r.book == book then
			local name = nameOf and nameOf(r.out) or nil
			if type(name) ~= "string" or name == "" then
				name = "refined " .. r.mat.name
			end
			name = name:gsub("^%l", string.upper)
			out[#out + 1] = {id = r.out, name = name, level = r.level, cost = r.cost, count = r.count, storage = 0,
				storageText = "", materials = {{id = r.mat.id, count = r.ins}}, chaosProfession = true}
		end
	end
	return out
end

-- the crafting book a profession's materials refine at (nil: none)
function K.refineBook(cfg, prof)
	for _, r in ipairs(cfg.refine or {}) do
		if r.prof == prof then
			return r.book
		end
	end
	return nil
end

-- ---------------------------------------------------------------- O395: nodes in the hunts of the teleport hall
-- entries: {{id, name, level = {lo, hi}, arrival = {x, y, z}}} (hunt_teleports_core.lua H.index list and base) ->
-- areas {key = "hunt_<id>", name, tier, center, r, nodes, fishing, hunt = true, band}; one per id, none near a fixed area
function K.huntAreas(cfg, entries)
	local h = cfg.huntNodes
	local out, seen = {}, {}
	if not (h and h.enabled) then
		return out
	end
	for _, e in ipairs(entries or {}) do
		local a = type(e) == "table" and (e.arrival or e.dest) or nil
		local lv = type(e) == "table" and e.level
		local key = type(e) == "table" and e.id and ("hunt_" .. tostring(e.id):gsub("[^%w]+", "_"):lower())
		if key and not seen[key] and type(a) == "table" and tonumber(a.x) and tonumber(a.y) and tonumber(a.z)
				and type(lv) == "table" and tonumber(lv[1]) then
			local near = false
			for _, f in ipairs(cfg.areas or {}) do
				if not f.hunt and f.center.z == a.z and math.abs(f.center.x - a.x) <= h.gap
						and math.abs(f.center.y - a.y) <= h.gap then
					near = true
				end
			end
			if not near then
				seen[key] = true
				local nodes = {}
				for prof, n in pairs(h.nodes or {}) do
					nodes[prof] = n
				end
				out[#out + 1] = {key = key, name = tostring(e.name or e.id), tier = K.charTier(cfg, tonumber(lv[1])),
					center = {x = a.x, y = a.y, z = a.z}, r = h.r, nodes = nodes, fishing = h.fishing and true or nil,
					hunt = true, band = {tonumber(lv[1]), tonumber(lv[2]) or tonumber(lv[1])}}
			end
		end
	end
	table.sort(out, function(x, y)
		if x.tier ~= y.tier then
			return x.tier < y.tier
		end
		return x.key < y.key
	end)
	return out
end

-- the most a character can get from the broker in one day for one material (the best demand week)
function K.dailyMax(cfg, mat)
	return K.quote(cfg, mat, K.maxDemand(cfg), 0, cfg.broker.capPerDay).gold
end

-- ---------------------------------------------------------------- places
function K.inArea(a, pos)
	return pos ~= nil and pos.z == a.center.z and math.abs(pos.x - a.center.x) <= a.r and math.abs(pos.y - a.center.y) <= a.r
end

-- the fishing place of a water tile: tier and area (nil area = anywhere else, the default tier)
function K.fishingPlace(cfg, pos)
	for _, a in ipairs(cfg.areas or {}) do
		if a.fishing and K.inArea(a, pos) then
			return a.tier, a
		end
	end
	return cfg.angling.defaultTier, nil
end

function K.flayTier(cfg, level)
	return K.charTier(cfg, level)
end

-- node spots of an area: {prof -> {{x, y, z}}}, fixed `pos` spots first, then random free tiles of the box at least
-- cfg.nodeSpacing apart. isFree(x, y, z) is the engine's tile check; rand a K.rng (seeded by the area key).
function K.seedOf(text)
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + text:byte(i)) % 2147483646
	end
	return h + 1
end

function K.pickSpots(area, cfg, isFree, rand)
	local out, taken = {}, {}
	local spacing = cfg.nodeSpacing or 0
	local function near(x, y)
		for _, s in ipairs(taken) do
			if math.abs(s.x - x) < spacing and math.abs(s.y - y) < spacing then
				return true
			end
		end
		return false
	end
	local z = area.center.z
	local profs = {}
	for _, p in ipairs(cfg.professions) do
		if (area.nodes or {})[p.key] or (area.pos or {})[p.key] then
			profs[#profs + 1] = p.key
		end
	end
	for _, prof in ipairs(profs) do
		out[prof] = {}
		for _, s in ipairs((area.pos or {})[prof] or {}) do
			local spot = {x = s.x, y = s.y, z = s.z or z}
			out[prof][#out[prof] + 1] = spot
			taken[#taken + 1] = spot
		end
	end
	for _, prof in ipairs(profs) do
		local want = (area.nodes or {})[prof] or 0
		local tries = want * 60
		local got = 0
		while got < want and tries > 0 do
			tries = tries - 1
			local x = area.center.x - area.r + rand(0, area.r * 2)
			local y = area.center.y - area.r + rand(0, area.r * 2)
			if not near(x, y) and isFree(x, y, z) then
				local spot = {x = x, y = y, z = z}
				out[prof][#out[prof] + 1] = spot
				taken[#taken + 1] = spot
				got = got + 1
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- the window state
-- view = {levels = {key -> {level, xp, gathered}}, charLevel, demand = {id -> mult}, sold = {id -> n}, have = {id -> n},
--         cid = {id -> client id} (the look in the window),
--         areas = {{area, ready = {prof -> n}, total = {prof -> n}, town}}, broker = bool, now, week}
function K.payload(cfg, idx, view)
	local profs, levels = {}, {}
	for _, p in ipairs(idx.list) do
		local e = view.levels[p.key] or {level = 1, xp = 0}
		levels[p.key] = e.level
		local perks = {}
		for _, pk in ipairs((cfg.perks or {})[p.key] or {}) do
			perks[#perks + 1] = {lv = pk.level, n = pk.name, k = pk.kind, v = pk.value, on = e.level >= pk.level or nil}
		end
		profs[#profs + 1] = {k = p.key, n = p.name, lv = e.level, xp = e.xp, need = K.xpNeed(cfg, e.level) or 0,
			pct = K.percent(cfg, e), tier = K.gatherTier(cfg, #cfg.tiers, e.level, view.charLevel),
			tool = p.toolName, d = p.desc, g = e.gathered or 0, perks = perks,
			bp = floor(K.byproductChance(cfg, p.key, e.level) * 1000 + 0.5) / 10, book = K.refineBook(cfg, p.key)}
	end
	local tiers = {}
	for i, t in ipairs(cfg.tiers) do
		tiers[i] = {n = t.name, p = t.profLevel, c = t.charLevel, g = t.price, col = t.color}
	end
	local demand = {}
	for _, p in ipairs(idx.list) do
		for t = 1, #cfg.tiers do
			local mat = idx.matOf[p.key][t]
			local mult = view.demand[mat.id] or 1
			local sold = view.sold[mat.id] or 0
			demand[#demand + 1] = {id = mat.id, c = (view.cid or {})[mat.id], n = mat.name, p = p.key, t = t, m = mult,
				g = K.unitPrice(cfg, mat, mult), l = K.latePrice(cfg, mat, mult), s = sold, h = view.have[mat.id] or 0}
		end
	end
	local areas = {}
	for _, row in ipairs(view.areas or {}) do
		local a = row.area
		local list = {}
		for _, p in ipairs(idx.list) do
			local total = (row.total or {})[p.key]
			if total and total > 0 then
				list[#list + 1] = {k = p.key, r = (row.ready or {})[p.key] or 0, t = total}
			end
		end
		areas[#areas + 1] = {n = a.name, t = a.tier, f = a.fishing and true or nil, m = a.monsters, near = row.town,
			x = a.center.x, y = a.center.y, z = a.center.z, nodes = list, h = a.hunt and true or nil}
	end
	return {profs = profs, bonus = K.bonusPct(cfg, levels), cap = cfg.bonus.cap, per = cfg.bonus.perLevel,
		tiers = tiers, demand = demand, areas = areas, broker = view.broker and true or false,
		full = cfg.broker.fullPerDay, capDay = cfg.broker.capPerDay, late = cfg.broker.lateMult,
		nextDay = view.nextDay, nextWeek = view.nextWeek, respawn = cfg.respawnMin}
end

return K
