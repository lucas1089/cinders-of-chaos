-- Purifying Wellspring: heals the caster, party members and own summons within 3 sqm and removes harmful conditions.
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
	local min, max = ChaosSpell.mlValues(player, 12, 20, 90, 190)
	ChaosSpell.vfxOr(player:getPosition(), "healing_bloom", "arcane_aura", CONST_ME_MAGIC_BLUE)
	for _, ally in ipairs(ChaosSpell.alliesAround(player, player:getPosition(), 3, true)) do
		for _, ctype in ipairs(CLEANSE) do
			ally:removeCondition(ctype)
		end
		-- each healed ally: the class swap (chaos_class_fx.lua: heal_sparkle -> mystic_mend) at its tile; the caster has
		-- the bloom (server/data/spells/README_FX.md "Mystic line effects")
		local healFx = Fx("heal_sparkle", CONST_ME_MAGIC_BLUE)
		if ally:getId() ~= player:getId() and ChaosSpell.vfx(ally:getPosition(), "heal_sparkle") then
			healFx = CONST_ME_NONE
		end
		ChaosSpell.healTarget(player, ally, min, max, healFx)
	end
	return true
end
