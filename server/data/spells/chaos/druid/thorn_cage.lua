-- Thorn Cage: thorns erupt around the target for 3 pulses, rooting enemies in a 3x3 for 5s.
dofile('data/spells/scripts/chaos/_common.lua')

local area = createCombatArea(AREA_SQUARE1X1)

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	if not target then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
	end
	local p = target:getPosition()
	local center = {x = p.x, y = p.y, z = p.z}
	local min, max = ChaosSpell.mlValues(player, 1.1, 1.95, 14, 25)

	ChaosSpell.shoot(player:getPosition(), p, "poison_dart", CONST_ANI_POISON)
	ChaosSpell.pulse(player:getId(), 3, 1000, function(caster, step)
		local pos = Position(center)
		doAreaCombat(caster, COMBAT_EARTHDAMAGE, pos, area, -math.floor(min), -math.floor(max), Fx("poison_cloud", CONST_ME_POISONAREA))
		ChaosSpell.fx(pos, "ground_slam", CONST_ME_GROUNDSHAKER)
		if step == 1 then
			for _, c in ipairs(ChaosSpell.enemiesAround(caster, pos, 1)) do
				ChaosSpell.slow(c, 5000, 0.9)
			end
		end
		return true
	end)
	return true
end
