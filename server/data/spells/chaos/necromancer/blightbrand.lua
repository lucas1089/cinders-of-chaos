-- Blightbrand: a brand of blight that burns in the target for 6 s.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key blightbrand): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('blightbrand', creature, variant)
end
