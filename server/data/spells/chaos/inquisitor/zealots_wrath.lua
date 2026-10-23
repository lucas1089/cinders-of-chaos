-- Zealot's Wrath: a burst of zeal; every enemy within 2 sqm of you takes holy damage.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key zealotswrath): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('zealotswrath', creature, variant)
end
