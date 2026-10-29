-- Lotus Stance: stillness that blooms. For 15 s every weapon or fist hit gives one more chi and you dodge 10 points more weapon hits.
-- The level 800 buff of the Monk line's spell quest (needlearn, taught by Archivist Odrenna; numbers in
-- data/scripts/chaos/quest_buffs_config.lua). A timer condition: data/scripts/chaos/monk_combat.lua reads it.
dofile('data/spells/scripts/chaos/_questbuffs.lua')

function onCastSpell(creature, variant, isHotkey)
	return QuestBuffSpell.cast(creature, 'lotus', nil, {'ironsage_ward', 'heal_sparkle', CONST_ME_MAGIC_GREEN})
end
