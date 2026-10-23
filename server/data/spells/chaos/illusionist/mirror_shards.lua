-- Mirror Shards: the glass of a mirror bursts; every enemy next to you is cut.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key mirrorshards): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('mirrorshards', creature, variant)
end
