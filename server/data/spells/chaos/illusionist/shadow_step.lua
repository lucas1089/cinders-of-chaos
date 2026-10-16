-- Umbral Stride: teleport to the far side of the target (range 5) and stab it with death damage.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end

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
	-- a shadow eruption where the Illusionist leaves, the pack shadow orb, the shadow hit on the stab when the orb
	-- arrives (server/data/spells/README_FX.md "Mystic line effects")
	local M = ChaosMysticFx
	ChaosSpell.vshoot(from, tpos, "shadow_orb", "shadow_bolt", CONST_ANI_DEATH)
	if M then
		M.send(from, "shadow_eruption")
	end
	ChaosSpell.vfxOr(from, "shade_vanish", "shadow_smoke", CONST_ME_MORTAREA)
	player:teleportTo(spots[1].pos)
	ChaosSpell.vfxOr(spots[1].pos, "shade_appear", "shadow_smoke", CONST_ME_MORTAREA)

	local min, max = ChaosSpell.mlValues(player, 4.7, 7.9, 54, 99, 1.4)
	local hitFx = Fx("shadow_smoke", CONST_ME_MORTAREA)
	if M and M.known("shadow_hit") then
		M.later(M.flightMs(from, tpos), tpos, "shadow_hit")
		hitFx = CONST_ME_NONE
	end
	ChaosSpell.damageTarget(player, target, COMBAT_DEATHDAMAGE, min, max, hitFx)
	return true
end
