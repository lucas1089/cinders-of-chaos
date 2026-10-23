-- Crypt Collapse: the ceiling of a crypt falls on the target and every enemy within 2 sqm of it.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key cryptcollapse): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('cryptcollapse', creature, variant)
end
