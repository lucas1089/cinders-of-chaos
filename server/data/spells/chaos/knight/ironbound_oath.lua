-- Ironbound Oath: a vow sworn in iron. For 20 s your melee skill is 20% higher and your shielding 25% higher.
-- The level 800 buff of the Warrior line's spell quest (needlearn, taught by Archivist Odrenna; numbers in
-- data/scripts/chaos/quest_buffs_config.lua). No pacify and no lock on other spells.
dofile('data/spells/scripts/chaos/_questbuffs.lua')

function onCastSpell(creature, variant, isHotkey)
	local c = ChaosQuestBuffsConfig.oath
	return QuestBuffSpell.cast(creature, 'oath', {
		[CONDITION_PARAM_SKILL_MELEEPERCENT] = c.melee,
		[CONDITION_PARAM_SKILL_SHIELDPERCENT] = c.shield
	}, {'shield_bubble', 'holy_cross', CONST_ME_MAGIC_BLUE})
end
