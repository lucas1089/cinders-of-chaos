-- Packhunter's Dart: a venom dart at the quarry the pack is circling.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key packdart): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('packdart', creature, variant)
end
