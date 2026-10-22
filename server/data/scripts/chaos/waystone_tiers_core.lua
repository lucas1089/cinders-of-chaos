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

-- name (any case) -> {tier =, boss = bool} of the config's lists
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

-- the tier of the map a position is in, or nil
function K.mapTier(cfg, pos)
	if not pos then
		return nil
	end
	for _, m in ipairs(cfg and cfg.maps or {}) do
		local f, t = m.from, m.to
		if pos.z == f.z and pos.x >= math.min(f.x, t.x) and pos.x <= math.max(f.x, t.x) and pos.y >= math.min(f.y, t.y)
			and pos.y <= math.max(f.y, t.y) then
			return m.tier
		end
	end
	return nil
end

-- {tier, boss} of a monster of type `name` at `pos`: only a tier's own monster (or boss) inside a map of that tier
function K.classify(cfg, index, name, pos)
	if not cfg or cfg.enabled == false or not name then
		return nil
	end
	local e = index[tostring(name):lower()]
	if not e then
		return nil
	end
	local at = K.mapTier(cfg, pos)
	if at ~= e.tier then
		return nil
	end
	return e
end

function K.levelMult(cfg, tier)
	return num(cfg and cfg.levelMult and cfg.levelMult[tier]) or 1
end

-- the level of a tier's monster: its hunting level x the tier's levelMult (whole number, at least 1)
function K.level(cfg, tier, base)
	base = num(base)
	if not base or base <= 0 then
		return nil
	end
	return math.max(1, math.floor(base * K.levelMult(cfg, tier) + 0.5))
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

-- the damage multiplier of a tier's monster (from its hunting level `base`) or boss
function K.damageMult(cfg, e, base)
	if not e then
		return 1
	end
	if e.boss then
		return num(cfg and cfg.bossDamage and cfg.bossDamage[e.tier]) or 1
	end
	local target = K.level(cfg, e.tier, base)
	if not target then
		return 1
	end
	return K.scale(cfg, base, target).damage
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
