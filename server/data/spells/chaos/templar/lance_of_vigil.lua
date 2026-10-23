-- Lance of Vigil: a lance of light through a line 5 sqm long towards the target.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key lanceofvigil): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('lanceofvigil', creature, variant)
end
