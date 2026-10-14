-- Radiant Smite: a hammer-blow of light on one target within 3 sqm. The Templar line's holy filler (cooldown 2 s).
--
-- Holy damage from the melee weapon (best of sword, club and axe skill x the main-hand attack) and a little magic
-- level (the line's level factor was dropped with the class trees). A judged target takes more of it.
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
	-- cooldown 2 s since the rotation pass (2026-10-14; was 4 s): x the class's scale (ChaosTemplar.cfg.radiantSmite)
	local scale = ChaosTemplar.smiteScale(player:getVocation():getId(), player:getLevel())
	min, max = min * scale, max * scale
	ChaosSpell.shoot(player:getPosition(), target:getPosition(), "holy_arrow", CONST_ANI_SMALLHOLY)
	ChaosSpell.fx(target:getPosition(), "holy_smite", CONST_ME_HOLYAREA)
	ChaosSpell.vfx(target:getPosition(), "px652_white")
	TemplarSpell.holyStrike(player, target, min, max, CONST_ME_HOLYDAMAGE)
	return true
end
