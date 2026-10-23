-- Heretic's Brand: a brand burned into a heretic: one heavy holy hit on one target.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key hereticsbrand): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('hereticsbrand', creature, variant)
end
