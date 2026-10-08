-- Holy Smite: single target holy bolt, the paladin's filler. Scales mostly with distance skill.
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_HOLYDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("holy_smite", CONST_ME_HOLYDAMAGE))
combat:setParameter(COMBAT_PARAM_DISTANCEEFFECT, FxMissile("holy_arrow", CONST_ANI_HOLY))

function onGetFormulaValues(player, level, magicLevel)
	local dist = player:getEffectiveSkillLevel(SKILL_DISTANCE)
	local min = (level / 5) + (dist * 3.2) + (magicLevel * 1.0) + 20
	local max = (level / 5) + (dist * 5.0) + (magicLevel * 1.6) + 40
	return -min, -max
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")

function onCastSpell(creature, variant, isHotkey)
	if not creature:isPlayer() then
		return false
	end
	return combat:execute(creature, variant)
end
