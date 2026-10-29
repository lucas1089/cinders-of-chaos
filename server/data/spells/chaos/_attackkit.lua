-- Shared cast of the attack kit (the 37 attack spells that give every class line the same count; owner 2026-10-23,
-- docs/CLASSES.md "Attack spell parity"). Each kit spell script is three lines:
--   dofile('data/spells/scripts/chaos/_attackkit.lua')
--   function onCastSpell(creature, variant, isHotkey) return AttackKit.cast('<key>', creature, variant) end
-- Numbers: data/scripts/chaos/attack_kit_config.lua (checked against spells_chaos.xml and rotation_model.csv by
-- tests/attack_kit_test.lua). Rules (damage, shapes): data/scripts/chaos/attack_kit_core.lua.
--
-- The hit is dealt the way the class's own spells deal it: the Templar line through TemplarSpell.holyStrike (the
-- Judgement events see it), the Necromancer line through ChaosNecro.damage (Soul Hoard, curses), the Monk line through
-- the strike formula (Pressure Points, chi), the Thief line's blade and shuriken spells as weapon strikes (stealth
-- ambush, Poison Blades), everything else as ORIGIN_SPELL damage (the class spell factor applies).
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosAttackKitCore then
	dofile('data/scripts/chaos/attack_kit_core.lua')
end
if not (ChaosAttackKit and ChaosAttackKit.cfg) then
	dofile('data/scripts/chaos/attack_kit_config.lua')
end
if AttackKit then
	return
end

AttackKit = {}
local A = AttackKit
local K = ChaosAttackKitCore
A.dots = {}
local tokens = 0

local COMBAT = {
	physical = COMBAT_PHYSICALDAMAGE, holy = COMBAT_HOLYDAMAGE, earth = COMBAT_EARTHDAMAGE,
	energy = COMBAT_ENERGYDAMAGE, ice = COMBAT_ICEDAMAGE, death = COMBAT_DEATHDAMAGE, fire = COMBAT_FIREDAMAGE
}
local DEFAULT_HIT = {
	physical = "CONST_ME_HITAREA", holy = "CONST_ME_HOLYDAMAGE", earth = "CONST_ME_POISONAREA",
	energy = "CONST_ME_ENERGYHIT", ice = "CONST_ME_ICEATTACK", death = "CONST_ME_MORTAREA", fire = "CONST_ME_FIREATTACK"
}
local SHOT_FALLBACK = {
	physical = "CONST_ANI_ARROW", holy = "CONST_ANI_SMALLHOLY", earth = "CONST_ANI_POISON", energy = "CONST_ANI_ENERGY",
	ice = "CONST_ANI_SMALLICE", death = "CONST_ANI_DEATH", fire = "CONST_ANI_FIRE"
}

local function const(name, default)
	return (name and _G[name]) or (default and _G[default]) or CONST_ME_HITAREA
end

function A.spec(key)
	return ChaosAttackKit.cfg.spells[key]
end

-- ------------------------------------------------------------------------------------ class helpers on demand
local function loadSchool(spec)
	if spec.school == "templar" then
		dofile('data/spells/scripts/chaos/_templar.lua')
	elseif spec.school == "necro" then
		dofile('data/spells/scripts/chaos/_necro.lua')
	elseif spec.school == "monk" then
		dofile('data/spells/scripts/chaos/_monk.lua')
	end
end

-- skill x attack (or 0 for a magic spell) of the spell's power term
function A.power(player, spec)
	local p = spec.power
	if p == "melee" then
		return ChaosSpell.meleeSkillLevel(player) * ChaosSpell.meleeAttack(player)
	elseif p == "distance" then
		return player:getEffectiveSkillLevel(SKILL_DISTANCE) * ChaosSpell.distanceAttack(player)
	elseif p == "blade" then
		return ChaosSpell.bladePower(player)
	elseif p == "shuriken" then
		return ChaosSpell.shurikenPower(player)
	elseif p == "monk" then
		return MonkSpell.power(player)
	end
	return 0
end

-- The class factor of a line spell quest spell (quest_spell_scale_config.lua): the spell is shared by the base class and both
-- ascensions, whose best sets differ, so each class has its own factor that puts the gain of the spell in bounds (rotation_sim.py
-- --quest). 1 for every other spell and for a class the table does not list.
function A.classFactor(player, spec)
	if not spec.quest then
		return 1
	end
	if not ChaosQuestSpellScale then
		pcall(dofile, 'data/scripts/chaos/quest_spell_scale_config.lua')
	end
	local row = ChaosQuestSpellScale and ChaosQuestSpellScale[spec.name]
	local okVoc, voc = pcall(function() return player:getVocation():getName() end)
	local f = row and okVoc and row[voc]
	if type(f) == "table" then
		-- a curve {{level, factor}, ...}: flat below the first point, linear between, the last point's value above it
		local okLv, level = pcall(function() return player:getLevel() end)
		level = okLv and tonumber(level) or 0
		if level <= f[1][1] then
			return f[1][2]
		end
		for i = 2, #f do
			if level <= f[i][1] then
				local a, b = f[i - 1], f[i]
				return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
			end
		end
		return f[#f][2]
	end
	return f or 1
end

-- positive min, max of one hit (one tick of a DoT) for the caster; `chiScale` is the finisher scale of a Monk finisher
function A.values(player, spec, chiScale)
	local lo, hi = A.rawValues(player, spec, chiScale)
	local k = A.classFactor(player, spec)
	return lo * k, hi * k
end

function A.rawValues(player, spec, chiScale)
	local scale = spec.scale or 1
	if spec.school == "templar" then
		local lo, hi = TemplarSpell.values(player, spec.pMin, spec.pMax, spec.mMin, spec.mMax, spec.bMin, spec.bMax)
		return lo * scale, hi * scale
	elseif spec.school == "necro" then
		return ChaosNecro.values(player, {mlMin = spec.mMin, mlMax = spec.mMax, baseMin = spec.bMin, baseMax = spec.bMax,
			scale = scale})
	elseif spec.school == "monk" then
		return ChaosMonk.strikeValues(player:getLevel(), MonkSpell.power(player),
			{spec.pMin, spec.bMin, spec.pMax, spec.bMax}, scale * (chiScale or 1))
	end
	return K.range(spec, player:getLevel(), player:getMagicLevel(), A.power(player, spec))
end

-- ------------------------------------------------------------------------------------------------- the hit
function A.hit(player, target, spec, lo, hi, effect)
	if spec.school == "templar" then
		return TemplarSpell.holyStrike(player, target, lo, hi, effect)
	elseif spec.school == "necro" then
		return ChaosNecro.damage(player, target, COMBAT[spec.ctype], lo, hi, effect) > 0
	elseif spec.school == "blade" then
		return ChaosSpell.weaponStrike(player, target, lo, hi, effect, ORIGIN_MELEE)
	elseif spec.school == "shuriken" then
		return ChaosSpell.weaponStrike(player, target, lo, hi, effect, ORIGIN_RANGED)
	end
	if not ChaosSpell.canAttack(player, target) then
		return false
	end
	return doTargetCombat(player, target, COMBAT[spec.ctype], -math.floor(lo), -math.floor(hi), effect, ORIGIN_SPELL)
end

-- the creatures of a shape the caster may hit: monsters (never the caster's summons) and the players PvP allows
local function victims(player, spec, origin, dir, skipCentre, extra)
	local set = K.tileSet(spec, origin, dir, skipCentre)
	local radius = math.max(spec.radius or 0, spec.length or 0, spec.depth or 0, 1) + 1
	local list, seen = {}, {}
	for _, c in ipairs(ChaosSpell.spectators(origin, radius)) do
		local p = c:getPosition()
		if p.z == origin.z and set[p.x .. ":" .. p.y] and c ~= player then
			if ChaosSpell.isEnemy(player, c) or (c:isPlayer() and ChaosSpell.canAttack(player, c)) then
				list[#list + 1] = c
				seen[c:getId()] = true
			end
		end
	end
	if extra and not seen[extra:getId()] and ChaosSpell.canAttack(player, extra) then
		local p = extra:getPosition()
		if set[p.x .. ":" .. p.y] then
			list[#list + 1] = extra
		end
	end
	return list
end

-- ---------------------------------------------------------------------------------------------- the effects
local function shot(player, spec, toPos)
	local pname = spec.pshot -- a pair 41 / 42 missile (O239), by class where pshotBy names the class
	if spec.pshotBy then
		local okVoc, voc = pcall(function() return player:getVocation():getName() end)
		pname = okVoc and spec.pshotBy[voc] or pname
	end
	if pname then
		ChaosSpell.pshoot(player:getPosition(), toPos, pname, spec.shot, spec.shot, const(SHOT_FALLBACK[spec.ctype], "CONST_ANI_ARROW"))
	elseif spec.shot then
		ChaosSpell.vshoot(player:getPosition(), toPos, spec.shot, spec.shot, const(SHOT_FALLBACK[spec.ctype], "CONST_ANI_ARROW"))
	end
end

local function burst(pos, spec, dir, fxOnly)
	local fallback = const(DEFAULT_HIT[spec.ctype])
	if spec.fx then
		ChaosSpell.fx(pos, spec.fx, fallback)
	end
	if fxOnly then
		return
	end
	if spec.vfx and not ChaosSpell.vfx(pos, spec.vfx) and dir then
		ChaosSpell.vfxDir(pos, spec.vfx, dir)
	end
end

-- the second effect of an ultimate (vfx2) at the target tile (the caster's own tile for a self-centred one)
local function burst2(pos, spec)
	if spec.vfx2 then
		ChaosSpell.vfx(pos, spec.vfx2)
	end
end

-- Death Between Heartbeats: a hit on a target above critAbove.hp percent health is a critical hit (x critAbove.mult)
local function critMult(player, target, spec)
	local c = spec.critAbove
	if not c then
		return 1
	end
	local max = target:getMaxHealth()
	if max and max > 0 and target:getHealth() * 100 > max * c.hp then
		if ChaosCombatFx and ChaosCombatFx.crit then
			ChaosCombatFx.crit(target:getPosition(), player:getId())
		end
		return c.mult
	end
	return 1
end

-- ------------------------------------------------------------------------------------------- damage over time
local function startDot(player, target, key, spec, lo, hi, effect)
	if spec.school == "necro" then
		return NecroSpell.dot(player:getId(), target:getId(), key, spec.ticks, spec.tickMs, lo, hi, COMBAT[spec.ctype], effect)
	end
	tokens = tokens + 1
	local token = tokens
	local slot = key .. ":" .. player:getId() .. ":" .. target:getId()
	A.dots[slot] = token
	local casterId, targetId = player:getId(), target:getId()
	ChaosSpell.pulse(casterId, spec.ticks, spec.tickMs, function(caster, step)
		local host = Creature(targetId)
		if A.dots[slot] ~= token or not host or host:getHealth() <= 0 then
			A.dots[slot] = nil
			return false
		end
		A.hit(caster, host, spec, lo, hi, effect)
		if step >= spec.ticks then
			A.dots[slot] = nil
		end
		return true
	end)
	return true
end

-- ---------------------------------------------------------------------------------------------------- the cast
local function targetOrCancel(player, variant, spec)
	local target = ChaosSpell.targetOf(variant)
	if not target or target == player then
		ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
		return nil
	end
	if spec.melee and K.distance(player:getPosition(), target:getPosition()) ~= 1 then
		ChaosSpell.cancel(player, RETURNVALUE_TOOFARAWAY)
		return nil
	end
	if not ChaosSpell.canAttack(player, target) then
		ChaosSpell.cancel(player, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER)
		return nil
	end
	return target
end

function A.cast(key, creature, variant)
	local player = creature:getPlayer()
	local spec = A.spec(key)
	if not player or not spec then
		return false
	end
	loadSchool(spec)
	local effect = const(spec.hitFx, DEFAULT_HIT[spec.ctype])
	local pos = player:getPosition()

	-- a self-centred burst: no target needed
	if spec.shape == "around" then
		local chiScale
		if spec.finisher then
			local spent = MonkSpell.finisher(player)
			if not spent then
				return false
			end
			chiScale = ChaosMonk.finisherScale(spent)
		end
		local lo, hi = A.values(player, spec, chiScale)
		burst(pos, spec, nil)
		burst2(pos, spec)
		for _, c in ipairs(victims(player, spec, pos, nil, true)) do
			A.hit(player, c, spec, lo, hi, effect)
		end
		if spec.chi then
			ChaosMonk.addChi(player, spec.chi)
		end
		return true
	end

	local target = targetOrCancel(player, variant, spec)
	if not target then
		return false
	end
	local tpos = target:getPosition()
	local chiScale
	if spec.finisher then
		local spent = MonkSpell.finisher(player)
		if not spent then
			return false
		end
		chiScale = ChaosMonk.finisherScale(spent)
	end
	local lo, hi = A.values(player, spec, chiScale)
	local dir = K.dirTo(pos, tpos)
	if not spec.melee then
		shot(player, spec, tpos)
	end

	if spec.shape == "single" then
		burst(tpos, spec, dir)
		burst2(tpos, spec)
		local m = critMult(player, target, spec)
		A.hit(player, target, spec, lo * m, hi * m, effect)
	elseif spec.shape == "dot" then
		burst(tpos, spec, dir)
		startDot(player, target, key, spec, lo, hi, effect)
	elseif spec.shape == "circle" then
		burst(tpos, spec, dir)
		burst2(tpos, spec)
		for _, c in ipairs(victims(player, spec, tpos, nil, false, target)) do
			-- spec.main: the target at the centre takes a heavier hit than the rest of the circle (Hammer of Ember Dawn)
			local m = (spec.main and c == target) and spec.main or 1
			A.hit(player, c, spec, lo * m, hi * m, effect)
		end
	else -- wave, line: from the caster toward the target
		local first = true
		for _, t in ipairs(K.tiles(spec, pos, dir)) do
			local p = Position(t[1], t[2], pos.z)
			burst(p, spec, dir, not first)
			first = false
		end
		burst2(tpos, spec)
		for _, c in ipairs(victims(player, spec, pos, dir, false)) do
			A.hit(player, c, spec, lo, hi, effect)
		end
	end
	if spec.chi then
		ChaosMonk.addChi(player, spec.chi)
	end
	return true
end
