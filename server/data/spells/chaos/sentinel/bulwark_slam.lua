-- Bulwark Slam: a slam of your shield arm at the target next to you, holy damage from your weapon.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key bulwarkslam): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('bulwarkslam', creature, variant)
end
