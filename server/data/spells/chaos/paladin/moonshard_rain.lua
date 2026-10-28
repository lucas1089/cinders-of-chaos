-- Moonshard Rain: shards of a hollow moon rain on the target and every enemy within 3 sqm of it.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key moonshardrain): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua. A line spell quest spell: needlearn, taught by the quest.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('moonshardrain', creature, variant)
end
