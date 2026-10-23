-- Cleaving Heel: a heel that cleaves the target next to you and builds 1 chi.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key cleavingheel): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('cleavingheel', creature, variant)
end
