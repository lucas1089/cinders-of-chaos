-- Holy Smite: single target holy bolt, scales with level, magic level and distance skill.
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_HOLYDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("holy_smite", CONST_ME_HOLYDAMAGE))
combat:setParameter(COMBAT_PARAM_DISTANCEEFFECT, FxMissile("holy_arrow", CONST_ANI_HOLY))

function onGetFormulaValues(player, level, magicLevel)
	local dist = player:getEffectiveSkillLevel(SKILL_DISTANCE)
	local min = (level / 5) + (magicLevel * 1.8) + (dist * 0.25) + 18
	local max = (level / 5) + (magicLevel * 3.0) + (dist * 0.45) + 35
	return -min, -max
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")

function onCastSpell(creature, variant, isHotkey)
	if not creature:isPlayer() then
		return false
	end
	return combat:execute(creature, variant)
end
