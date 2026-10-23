-- Penitent Lash: a lash of penance over the 3 x 2 sqm in front of you.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key penitentlash): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('penitentlash', creature, variant)
end
