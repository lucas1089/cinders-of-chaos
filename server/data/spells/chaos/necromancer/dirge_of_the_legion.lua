-- Dirge of the Legion: a funeral song that wakes. For 20 s your minions hit 25% harder and your death spells deal 10% more.
-- The level 800 buff of the Necromancer line's spell quest (needlearn, taught by Archivist Odrenna; numbers in
-- data/scripts/chaos/quest_buffs_config.lua). A timer condition: data/scripts/chaos/necro_minions.lua (minions) and
-- passivetree_effects.lua (death spells) read it. It works without minions out: the death spells still gain.
dofile('data/spells/scripts/chaos/_questbuffs.lua')

function onCastSpell(creature, variant, isHotkey)
	return QuestBuffSpell.cast(creature, 'dirge', nil, {'necro_curse', 'necro_skull', CONST_ME_MORTAREA})
end
