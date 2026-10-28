-- Mantle of Dawn: light worn as armour. For 20 s you take 15% less damage and the holy strike after your melee hits is 20% stronger.
-- The level 800 buff of the Templar line's spell quest (needlearn, taught by Archivist Odrenna; numbers in
-- data/scripts/chaos/quest_buffs_config.lua). A timer condition: data/scripts/chaos/templar_combat.lua reads it.
dofile('data/spells/scripts/chaos/_questbuffs.lua')

function onCastSpell(creature, variant, isHotkey)
	return QuestBuffSpell.cast(creature, 'mantle', nil, {'big_sanctum_holy_5', 'holy_spiral', CONST_ME_HOLYAREA})
end
