-- Veil of Whispers: secrets lend power. For 20 s your magic level is 15% higher and 1% of your maximum mana comes back every second.
-- The level 800 buff of the Mystic line's spell quest (needlearn, taught by Archivist Odrenna; numbers in
-- data/scripts/chaos/quest_buffs_config.lua). The regeneration is a second condition (sub id + regenOffset) beside the buff's own.
dofile('data/spells/scripts/chaos/_questbuffs.lua')

function onCastSpell(creature, variant, isHotkey)
	local c = ChaosQuestBuffsConfig.veil
	return QuestBuffSpell.cast(creature, 'veil', {
		[CONDITION_PARAM_STAT_MAGICPOINTSPERCENT] = c.magic
	}, {'big_nova_arcane_7', 'arcane_circle', CONST_ME_MAGIC_BLUE}, function(player, cfg)
		local regen = Condition(CONDITION_REGENERATION)
		regen:setParameter(CONDITION_PARAM_SUBID, ChaosQuestBuffsConfig.subId.veil + ChaosQuestBuffsConfig.regenOffset)
		regen:setParameter(CONDITION_PARAM_TICKS, cfg.durationMs)
		regen:setParameter(CONDITION_PARAM_MANAGAIN, ChaosQuestBuffs.manaTick(player:getMaxMana()))
		regen:setParameter(CONDITION_PARAM_MANATICKS, 1000)
		player:addCondition(regen)
	end)
end
