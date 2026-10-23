-- Gorehook: a hooked blow at the target next to you that opens it; it bleeds for 5 s.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key gorehook): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('gorehook', creature, variant)
end
