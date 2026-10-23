-- Waystone tier maps (waystone_tiers.lua; server/README.md "Waystone tiers"): the pure part. Numbers:
-- waystone_tiers_config.lua. Tests: tests/waystone_tiers_test.lua. Lua 5.1 / LuaJIT and 5.3.

ChaosWaystoneTiersCore = ChaosWaystoneTiersCore or {}
local K = ChaosWaystoneTiersCore

local function num(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return v
end

-- name (any case) -> {tier =, boss = bool} of the config's lists (tier: the base tier whose maps it lives in)
function K.index(cfg)
	local out = {}
	for tier, list in ipairs(cfg and cfg.monsters or {}) do
		for _, name in ipairs(list) do
			out[tostring(name):lower()] = {tier = tier, boss = false}
		end
	end
	for tier, name in ipairs(cfg and cfg.bosses or {}) do
		out[tostring(name):lower()] = {tier = tier, boss = true}
	end
	return out
end

function K.tierCount(cfg)
	return #(cfg and cfg.tiers or {})
end

-- the monster level of a run of tier t (nil: no such tier)
function K.tierLevel(cfg, t)
	local e = cfg and cfg.tiers and cfg.tiers[tonumber(t) or 0]
	return e and num(e.level) or nil
end

-- the tier of a Waystone Tier item (server id), or nil
function K.tierOfItem(cfg, id)
	id = tonumber(id)
	for t, e in ipairs(cfg and cfg.tiers or {}) do
		if e.item == id then
			return t
		end
	end
	return nil
end

-- the band (index, entry) of tier t
function K.bandOf(cfg, t)
	t = tonumber(t)
	for i, b in ipairs(cfg and cfg.bands or {}) do
		if t and t >= b.first and t <= b.last then
			return i, b
		end
	end
	return nil
end

-- the index and entry of the map a position is in, or nil
function K.mapAt(cfg, pos)
	if not pos then
		return nil
	end
	for i, m in ipairs(cfg and cfg.maps or {}) do
		local f, t = m.from, m.to
		if pos.z == f.z and pos.x >= math.min(f.x, t.x) and pos.x <= math.max(f.x, t.x) and pos.y >= math.min(f.y, t.y)
			and pos.y <= math.max(f.y, t.y) then
			return i, m
		end
	end
	return nil
end

-- the base tier of the map a position is in, or nil
function K.mapTier(cfg, pos)
	local _, m = K.mapAt(cfg, pos)
	return m and m.tier or nil
end

-- the band (index, entry) whose runs open map i
function K.bandOfMap(cfg, i)
	local m = cfg and cfg.maps and cfg.maps[tonumber(i) or 0]
	if not m then
		return nil
	end
	for bi, b in ipairs(cfg.bands or {}) do
		for _, bt in ipairs(b.maps or {}) do
			if bt == m.tier then
				return bi, b
			end
		end
	end
	return nil
end

-- the tier a map counts at before its first run: the first tier of its band
function K.defaultTier(cfg, i)
	local _, b = K.bandOfMap(cfg, i)
	return b and b.first or nil
end

-- the base tiers whose maps a run of tier t may open (its band's), or {}
function K.baseTiersOf(cfg, t)
	local _, b = K.bandOf(cfg, t)
	return b and b.maps or {}
end

-- the map index whose area starts at `from` (tier_maps.lua area.fromPos), or nil
function K.mapOfArea(cfg, from)
	if not from then
		return nil
	end
	for i, m in ipairs(cfg and cfg.maps or {}) do
		if m.from.x == from.x and m.from.y == from.y and m.from.z == from.z then
			return i
		end
	end
	return nil
end

-- {tier, boss, map, run} of a monster of type `name` at `pos`: only a base tier's own monster (or boss) inside a map of
-- that base tier. run: the tier of the map's run (active[map]), else the first tier of its band
function K.classify(cfg, index, name, pos, active)
	if not cfg or cfg.enabled == false or not name then
		return nil
	end
	local e = index[tostring(name):lower()]
	if not e then
		return nil
	end
	local i, m = K.mapAt(cfg, pos)
	if not m or m.tier ~= e.tier then
		return nil
	end
	local run = active and active[i] or K.defaultTier(cfg, i)
	if not K.tierLevel(cfg, run) then
		return nil
	end
	return {tier = e.tier, boss = e.boss, map = i, run = run}
end

-- the level of a classified monster (its run's level)
function K.level(cfg, e)
	return e and K.tierLevel(cfg, e.run) or nil
end

-- health / damage / experience multipliers from level `native` to `target` (the engine's level formulas, as
-- areagen_core.lua A.levelScale): health x(1 + h T)/(1 + h N), damage x(1 + d T)/(1 + d N), experience x T / N
function K.scale(cfg, native, target)
	native = math.max(1, num(native) or 1)
	target = math.max(1, num(target) or native)
	local h = num(cfg and cfg.healthPerLevel) or 0.0074
	local d = num(cfg and cfg.damagePerLevel) or 0.0015
	return {
		health = (1 + h * target) / (1 + h * native),
		damage = (1 + d * target) / (1 + d * native),
		experience = target / native
	}
end

-- the factors of a classified monster: a monster from its hunting level `base` to the run's level; a boss from the
-- level of its band's first tier to the run's level (nil: no base level for a monster)
function K.factors(cfg, e, base)
	if not e then
		return nil
	end
	local target = K.level(cfg, e)
	if e.boss then
		return K.scale(cfg, K.tierLevel(cfg, K.defaultTier(cfg, e.map)) or target, target)
	end
	base = num(base)
	if not base or base <= 0 then
		return nil
	end
	return K.scale(cfg, base, target)
end

-- the damage multiplier of a classified monster (from its hunting level `base`) or boss
function K.damageMult(cfg, e, base)
	local f = K.factors(cfg, e, base)
	if not f then
		return 1
	end
	if e.boss then
		return (num(cfg and cfg.bossDamage and cfg.bossDamage[e.tier]) or 1) * f.damage
	end
	return f.damage
end

-- the tier of a waystone dropped in a run of tier `run` (nil: outside the maps, tier 1); roll: 1..100
function K.dropTier(cfg, run, roll)
	local n = K.tierCount(cfg)
	if n < 1 then
		return nil
	end
	run = tonumber(run)
	if not run then
		return 1
	end
	local list = cfg.drops and cfg.drops.inside or {}
	local total = 0
	for _, d in ipairs(list) do
		total = total + (num(d.chance) or 0)
	end
	local step = 0
	if total > 0 then
		local at = (num(roll) or 1) / 100 * total
		local acc = 0
		for _, d in ipairs(list) do
			acc = acc + (num(d.chance) or 0)
			if at <= acc then
				step = num(d.step) or 0
				break
			end
		end
	end
	return math.max(1, math.min(n, run + step))
end

-- the run's boss drops one waystone of this tier as well (nil: none)
function K.bossDrop(cfg, run)
	if not (cfg and cfg.drops and cfg.drops.bossNext) or not tonumber(run) then
		return nil
	end
	return math.min(K.tierCount(cfg), run + 1)
end

-- new max health (whole, at least 1; never above the engine's int32 health)
function K.health(maxHealth, mult)
	maxHealth, mult = num(maxHealth), num(mult)
	if not maxHealth or maxHealth <= 0 or not mult or mult <= 0 then
		return nil
	end
	return math.max(1, math.min(2147483647, math.floor(maxHealth * mult + 0.5)))
end

-- a hit on a pillar-shielded boss away from its pillar: the share it keeps (whole numbers; 0..1)
function K.shielded(cfg, primary, secondary)
	local f = num(cfg and cfg.shieldedShare) or 0
	f = math.max(0, math.min(1, f))
	return math.floor((num(primary) or 0) * f), math.floor((num(secondary) or 0) * f)
end

return K
