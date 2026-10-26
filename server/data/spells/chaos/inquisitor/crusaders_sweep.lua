-- Crusader's Sweep: a holy sweep 3 sqm ahead.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key crusaderssweep): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('crusaderssweep', creature, variant)
end
