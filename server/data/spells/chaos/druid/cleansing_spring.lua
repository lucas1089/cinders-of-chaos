-- Cleansing Spring: heals the caster, party members and own summons within 3 sqm and removes harmful conditions.
dofile('data/spells/scripts/chaos/_common.lua')

local CLEANSE = {
	CONDITION_POISON, CONDITION_FIRE, CONDITION_ENERGY, CONDITION_BLEEDING,
	CONDITION_CURSED, CONDITION_FREEZING, CONDITION_DAZZLED, CONDITION_DROWN,
}

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local min, max = ChaosSpell.mlValues(player, 3.0, 5.5, 40, 70)
	ChaosSpell.fx(player:getPosition(), "aura_ring", CONST_ME_MAGIC_BLUE)
	for _, ally in ipairs(ChaosSpell.alliesAround(player, player:getPosition(), 3, true)) do
		for _, ctype in ipairs(CLEANSE) do
			ally:removeCondition(ctype)
		end
		ChaosSpell.healTarget(player, ally, min, max, Fx("heal_sparkle", CONST_ME_MAGIC_BLUE))
	end
	return true
end
