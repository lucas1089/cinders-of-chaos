-- The Thief line's area strikes (2026-10-15, pack farming): Blade Flurry (192, all three classes) and Iaido Sweep
-- (193, Samurai). Numbers: B.cfg below; spells: server/data/spells/README.md "Thief line"; balance: "Pack farming for
-- every class" there. Read by server/tools/rotation_sim.py (the class scales, the same text form as Shuriken Toss).
--
-- Both are melee weapon strikes (ChaosSpell.weaponStrike, ORIGIN_MELEE), one per monster hit, so the line's weapon
-- rules apply to every hit (stealth crit, Poison Blades and Blackblood Creed, the Bushido crit, the Ninja's off-hand
-- strike, the pack cleave). Targets: monsters that are not a player's summon (ChaosSpell.isEnemy); a player is hit only
-- when it is Iaido Sweep's target. The pure parts (ranges, scales, the sweep's tiles) need no engine.
-- Lua 5.1 / LuaJIT / 5.3.

if ChaosBlades then
	return
end
ChaosBlades = {}
local B = ChaosBlades

B.cfg = {
	-- Blade Flurry: every monster within `radius` sqm of the Thief (the 5x5 square around it; 3x3 until the second pass
	-- of 2026-10-15, when the cleave was cut). One hit on a lone target
	-- matches a Shuriken Toss of the class (its class scale; the Ninja's off-hand strike adds about half), so single
	-- target damage stays where it was and the spell's worth is the pack.
	flurry = {
		radius = 2,
		minK = 0.050, minBase = 20, maxK = 0.080, maxBase = 40,
		scale = {[11] = 1.33, [12] = 1.08, [13] = 1.5},
		early = {[12] = {below = 180, scale = 0.89}, [13] = {below = 120, scale = 1.33}},
		defaultScale = 1.33,
	},
	-- Iaido Sweep: a wide draw cut in front of the Samurai, towards its target (within `reach` sqm): `depth` rows of
	-- 2 x halfWidth + 1 tiles (3 x 2) along a straight direction, the 7 nearest tiles of the quarter along a diagonal.
	-- Half of Iaijutsu per monster, no charge.
	sweep = {
		reach = 2, depth = 2, halfWidth = 1,
		minK = 0.10, minBase = 30, maxK = 0.16, maxBase = 60,
		scale = 0.8,
		-- every monster in the cut but the target takes `pack` x the hit (second pass, 2026-10-15; the target, and a
		-- player, the plain hit)
		pack = 1.5,
	},
}

local floor = math.floor

local function num(v, d)
	v = tonumber(v)
	return v == nil and d or v
end

-- min, max of a strike: (level / 5 + power x k + base) x scale for both ends
function B.range(level, power, c, scale)
	local l = num(level, 0) / 5
	local p = num(power, 0)
	local s = num(scale, 1)
	return floor((l + p * c.minK + c.minBase) * s), floor((l + p * c.maxK + c.maxBase) * s)
end

-- Blade Flurry's class scale for a vocation id at a level
function B.flurryScale(vocationId, level)
	local f = B.cfg.flurry
	local e = f.early[vocationId]
	if e and num(level, 0) < e.below then
		return e.scale
	end
	return f.scale[vocationId] or f.defaultScale
end

function B.flurryRange(level, power, vocationId)
	return B.range(level, power, B.cfg.flurry, B.flurryScale(vocationId, level))
end

function B.sweepRange(level, power)
	return B.range(level, power, B.cfg.sweep, B.cfg.sweep.scale)
end

-- the unit step of a direction from one tile towards another (-1 / 0 / 1 each), as ChaosSpell.dirTo picks it: a
-- straight direction unless the other axis is at least half of the main one
function B.stepTowards(from, to)
	local dx, dy = to.x - from.x, to.y - from.y
	local sx = dx > 0 and 1 or (dx < 0 and -1 or 0)
	local sy = dy > 0 and 1 or (dy < 0 and -1 or 0)
	if math.abs(dx) >= 2 * math.abs(dy) then
		sy = 0
	elseif math.abs(dy) >= 2 * math.abs(dx) then
		sx = 0
	end
	if sx == 0 and sy == 0 then
		sy = 1 -- the same tile: south, as dirTo
	end
	return sx, sy
end

-- is `pos` in the sweep of a Samurai at `from` cutting along the step (sx, sy)?
function B.inSweep(from, sx, sy, pos, c)
	c = c or B.cfg.sweep
	if pos.z ~= from.z then
		return false
	end
	local dx, dy = pos.x - from.x, pos.y - from.y
	if dx == 0 and dy == 0 then
		return false
	end
	if sx ~= 0 and sy ~= 0 then -- diagonal: the quarter, within depth, the far corner left out
		local ax, ay = dx * sx, dy * sy
		return ax >= 0 and ay >= 0 and math.max(ax, ay) <= c.depth and ax + ay <= c.depth + 1
	end
	local along = dx * sx + dy * sy
	local across = math.abs(sx ~= 0 and dy or dx)
	return along >= 1 and along <= c.depth and across <= c.halfWidth
end

-- every tile of the sweep (offsets from the caster), for the effects and the tests
function B.sweepTiles(sx, sy, c)
	c = c or B.cfg.sweep
	local out = {}
	local o = {x = 0, y = 0, z = 0}
	for dy = -c.depth, c.depth do
		for dx = -c.depth, c.depth do
			if B.inSweep(o, sx, sy, {x = dx, y = dy, z = 0}, c) then
				out[#out + 1] = {x = dx, y = dy}
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------- the casts
-- (engine side: ChaosSpell from _common.lua)

-- Blade Flurry: the caster spins, every monster around it takes a melee weapon strike. `spin` is the effect name the
-- spell script sends at the caster (named there, so a class effect can stand in for it: chaos_class_fx.lua)
function B.flurry(player, spin)
	local pos = player:getPosition()
	local targets = ChaosSpell.enemiesAround(player, pos, B.cfg.flurry.radius)
	local min, max = B.flurryRange(player:getLevel(), ChaosSpell.bladePower(player), player:getVocation():getId())
	ChaosSpell.vfxOr(pos, spin, "aura_ring", CONST_ME_HITAREA)
	local hit = 0
	for _, t in ipairs(targets) do
		if ChaosSpell.weaponStrike(player, t, min, max, CONST_ME_DRAWBLOOD, ORIGIN_MELEE) ~= false then
			hit = hit + 1
		end
	end
	return hit
end

-- Iaido Sweep: the target (a player too, when it is the target) and every monster in the cut (x pack). `cut` is the directional
-- effect sent on the first tile of the cut, `fallback` the effect name when the pair has no directional one
function B.sweep(player, target, cut, fallback)
	local from, tpos = player:getPosition(), target:getPosition()
	local sx, sy = B.stepTowards(from, tpos)
	local c = B.cfg.sweep
	local targets = {target}
	for _, m in ipairs(ChaosSpell.enemiesAround(player, from, c.depth)) do
		if m ~= target and B.inSweep(from, sx, sy, m:getPosition(), c) then
			targets[#targets + 1] = m
		end
	end
	local min, max = B.sweepRange(player:getLevel(), ChaosSpell.bladePower(player))
	local dir = ChaosSpell.dirTo(from, tpos)
	local front = {x = from.x + sx, y = from.y + sy, z = from.z}
	if not ChaosSpell.vfxDir(front, cut, dir) then
		ChaosSpell.fx(front, fallback, CONST_ME_HITAREA)
	end
	local hit = 0
	for i, t in ipairs(targets) do
		local mn, mx = min, max
		if i > 1 then
			mn, mx = math.floor(min * c.pack), math.floor(max * c.pack)
		end
		if ChaosSpell.weaponStrike(player, t, mn, mx, CONST_ME_DRAWBLOOD, ORIGIN_MELEE) ~= false then
			hit = hit + 1
		end
	end
	return hit
end

return B
