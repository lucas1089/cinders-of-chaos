-- Keepfall: a wall of the keep drops on the target and every enemy within 2 sqm of it.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key keepfall): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua. A line spell quest spell: needlearn, taught by the quest.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('keepfall', creature, variant)
end
