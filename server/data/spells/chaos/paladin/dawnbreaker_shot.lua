-- Dawnbreaker Shot: one arrow that ends the night: a holy shot that pierces every enemy in a line of 8 sqm.

-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key dawnbreakershot): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua. A line spell quest ultimate (quest 3, level 1200):
-- needlearn, taught by the quest, a long cooldown, and no slot in the helper's rotation of 5.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('dawnbreakershot', creature, variant)
end
