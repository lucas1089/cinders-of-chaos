-- Radiant Smite: a hammer-blow of light on one target within 3 sqm. The Templar line's holy filler.
--
-- Holy damage from the melee weapon (best of sword, club and axe skill x the main-hand attack) and a little magic
-- level, times the line's level factor (ChaosTemplar.cfg.spellLevelScale). A judged target takes more of it.
dofile('data/spells/scripts/chaos/_templar.lua')

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
	local min, max = TemplarSpell.values(player, 0.10, 0.16, 1.0, 1.5, 30, 60)
	ChaosSpell.shoot(player:getPosition(), target:getPosition(), "holy_arrow", CONST_ANI_SMALLHOLY)
	ChaosSpell.fx(target:getPosition(), "holy_smite", CONST_ME_HOLYAREA)
	ChaosSpell.vfx(target:getPosition(), "px652_white")
	TemplarSpell.holyStrike(player, target, min, max, CONST_ME_HOLYDAMAGE)
	return true
end
