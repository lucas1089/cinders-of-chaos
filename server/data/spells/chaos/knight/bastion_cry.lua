-- Bastion Cry: a shout that hurls a shockwave 3 sqm ahead.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key bastioncry): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('bastioncry', creature, variant)
end
