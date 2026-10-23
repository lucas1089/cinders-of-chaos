-- Bell of Reckoning: a bell tolls over the target; every enemy within 2 sqm of it takes holy damage.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key bellofreckoning): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('bellofreckoning', creature, variant)
end
