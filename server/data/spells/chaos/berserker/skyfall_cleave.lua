-- Skyfall Cleave: leap next to the target (range 5) and bring the two-handed weapon down on it: physical damage to
-- everything in a 3x3 square around the target, from weapon attack and skill (the knight spells' formula style).
--
-- The Berserker's leaping slam. Every hit gets Rage (data/scripts/chaos/berserker_combat.lua), and the slam staggers
-- (30% slow, 2 s).
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("ground_slam", CONST_ME_GROUNDSHAKER))
combat:setParameter(COMBAT_PARAM_BLOCKARMOR, true)
combat:setParameter(COMBAT_PARAM_USECHARGES, true)
combat:setArea(createCombatArea(AREA_SQUARE1X1))

function onGetFormulaValues(player, skill, attack, factor)
	local min = ((player:getLevel() / 5) + (skill * attack * 0.060) + 20) * 0.7
	local max = ((player:getLevel() / 5) + (skill * attack * 0.105) + 40) * 0.7
	return -min, -max
end

function onSkyfallTarget(creature, target)
	ChaosSpell.slow(target, 2000, 0.3)
	return true
end

combat:setCallback(CALLBACK_PARAM_SKILLVALUE, "onGetFormulaValues")
combat:setCallback(CALLBACK_PARAM_TARGETCREATURE, "onSkyfallTarget")

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
		ChaosSpell.shoot(from, spots[1].pos, "blood_spear", CONST_ANI_WHIRLWINDAXE)
	end
	return combat:execute(player, Variant(tpos))
end
