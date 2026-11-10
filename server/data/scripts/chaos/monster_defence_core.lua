-- Monster defence, pure logic (no engine calls): how a monster takes a hit from a player, and what the rank modifiers
-- do to a hit a monster deals. Used by monster_defence.lua and monster_tiers.lua, tested by
-- server/tests/monster_defence_test.lua. Numbers: defence_config.lua (shared), monster_defence_config.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. server/README.md "Monster defence (O462)".
--
-- The order of a hit on a monster (the engine's first: immunity, the flat armour and defence of the XML, the monster's
-- element percent; then this layer, the first Lua event of the monster; then the older multipliers):
--   1  block (Bulwark), weapon hits only
--   2  physical part: armour by hit size and the Plated modifier, inside one cap together with the monster's own
--      physical percent
--   3  element part: one cap on the resistance (rank bonus and Resistant included), penetration after the cap
-- The engine has applied the element percent already; each step multiplies by (the wanted share) / (the share the engine
-- left), so the result is the same as if the engine had used the new number.

ChaosMonsterDefenceCore = ChaosMonsterDefenceCore or {}
local C = ChaosMonsterDefenceCore

local floor, abs, min, max, log = math.floor, math.abs, math.min, math.max, math.log

-- modifier key -> what it does. added: the element of the extra damage; physReduction, crit, block: flags; resist: the
-- element is drawn when the modifier is rolled (state.draw[key]).
C.MOD = {
	emberforged = {added = "fire"},
	frostforged = {added = "ice"},
	stormforged = {added = "energy"},
	plated = {physReduction = true},
	resistant = {resist = true},
	ruthless = {crit = true},
	bulwark = {block = true}
}

-- the engine constants the core compares with (a table so that the tests need no globals): combat types, origins, and
-- the element names of C.MOD / monster_defence_config.lua resistElements
function C.engineConstants()
	return {physical = COMBAT_PHYSICALDAMAGE, healing = COMBAT_HEALING, undefined = COMBAT_UNDEFINEDDAMAGE,
		none = COMBAT_NONE, manadrain = COMBAT_MANADRAIN, lifedrain = COMBAT_LIFEDRAIN, melee = ORIGIN_MELEE,
		ranged = ORIGIN_RANGED, spell = ORIGIN_SPELL, condition = ORIGIN_CONDITION, fire = COMBAT_FIREDAMAGE,
		ice = COMBAT_ICEDAMAGE, energy = COMBAT_ENERGYDAMAGE, earth = COMBAT_EARTHDAMAGE, death = COMBAT_DEATHDAMAGE,
		holy = COMBAT_HOLYDAMAGE}
end

-- the flags of a monster's modifier list: {added = "fire", physReduction = true, resist = "ice", crit = true, block = true}.
-- draw: {key = element name} of the modifiers that draw an element. nil for a monster without any of them.
function C.modSet(list, draw)
	local set
	for _, key in ipairs(list or {}) do
		local m = C.MOD[key]
		if m then
			set = set or {}
			if m.added then
				set.added = m.added
			elseif m.resist then
				if draw and draw[key] then
					set.resist = draw[key]
				end
			elseif m.physReduction then
				set.physReduction = true
			elseif m.crit then
				set.crit = true
			elseif m.block then
				set.block = true
			end
		end
	end
	return set
end

-- the median class hit at a level: a straight line in log(level), log(hit) between two rows of cfg.hitCurve, the slope
-- of the last two rows beyond the ends
function C.hitAtLevel(cfg, level)
	local pts = cfg.hitCurve
	level = max(1, tonumber(level) or 1)
	local a, b = pts[1], pts[2]
	for i = 2, #pts do
		a, b = pts[i - 1], pts[i]
		if level <= b.level then
			break
		end
	end
	local e = (log(b.hit) - log(a.hit)) / (log(b.level) - log(a.level))
	return a.hit * (level / a.level) ^ e
end

-- "boss", "elite" or "normal": the class of a monster for its armour. tier: ChaosTierOf, bossLike: boolean
function C.rankClass(cfg, tier, bossLike)
	if bossLike then
		return "boss"
	end
	if tier and cfg.eliteRanks[tier] then
		return "elite"
	end
	return "normal"
end

-- the armour value A of a monster of this level and class: the median class hit of the level loses armourTarget percent
function C.armourValue(def, cfg, level, class, typeName)
	local o = typeName and cfg.armourOverride and cfg.armourOverride[typeName:lower()]
	if o then
		return o
	end
	local f = (cfg.armourTarget[class] or cfg.armourTarget.normal) / 100
	return f / (1 - f) * def.armourHitFactor * C.hitAtLevel(cfg, level)
end

-- the share of a hit of size H that armour A removes (0 .. 1)
function C.armourReduction(def, A, H)
	if not A or A <= 0 or not H or H <= 0 then
		return 0
	end
	return A / (A + def.armourHitFactor * H)
end

-- the multiplier on a physical part that arrived (the engine took the monster's physical percent p0 already): armour
-- share `arm` and modifier share `mod` (0 .. 1) on top, the total of the three at most def.physicalReductionCap
function C.physicalFactor(def, p0, arm, mod)
	local keep0 = 1 - (p0 or 0) / 100
	if keep0 <= 0 then
		return 0
	end
	local total = 1 - keep0 * (1 - arm) * (1 - mod)
	local cap = def.physicalReductionCap / 100
	if total > cap then
		return (1 - cap) / keep0
	end
	return (1 - arm) * (1 - mod)
end

-- the effective resistance (percent) of an element: the monster's percent plus the rank bonus, raised to modValue (the
-- Resistant modifier's number, for its element), at most def.resistCap; then penetration off it, down to def.resistFloor
-- (-100). Not clamped at 0: penetration beyond the resistance turns it into a weakness (O464: no re-derivation of a rounded
-- value any more, the engine's element percent is divided out in C.elementFactor).
function C.effectiveResist(def, base, bonus, modValue, pen)
	local r = (base or 0) + (bonus or 0)
	if modValue and modValue > r then
		r = modValue
	end
	if r > def.resistCap then
		r = def.resistCap
	end
	r = r - (pen or 0)
	if def.resistFloor and r < def.resistFloor then
		r = def.resistFloor
	end
	return r
end

-- the multiplier on an element part that arrived (the engine took `base` percent): the wanted resistance `eff`
function C.elementFactor(base, eff)
	local keep0 = 1 - (base or 0) / 100
	if keep0 <= 0 then
		return 0
	end
	return (1 - eff / 100) / keep0
end

local function scaleValue(value, m)
	local a = abs(value)
	local n = floor(a * m + 0.5)
	if n < 1 and a >= 1 and m > 0 then
		n = 1 -- a hit that reaches the monster never rounds to nothing
	end
	return value < 0 and -n or n
end
C.scaleValue = scaleValue

-- a damage part that armour and resistance never touch: healing, no damage, scripted costs, mana and life drain
local function untouched(k, ctype)
	return ctype == nil or ctype == k.none or ctype == k.healing or ctype == k.undefined or ctype == k.manadrain
		or ctype == k.lifedrain
end
C.untouched = untouched

-- One hit on a monster. ctx: {def, cfg, k (engine constants: physical, healing, undefined, none, manadrain, lifedrain,
-- melee, ranged, spell, condition), A (the armour value), set (C.modSet of the monster or nil), bonus (rank resistance
-- bonus), resistOf(ctype) -> the monster's element percent, pen (the player's elemental penetration, percent points off the
-- capped resistance), physPen (its physical penetration: points off the armour share, down to 0), rand(n) -> 1..n}.
-- hit: {primary, ptype, secondary, stype, origin}. Returns primary, secondary, info {blocked = true | nil}.
-- Origins: melee and ranged are weapon hits (and a monster summon's attacks), spell a spell, condition a tick (a field
-- is a tick too: its damage comes from a condition).
function C.defend(ctx, hit)
	local k, def, cfg, set = ctx.k, ctx.def, ctx.cfg, ctx.set
	local origin = hit.origin
	local weapon = origin == k.melee or origin == k.ranged
	local armoured = weapon or origin == k.spell
	if set and set.block and weapon and not untouched(k, hit.ptype) then
		local chance = min(def.blockCap, cfg.mods.block.chance)
		if ctx.rand(100) <= chance then
			return 0, 0, {blocked = true}
		end
	end
	local function part(value, ctype)
		if value == 0 or untouched(k, ctype) then
			return value
		end
		local m
		if ctype == k.physical then
			local arm = armoured and max(0, C.armourReduction(def, ctx.A, abs(value)) - (ctx.physPen or 0) / 100) or 0
			local mod = set and set.physReduction and cfg.mods.physReduction / 100 or 0
			m = C.physicalFactor(def, ctx.resistOf(ctype), arm, mod)
		else
			local base = ctx.resistOf(ctype)
			local modValue = set and set.resist and set.resist == ctx.elementName(ctype) and cfg.mods.resist or nil
			m = C.elementFactor(base, C.effectiveResist(def, base, ctx.bonus, modValue, ctx.pen))
		end
		if m == 1 then
			return value
		end
		return scaleValue(value, m)
	end
	return part(hit.primary, hit.ptype), part(hit.secondary, hit.stype), {}
end

-- the hit a monster deals to a player, with its rank modifiers: Ruthless (a critical hit) and the extra element of
-- Emberforged / Frostforged / Stormforged. set: C.modSet; absorbOf(ctype) -> the player's absorb percent for the added
-- element (the one small function the player stage replaces); rand(n) -> 1..n. Returns primary, ptype, secondary,
-- stype, info {crit = true | nil, added = amount | nil}. A condition tick gets neither.
function C.attackHit(cfg, k, set, hit, rand, absorbOf)
	local primary, ptype, secondary, stype = hit.primary, hit.ptype, hit.secondary, hit.stype
	local info = {}
	if not set then
		return primary, ptype, secondary, stype, info
	end
	local origin = hit.origin
	local weapon = origin == k.melee or origin == k.ranged
	if set.crit and (weapon or origin == k.spell) and not untouched(k, ptype) and rand(100) <= cfg.mods.crit.chance then
		primary = scaleValue(primary, cfg.mods.crit.mult)
		secondary = scaleValue(secondary, cfg.mods.crit.mult)
		info.crit = true
	end
	if set.added and weapon and ptype == k.physical and primary ~= 0 and (secondary == 0 or stype == nil or stype == k.none) then
		local ctype = k[set.added]
		if ctype then
			local add = floor(abs(primary) * cfg.mods.addedAs / 100 + 0.5)
			local pct = absorbOf and absorbOf(ctype) or 0
			if pct >= 100 then
				add = 0
			elseif pct ~= 0 and add > 0 then
				add = max(1, floor(add * (1 - pct / 100) + 0.5))
			end
			if add > 0 then
				secondary = primary < 0 and -add or add
				stype = ctype
				info.added = add
			end
		end
	end
	return primary, ptype, secondary, stype, info
end

return C
