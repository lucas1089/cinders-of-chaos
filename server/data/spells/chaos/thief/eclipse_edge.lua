-- Eclipse Edge: a blade drawn between two shadows cuts the five tiles in front of you.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key eclipseedge): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua. A line spell quest spell: needlearn, taught by the quest.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('eclipseedge', creature, variant)
end
