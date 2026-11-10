-- Dreamrot: a rotting dream settles on the target and eats at it for 2.4 s; it ignores armour and moves to a nearby enemy if the target dies.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key dreamrot): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('dreamrot', creature, variant)
end
