-- Verdant Sanctuary: a healing zone on the caster's tile; 8 pulses (1/s) heal allies standing within 3 sqm.
dofile('data/spells/scripts/chaos/_common.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local p = player:getPosition()
	local center = {x = p.x, y = p.y, z = p.z}
	local min, max = ChaosSpell.mlValues(player, 3.8, 5.9, 40, 70)

	ChaosSpell.pulse(player:getId(), 8, 1000, function(caster, step)
		local pos = Position(center)
		if step % 2 == 1 then
			ChaosSpell.vfxOr(pos, "grove_glyph", "aura_ring", CONST_ME_GREEN_RINGS)
		end
		for _, ally in ipairs(ChaosSpell.alliesAround(caster, pos, 3, true)) do
			if step % 3 == 0 then
				ally:removeCondition(CONDITION_POISON)
				ally:removeCondition(CONDITION_BLEEDING)
			end
			ChaosSpell.healTarget(caster, ally, min, max, Fx("heal_sparkle", CONST_ME_MAGIC_GREEN))
		end
		return true
	end)
	return true
end
