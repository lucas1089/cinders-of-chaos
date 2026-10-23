-- Rampart Quake: the rampart shakes; every enemy within 2 sqm of you takes holy damage.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key rampartquake): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('rampartquake', creature, variant)
end
