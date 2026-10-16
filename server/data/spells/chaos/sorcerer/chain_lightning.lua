-- Forked Storm: hits the target, then jumps to up to 3 more monsters within 3 sqm (70% damage per jump).
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end
local M = ChaosMysticFx

local JUMPS = 3
local JUMP_RANGE = 3
local FALLOFF = 0.7

-- the hit lands when the orb arrives: lightning_hit (pair 27 storm_chain) on the first target, a bolt from the sky
-- (lightning_strike) on each jump; no extra tile effect then (server/data/spells/README_FX.md "Mystic line effects")
local function strike(casterId, fromPos, targetId, factor, min, max, jump)
	local caster = Creature(casterId)
	local target = Creature(targetId)
	if not caster or not target then
		return
	end
	local toPos = target:getPosition()
	ChaosSpell.vshoot(fromPos, toPos, "lightning_orb", "lightning_orb", CONST_ANI_ENERGY)
	local hitFx = Fx("chain_lightning", CONST_ME_ENERGYHIT)
	if M and M.known("lightning_hit") then
		local fly = M.flightMs(fromPos, toPos)
		if (jump or 0) > 0 and M.known("lightning_strike") then
			M.later(fly, toPos, "lightning_strike")
		else
			local p = {x = toPos.x, y = toPos.y, z = toPos.z}
			addEvent(function() ChaosSpell.vfx(p, "lightning_hit") end, math.max(1, fly))
		end
		hitFx = CONST_ME_NONE
	else
		ChaosSpell.vfx(toPos, "lightning_hit")
	end
	ChaosSpell.damageTarget(caster, target, COMBAT_ENERGYDAMAGE, min * factor, max * factor, hitFx)
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
	if not ChaosSpell.canAttack(player, first) then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER)
	end

	local min, max = ChaosSpell.mlValues(player, 2.85, 4.85, 28, 55, 1.2)
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
		addEvent(strike, 160 * jump, casterId, cpos, best:getId(), factor, min, max, jump)
		current = best
	end
	return true
end
