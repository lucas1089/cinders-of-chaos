-- Late-game monster damage boost, pure logic (no engine calls): the percent by monster level and the scaling of one hit.
-- Used by monster_damage.lua and tested by server/tests/monster_damage_test.lua. Config: monster_damage_config.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosMonsterDamageCore = ChaosMonsterDamageCore or {}
local C = ChaosMonsterDamageCore

local floor = math.floor

-- percent for a monster level: linear between cfg.points ({level, percent}, sorted by level), flat beyond the ends;
-- 0 for an unknown level (0 or nil) or without points
function C.percentFor(cfg, level)
	local pts = cfg and cfg.points
	level = tonumber(level) or 0
	if not pts or #pts == 0 or level <= 0 then
		return 0
	end
	if level <= pts[1].level then
		return pts[1].percent
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if level <= b.level then
			return a.percent + (b.percent - a.percent) * (level - a.level) / (b.level - a.level)
		end
	end
	return pts[#pts].percent
end

-- the multiplier for a monster level (1 when the boost is off)
function C.multiplierFor(cfg, level)
	if not cfg or cfg.enabled == false then
		return 1
	end
	return 1 + C.percentFor(cfg, level) / 100
end

-- value x mult, rounded to the nearest point, keeping the sign (the engine passes positive values to onHealthChange)
function C.scale(value, mult)
	value = tonumber(value) or 0
	if mult == 1 or value == 0 then
		return value
	end
	if value < 0 then
		return -floor(-value * mult + 0.5)
	end
	return floor(value * mult + 0.5)
end

-- whether a damage part of this combat type and origin is boosted. k = the engine constants
-- {physical, healing, undefined, none, manadrain, melee, ranged, spell} (tables so the tests need no globals).
-- Physical: the monster's melee and ranged attacks only (ORIGIN_MELEE / ORIGIN_RANGED, the hits armour reduces);
-- scripted damage (ORIGIN_SPELL: reflection, boss scripts), conditions (bleeding) and ORIGIN_NONE never.
-- Elemental (cfg.elemental): the same origins plus the monster's spells.
function C.isBoosted(cfg, k, combatType, origin)
	if combatType == nil or combatType == k.none or combatType == k.healing or combatType == k.undefined
		or combatType == k.manadrain then
		return false
	end
	if combatType == k.physical then
		return origin == k.melee or origin == k.ranged
	end
	if cfg and cfg.elemental then
		return origin == k.melee or origin == k.ranged or origin == k.spell
	end
	return false
end

-- scale one hit: returns primary, secondary (types unchanged)
function C.scaleHit(cfg, k, mult, primary, primaryType, secondary, secondaryType, origin)
	if mult == 1 then
		return primary, secondary
	end
	if C.isBoosted(cfg, k, primaryType, origin) then
		primary = C.scale(primary, mult)
	end
	if C.isBoosted(cfg, k, secondaryType, origin) then
		secondary = C.scale(secondary, mult)
	end
	return primary, secondary
end

-- pack combat (pace.lua, pace_config.lua damage): a paced monster's whole hit x mult, every combat type but healing and
-- none (elements, conditions, mana drain included). Returns primary, secondary.
function C.scalePace(k, mult, primary, primaryType, secondary, secondaryType)
	if not mult or mult == 1 then
		return primary, secondary
	end
	local function scaled(v, t)
		if t == nil or t == k.healing or t == k.none then
			return v
		end
		return C.scale(v, mult)
	end
	return scaled(primary, primaryType), scaled(secondary, secondaryType)
end

-- a bounded key -> value cache in two generations: lookups hit the new one, then the old one (and move the entry up);
-- when the new one holds `cap` entries it becomes the old one and the previous old one is dropped. Memory stays below
-- 2 x cap entries, and an entry still in use survives the turnover (no full clear that drops every live monster at
-- once, which thrashed with pack combat's ~100k monsters alive).
function C.newCache(cap)
	cap = math.max(1, math.floor(tonumber(cap) or 32768))
	local cur, old, size = {}, {}, 0
	local cache = {}
	function cache.get(key)
		local v = cur[key]
		if v ~= nil then
			return v
		end
		v = old[key]
		if v ~= nil then
			old[key] = nil
			cache.put(key, v)
		end
		return v
	end
	function cache.put(key, value)
		if cur[key] == nil then
			if size >= cap then
				old, cur, size = cur, {}, 0
			end
			size = size + 1
		end
		cur[key] = value
	end
	function cache.size()
		local n = size
		for _ in pairs(old) do
			n = n + 1
		end
		return n
	end
	return cache
end

return C
