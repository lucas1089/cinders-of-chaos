-- Witchfire Bolt: single target fire bolt that leaves the target burning.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end
local M = ChaosMysticFx

local HIT = Fx("fire_nova", CONST_ME_FIREAREA)
local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_FIREDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, HIT)
-- with the animated missiles (data/lib/chaos_vfx.lua) the bolt is shot by onCastSpell instead
combat:setParameter(COMBAT_PARAM_DISTANCEEFFECT, ChaosVfxMissile and CONST_ANI_NONE or FxMissile("fire_bolt", CONST_ANI_FIRE))

function onGetFormulaValues(player, level, magicLevel)
	local min = ((level / 5) + (magicLevel * 3.0) + 15) * 1.2
	local max = ((level / 5) + (magicLevel * 5.0) + 30) * 1.2
	return -min, -max
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")

function onCastSpell(creature, variant, isHotkey)
	if not creature:isPlayer() then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	-- the impact lands when the fireball arrives (it went out with the cast before): the pack fire_explosion then,
	-- no tile effect at the cast (server/data/spells/README_FX.md "Mystic line effects")
	local delayed = target ~= nil and ChaosVfxMissile ~= nil and M ~= nil and M.known("fire_explosion")
	combat:setParameter(COMBAT_PARAM_EFFECT, delayed and CONST_ME_NONE or HIT)
	if not combat:execute(creature, variant) then
		return false
	end
	if target and ChaosVfxMissile then
		local from, to = creature:getPosition(), target:getPosition()
		VfxShoot(from, to, "fireball")
		if delayed then
			M.later(M.flightMs(from, to), to, "fire_explosion")
		else
			ChaosSpell.vfx(to, "fireball_hit")
		end
	end
	if target and target ~= creature then
		local dmg = math.max(2, math.floor(creature:getMagicLevel() * 0.15) + 3)
		creature:addDamageCondition(target, CONDITION_FIRE, DAMAGELIST_VARYING_PERIOD, dmg, {10, 12}, 4)
	end
	return true
end
