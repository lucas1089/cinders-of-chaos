-- Thousand-Echo Palm: one palm, a thousand echoes: a wave, 3 tiles deep and 5 wide. Spends all chi.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key thousandechopalm): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua. A line spell quest spell: needlearn, taught by the quest.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('thousandechopalm', creature, variant)
end
