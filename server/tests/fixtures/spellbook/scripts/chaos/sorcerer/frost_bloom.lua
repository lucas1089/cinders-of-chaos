-- Frost Bloom: ice burst around the caster,
-- chills everything it hits.
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_ICEDAMAGE)
combat:setArea(createCombatArea(AREA_CIRCLE3X3))
function onCastSpell(creature, variant, isHotkey)
	local min, max = ChaosSpell.mlValues(creature, 1, 2, 3, 4)
	return combat:execute(creature, variant)
end
