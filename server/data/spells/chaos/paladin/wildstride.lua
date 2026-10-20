-- Wildstride: +50% speed for 12 s, on top of Haste. No pacify and no lock on other spells: the bow keeps firing.

-- A haste of its own sub id (ChaosSpell.SUBID.wildstride), so it adds to the stock Haste the helper keeps up.

-- The Ranger line's run buff since the stock Swift Foot (Windrunner, "utamo tempo san") was retired on 2026-10-20
-- (tools/retire_cure_spells.py): that one gave a strong haste for 10 s but it also pacified the caster (no attack)
-- and put a 10 s cooldown on the attack group, so no attack while it ran. Its spell id 134 is this one's.
dofile('data/spells/scripts/chaos/_common.lua')

local DURATION = 12000

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local haste = Condition(CONDITION_HASTE)
	haste:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.wildstride)
	haste:setParameter(CONDITION_PARAM_TICKS, DURATION)
	haste:setFormula(0.5, -40, 0.5, -40)
	player:addCondition(haste)

	local pos = player:getPosition()
	ChaosSpell.vfxOr(pos, "gale_ring", "frost_ripple", CONST_ME_MAGIC_GREEN)
	pos:sendMagicEffect(CONST_ME_MAGIC_GREEN)
	return true
end
