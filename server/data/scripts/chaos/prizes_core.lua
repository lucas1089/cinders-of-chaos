-- prizes_core.lua: where a prize of a base script goes, and the roulettes' winner (server/README.md "Prizes into the
-- backpack"). Pure Lua, no engine calls; the glue is prizes.lua, the base script changes are tools/patch_prizes.py;
-- tests/prizes_test.lua.
--
-- User report 2026-10-21: the Boss Roulette said "you won The Awakener" (a ship) and the ship was in no bag and not in
-- the inbox. The base roulettes give the prize with player:addItem(id, count, true), and the engine puts an item into
-- an empty inventory slot that takes it before any container: a ship went into the ship slot (14), which no client
-- draws. Engine patch 0058 refuses those slots now; the base scripts that hand out prizes give them to the backpack
-- first (a container in it when it is full), then the store inbox ("Purse"), then the ground under the player.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosPrizesCore = ChaosPrizesCore or {}
local K = ChaosPrizesCore

-- where a prize may go, in order
K.PLACES = {"backpack", "store inbox", "ground"}

-- the roulette tile's winner: {id, count, charges} from the top visible thing of the tile, or nil when that is no prize
-- (the tile changed: nothing there, a creature, the ground, a decoration the roulette ignores). thing is a table with
-- the values read from the engine: {isItem, id, count, charges, showCharges}; groundId the tile's ground id or nil.
function K.winner(thing, groundId, ignored)
	if type(thing) ~= "table" or not thing.isItem then
		return nil
	end
	local id = tonumber(thing.id)
	if not id or id <= 0 or id == tonumber(groundId) then
		return nil
	end
	for _, ig in ipairs(ignored or {}) do
		if tonumber(ig) == id then
			return nil
		end
	end
	local count = math.max(1, math.floor(tonumber(thing.count) or 1))
	local out = {id = id, count = count}
	if thing.showCharges then
		out.count = 1
		out.charges = math.max(1, math.floor(tonumber(thing.charges) or count))
	end
	return out
end

-- true when the prize is rare enough to be broadcast: the lowest chance the pool gives this item is at most the
-- threshold (the base looked up chancedItems[#chancedItems - 3], the chance of another spin's item, nil after fewer
-- than four spins)
function K.isRare(pool, id, threshold)
	id = tonumber(id)
	local best
	for _, p in ipairs(pool or {}) do
		if tonumber(p.itemId) == id then
			local c = tonumber(p.chance) or 0
			best = best and math.min(best, c) or c
		end
	end
	return best ~= nil and best <= (tonumber(threshold) or 0)
end

-- the pool without the items no slot shows (badges_core.lua: decks, ships, belts, gloves). The install tool takes them
-- out of the base files; this is the guard for a pool it did not reach. Returns the new pool and the ids taken out.
function K.cleanPool(pool, isRetired)
	local out, gone = {}, {}
	for _, p in ipairs(pool or {}) do
		if isRetired and isRetired(p.itemId) then
			gone[#gone + 1] = tonumber(p.itemId)
		else
			out[#out + 1] = p
		end
	end
	return out, gone
end

-- the odds of each pool entry under the base draw (every entry rolls its chance in 1..10000; one of those that hit is
-- picked at random; nothing hit: roll again): {[index] = probability}. Exact over the hit sets for up to 20 entries
-- (the base pools have 5-21), used by the tests and the README numbers.
function K.odds(pool)
	local n = #pool
	local out = {}
	for i = 1, n do
		out[i] = 0
	end
	if n == 0 then
		return out
	end
	local p = {}
	for i = 1, n do
		p[i] = math.min(1, math.max(0, (tonumber(pool[i].chance) or 0) / 10000))
	end
	-- P(entry i picked) = sum over k of P(i hit and k-1 others hit) / k, then divided by P(any hit)
	-- the count distribution of the others is a Poisson binomial, built by dynamic programming per entry
	local none = 1
	for i = 1, n do
		none = none * (1 - p[i])
	end
	for i = 1, n do
		local dist = {[0] = 1}
		for j = 1, n do
			if j ~= i then
				local nd = {}
				for k = 0, n do
					nd[k] = (dist[k] or 0) * (1 - p[j]) + (k > 0 and (dist[k - 1] or 0) * p[j] or 0)
				end
				dist = nd
			end
		end
		local s = 0
		for k = 0, n - 1 do
			s = s + (dist[k] or 0) / (k + 1)
		end
		out[i] = p[i] * s / (1 - none)
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Boss Roulette prizes that are not a plain item (boss_roulette_config.lua, O148): gold that grows with the level and a
-- unique of the winner's level. The tile shows an ordinary item (crystal coins, a chest); these functions say what the
-- winner gets.
-- ---------------------------------------------------------------------------------------------------------------------

-- the roulette config entry of a won item id: the first pool entry with that id (nil when none)
function K.entryOf(cfg, id)
	id = tonumber(id)
	for _, e in ipairs(cfg and cfg.pool or {}) do
		if tonumber(e.id) == id then
			return e
		end
	end
	return nil
end

-- piecewise linear on {{x, y}, ...}, flat beyond the ends
function K.curve(points, x)
	if not points or #points == 0 then
		return 0
	end
	x = tonumber(x) or 0
	if x <= points[1][1] then
		return points[1][2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if x <= b[1] then
			return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
		end
	end
	return points[#points][2]
end

-- the gold of a gold prize: `units` (the crystal coins the tile showed) x gold.perUnit of an hour of hunting gold at the
-- winner's level, rounded to whole crystal coins, at least one
function K.goldFor(cfg, units, level)
	local g = cfg and cfg.gold or {}
	local perHour = K.curve(g.hunting, level)
	local gold = (tonumber(units) or 1) * (tonumber(g.perUnit) or 0) * perHour
	return math.max(10000, math.floor(gold / 10000 + 0.5) * 10000)
end

-- whole gold as coin stacks, largest first: list of {id, count}
function K.coinStacks(gold)
	gold = math.floor(tonumber(gold) or 0)
	local out = {}
	for _, c in ipairs({{2160, 10000}, {2152, 100}, {2148, 1}}) do
		local n = math.floor(gold / c[2])
		if n > 0 then
			out[#out + 1] = {c[1], n}
			gold = gold - n * c[2]
		end
	end
	return out
end

-- the uniques a unique chest may hold for a winner of this level: no season unique, no Ascended one, no boss-only one,
-- an item level in [level x low, level x high]; none in the band: those of the highest item level at most the level
-- (the lowest ones when the level is below all). list = ChaosLoot.uniqueList() entries {id, name, level, ...}
function K.uniqueChoices(cfg, list, level)
	local u = cfg and cfg.unique or {}
	local lo, hi = (tonumber(u.low) or 0.5) * level, (tonumber(u.high) or 1) * level
	local band, below, best = {}, {}, nil
	for _, e in ipairs(list or {}) do
		if not e.season and not e.ascended and not e.bossOnly and tonumber(e.level) then
			local lv = tonumber(e.level)
			if lv >= lo and lv <= hi then
				band[#band + 1] = e
			elseif lv < lo then
				if not best or lv > best then
					best = lv
					below = {}
				end
				if lv == best then
					below[#below + 1] = e
				end
			end
		end
	end
	if #band > 0 then
		return band
	end
	if #below > 0 then
		return below
	end
	local lowest, out = nil, {}
	for _, e in ipairs(list or {}) do
		if not e.season and not e.ascended and not e.bossOnly and tonumber(e.level) then
			if not lowest or tonumber(e.level) < lowest then
				lowest = tonumber(e.level)
				out = {}
			end
			if tonumber(e.level) == lowest then
				out[#out + 1] = e
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------------------------
-- The other four roulettes (exercise, premium, the two crystal token ones; O151, roulette_*_config.lua) share the gold and
-- the unique chest above. Their configs are found by the roulette script's actionId.
-- ---------------------------------------------------------------------------------------------------------------------

-- the config of a roulette: by the script's config.actionId, else (a script without one) the Boss Roulette's for the label
-- "boss". pools = {[actionId] = config, boss = config}
function K.configFor(pools, config, label)
	local id = tonumber(config and config.actionId)
	if id and pools and pools[id] then
		return pools[id]
	end
	if tostring(label) == "boss" and pools then
		return pools.boss
	end
	return nil
end

-- the exercise chest a class can use. cfg.chests = {kinds = {"melee", ...}, tiers = {{melee = id, ...}, ...}}: the chest on
-- the tile is one of a tier; when the winner's class cannot use its kind (allowed(kind) false) it becomes the chest of
-- the same tier of a kind it can use, picked by pick(n) -> 1..n. Returns the id to give and whether it changed; an id that
-- is no chest of the table is returned as it is.
function K.classChest(cfg, id, allowed, pick)
	id = tonumber(id)
	local chests = cfg and cfg.chests
	if not chests then
		return id, false
	end
	for _, tier in ipairs(chests.tiers or {}) do
		for _, kind in ipairs(chests.kinds or {}) do
			if tonumber(tier[kind]) == id then
				if not allowed or allowed(kind) then
					return id, false
				end
				local ok = {}
				for _, k2 in ipairs(chests.kinds) do
					if tier[k2] and allowed(k2) then
						ok[#ok + 1] = tier[k2]
					end
				end
				if #ok == 0 then
					return id, false
				end
				return ok[math.max(1, math.min(#ok, pick and pick(#ok) or 1))], true
			end
		end
	end
	return id, false
end

K.TEXT_GOLD = "Your roulette prize is %s gold, scaled to your level."
K.TEXT_UNIQUE = "The chest held a unique: %s!"
K.TEXT_CHEST = "Your class cannot train with that weapon: the chest became %s."


K.TEXT_INBOX = "Your prize %s is in your Purse (the store inbox): your backpack had no room."
K.TEXT_GROUND = "Your prize %s is on the ground under you: your backpack and your Purse had no room."
K.TEXT_LOST_SPIN = "The roulette could not find your prize. Your next spin is free."

return K
