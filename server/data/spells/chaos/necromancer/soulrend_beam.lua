-- Soulrend Beam: a beam that rends everything in a line 6 sqm long towards the target.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key soulrendbeam): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('soulrendbeam', creature, variant)
end
