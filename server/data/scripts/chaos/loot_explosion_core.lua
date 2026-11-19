-- Loot explosion, the pure part (ChaosLootExplosion; config loot_explosion_config.lua, engine glue loot_explosion.lua,
-- tests/loot_explosion_test.lua). server/README.md "Loot explosion (O669)". No engine calls: the glue gives it the facts about
-- the tiles and the items and a random function. Lua 5.1 / LuaJIT compatible.
--   X.validate(cfg, corpseCfg)         list of problems (empty = fine)
--   X.active(cfg, corpseCfg)           true when the explosion may run (switch on, config valid)
--   X.ownerSeconds(cfg, corpseCfg), X.decaySeconds(cfg, corpseCfg)   the two times, in seconds
--   X.groupOf(cfg, drop)               "gold" | "plain" | "rare" | "epic" | "unique": the effect group of an item
--   X.groupOfRank(cfg, rank, gold)     the same from a rank (a unique counts 100)
--   X.beamGroup(cfg, drop)             "set" | "unique" | "divine" | "orange" | nil: the loot beam group the client draws a burst in (O677)
--   X.flightMs(cfg, group, ring)       how long an item of that group flies to a tile of that ring
--   X.explodePayload(cfg, origin, killId, flights)   the one opcode 230 `explode` message of a kill (O677)
--   X.parseAnim(data)                  the client's `burst {on}` capability message -> true | false
--   X.animViewers(cfg, cands, flagged, origin)       ids of the owner / party members who see the death tile and draw the burst
--   X.isStrict(cfg, drop)              true: the owner rule holds for the item's whole life
--   X.pickTiles(cfg, facts, n, rng)    the tile (index into facts) of each of n drops: cheapest first, spread before piled
--   X.plan(cfg, items, facts, rng)     the whole kill: which items fly where and when, which stay in the bag
--   X.newGate() / X.gateTake(cfg, gate, areaKey, n, nowMs)   the caps per area and per second
--   X.areaKey(cfg, pos)                the square of tiles a position belongs to
--   X.encode(info) / X.decode(text)    the attribute text of a loose item {owner, ownUntil, expiry, strict, seq}
--   X.canTake(info, now, playerId, friend, staff)   may this player take the item: ok, why
--   X.expired(info, now) / X.left(info, now)        the item has vanished / seconds it still lies
--   X.facts(...)                       see the engine glue (tile facts are plain tables)

ChaosLootExplosion = ChaosLootExplosion or {}
local X = ChaosLootExplosion

X.ATTR = "chaos_loot"      -- the custom attribute of a loose item (X.encode)
X.KILL_ATTR = "lf_loot"    -- the loot filter's kill id on an item that left the bag (lootfilter.lua)
X.GOLD = {[2148] = true, [2152] = true, [2160] = true}
X.MAX_FLIGHT_MS = 1500     -- the longest flight the animation message may carry (the client clamps to it too)
X.MAX_DELAY_MS = 3000      -- the latest start of a flight in the message
X.BEAM_GROUPS = {orange = true, divine = true, set = true, unique = true} -- the loot beam groups of the client (game_lootbeams)

local floor, max, min = math.floor, math.max, math.min

local function num(v, d)
	v = tonumber(v)
	if v == nil or v ~= v then
		return d
	end
	return v
end

function X.validate(cfg, corpseCfg)
	local out = {}
	if type(cfg) ~= "table" then
		return {"no config"}
	end
	local function range(key, lo, hi, whole)
		local v = cfg[key]
		if type(v) ~= "number" or v < lo or v > hi or v ~= v or (whole and v ~= floor(v)) then
			out[#out + 1] = key .. " must be " .. (whole and "a whole number " or "a number ") .. lo .. "-" .. hi
		end
	end
	range("index", 5, 98.5)
	range("radius", 1, 2, true)
	range("ringPenalty", 0, 5)
	range("occupiedPenalty", 0, 10)
	range("pilePenalty", 0, 10)
	range("jitter", 0, 5)
	range("originPenalty", 0, 50)
	range("maxItems", 1, 40, true)
	range("maxPerAreaSecond", 1, 1000, true)
	range("areaSize", 2, 64, true)
	range("maxPerSecond", 1, 5000, true)
	range("staggerMinMs", 0, 500, true)
	range("staggerMaxMs", 0, 500, true)
	range("flightBaseMs", 0, 1500, true)
	range("flightPerTileMs", 0, 300, true)
	range("sweepSeconds", 1, 30)
	range("reachX", 1, 15, true)
	range("reachY", 1, 15, true)
	range("lootAllMax", 1, 200, true)
	range("rareRank", 1, 20, true)
	range("epicRank", 1, 20, true)
	range("divineRank", 1, 20, true)
	range("viewX", 1, 15, true)
	range("viewY", 1, 15, true)
	if type(cfg.clientAnim) ~= "boolean" then
		out[#out + 1] = "clientAnim must be true or false"
	end
	if type(cfg.flightMul) ~= "table" then
		out[#out + 1] = "flightMul must be a table"
	else
		for _, g in ipairs({"gold", "plain", "rare", "epic", "unique"}) do
			local m = cfg.flightMul[g]
			if type(m) ~= "number" or m < 0.5 or m > 4 then
				out[#out + 1] = "flightMul." .. g .. " must be a number 0.5-4"
			end
		end
	end
	if type(cfg.staggerMinMs) == "number" and type(cfg.staggerMaxMs) == "number" and cfg.staggerMaxMs < cfg.staggerMinMs then
		out[#out + 1] = "staggerMaxMs must not be below staggerMinMs"
	end
	if type(cfg.rareRank) == "number" and type(cfg.epicRank) == "number" and cfg.epicRank < cfg.rareRank then
		out[#out + 1] = "epicRank must not be below rareRank"
	end
	if type(cfg.divineRank) == "number" and type(cfg.epicRank) == "number" and cfg.divineRank < cfg.epicRank then
		out[#out + 1] = "divineRank must not be below epicRank"
	end
	-- the longest flight (the biggest multiplier, ring 2) must stay inside what the payload and the client allow (X.MAX_FLIGHT_MS)
	if type(cfg.flightBaseMs) == "number" and type(cfg.flightPerTileMs) == "number" and type(cfg.flightMul) == "table" then
		local top = 0
		for _, m in pairs(cfg.flightMul) do
			top = max(top, tonumber(m) or 0)
		end
		if (cfg.flightBaseMs + cfg.flightPerTileMs * 2) * top > X.MAX_FLIGHT_MS then
			out[#out + 1] = "the longest flight must stay under " .. X.MAX_FLIGHT_MS .. " ms"
		end
	end
	if type(cfg.maxItems) == "number" and type(cfg.maxPerAreaSecond) == "number" and cfg.maxPerAreaSecond < cfg.maxItems then
		out[#out + 1] = "maxPerAreaSecond must hold at least one kill (maxItems)"
	end
	if type(cfg.maxPerAreaSecond) == "number" and type(cfg.maxPerSecond) == "number" and cfg.maxPerSecond < cfg.maxPerAreaSecond then
		out[#out + 1] = "maxPerSecond must not be below maxPerAreaSecond"
	end
	local life = X.decaySeconds(cfg, corpseCfg)
	if not life or life < 30 or life > 300 then
		out[#out + 1] = "decaySeconds must be 30-300 (the owner's rule: loot stays at most 5 minutes)"
	end
	if cfg.ownerSeconds ~= nil and (type(cfg.ownerSeconds) ~= "number" or cfg.ownerSeconds < 0 or (life and cfg.ownerSeconds > life)) then
		out[#out + 1] = "ownerSeconds must be nil or 0 .. decaySeconds"
	end
	for _, key in ipairs({"strictAttributes", "strictIds", "inheritAttributes"}) do
		if type(cfg[key]) ~= "table" then
			out[#out + 1] = key .. " must be a list"
		end
	end
	if type(cfg.missiles) ~= "table" or type(cfg.land) ~= "table" then
		out[#out + 1] = "missiles and land must be tables"
	end
	return out
end

function X.active(cfg, corpseCfg)
	return type(cfg) == "table" and cfg.enabled == true and #X.validate(cfg, corpseCfg) == 0
end

function X.decaySeconds(cfg, corpseCfg)
	local s = cfg and cfg.decaySeconds
	if s == nil then
		s = corpseCfg and corpseCfg.seconds
	end
	return tonumber(s)
end

-- the seconds only the owner and the party may take a plain item; nil in the config = the bag's whole life
function X.ownerSeconds(cfg, corpseCfg)
	local s = cfg and cfg.ownerSeconds
	if s == nil then
		return X.decaySeconds(cfg, corpseCfg)
	end
	return tonumber(s)
end

-- ---------------------------------------------------------------- items
-- drop = {id, rank, unique, attrs = {name = true}} (the glue reads them off the item)
function X.groupOf(cfg, drop)
	if drop.gold then
		return "gold"
	end
	if drop.unique then
		return "unique"
	end
	local r = num(drop.rank, 0)
	if r >= cfg.epicRank then
		return "epic"
	end
	if r >= cfg.rareRank then
		return "rare"
	end
	return "plain"
end

-- the effect group of a rank (the plan knows only ranks: a unique counts 100)
function X.groupOfRank(cfg, rank, gold)
	if gold then
		return "gold"
	end
	local r = num(rank, 0)
	if r >= 100 then
		return "unique"
	end
	if r >= cfg.epicRank then
		return "epic"
	end
	if r >= cfg.rareRank then
		return "rare"
	end
	return "plain"
end

-- the loot beam group of an item (client game_lootbeams): only Legendary, Divine, a set piece and a unique have one (O677); the
-- burst draws its trail and landing ring in that colour. A set piece is "set" whatever its rarity. drop = {rank, unique, set, gold}
function X.beamGroup(cfg, drop)
	if drop.gold then
		return nil
	end
	if drop.set then
		return "set"
	end
	if drop.unique then
		return "unique"
	end
	local r = num(drop.rank, 0)
	if r >= (cfg.divineRank or 6) then
		return "divine"
	end
	if r >= cfg.epicRank then
		return "orange"
	end
	return nil
end

-- how long an item of the group flies to a tile of the ring (ring 0 and 1 count as 1): the base and the per tile time, times the group
function X.flightMs(cfg, group, ring)
	local mul = cfg.flightMul and cfg.flightMul[group] or 1
	return floor((cfg.flightBaseMs + cfg.flightPerTileMs * max(1, ring or 1)) * mul + 0.5)
end

function X.isStrict(cfg, drop)
	if drop.unique then
		return true
	end
	for _, id in ipairs(cfg.strictIds or {}) do
		if id == drop.id then
			return true
		end
	end
	for _, name in ipairs(cfg.strictAttributes or {}) do
		if drop.attrs and drop.attrs[name] then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------- tiles
-- facts = list of {dx, dy, ring, items}: the free tiles (the glue already dropped walls, water, stairs, houses, protection
-- zones and tiles out of sight). ring 0 is the death tile. Returns the index of the tile of each of n drops. The cost of a
-- tile: its ring, the items it holds, the drops this kill already sent there, a random share. nil when there are no tiles.
function X.pickTiles(cfg, facts, n, rng)
	if type(facts) ~= "table" or #facts == 0 or n <= 0 then
		return nil
	end
	local used, out = {}, {}
	for i = 1, n do
		local best, bestCost
		for idx, f in ipairs(facts) do
			local cost = (f.ring <= 1 and 0 or (f.ring - 1) * cfg.ringPenalty)
				+ min(3, f.items or 0) * cfg.occupiedPenalty
				+ (used[idx] or 0) * cfg.pilePenalty
				+ (f.ring == 0 and cfg.originPenalty or 0)
				+ (cfg.jitter > 0 and (rng(0, 1000) / 1000) * cfg.jitter or 0)
			if not bestCost or cost < bestCost then
				best, bestCost = idx, cost
			end
		end
		used[best] = (used[best] or 0) + 1
		out[i] = best
	end
	return out
end

-- ---------------------------------------------------------------- the plan
-- items = list of {key, rank, gold}; facts as above; rng(a, b) = a whole number a..b.
-- Returns {drops = {{tile, keys, rank, gold, delay, flight, ring}, ...} in the order they leave, bag = {keys}, fallback}
--   fallback: nil | "tiles" (no free tile: everything stays in the bag) | "empty"
-- Gold (all its stacks) is one drop on one tile; the other items are one drop each. At most cfg.maxItems drops: the rarest
-- fly (gold counts as rank 0), the rest stays in the bag. They leave in rank order, gold and the plain ones first, the rarest
-- last, a random 50 .. 80 ms (config) apart.
function X.plan(cfg, items, facts, rng)
	local plan = {drops = {}, bag = {}}
	if type(items) ~= "table" or #items == 0 then
		plan.fallback = "empty"
		return plan
	end
	if type(facts) ~= "table" or #facts == 0 then
		for _, it in ipairs(items) do
			plan.bag[#plan.bag + 1] = it.key
		end
		plan.fallback = "tiles"
		return plan
	end
	local gold, others = {}, {}
	for _, it in ipairs(items) do
		if it.gold then
			gold[#gold + 1] = it
		else
			others[#others + 1] = it
		end
	end
	-- the rarest first for the cap (a stable order for equal ranks: the bag's order)
	local ranked = {}
	for i, it in ipairs(others) do
		ranked[i] = {it = it, i = i}
	end
	table.sort(ranked, function(a, b)
		local ra, rb = num(a.it.rank, 0), num(b.it.rank, 0)
		if ra ~= rb then
			return ra > rb
		end
		return a.i < b.i
	end)
	local room = cfg.maxItems - (#gold > 0 and 1 or 0)
	local fly = {}
	for i, r in ipairs(ranked) do
		if i <= room then
			fly[#fly + 1] = {keys = {r.it.key}, rank = num(r.it.rank, 0), gold = false, tie = rng(0, 1000)}
		else
			plan.bag[#plan.bag + 1] = r.it.key
		end
	end
	if #gold > 0 then
		local keys = {}
		for _, g in ipairs(gold) do
			keys[#keys + 1] = g.key
		end
		fly[#fly + 1] = {keys = keys, rank = 0, gold = true, tie = -1}
	end
	-- the order they leave: gold, then by rank, the rarest last
	table.sort(fly, function(a, b)
		if a.gold ~= b.gold then
			return a.gold
		end
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.tie < b.tie
	end)
	local tiles = X.pickTiles(cfg, facts, #fly, rng)
	local at = 0
	for i, d in ipairs(fly) do
		local f = facts[tiles[i]]
		d.tile = tiles[i]
		d.ring = f.ring
		d.delay = at
		d.group = X.groupOfRank(cfg, d.rank, d.gold)
		d.flight = X.flightMs(cfg, d.group, f.ring)
		at = at + rng(cfg.staggerMinMs, cfg.staggerMaxMs)
		plan.drops[#plan.drops + 1] = d
	end
	return plan
end

-- ---------------------------------------------------------------- the client animation (O677)
-- One opcode 230 message, action "explode", before the first item flies, to the owner and the party members who see the death tile
-- and told the server their client draws the burst (opcode 230 `burst {on = 1}`):
--   {o = [x, y, z] the death tile, k = the loot filter's kill id, f = [{id = client id, c = count (1 if not stackable),
--    to = [x, y, z] the landing tile, d = ms from now until it leaves, fl = ms of the flight, g = beam group "orange" | "divine" | "set" |
--    "unique" (absent for a plain item)}, ...]}
-- At most cfg.maxItems flights (14), each about 70 bytes: far under the 8192 byte limit of one extended opcode message, so no chunking.
-- flights = [{id, c, to = {x, y, z}, d, fl, g}] in the order they leave.
local function clampInt(v, lo, hi, d)
	v = floor(num(v, d))
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function pos3(p)
	if type(p) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
	if not x or not y or not z or x ~= x or y ~= y or z ~= z then
		return nil
	end
	return {floor(x), floor(y), floor(z)}
end

function X.explodePayload(cfg, origin, killId, flights)
	local o = pos3(origin)
	if not o or type(flights) ~= "table" then
		return nil
	end
	local f = {}
	for _, fl in ipairs(flights) do
		if #f >= cfg.maxItems then
			break
		end
		local to = pos3(fl.to)
		local id = clampInt(fl.id, 0, 65535, 0)
		if to and id >= 1 then
			local e = {id = id, c = clampInt(fl.c, 1, 65535, 1), to = to, d = clampInt(fl.d, 0, X.MAX_DELAY_MS, 0),
				fl = clampInt(fl.fl, 1, X.MAX_FLIGHT_MS, 1)}
			if X.BEAM_GROUPS[fl.g] then
				e.g = fl.g
			end
			f[#f + 1] = e
		end
	end
	if #f == 0 then
		return nil
	end
	local k = tonumber(killId)
	return {o = o, k = k and floor(k) or nil, f = f}
end

-- the capability message of the client: {on = 1 | true | "1"} -> true, anything else -> false
function X.parseAnim(data)
	if type(data) ~= "table" then
		return false
	end
	local v = data.on
	return v == true or v == 1 or v == "1"
end

-- cands = [{id, x, y, z}] (the owner and the party members online), flagged = {[id] = true} (told us they draw the burst), origin = the
-- death tile. Returns {[id] = true} of those on the death tile's floor within cfg.viewX / viewY squares (they see it)
function X.animViewers(cfg, cands, flagged, origin)
	local out = {}
	if cfg.clientAnim ~= true or type(cands) ~= "table" or type(flagged) ~= "table" or type(origin) ~= "table" then
		return out
	end
	for _, c in ipairs(cands) do
		if flagged[c.id] and c.z == origin.z and math.abs(c.x - origin.x) <= (cfg.viewX or 9) and math.abs(c.y - origin.y) <= (cfg.viewY or 7) then
			out[c.id] = true
		end
	end
	return out
end

-- ---------------------------------------------------------------- the caps
function X.newGate()
	return {areas = {}, sec = -1, total = 0}
end

function X.areaKey(cfg, pos)
	local s = max(1, cfg.areaSize)
	return floor(pos.x / s) .. "," .. floor(pos.y / s) .. "," .. pos.z
end

-- asks for n items in the area at nowMs; true = granted (and counted). Every second starts fresh: nothing is kept longer.
function X.gateTake(cfg, gate, areaKey, n, nowMs)
	local sec = floor(nowMs / 1000)
	if gate.sec ~= sec then
		gate.sec, gate.areas, gate.total = sec, {}, 0
	end
	local inArea = gate.areas[areaKey] or 0
	if inArea + n > cfg.maxPerAreaSecond or gate.total + n > cfg.maxPerSecond then
		return false
	end
	gate.areas[areaKey] = inArea + n
	gate.total = gate.total + n
	return true
end

-- ---------------------------------------------------------------- ownership
-- info = {owner = creature id, ownUntil = epoch seconds, expiry = epoch seconds, strict = bool, seq = number}
function X.encode(info)
	return string.format("o=%d;u=%d;x=%d;s=%d;q=%d", floor(num(info.owner, 0)), floor(num(info.ownUntil, 0)),
		floor(num(info.expiry, 0)), info.strict and 1 or 0, floor(num(info.seq, 0)))
end

function X.decode(text)
	if type(text) ~= "string" then
		return nil
	end
	local o, u, x, s, q = text:match("^o=(%-?%d+);u=(%-?%d+);x=(%-?%d+);s=(%d);q=(%-?%d+)$")
	if not o then
		return nil
	end
	return {owner = tonumber(o), ownUntil = tonumber(u), expiry = tonumber(x), strict = s == "1", seq = tonumber(q)}
end

function X.expired(info, now)
	return info.expiry > 0 and now >= info.expiry
end

function X.left(info, now)
	if info.expiry <= 0 then
		return nil
	end
	return max(0, info.expiry - now)
end

-- may this player take the item: the owner (and whoever the glue says is a friend: the party of the owner), staff, anyone after
-- the owner rule ran out (a plain item), nobody else. Returns ok, why ("owner" | "strict" | "wait", with the seconds left in
-- the third value for "wait").
function X.canTake(info, now, playerId, friend, staff)
	if staff or not info or info.owner == 0 or info.owner == playerId or friend then
		return true
	end
	if info.strict then
		return false, "strict"
	end
	if now >= info.ownUntil then
		return true
	end
	return false, "wait", info.ownUntil - now
end
