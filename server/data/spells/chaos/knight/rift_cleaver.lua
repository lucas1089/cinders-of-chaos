-- Rift Cleaver: a cleave that tears a line 3 sqm long, cast on a target within 2 sqm towards the target.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key riftcleaver): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('riftcleaver', creature, variant)
end
