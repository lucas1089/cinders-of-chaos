-- Censer Swing: a swung censer; every enemy next to you takes holy damage.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key censerswing): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('censerswing', creature, variant)
end
