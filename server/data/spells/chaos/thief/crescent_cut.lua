-- Crescent Cut: a wide arc in front of you, towards the target, a melee weapon strike on each.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key crescentcut): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('crescentcut', creature, variant)
end
