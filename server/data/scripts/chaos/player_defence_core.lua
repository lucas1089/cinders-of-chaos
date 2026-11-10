-- Player defence, pure logic (no engine calls): the order in which a player defends, O464. Used by player_defence.lua, tested
-- by server/tests/player_defence_test.lua. Numbers: defence_config.lua (shared with the monster side), player_defence_config.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. server/README.md "Player defence (O464)".
--
-- The order of a hit on a player (the monster stage already multiplied it by the rank, rift and level damage; the engine took
-- the immunity, the shield's block and, still, the worn pieces' absorb; this layer takes that absorb out again):
--   1  avoidance, hits only (never a condition tick or a field):
--        dodge             attack hits (melee, ranged, wand), any damage type
--        block             attack hits, any damage type
--        spell suppression spell hits: a suppressed hit deals suppressLess percent less
--   2  mitigation by type, each part of the hit on its own:
--        physical    armour share A / (A + armourHitFactor x H) plus every physical absorb source, at most physicalReductionCap
--                    (armour only for attack and spell hits, not for ticks or scripted hits)
--        a group     fire, cold, lightning, chaos: x (1 - resistance / 100)
--   3  (not here) the older multipliers, mana shield, energy shield, health.
-- The resistance of a group = sum of its sources - the level penalty - area penalties, at most resistCap + the cap raise - the
-- cap lowering of an area, then minus the attacker's penetration, never below defence_config.lua resistFloor.

ChaosPlayerDefenceCore = ChaosPlayerDefenceCore or {}
local C = ChaosPlayerDefenceCore

local floor, abs, min, max = math.floor, math.abs, math.min, math.max

local function num(v)
	return tonumber(v) or 0
end

-- the engine constants the core compares with (a table so that the tests need no globals): the damage types by name and the
-- origins. nil entries are skipped (a fork without water or arcane damage)
function C.engineConstants()
	return {physical = COMBAT_PHYSICALDAMAGE, healing = COMBAT_HEALING, undefined = COMBAT_UNDEFINEDDAMAGE,
		none = COMBAT_NONE, manadrain = COMBAT_MANADRAIN, lifedrain = COMBAT_LIFEDRAIN, fire = COMBAT_FIREDAMAGE,
		ice = COMBAT_ICEDAMAGE, energy = COMBAT_ENERGYDAMAGE, earth = COMBAT_EARTHDAMAGE, death = COMBAT_DEATHDAMAGE,
		holy = COMBAT_HOLYDAMAGE, drown = COMBAT_DROWNDAMAGE, water = COMBAT_WATERDAMAGE, arcane = COMBAT_ARCANEDAMAGE,
		melee = ORIGIN_MELEE, ranged = ORIGIN_RANGED, spell = ORIGIN_SPELL, wand = ORIGIN_WAND, condition = ORIGIN_CONDITION}
end

-- engine combat type constant -> group name, from cfg.groups and the constants k
function C.groupTable(cfg, k)
	local map = {}
	for group, names in pairs(cfg.groups) do
		for _, name in ipairs(names) do
			if k[name] ~= nil then
				map[k[name]] = group
			end
		end
	end
	return map
end

-- empty sums: {phys = percent, group = {fire = percent, ...}}
function C.newSums(cfg)
	local s = {phys = 0, group = {}}
	for _, g in ipairs(cfg.groupOrder) do
		s.group[g] = 0
	end
	return s
end

-- add a source of one damage type: percent at its full value, to the group of the type (physical: the physical reduction)
function C.addType(sums, groupOf, k, ctype, percent)
	percent = num(percent)
	if percent == 0 or ctype == nil then
		return
	end
	if ctype == k.physical then
		sums.phys = sums.phys + percent
		return
	end
	local g = groupOf[ctype]
	if g then
		sums.group[g] = sums.group[g] + percent
	end
end

-- add an "all elements" source: to fire, cold and lightning, not to chaos
function C.addAll(sums, cfg, percent)
	for _, g in ipairs(cfg.allGroups) do
		sums.group[g] = sums.group[g] + num(percent)
	end
end

function C.addGroup(sums, group, percent)
	if sums.group[group] ~= nil then
		sums.group[group] = sums.group[group] + num(percent)
	end
end

-- the points of the passive tree and Paragon that count toward one resistance: cfg.tree.share of them, at most cfg.tree.cap
function C.treeCounted(cfg, points)
	points = num(points)
	local t = cfg.tree
	if not t then
		return points
	end
	local v = points * (t.share or 1)
	if t.cap and v > t.cap then
		v = t.cap
	end
	return v
end

-- ------------------------------------------------------------------------------------------------- level penalty
-- the penalty (percent points) on all four resistances at this level
function C.penalty(cfg, level)
	local p = cfg.penalty
	if not p or p.enabled == false then
		return 0
	end
	level = num(level)
	local points = 0
	for _, m in ipairs(p.marks) do
		if level >= m.level then
			points = m.points
		end
	end
	return points
end

-- the mark a player is warned about at this level (warnFrom <= level < the mark's level), or nil
function C.warning(cfg, level)
	local p = cfg.penalty
	if not p or p.enabled == false then
		return nil
	end
	level = num(level)
	for _, m in ipairs(p.marks) do
		if level >= (m.warnFrom or m.level) and level < m.level then
			return m
		end
	end
	return nil
end

-- the mark a character has just crossed going from oldLevel to newLevel (the highest one crossed), or nil
function C.crossed(cfg, oldLevel, newLevel)
	local p = cfg.penalty
	if not p or p.enabled == false then
		return nil
	end
	oldLevel, newLevel = num(oldLevel), num(newLevel)
	local hit
	for _, m in ipairs(p.marks) do
		if oldLevel < m.level and newLevel >= m.level then
			hit = m
		end
	end
	return hit
end

-- ------------------------------------------------------------------------------------------------- resistance
-- the resistance (percent, may be negative) of one group. sum: the sources; ctx: level, area (penalty points of the area),
-- capDelta (a raise of the cap, negative: an area lowers it), pen (the attacker's penetration)
function C.resistance(def, cfg, sum, ctx)
	local r = num(sum) - C.penalty(cfg, ctx.level) - num(ctx.area)
	local cap = def.resistCap + num(ctx.capDelta)
	if r > cap then
		r = cap
	end
	r = r - num(ctx.pen)
	if r < def.resistFloor then
		r = def.resistFloor
	end
	return r
end

-- the four resistances: {fire = r, ...}
function C.resistances(def, cfg, sums, ctx)
	local out = {}
	for _, g in ipairs(cfg.groupOrder) do
		out[g] = C.resistance(def, cfg, sums.group[g], ctx)
	end
	return out
end

-- ------------------------------------------------------------------------------------------------- armour
-- the share (0 .. 1) of a physical hit of size H that armour A removes
function C.armourShare(def, A, H)
	A, H = num(A), num(H)
	if A <= 0 or H <= 0 then
		return 0
	end
	return A / (A + def.armourHitFactor * H)
end

-- the typical monster hit at a level (display only, cfg.typicalHit): a straight line in log level and log hit
function C.typicalHit(cfg, level)
	local pts = cfg.typicalHit
	level = max(1, num(level))
	local a, b = pts[1], pts[2]
	for i = 2, #pts do
		a, b = pts[i - 1], pts[i]
		if level <= b.level then
			break
		end
	end
	local e = (math.log(b.hit) - math.log(a.hit)) / (math.log(b.level) - math.log(a.level))
	return a.hit * (level / a.level) ^ e
end

-- the share (-1 .. cap) of a physical hit that does not land: armour share plus the physical reduction (percent), at most
-- physicalReductionCap, at least -1
function C.physicalTotal(def, share, reductionPercent)
	local total = share + num(reductionPercent) / 100
	local cap = def.physicalReductionCap / 100
	if total > cap then
		total = cap
	end
	if total < -1 then
		total = -1
	end
	return total
end

-- ------------------------------------------------------------------------------------------------- the engine's absorb
-- what the engine's Player::blockHit left of a hit (0 .. 1.x) before any event: each worn piece takes its percent of what the
-- last one left (negative: adds), then patch 0049 raises the result so that equipment and the absorb storages together never
-- remove more than the ceiling. wornPercents: the pieces' absorb percent of the type; storagePercent: the sum of the two
-- storages of the type
function C.engineKeep(wornPercents, storagePercent, ceiling)
	local keep = 1
	for _, p in ipairs(wornPercents or {}) do
		if num(p) ~= 0 then
			keep = keep * (1 - p / 100)
		end
	end
	if keep < 1 then
		local c = ceiling or 75
		local storage = min(max(0, num(storagePercent)), 100)
		storage = min(storage, c)
		local floorKeep = ((100 - c) / 100) / (1 - storage / 100)
		if keep < floorKeep then
			keep = min(floorKeep, 1)
		end
	end
	return keep
end

-- a value as it was before the engine kept `keep` of it (rounded, never 0 for a hit that arrived)
local function unscale(value, keep)
	if not keep or keep == 1 or keep <= 0 or value == 0 then
		return value
	end
	local n = floor(abs(value) / keep + 0.5)
	if n < 1 then
		n = 1
	end
	return value < 0 and -n or n
end
C.unscale = unscale

-- a value times m, rounded; a hit that arrives never rounds to nothing unless m is 0 or less
local function scale(value, m)
	if value == 0 or m == 1 then
		return value
	end
	local a = abs(value)
	local n = m > 0 and floor(a * m + 0.5) or 0
	if n < 1 and a >= 1 and m > 0 then
		n = 1
	end
	return value < 0 and -n or n
end
C.scale = scale

-- a damage part that no defence of the player touches: healing, no damage, scripted costs
local function untouched(k, ctype)
	return ctype == nil or ctype == k.none or ctype == k.healing or ctype == k.undefined
end
C.untouched = untouched

-- "attack" (melee, ranged, wand), "spell", "tick" (a condition, a field is one) or "other" (a scripted hit, reflect)
function C.kindOf(k, origin)
	if origin == k.melee or origin == k.ranged or (k.wand ~= nil and origin == k.wand) then
		return "attack"
	end
	if origin == k.spell then
		return "spell"
	end
	if origin == k.condition then
		return "tick"
	end
	return "other"
end

-- ------------------------------------------------------------------------------------------------- one hit
-- ctx: def, cfg, k (engine constants), groupOf (C.groupTable), sums (C.newSums filled by the sources), A (armour), dodge,
-- block, suppress (percent), level, area, capDelta, pen (the attacker's elemental penetration, percent points: 0 for
-- monsters), physPen (its physical penetration: points off the armour share),
-- engineKeep(ctype) -> what the engine left of a hit of that type (nil: nothing to undo), rand(n) -> 1..n.
-- hit: {primary, ptype, secondary, stype, origin}. Returns primary, secondary, info
-- {kind, dodged, blocked, suppressed, undone}.
function C.defend(ctx, hit)
	local k, def, cfg = ctx.k, ctx.def, ctx.cfg
	local kind = C.kindOf(k, hit.origin)
	local info = {kind = kind}
	local pd, sd = hit.primary or 0, hit.secondary or 0
	local ptype, stype = hit.ptype, hit.stype
	if untouched(k, ptype) and (sd == 0 or untouched(k, stype)) then
		return pd, sd, info
	end
	-- the engine's own absorb comes out first
	if ctx.engineKeep then
		local kp, ks = ctx.engineKeep(ptype), ctx.engineKeep(stype)
		if (kp and kp ~= 1) or (ks and ks ~= 1) then
			pd, sd = unscale(pd, kp), unscale(sd, ks)
			info.undone = true
		end
	end
	-- 1 avoidance
	if kind == "attack" then
		local dodge = min(cfg.dodgeCap, num(ctx.dodge))
		if dodge > 0 and ctx.rand(100) <= dodge then
			info.dodged = true
			return 0, 0, info
		end
		local block = min(def.blockCap, num(ctx.block))
		if block > 0 and ctx.rand(100) <= block then
			info.blocked = true
			return 0, 0, info
		end
	elseif kind == "spell" then
		local sup = min(cfg.suppressCap, num(ctx.suppress))
		if sup > 0 and ctx.rand(100) <= sup then
			info.suppressed = true
			local m = 1 - cfg.suppressLess / 100
			pd, sd = scale(pd, m), scale(sd, m)
		end
	end
	-- 2 mitigation by type
	local armoured = kind == "attack" or kind == "spell"
	local res
	local function part(value, ctype)
		if value == 0 or untouched(k, ctype) then
			return value
		end
		if ctype == k.physical then
			local share = armoured and max(0, C.armourShare(def, ctx.A, abs(value)) - num(ctx.physPen) / 100) or 0
			return scale(value, 1 - C.physicalTotal(def, share, ctx.sums.phys))
		end
		local g = ctx.groupOf[ctype]
		if not g then
			return value
		end
		res = res or C.resistances(def, cfg, ctx.sums, ctx)
		return scale(value, 1 - res[g] / 100)
	end
	return part(pd, ptype), part(sd, stype), info
end

return C
