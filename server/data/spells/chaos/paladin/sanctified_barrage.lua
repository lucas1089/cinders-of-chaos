-- Sanctified Barrage: 3 volleys of 5 holy arrows rain down within 2 sqm of the target.
dofile('data/spells/scripts/chaos/_common.lua')

local single = createCombatArea({{3}})

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
	local dist = player:getEffectiveSkillLevel(SKILL_DISTANCE)
	local min, max = ChaosSpell.mlValues(player, 1.4, 2.4, 25, 45)
	min = min + dist * 0.25
	max = max + dist * 0.45

	ChaosSpell.pulse(player:getId(), 3, 600, function(caster, step)
		for i = 1, 5 do
			local pos = Position(center.x + math.random(-2, 2), center.y + math.random(-2, 2), center.z)
			if Tile(pos) then
				ChaosSpell.shoot(Position(pos.x - 3, pos.y - 3, pos.z), pos, "holy_arrow", CONST_ANI_HOLY)
				doAreaCombat(caster, COMBAT_HOLYDAMAGE, pos, single, -math.floor(min), -math.floor(max), Fx("holy_smite", CONST_ME_HOLYDAMAGE))
			end
		end
		return true
	end)
	return true
end
