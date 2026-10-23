-- Ossuary Surge: bones rise from the floor around you; every enemy within 2 sqm is struck.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key ossuarysurge): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('ossuarysurge', creature, variant)
end
