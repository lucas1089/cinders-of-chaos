-- Last Breath: a heavy finishing thrust at the target next to you, a melee weapon strike.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key lastbreath): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('lastbreath', creature, variant)
end
