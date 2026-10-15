-- Pack tools (2026-10-15, owner: the classes that needed a large pack cleave get real area tools of their lore
-- instead, and a small cleave): Palm Shockwave (194, the Monk line), Shadow Ricochet (195, Shadowfist), Iron Chain
-- (196, Iron Sage), Bone Shrapnel (197, Necromancer), Sanctified Ground (137, Templar), Shield Wave (170, Sentinel),
-- Fan of Knives (136, Thief). Numbers: T.cfg below; spells and balance: server/data/spells/README.md "Pack farming for
-- every class"; read by server/tools/rotation_sim.py (the scales, the text form of _blades.lua).
--
-- One rule for all seven: the spell's target takes what the class's filler deals (Ashen Fist, Bone Spear, Radiant
-- Smite, Shuriken Toss), so a lone target (a boss) takes no more than before; every other monster the spell reaches
-- takes `pack` x that. Players never take the pack share: a player is hit only as the spell's target, or (the area
-- ones) with the plain hit and the usual PvP rules (ChaosSpell.canAttack). The pure parts (ranges, the jump, fan and
-- area targets, the hit of each target) need no engine. Lua 5.1 / LuaJIT / 5.3.

if ChaosPackTools then
	return
end
ChaosPackTools = {}
local T = ChaosPackTools

T.cfg = {
	-- Palm Shockwave: an open palm on the target next to the Monk (an Ashen Fist: its formula, +2 chi) and a shockwave
	-- from it through every monster within `radius` sqm of the target
	shockwave = {
		radius = 2, chi = 2,
		formula = {0.04, 20, 0.07, 40},
		pack = 2.0,
	},
	-- Shadow Ricochet: a strike on the target (an Ashen Fist, +2 chi) that jumps on to `jumps` more monsters, each
	-- within `reach` sqm of the one before (nearest first, none twice)
	ricochet = {
		jumps = 4, reach = 3, chi = 2,
		formula = {0.04, 20, 0.07, 40},
		pack = 2.5,
	},
	-- Iron Chain: a chain of iron on the target (an Ashen Fist, +2 chi) that links on to `links` more monsters within
	-- `reach` sqm of the one before
	chain = {
		links = 4, reach = 2, chi = 2,
		formula = {0.04, 20, 0.07, 40},
		pack = 2.0,
	},
	-- Bone Shrapnel: a Bone Spear's hit on the target, then its bones burst: every monster within `radius` sqm of it
	-- (ChaosNecro.values: level / 5 + magic level x mlMin..mlMax + baseMin..baseMax)
	shrapnel = {
		radius = 1,
		f = {mlMin = 1.6, mlMax = 2.6, baseMin = 20, baseMax = 40},
		pack = 2.5,
	},
	-- Sanctified Ground: `pulses` pulses of holy light `intervalMs` apart on the cast tile; the Templar's target takes a
	-- Radiant Smite over them (Smite's numbers x the Templar's Smite scale / pulses), every other creature within
	-- `radius` sqm `pack` x that
	sanctified = {
		radius = 2, pulses = 3, intervalMs = 1000,
		values = {0.10, 0.16, 1.0, 1.5, 30, 60},
		scale = 0.1867,
		pack = 2.5,
	},
	-- Shield Wave: a Radiant Smite of holy force on the target (Smite's numbers x the Sentinel's Smite scale) and on
	-- every creature in `depth` rows of 2 x halfWidth + 1 tiles in front, towards the target (ChaosBlades.inSweep)
	shieldWave = {
		depth = 3, halfWidth = 1,
		values = {0.10, 0.16, 1.0, 1.5, 30, 60},
		scale = 0.56,
		pack = 2.0,
	},
	-- Fan of Knives: a Shuriken Toss of the Thief (its formula x 1.33) on the target and on up to `extra` more monsters
	-- within `reach` sqm of the Thief (nearest first)
	fan = {
		extra = 5, reach = 4,
		minK = 0.050, minBase = 20, maxK = 0.080, maxBase = 40,
		scale = 1.33,
		pack = 1.0,
	},
}

local floor = math.floor

local function num(v, d)
	v = tonumber(v)
	return v == nil and d or v
end

local function dist(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end
T.dist = dist

-- a (min, max) pair: (level / 5 + power x a + b) x scale, (level / 5 + power x c + d) x scale
function T.strikeRange(level, power, f, scale)
	local l = num(level, 0) / 5
	local p, s = num(power, 0), num(scale, 1)
	return floor((l + p * f[1] + f[2]) * s), floor((l + p * f[3] + f[4]) * s)
end

-- the hit of one creature: the spell's target and every player the plain hit, a pack monster `pack` x it
function T.hitFor(min, max, pack, isTarget, isPlayer)
	if isTarget or isPlayer then
		return min, max
	end
	return floor(min * pack), floor(max * pack)
end

-- the jumps of a ricochet or a chain: from `first` ({id, pos}), up to n more of `cands` ({id, pos} entries), each the
-- nearest not yet hit within `reach` of the one before (ties by id)
function T.jumpTargets(first, cands, n, reach)
	local out, used = {}, {}
	local at = first.pos
	used[first.id] = true
	for _ = 1, n do
		local best, bestD
		for _, c in ipairs(cands) do
			if not used[c.id] and c.pos.z == at.z then
				local d = dist(c.pos, at)
				if d <= reach and (not best or d < bestD or (d == bestD and c.id < best.id)) then
					best, bestD = c, d
				end
			end
		end
		if not best then
			break
		end
		used[best.id] = true
		out[#out + 1] = best
		at = best.pos
	end
	return out
end

-- up to n of `cands` within `reach` of `from`, nearest first (ties by id), never `skipId`
function T.nearest(from, cands, n, reach, skipId)
	local list = {}
	for _, c in ipairs(cands) do
		if c.id ~= skipId and c.pos.z == from.z and dist(c.pos, from) <= reach then
			list[#list + 1] = c
		end
	end
	table.sort(list, function(a, b)
		local da, db = dist(a.pos, from), dist(b.pos, from)
		if da ~= db then
			return da < db
		end
		return a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(n, #list) do
		out[i] = list[i]
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------- engine side
-- (ChaosSpell from _common.lua; MonkSpell / ChaosMonk, ChaosNecro / NecroSpell, TemplarSpell and ChaosBlades loaded by
-- the spell scripts)

-- monsters a player may hit (ChaosSpell.isEnemy: no player, no player's summon) around pos, as {id, pos, c}
local function monsters(player, pos, radius, skip)
	local out = {}
	for _, m in ipairs(ChaosSpell.enemiesAround(player, pos, radius)) do
		if m ~= skip then
			out[#out + 1] = {id = m:getId(), pos = m:getPosition(), c = m}
		end
	end
	return out
end

-- creatures (monsters and the players the PvP rules allow) around pos, for the area tools
local function areaCreatures(player, pos, radius, skip)
	local out = {}
	for _, s in ipairs(ChaosSpell.spectators(pos, radius)) do
		if s ~= skip and s ~= player
				and (ChaosSpell.isEnemy(player, s) or (s:isPlayer() and ChaosSpell.canAttack(player, s))) then
			out[#out + 1] = s
		end
	end
	return out
end

local function isPlayer(c)
	return c.isPlayer ~= nil and c:isPlayer() or false
end

-- Monk strikes on the target and its pack (+chi once)
local function monkHits(player, list, c, missile, missileFallback, hit, hitFallback)
	local min, max = MonkSpell.values(player, c.formula, 1)
	local from = player:getPosition()
	for i, t in ipairs(list) do
		local to = t:getPosition()
		if missile then
			ChaosSpell.shoot(from, to, missile, missileFallback)
			from = to
		end
		if hit then
			ChaosSpell.fx(to, hit, hitFallback)
		end
		if ChaosSpell.canAttack(player, t) then
			local mn, mx = T.hitFor(min, max, c.pack, i == 1, isPlayer(t))
			doTargetCombat(player, t, COMBAT_PHYSICALDAMAGE, -mn, -mx, CONST_ME_HITAREA, ORIGIN_SPELL)
		end
	end
	ChaosMonk.addChi(player, c.chi)
	return #list
end

-- Palm Shockwave: the target (next to the Monk) and the monsters within radius of it
function T.shockwave(player, target, burst)
	local c = T.cfg.shockwave
	local tpos = target:getPosition()
	local list = {target}
	for _, e in ipairs(monsters(player, tpos, c.radius, target)) do
		list[#list + 1] = e.c
	end
	ChaosSpell.vfxOr(tpos, burst, "shockwave", CONST_ME_GROUNDSHAKER)
	return monkHits(player, list, c)
end

-- Shadow Ricochet ("ricochet") / Iron Chain ("chain"): the target and its jumps
function T.jumpStrike(player, target, key, missile, missileFallback, hit, hitFallback)
	local c = T.cfg[key]
	local n = c.jumps or c.links
	local tpos = target:getPosition()
	local list = {target}
	local cands = monsters(player, tpos, n * c.reach, target)
	for _, e in ipairs(T.jumpTargets({id = target:getId(), pos = tpos}, cands, n, c.reach)) do
		list[#list + 1] = e.c
	end
	return monkHits(player, list, c, missile, missileFallback, hit, hitFallback)
end

-- Bone Shrapnel: the target, then the monsters within radius of it
function T.shrapnel(player, target, burst)
	local c = T.cfg.shrapnel
	local L = ChaosNecro
	local min, max = L.values(player, c.f)
	local tpos = target:getPosition()
	ChaosSpell.vshoot(player:getPosition(), tpos, "bone_spear", "bone_spear", CONST_ANI_ETHEREALSPEAR)
	NecroSpell.fx(tpos, {burst, "bone_spear"}, "necro_skull", CONST_ME_MORTAREA)
	local n = 0
	if L.damage(player, target, COMBAT_PHYSICALDAMAGE, min, max, CONST_ME_HITAREA, ORIGIN_SPELL) > 0 then
		n = 1
	end
	local mn, mx = T.hitFor(min, max, c.pack, false, false)
	for _, e in ipairs(monsters(player, tpos, c.radius, target)) do
		if L.damage(player, e.c, COMBAT_PHYSICALDAMAGE, mn, mx, CONST_ME_HITAREA, ORIGIN_SPELL) > 0 then
			n = n + 1
		end
	end
	return n
end

-- holy hits of the Templar line (the spell's target takes the plain hit, the pack `pack` x it)
local function holyHits(player, list, min, max, pack, target)
	local n = 0
	for _, t in ipairs(list) do
		if ChaosSpell.canAttack(player, t) then
			local mn, mx = T.hitFor(min, max, pack, t == target, isPlayer(t))
			t:registerEvent("ChaosTemplarCombat")
			doTargetCombat(player, t, COMBAT_HOLYDAMAGE, -mn, -mx, CONST_ME_HOLYDAMAGE, ORIGIN_SPELL)
			n = n + 1
		end
	end
	return n
end

local function templarValues(player, c)
	local v = c.values
	local min, max = TemplarSpell.values(player, v[1], v[2], v[3], v[4], v[5], v[6])
	return floor(min * c.scale), floor(max * c.scale)
end

-- Sanctified Ground: pulses on the cast tile; the Templar's attack target is the spell's "target"
function T.sanctified(player, seal)
	local c = T.cfg.sanctified
	local min, max = templarValues(player, c)
	local p = player:getPosition()
	local center = {x = p.x, y = p.y, z = p.z}
	ChaosSpell.pulse(player:getId(), c.pulses, c.intervalMs, function(caster, step)
		local pos = Position(center)
		if step == 1 then
			ChaosSpell.vfxOr(pos, seal, "holy_cross", CONST_ME_HOLYAREA)
		end
		holyHits(caster, areaCreatures(caster, pos, c.radius), min, max, c.pack, caster:getTarget())
		return true
	end)
	return true
end

-- Shield Wave: the target and every creature in the wave in front
function T.shieldWave(player, target, wave)
	local c = T.cfg.shieldWave
	local min, max = templarValues(player, c)
	local from = player:getPosition()
	local sx, sy = ChaosBlades.stepTowards(from, target:getPosition())
	local list = {target}
	for _, s in ipairs(areaCreatures(player, from, c.depth, target)) do
		if ChaosBlades.inSweep(from, sx, sy, s:getPosition(), c) then
			list[#list + 1] = s
		end
	end
	ChaosSpell.vfxOr({x = from.x + sx, y = from.y + sy, z = from.z}, wave, "holy_spiral", CONST_ME_HOLYAREA)
	return holyHits(player, list, min, max, c.pack, target)
end

-- Fan of Knives (ranged weapon strikes, ChaosSpell.shurikenPower)
function T.fan(player, target, knife)
	local c = T.cfg.fan
	local from = player:getPosition()
	local list = {target}
	for _, e in ipairs(T.nearest(from, monsters(player, from, c.reach, target), c.extra, c.reach, target:getId())) do
		list[#list + 1] = e.c
	end
	local power = ChaosSpell.shurikenPower(player)
	local l = player:getLevel() / 5
	local min, max = (l + power * c.minK + c.minBase) * c.scale, (l + power * c.maxK + c.maxBase) * c.scale
	for i, t in ipairs(list) do
		local mn, mx = T.hitFor(min, max, c.pack, i == 1, false)
		ChaosSpell.vshoot(from, t:getPosition(), knife, "knife", CONST_ANI_THROWINGKNIFE)
		ChaosSpell.weaponStrike(player, t, mn, mx, CONST_ME_DRAWBLOOD, ORIGIN_RANGED)
	end
	return #list
end

return T
