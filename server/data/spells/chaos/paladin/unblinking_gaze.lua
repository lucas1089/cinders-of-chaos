-- Unblinking Gaze: the hunt narrows to one point. For 20 s your distance skill is 25% higher and you crit 10 points more often.
-- The level 800 buff of the Ranger line's spell quest (needlearn, taught by Archivist Odrenna; numbers in
-- data/scripts/chaos/quest_buffs_config.lua).
dofile('data/spells/scripts/chaos/_questbuffs.lua')

function onCastSpell(creature, variant, isHotkey)
	local c = ChaosQuestBuffsConfig.gaze
	return QuestBuffSpell.cast(creature, 'gaze', {
		[CONDITION_PARAM_SKILL_DISTANCEPERCENT] = c.distance,
		[CONDITION_PARAM_SPECIALSKILL_CRITICALHITCHANCE] = c.crit
	}, {'ranger_pierce', 'holy_smite', CONST_ME_HITAREA})
end
