-- Waystone endgame (waystone_endgame.lua; server/README.md "Waystone endgame (O666)"): the pure part. Numbers:
-- waystone_endgame_config.lua. Tests: tests/waystone_endgame_test.lua. Lua 5.1 / LuaJIT and 5.3. No engine calls, no bit operators.
--
--   E.bandBoss(cfg, tcfg, tier)            the band boss row of the band whose last tier is `tier`, or nil
--   E.bandBossOfBand(cfg, tcfg, tier)      the band boss row of the band tier belongs to (the one a lucky run of that band may bring)
--   E.bandSpawns(cfg, tcfg, tier, chance, roll)   true when a map boss of run `tier` brings the band boss (always at the band's last tier)
--   E.bandPlan(cfg, row, rand)             what a band boss's table adds: {pieces, uniqueRolls, void, orbs = {{id, name, count}}}
--   E.chestPlan(cfg, tier, rand)           the map boss chest of the atlas: {{id, name, count}}
--   E.corruptCheck(cfg, mods, corrupt)     ok, reason code of a Void Orb on a waystone with `mods` (list) and `corrupt` (list)
--   E.corrupt(cfg, mods, defOf, rand)      {broken = bool, corrupt = {{key, value}, ...}}
--   E.encode(list) / E.decode(cfg, text, defOf)   the attribute text "key:value,..."
--   E.merge(mods, corrupt)                 the run's list: the waystone's modifiers and the corrupted ones (a key once)
--   E.tierPaid / E.markPaid / E.paidCount  the bit mask of the tiers paid (storage +0), in plain arithmetic
--   E.ranks(cfg, number) / E.packRanks(cfg, ranks)  the ranks storage (one decimal digit a stat)
--   E.points / E.spent / E.free            atlas points: tiers paid, ranks bought, left
--   E.spend(cfg, paid, ranks, key)         ok, reason, new ranks
--   E.effects(cfg, ranks)                  {density, bossChance, chestChance, fragmentChance} in percent
ChaosWaystoneEndgameCore = ChaosWaystoneEndgameCore or {}
local E = ChaosWaystoneEndgameCore
local floor, min, max = math.floor, math.min, math.max

local function num(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return v
end

local function weighted(rows, rand, field)
	local total = 0
	for _, r in ipairs(rows) do
		total = total + (r[field or 2] or 0)
	end
	if total <= 0 then
		return rows[1]
	end
	local roll, acc = rand(1, total), 0
	for _, r in ipairs(rows) do
		acc = acc + (r[field or 2] or 0)
		if roll <= acc then
			return r
		end
	end
	return rows[#rows]
end

-- ===================================================================== band bosses
function E.bandBoss(cfg, tcfg, tier)
	tier = tonumber(tier)
	for _, b in ipairs(cfg and cfg.bandBosses or {}) do
		if b.tier == tier then
			return b
		end
	end
	return nil
end

-- the band (index, entry) tier t is in
local function bandOf(tcfg, t)
	t = tonumber(t)
	for i, b in ipairs(tcfg and tcfg.bands or {}) do
		if t and t >= b.first and t <= b.last then
			return i, b
		end
	end
	return nil
end

function E.bandBossOfBand(cfg, tcfg, tier)
	local _, b = bandOf(tcfg, tier)
	return b and E.bandBoss(cfg, tcfg, b.last) or nil, b
end

-- chance: the atlas's percent (bossChance); the last tier of a band always brings it. roll 1..100
function E.bandSpawns(cfg, tcfg, tier, chance, roll)
	local row, b = E.bandBossOfBand(cfg, tcfg, tier)
	if not row then
		return false
	end
	if tonumber(tier) == b.last then
		return true
	end
	return (num(roll) or 101) <= (num(chance) or 0)
end

local function count(x, rand)
	local n = floor(x)
	if x - n > 0 and rand(1, 10000) <= (x - n) * 10000 then
		n = n + 1
	end
	return n
end

function E.bandPlan(cfg, row, rand)
	local out = {pieces = row.pieces or 0, uniqueRolls = row.uniqueRolls or 0, void = 0, orbs = {}}
	local v = row.void
	if v and rand(1, 100) <= (v[3] or 0) then
		out.void = rand(v[1], v[2])
	end
	for _, o in ipairs(cfg.bandOrbs or {}) do
		if rand(1, 100) <= o.chance then
			out.orbs[#out.orbs + 1] = {id = o.id, name = o.name, count = rand(o.min, o.max)}
		end
	end
	return out
end

function E.chestPlan(cfg, tier, rand)
	local out = {}
	local steps = max(0, (tonumber(tier) or 1) - 1)
	for _, o in ipairs(cfg.chest and cfg.chest.orbs or {}) do
		local n = count((o.base or 0) + (o.perTier or 0) * steps, rand)
		if n > 0 then
			out[#out + 1] = {id = o.id, name = o.name, count = n}
		end
	end
	return out
end

-- ===================================================================== corruption
-- ok, reason code (chaos_crafting.lua C.reasons): a corrupted waystone is final; a Normal one has nothing to corrupt
function E.corruptCheck(cfg, mods, corrupt)
	if corrupt and #corrupt > 0 then
		return false, "corrupted"
	end
	if not mods or #mods == 0 then
		return false, "wsNoMods"
	end
	return true
end

-- the value of pool row `row` ({key, x, weight}) for the definition `def` ({range = {lo, hi}, step}): x times the top of the range,
-- on the step (a flag modifier, range {1, 1}, stays 1)
function E.value(row, def)
	local hi = def and def.range and def.range[2] or 1
	local step = max(1, num(def and def.step) or 1)
	if hi <= 1 then
		return 1
	end
	return max(1, floor(hi * (num(row[2]) or 1) / step + 0.5) * step)
end

-- a Void Orb on a waystone with modifiers `mods`: it breaks (cfg.corrupt.breakChance percent), else gets `count` corrupted ones.
-- defOf(key) -> modifier definition (range, step, group, side) or nil; conflict(defA, defB) -> bool (same group); rand(a, b)
function E.corrupt(cfg, mods, defOf, rand, conflict)
	local c = cfg.corrupt
	if rand(1, 100) <= (c.breakChance or 0) then
		return {broken = true, corrupt = {}}
	end
	local have = {}
	for _, m in ipairs(mods or {}) do
		have[m.key] = true
	end
	local n = weighted(c.count, rand)[1]
	local out = {}
	for _ = 1, n do
		local rows = {}
		for _, row in ipairs(c.pool) do
			local def = defOf(row[1])
			local ok = def ~= nil and not have[row[1]]
			if ok and conflict then
				for k in pairs(have) do
					local d2 = defOf(k)
					if d2 and conflict(def, d2) then
						ok = false
						break
					end
				end
			end
			if ok then
				rows[#rows + 1] = row
			end
		end
		if #rows == 0 then
			break
		end
		local row = weighted(rows, rand, 3)
		have[row[1]] = true
		out[#out + 1] = {key = row[1], value = E.value(row, defOf(row[1]))}
	end
	if #out == 0 then
		return {broken = true, corrupt = {}}
	end
	return {broken = false, corrupt = out}
end

function E.encode(list)
	local parts = {}
	for _, m in ipairs(list or {}) do
		parts[#parts + 1] = tostring(m.key) .. ":" .. tostring(floor(num(m.value) or 0))
	end
	return table.concat(parts, ",")
end

-- the attribute text -> list: only keys of the corruption pool, values inside [1, x top] of their definition, at most 3, no key twice
function E.decode(cfg, text, defOf)
	local out, seen = {}, {}
	local pool = {}
	for _, row in ipairs(cfg.corrupt.pool) do
		pool[row[1]] = row
	end
	for key, value in tostring(text or ""):gmatch("([%w_]+):(%-?%d+)") do
		local row, def = pool[key], defOf(key)
		if row and def and not seen[key] and #out < 3 then
			seen[key] = true
			out[#out + 1] = {key = key, value = max(1, min(E.value(row, def), tonumber(value)))}
		end
	end
	return out
end

-- the waystone's modifiers and the corrupted ones in one list for the run (a key the waystone holds is not doubled); the caller's
-- table is not touched
function E.merge(mods, corrupt)
	local out, have = {}, {}
	for _, m in ipairs(mods or {}) do
		out[#out + 1] = m
		have[m.key] = true
	end
	for _, m in ipairs(corrupt or {}) do
		if not have[m.key] then
			have[m.key] = true
			out[#out + 1] = {key = m.key, value = m.value}
		end
	end
	return out
end

-- ===================================================================== the atlas (tiers paid, ranks)
local function pow2(n)
	return 2 ^ n
end

function E.tierPaid(mask, tier)
	tier = floor(tonumber(tier) or 0)
	if tier < 1 or tier > 52 then
		return false
	end
	return floor((tonumber(mask) or 0) / pow2(tier - 1)) % 2 == 1
end

function E.markPaid(mask, tier)
	mask = floor(tonumber(mask) or 0)
	tier = floor(tonumber(tier) or 0)
	if tier < 1 or tier > 52 or E.tierPaid(mask, tier) then
		return mask
	end
	return mask + pow2(tier - 1)
end

function E.paidCount(mask)
	mask = floor(tonumber(mask) or 0)
	local n = 0
	while mask > 0 do
		n = n + mask % 2
		mask = floor(mask / 2)
	end
	return n
end

-- the ranks storage: one decimal digit a stat, the first stat the lowest digit
function E.ranks(cfg, number)
	number = floor(tonumber(number) or 0)
	local out = {}
	for i, s in ipairs(cfg.atlas.stats) do
		local d = number % 10
		number = floor(number / 10)
		out[s.key] = min(d, s.maxRank)
		out[i] = out[s.key]
	end
	return out
end

function E.packRanks(cfg, ranks)
	local n, mult = 0, 1
	for _, s in ipairs(cfg.atlas.stats) do
		n = n + min(s.maxRank, max(0, floor(tonumber(ranks[s.key]) or 0))) * mult
		mult = mult * 10
	end
	return n
end

function E.points(mask)
	return E.paidCount(mask)
end

function E.spent(cfg, ranks)
	local n = 0
	for _, s in ipairs(cfg.atlas.stats) do
		n = n + (tonumber(ranks[s.key]) or 0) * (cfg.atlas.cost or 1)
	end
	return n
end

function E.free(cfg, mask, ranks)
	return E.points(mask) - E.spent(cfg, ranks)
end

function E.statOf(cfg, key)
	for _, s in ipairs(cfg.atlas.stats) do
		if s.key == key then
			return s
		end
	end
	return nil
end

-- ok, reason, ranks (new copy)
function E.spend(cfg, mask, ranks, key)
	local s = E.statOf(cfg, key)
	if not s then
		return false, "unknown"
	end
	if (ranks[key] or 0) >= s.maxRank then
		return false, "maxed"
	end
	if E.free(cfg, mask, ranks) < (cfg.atlas.cost or 1) then
		return false, "points"
	end
	local out = {}
	for k, v in pairs(ranks) do
		out[k] = v
	end
	out[key] = (out[key] or 0) + 1
	return true, nil, out
end

function E.effects(cfg, ranks)
	local out = {}
	for _, s in ipairs(cfg.atlas.stats) do
		out[s.key] = (tonumber(ranks and ranks[s.key]) or 0) * s.per
	end
	return out
end

return E
