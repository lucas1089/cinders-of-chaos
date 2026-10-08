-- Shared helpers for the Chaos spells.
-- Loaded by every chaos spell with: dofile('data/spells/scripts/chaos/_common.lua')
-- (path is relative to the server working dir, same convention as the rest of data/).
if not Fx or not FxMissile then
	pcall(dofile, 'data/lib/chaos_fx.lua') -- real ids, once the merged dat/spr is in use
	if not Fx or not FxMissile then
		dofile('data/spells/scripts/chaos/_fx_fallback.lua')
	end
end
-- the spells use a few names the effect catalog spells differently
if ChaosFx then
	ChaosFx.aura_ring = ChaosFx.aura_ring or ChaosFx.arcane_aura
	ChaosFx.poison_cloud = ChaosFx.poison_cloud or ChaosFx.poison_burst
end
if ChaosFxMissile then
	ChaosFxMissile.holy_arrow = ChaosFxMissile.holy_arrow or ChaosFxMissile.holy_bolt
end
if ChaosSpell then
	return
end

ChaosSpell = {}

local DIR_STEP = {
	[NORTH] = {0, -1}, [EAST] = {1, 0}, [SOUTH] = {0, 1}, [WEST] = {-1, 0},
	[NORTHEAST] = {1, -1}, [SOUTHEAST] = {1, 1}, [SOUTHWEST] = {-1, 1}, [NORTHWEST] = {-1, -1},
}

function ChaosSpell.cancel(creature, message)
	if message then
		creature:sendCancelMessage(message)
	else
		creature:sendCancelMessage(RETURNVALUE_NOTPOSSIBLE)
	end
	creature:getPosition():sendMagicEffect(CONST_ME_POFF)
	return false
end

function ChaosSpell.fx(pos, name, fallback)
	Position(pos):sendMagicEffect(Fx(name, fallback))
end

function ChaosSpell.shoot(fromPos, toPos, name, fallback)
	Position(fromPos):sendDistanceEffect(Position(toPos), FxMissile(name, fallback))
end

-- Damage helper: returns positive min, max from the usual TFS level/magic-level formula.
function ChaosSpell.mlValues(player, mlMin, mlMax, baseMin, baseMax)
	local l = player:getLevel() / 5
	local m = player:getMagicLevel()
	return l + m * mlMin + baseMin, l + m * mlMax + baseMax
end

-- Damage helper for skill based spells (melee / distance).
function ChaosSpell.skillValues(player, skillId, mult, baseMin, baseMax)
	local s = player:getEffectiveSkillLevel(skillId)
	local l = player:getLevel() / 5
	return l + s * mult * 0.6 + baseMin, l + s * mult + baseMax
end

function ChaosSpell.bestMeleeSkill(player)
	local best = SKILL_SWORD
	local bestValue = -1
	for _, id in ipairs({SKILL_SWORD, SKILL_CLUB, SKILL_AXE}) do
		local v = player:getEffectiveSkillLevel(id)
		if v > bestValue then
			best, bestValue = id, v
		end
	end
	return best
end

function ChaosSpell.spectators(pos, radius, onlyPlayers)
	return Game.getSpectators(Position(pos), false, onlyPlayers or false, radius, radius, radius, radius) or {}
end

-- A monster the caster may hit with manually looped spells (never the caster's own summons).
function ChaosSpell.isEnemy(caster, target)
	if not target or target == caster or not target:isMonster() then
		return false
	end
	local master = target:getMaster()
	if master and (master == caster or master:isPlayer()) then
		return false
	end
	local tile = target:getTile()
	if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		return false
	end
	return true
end

function ChaosSpell.enemiesAround(caster, pos, radius)
	local list = {}
	for _, c in ipairs(ChaosSpell.spectators(pos, radius)) do
		if ChaosSpell.isEnemy(caster, c) then
			list[#list + 1] = c
		end
	end
	return list
end

-- Caster + party members (+ caster's summons when includeSummons) around pos.
function ChaosSpell.alliesAround(caster, pos, radius, includeSummons)
	local list = {}
	local party = caster:isPlayer() and caster:getParty() or nil
	for _, c in ipairs(ChaosSpell.spectators(pos, radius)) do
		if c == caster then
			list[#list + 1] = c
		elseif c:isPlayer() then
			if party and c:getParty() == party then
				list[#list + 1] = c
			end
		elseif includeSummons then
			local master = c:getMaster()
			if master and master == caster then
				list[#list + 1] = c
			end
		end
	end
	return list
end

-- Target of a "needtarget" spell. Variants are tables ({number=...}) or userdata depending on build.
function ChaosSpell.targetOf(variant)
	local id
	if type(variant) == 'table' or type(variant) == 'userdata' then
		id = variant.number
		if not id and variant.getNumber then
			id = variant:getNumber()
		end
	elseif type(variant) == 'number' then
		id = variant
	end
	if id and id ~= 0 then
		return Creature(id)
	end
	return nil
end

function ChaosSpell.stepPos(pos, direction, steps)
	local d = DIR_STEP[direction] or {0, 0}
	steps = steps or 1
	return Position(pos.x + d[1] * steps, pos.y + d[2] * steps, pos.z)
end

-- Free to stand on: ground, nothing solid, no creature, no floor change, not protection zone.
function ChaosSpell.isFreeTile(pos)
	local tile = Tile(pos)
	if not tile or not tile:getGround() then
		return false
	end
	if tile:hasFlag(TILESTATE_BLOCKSOLID) or tile:hasFlag(TILESTATE_PROTECTIONZONE)
		or tile:hasFlag(TILESTATE_FLOORCHANGE) or tile:hasFlag(TILESTATE_TELEPORT)
		or tile:hasFlag(TILESTATE_MAGICFIELD) then
		return false
	end
	if tile:getTopCreature() then
		return false
	end
	return true
end

-- Free tiles around center, ordered by distance to ref (ascending). Set far=true for descending.
function ChaosSpell.freeAround(center, ref, far)
	local list = {}
	for dx = -1, 1 do
		for dy = -1, 1 do
			if dx ~= 0 or dy ~= 0 then
				local p = Position(center.x + dx, center.y + dy, center.z)
				if ChaosSpell.isFreeTile(p) then
					local dist = (p.x - ref.x) ^ 2 + (p.y - ref.y) ^ 2
					list[#list + 1] = {pos = p, dist = dist}
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if far then return a.dist > b.dist end
		return a.dist < b.dist
	end)
	return list
end

-- Run fn(caster, step) now and then every `interval` ms until `count` runs were made.
-- Stops when the caster is gone/dead or fn returns false.
function ChaosSpell.pulse(casterId, count, interval, fn, step)
	step = step or 1
	local caster = Creature(casterId)
	if not caster or caster:getHealth() <= 0 then
		return
	end
	if fn(caster, step) == false then
		return
	end
	if step < count then
		addEvent(ChaosSpell.pulse, interval, casterId, count, interval, fn, step + 1)
	end
end

-- Remove a creature later (summons / clones).
function ChaosSpell.removeLater(creatureId)
	local c = Creature(creatureId)
	if c then
		c:getPosition():sendMagicEffect(CONST_ME_POFF)
		c:remove()
	end
end

-- Slow a creature: ticks ms, percent 0..1 of speed removed.
function ChaosSpell.slow(target, ticks, percent)
	local c = Condition(CONDITION_PARALYZE)
	c:setParameter(CONDITION_PARAM_TICKS, ticks)
	c:setFormula(-percent, 0, -percent, 0)
	target:addCondition(c)
end

function ChaosSpell.damageTarget(caster, target, ctype, min, max, effect)
	doTargetCombat(caster, target, ctype, -math.floor(min), -math.floor(max), effect)
end

function ChaosSpell.healTarget(caster, target, min, max, effect)
	doTargetCombat(caster, target, COMBAT_HEALING, math.floor(min), math.floor(max), effect)
end

-- Distinct condition sub ids so several chaos buffs can run together.
ChaosSpell.SUBID = {
	blood_pact = 71001, crimson_fury = 71002, rally = 71003, barkskin = 71004,
	divine_ward = 71005, soul_aegis = 71006, phantom_veil = 71007, dash = 71008, iron_will = 71009,
}
