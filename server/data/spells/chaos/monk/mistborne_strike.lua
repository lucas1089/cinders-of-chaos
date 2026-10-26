-- Mistborne Strike: a finisher wave of mist 3 sqm ahead.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key mistbornestrike): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('mistbornestrike', creature, variant)
end
