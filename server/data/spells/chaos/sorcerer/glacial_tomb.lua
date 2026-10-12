-- Frozen Crypt: freezing zone on the target's position, 6 pulses over 5s, enemies inside are heavily slowed.
dofile('data/spells/scripts/chaos/_common.lua')

local area = createCombatArea(AREA_CIRCLE2X2)

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	local center = target and target:getPosition() or player:getPosition()
	center = {x = center.x, y = center.y, z = center.z}
	local min, max = ChaosSpell.mlValues(player, 1.8, 3.0, 20, 40, 1.2)

	ChaosSpell.vshoot(player:getPosition(), Position(center), "ice_lance", "ice_shard", CONST_ANI_ICE)
	ChaosSpell.pulse(player:getId(), 6, 1000, function(caster, step)
		local pos = Position(center)
		if step % 2 == 1 then
			ChaosSpell.vfx(pos, "frost_glyph")
		end
		doAreaCombat(caster, COMBAT_ICEDAMAGE, pos, area, -math.floor(min), -math.floor(max), Fx("frost_burst", CONST_ME_ICEAREA))
		for _, c in ipairs(ChaosSpell.enemiesAround(caster, pos, 2)) do
			ChaosSpell.slow(c, 2000, 0.7)
		end
		return true
	end)
	return true
end
