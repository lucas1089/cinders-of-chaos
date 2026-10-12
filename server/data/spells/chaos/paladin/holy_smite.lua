-- Dawnpiercer: single target holy bolt, the paladin's filler. Scales with distance skill x weapon attack (the bow's own).
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_HOLYDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("holy_smite", CONST_ME_HOLYDAMAGE))
-- with the animated missiles (data/lib/chaos_vfx.lua) the spear is shot by onCastSpell instead
combat:setParameter(COMBAT_PARAM_DISTANCEEFFECT, ChaosVfxMissile and CONST_ANI_NONE or FxMissile("holy_arrow", CONST_ANI_HOLY))

function onGetFormulaValues(player, level, magicLevel)
	local power = player:getEffectiveSkillLevel(SKILL_DISTANCE) * ChaosSpell.distanceAttack(player)
	local min = (level / 5) + (power * 0.042) + (magicLevel * 1.0) + 20
	local max = (level / 5) + (power * 0.065) + (magicLevel * 1.6) + 40
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
	if target and ChaosVfxMissile then
		VfxShoot(creature:getPosition(), target:getPosition(), "holy_spear")
		ChaosSpell.vfx(target:getPosition(), "holy_hit")
	end
	return true
end
