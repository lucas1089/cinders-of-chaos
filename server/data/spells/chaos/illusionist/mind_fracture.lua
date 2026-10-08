-- Shattered Psyche: death damage bolt, then a cursing damage-over-time and a short slow.
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_DEATHDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("arcane_circle", CONST_ME_MORTAREA))
combat:setParameter(COMBAT_PARAM_DISTANCEEFFECT, FxMissile("arcane_orb", CONST_ANI_DEATH))

function onGetFormulaValues(player, level, magicLevel)
	local min = (level / 5) + (magicLevel * 5.7) + 55
	local max = (level / 5) + (magicLevel * 9.7) + 100
	return -min, -max
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")

function onCastSpell(creature, variant, isHotkey)
	if not creature:isPlayer() then
		return false
	end
	if not combat:execute(creature, variant) then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	if target and target ~= creature then
		local dmg = math.max(3, math.floor(creature:getMagicLevel() * 0.3) + 4)
		creature:addDamageCondition(target, CONDITION_CURSED, DAMAGELIST_EXPONENTIAL_DAMAGE, dmg)
		ChaosSpell.slow(target, 2500, 0.3)
	end
	return true
end
