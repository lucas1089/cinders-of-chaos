-- Chain Lightning: hits the target, then jumps to up to 3 more monsters within 3 sqm (70% damage per jump).
dofile('data/spells/scripts/chaos/_common.lua')

local JUMPS = 3
local JUMP_RANGE = 3
local FALLOFF = 0.7

local function strike(casterId, fromPos, targetId, factor, min, max)
	local caster = Creature(casterId)
	local target = Creature(targetId)
	if not caster or not target then
		return
	end
	local toPos = target:getPosition()
	ChaosSpell.shoot(fromPos, toPos, "lightning_orb", CONST_ANI_ENERGY)
	ChaosSpell.damageTarget(caster, target, COMBAT_ENERGYDAMAGE, min * factor, max * factor,
		Fx("chain_lightning", CONST_ME_ENERGYHIT))
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local first = ChaosSpell.targetOf(variant)
	if not first or first == player then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
	end

	local min, max = ChaosSpell.mlValues(player, 2.6, 4.4, 25, 50)
	local casterId = player:getId()
	strike(casterId, player:getPosition(), first:getId(), 1, min, max)

	local hit = {[first:getId()] = true}
	local current = first
	local factor = 1
	for jump = 1, JUMPS do
		local best, bestDist
		local cpos = current:getPosition()
		for _, c in ipairs(ChaosSpell.enemiesAround(player, cpos, JUMP_RANGE)) do
			if not hit[c:getId()] then
				local p = c:getPosition()
				local dist = math.max(math.abs(p.x - cpos.x), math.abs(p.y - cpos.y))
				if not bestDist or dist < bestDist then
					best, bestDist = c, dist
				end
			end
		end
		if not best then
			break
		end
		hit[best:getId()] = true
		factor = factor * FALLOFF
		addEvent(strike, 160 * jump, casterId, cpos, best:getId(), factor, min, max)
		current = best
	end
	return true
end
