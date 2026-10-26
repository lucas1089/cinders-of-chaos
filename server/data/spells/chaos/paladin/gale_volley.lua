-- Gale Volley: a volley of arrows in a line 6 sqm long.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key galevolley): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('galevolley', creature, variant)
end
