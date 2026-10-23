-- Skysplitter Fist: a finisher that spends all your chi in one blow at the target next to you.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key skysplitter): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('skysplitter', creature, variant)
end
