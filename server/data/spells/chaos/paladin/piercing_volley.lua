-- Skewering Line: a 7 sqm line of spears hitting everything in it. Scales with distance skill x weapon attack.
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("blood_splash", CONST_ME_HITAREA))
combat:setParameter(COMBAT_PARAM_BLOCKARMOR, true)
combat:setArea(createCombatArea(AREA_BEAM7))

function onGetFormulaValues(player, skill, attack, factor)
	local power = player:getEffectiveSkillLevel(SKILL_DISTANCE) * ChaosSpell.distanceAttack(player)
	local min = (player:getLevel() / 5) + (power * 0.0195) + 20
	local max = (player:getLevel() / 5) + (power * 0.0325) + 40
	return -min, -max
end

combat:setCallback(CALLBACK_PARAM_SKILLVALUE, "onGetFormulaValues")

function onCastSpell(creature, variant, isHotkey)
	if not creature:isPlayer() then
		return false
	end
	local from = creature:getPosition()
	local dir = creature:getDirection()
	for i = 2, 6, 2 do
		ChaosSpell.shoot(from, ChaosSpell.stepPos(from, dir, i), "blood_spear", CONST_ANI_SPEAR)
	end
	ChaosSpell.vfxDir(from, "thrust", dir)
	return combat:execute(creature, variant)
end
