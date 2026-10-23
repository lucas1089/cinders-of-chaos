-- Tautstring: +25% distance skill for 12 s. No slow and no lock on other spells: the bow keeps firing.

-- The Ranger line's fight buff since the stock Sharpshooter (Hawkeye, "utito tempo san") was retired on 2026-10-20
-- (tools/retire_cure_spells.py): that one also slowed the caster 70% for its 10 s and put the healing group on a 10 s
-- cooldown, and the beta saw the Ranger's bow stop while the helper kept it up. Its spell id 135 is this spell's.
dofile('data/spells/scripts/chaos/_common.lua')

local DURATION = 12000
local DISTANCE_PERCENT = 125

-- the card line of this spell (data/scripts/chaos/cards_config.lua, kind bow) adds seconds and percentage points while on
local cards = rawget(_G, "ChaosCardsConfig") or dofile('data/scripts/chaos/cards_config.lua')
ChaosCardsConfig = cards

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local extraSecs, extraPct = cards.buffBonus(135, function(key) return player:getStorageValue(key) end)
	local buff = Condition(CONDITION_ATTRIBUTES)
	buff:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.tautstring)
	buff:setParameter(CONDITION_PARAM_TICKS, DURATION + extraSecs * 1000)
	buff:setParameter(CONDITION_PARAM_SKILL_DISTANCEPERCENT, DISTANCE_PERCENT + extraPct)
	buff:setParameter(CONDITION_PARAM_BUFF_SPELL, true)
	player:addCondition(buff)

	local pos = player:getPosition()
	ChaosSpell.vfxOr(pos, "aura_burst_gold", "holy_cross", CONST_ME_MAGIC_GREEN)
	pos:sendMagicEffect(CONST_ME_MAGIC_GREEN)
	return true
end
