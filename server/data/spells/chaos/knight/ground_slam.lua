-- Ground Slam: shockwave (5x5) that deals physical damage and staggers enemies (heavy slow for 3s).
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("ground_slam", CONST_ME_GROUNDSHAKER))
combat:setParameter(COMBAT_PARAM_BLOCKARMOR, true)
combat:setParameter(COMBAT_PARAM_USECHARGES, true)
combat:setArea(createCombatArea(AREA_CIRCLE2X2))

function onGetFormulaValues(player, skill, attack, factor)
	local min = (player:getLevel() / 5) + (skill * attack * 0.06) + 20
	local max = (player:getLevel() / 5) + (skill * attack * 0.12) + 35
	return -min, -max
end

function onGroundSlamTarget(creature, target)
	ChaosSpell.slow(target, 3000, 0.6)
	return true
end

combat:setCallback(CALLBACK_PARAM_SKILLVALUE, "onGetFormulaValues")
combat:setCallback(CALLBACK_PARAM_TARGETCREATURE, "onGroundSlamTarget")

function onCastSpell(creature, variant, isHotkey)
	if not creature:isPlayer() then
		return false
	end
	return combat:execute(creature, variant)
end
