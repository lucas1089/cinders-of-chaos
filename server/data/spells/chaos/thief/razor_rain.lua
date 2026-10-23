-- Razor Rain: blades fall in a circle of 2 sqm around the target, a ranged weapon strike on each.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key razorrain): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('razorrain', creature, variant)
end
