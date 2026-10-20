-- Shadow Mend: heals you for your level / 2 + magic level x 20 + 5% of your maximum health, 30% more while Shadow Veil is
-- up. Healing does not end the veil.
--
-- The Thief line's self heal (Thief, Ninja, Samurai). Numbers: Chaos.classes.shadowMend, rule ChaosClasses.shadowMendRange
-- (+-10%); measured in server/data/spells/README.md "Healing".
dofile('data/spells/scripts/chaos/_common.lua')
ChaosSpell.loadClasses()

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local veiled = player:getCondition(CONDITION_INVISIBLE, CONDITIONID_COMBAT, Chaos.classes.subId.stealth) ~= nil
	local min, max = ChaosClasses.shadowMendRange(player:getMaxHealth(), player:getLevel(), player:getMagicLevel(), veiled)
	ChaosSpell.healTarget(player, player, min, max, Fx("shadow_smoke", CONST_ME_MAGIC_BLUE))
	if veiled then
		ChaosSpell.vfxOr(player:getPosition(), "shade_vanish", "shadow_smoke", CONST_ME_MAGIC_BLUE)
	end
	return true
end
