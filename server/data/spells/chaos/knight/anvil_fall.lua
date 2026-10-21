-- Anvil Fall: the Juggernaut brings its weapon down on the target (range 3): one crushing blow to everything in a 5x5
-- square around it, from weapon attack and skill; every enemy hit is stunned (90% slow) for 2.5 s.
-- 12 s cooldown (the cooldown ladder, 2026-10-20; was 20 s).
-- About 0.8 of Colossus Fall's damage on a smaller area, in one hit (docs/CLASSES.md "Spells by level").
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("ground_slam", CONST_ME_GROUNDSHAKER))
combat:setParameter(COMBAT_PARAM_BLOCKARMOR, true)
combat:setParameter(COMBAT_PARAM_USECHARGES, true)
combat:setArea(createCombatArea(AREA_CIRCLE2X2))

function onGetFormulaValues(player, skill, attack, factor)
	local min = ((player:getLevel() / 5) + (skill * attack * 0.085) + 40)
	local max = ((player:getLevel() / 5) + (skill * attack * 0.150) + 80)
	return -min, -max
end

function onAnvilFallTarget(creature, target)
	ChaosSpell.slow(target, 2500, 0.9)
	return true
end

combat:setCallback(CALLBACK_PARAM_SKILLVALUE, "onGetFormulaValues")
combat:setCallback(CALLBACK_PARAM_TARGETCREATURE, "onAnvilFallTarget")

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
	local tpos = target:getPosition()
	ChaosSpell.vfx(tpos, "earth_spikes")
	return combat:execute(player, Variant(tpos))
end
