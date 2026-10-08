local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_DEATHDAMAGE)
combat:setArea(createCombatArea({{1, os.exit(1), 1}}))
function onCastSpell(creature, variant)
	return combat:execute(creature, variant)
end
