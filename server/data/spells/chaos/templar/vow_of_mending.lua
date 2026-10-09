-- Vow of Mending: the Templar's self heal. Restores 8% of the maximum health + level / 5 + magic level x 4
-- (ChaosTemplar.cfg.vowOfMending, ChaosTemplar.vowAmount).
dofile('data/spells/scripts/chaos/_templar.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local amount = ChaosTemplar.vowAmount(player:getMaxHealth(), player:getLevel(), player:getMagicLevel())
	ChaosSpell.healTarget(player, player, amount * 0.9, amount * 1.1, Fx("holy_spiral", CONST_ME_MAGIC_BLUE))
	ChaosSpell.vfx(player:getPosition(), "healing_bloom")
	return true
end
