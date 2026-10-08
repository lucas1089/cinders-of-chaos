-- Vaulting Cleave: jump next to the target (range 5) and strike it with weapon attack and skill.
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("ground_slam", CONST_ME_HITAREA))
combat:setParameter(COMBAT_PARAM_BLOCKARMOR, true)
combat:setParameter(COMBAT_PARAM_USECHARGES, true)

function onGetFormulaValues(player, skill, attack, factor)
	local min = (player:getLevel() / 5) + (skill * attack * 0.047) + 17
	local max = (player:getLevel() / 5) + (skill * attack * 0.093) + 33
	return -min, -max
end

combat:setCallback(CALLBACK_PARAM_SKILLVALUE, "onGetFormulaValues")

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	if not target or target == player then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
	end
	if not ChaosSpell.canAttack(player, target) then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER)
	end
	local from = player:getPosition()
	local tpos = target:getPosition()
	if math.max(math.abs(from.x - tpos.x), math.abs(from.y - tpos.y)) > 1 then
		local spots = ChaosSpell.freeAround(tpos, from)
		if #spots == 0 then
			return ChaosSpell.cancel(player, RETURNVALUE_NOTENOUGHROOM)
		end
		from:sendMagicEffect(CONST_ME_POFF)
		player:teleportTo(spots[1].pos)
		ChaosSpell.fx(spots[1].pos, "ground_slam", CONST_ME_GROUNDSHAKER)
	end
	return combat:execute(player, variant)
end
