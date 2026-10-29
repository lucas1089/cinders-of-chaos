-- Shroud of Knives: steel you do not see. For 15 s your melee and distance skill are 20% higher and you dodge 10 points more
-- weapon hits (data/scripts/chaos/thief_combat.lua adds the evasion).
-- The level 800 buff of the Thief line's spell quest (needlearn, taught by Archivist Odrenna; numbers in
-- data/scripts/chaos/quest_buffs_config.lua). The caster stays visible: no stealth, no lock on other spells.
dofile('data/spells/scripts/chaos/_questbuffs.lua')

function onCastSpell(creature, variant, isHotkey)
	local c = ChaosQuestBuffsConfig.knives
	return QuestBuffSpell.cast(creature, 'knives', {
		[CONDITION_PARAM_SKILL_MELEEPERCENT] = c.melee,
		[CONDITION_PARAM_SKILL_DISTANCEPERCENT] = c.distance
	}, {'ninja_vanish', 'dodge_whoosh', CONST_ME_BLOCKHIT})
end
