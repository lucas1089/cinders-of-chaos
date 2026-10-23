-- Arrowstorm: a volley that lands in a circle of 2 sqm around the target.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key arrowstorm): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('arrowstorm', creature, variant)
end
