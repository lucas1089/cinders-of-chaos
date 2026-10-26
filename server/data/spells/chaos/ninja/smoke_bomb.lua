-- Smoke Bomb: a bomb that bursts in a cloud around the caster.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key smokebomb): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('smokebomb', creature, variant)
end
