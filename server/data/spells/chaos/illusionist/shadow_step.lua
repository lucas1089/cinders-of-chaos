-- Umbral Stride: teleport to the far side of the target (range 5) and stab it with death damage.
dofile('data/spells/scripts/chaos/_common.lua')

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
	local spots = ChaosSpell.freeAround(tpos, from, true)
	if #spots == 0 then
		return ChaosSpell.cancel(player, RETURNVALUE_NOTENOUGHROOM)
	end
	ChaosSpell.shoot(from, tpos, "shadow_bolt", CONST_ANI_DEATH)
	ChaosSpell.fx(from, "shadow_smoke", CONST_ME_MORTAREA)
	player:teleportTo(spots[1].pos)
	ChaosSpell.fx(spots[1].pos, "shadow_smoke", CONST_ME_MORTAREA)

	local min, max = ChaosSpell.mlValues(player, 4.7, 7.9, 54, 99, 1.4)
	ChaosSpell.damageTarget(player, target, COMBAT_DEATHDAMAGE, min, max, Fx("shadow_smoke", CONST_ME_MORTAREA))
	return true
end
