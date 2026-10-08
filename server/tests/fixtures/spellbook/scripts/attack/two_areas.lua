local small = createCombatArea(AREA_SQUARE1X1)
local big = createCombatArea(AREA_CIRCLE3X3)
function onCastSpell(creature, variant)
	doAreaCombat(creature, COMBAT_EARTHDAMAGE, creature:getPosition(), small, -10, -20, CONST_ME_POISONAREA)
	doAreaCombat(creature, COMBAT_EARTHDAMAGE, creature:getPosition(), big, -10, -20, CONST_ME_POISONAREA)
	return true
end
