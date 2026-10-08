-- Consecration: consecrates the caster's tile for 6s. Each second holy damage hits enemies within 2 sqm
-- and allies (party, own summons, caster) standing in it are healed a little.
dofile('data/spells/scripts/chaos/_common.lua')

local area = createCombatArea(AREA_CIRCLE2X2)

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local p = player:getPosition()
	local center = {x = p.x, y = p.y, z = p.z}
	local dist, ml = player:getEffectiveSkillLevel(SKILL_DISTANCE), player:getMagicLevel()
	local min = player:getLevel() / 5 + dist * 0.25 + ml * 0.4 + 8
	local max = player:getLevel() / 5 + dist * 0.4 + ml * 0.6 + 15

	ChaosSpell.pulse(player:getId(), 6, 1000, function(caster, step)
		local pos = Position(center)
		ChaosSpell.fx(pos, "aura_ring", CONST_ME_HOLYAREA)
		doAreaCombat(caster, COMBAT_HOLYDAMAGE, pos, area, -math.floor(min), -math.floor(max), Fx("holy_smite", CONST_ME_HOLYDAMAGE))
		for _, ally in ipairs(ChaosSpell.alliesAround(caster, pos, 2, true)) do
			ChaosSpell.healTarget(caster, ally, min * 0.5, max * 0.5, Fx("heal_sparkle", CONST_ME_MAGIC_BLUE))
		end
		return true
	end)
	return true
end
