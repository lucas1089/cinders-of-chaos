-- Splinter Volley: bone shards that burst in a circle at the target.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key splintervolley): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('splintervolley', creature, variant)
end
