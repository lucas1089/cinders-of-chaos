-- Venom Spiral: a coiled blade of venom; the target is poisoned for 2 s, and the poison ignores armour and moves to a nearby enemy if the target dies.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key venomspiral): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('venomspiral', creature, variant)
end
