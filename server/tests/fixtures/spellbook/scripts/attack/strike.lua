-- Author: nobody (a stock script: this header must not be used as the description)
local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_FIREDAMAGE)
-- COMBAT_ICEDAMAGE in a comment does not count
combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")
function onCastSpell(creature, variant)
	return combat:execute(creature, variant)
end
