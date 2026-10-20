-- Ironhold: +40% shielding for 12 s. No pacify and no lock on other spells: the weapon keeps swinging.

-- The Warrior line's guard buff since the stock Protector (Bulwark, "utamo tempo") was retired on 2026-10-20
-- (tools/retire_cure_spells.py): that one gave +120% shielding for 13 s but it also pacified the caster (no attack)
-- and put a 10 s cooldown on the attack group, and the helper's Auto setup kept it up, so the Warrior stopped
-- attacking. Its spell id 132 is this one's.
dofile('data/spells/scripts/chaos/_common.lua')

local DURATION = 12000
local SHIELD_PERCENT = 140

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local buff = Condition(CONDITION_ATTRIBUTES)
	buff:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.ironhold)
	buff:setParameter(CONDITION_PARAM_TICKS, DURATION)
	buff:setParameter(CONDITION_PARAM_SKILL_SHIELDPERCENT, SHIELD_PERCENT)
	buff:setParameter(CONDITION_PARAM_BUFF_SPELL, true)
	player:addCondition(buff)

	local pos = player:getPosition()
	ChaosSpell.vfxOr(pos, "shield_bubble", "holy_cross", CONST_ME_MAGIC_BLUE)
	pos:sendMagicEffect(CONST_ME_MAGIC_BLUE)
	return true
end
