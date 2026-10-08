-- Shuriken Toss: throw a shuriken at one target; physical damage from your sword or distance skill.
--
-- The Thief's filler (range 5). A ranged weapon strike: the better of sword and distance skill x the throwing star in
-- hand (or a default star), so it works with a blade in hand too. It crits out of Shadow Veil and carries Poison Blades.
dofile('data/spells/scripts/chaos/_common.lua')

local SCALE = 2.0

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
	local power = ChaosSpell.shurikenPower(player)
	local l = player:getLevel() / 5
	local min = (l + power * 0.050 + 20) * SCALE
	local max = (l + power * 0.080 + 40) * SCALE
	ChaosSpell.shoot(player:getPosition(), target:getPosition(), "shuriken", CONST_ANI_REDSTAR)
	ChaosSpell.weaponStrike(player, target, min, max, CONST_ME_DRAWBLOOD, ORIGIN_RANGED)
	return true
end
