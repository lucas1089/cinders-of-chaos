-- Blessed Earth: consecrates the ground around the caster for 6s, and the zone follows the caster. Each second holy damage hits enemies within 2 sqm
-- of the caster, and allies (party, own summons, caster) within 2 sqm of the caster are healed a little.

-- O466: every pulse is centred on where the caster stands at that moment (damage, heal and the picture); before, the
-- zone stayed on the tile of the cast. Still 6 pulses a second apart, ending when the caster dies or logs out.
dofile('data/spells/scripts/chaos/_common.lua')

local area = createCombatArea(AREA_CIRCLE2X2)

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local power, ml = player:getEffectiveSkillLevel(SKILL_DISTANCE) * ChaosSpell.distanceAttack(player), player:getMagicLevel()
	local min = player:getLevel() / 5 + power * 0.00325 + ml * 0.4 + 8
	local max = player:getLevel() / 5 + power * 0.0052 + ml * 0.6 + 15

	ChaosSpell.pulse(player:getId(), 6, 1000, function(caster, step)
		local pos = caster:getPosition() -- the zone follows the caster (O466)
		if step % 2 == 1 then
			ChaosSpell.vfxOr(pos, "holy_seal", "holy_cross", CONST_ME_HOLYAREA)
		end
		doAreaCombat(caster, COMBAT_HOLYDAMAGE, pos, area, -math.floor(min), -math.floor(max), Fx("holy_smite", CONST_ME_HOLYDAMAGE))
		for _, ally in ipairs(ChaosSpell.alliesAround(caster, pos, 2, true)) do
			ChaosSpell.healTarget(caster, ally, min * 0.5, max * 0.5, Fx("heal_sparkle", CONST_ME_MAGIC_BLUE))
		end
		return true
	end)
	return true
end
