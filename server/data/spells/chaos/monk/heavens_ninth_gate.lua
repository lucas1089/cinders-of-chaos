-- Heaven's Ninth Gate: the last door opens inward: a melee chi finisher that hits with the chi it spends.

-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key heavensninthgate): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua. A line spell quest ultimate (quest 3, level 1200):
-- needlearn, taught by the quest, a long cooldown, and no slot in the helper's rotation of 5.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('heavensninthgate', creature, variant)
end
