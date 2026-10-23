-- Chi Lance: a finisher: all your chi leaves in a line 4 sqm long; the damage grows with the chi spent.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key chilance): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('chilance', creature, variant)
end
