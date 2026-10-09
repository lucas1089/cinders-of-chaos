-- Whirling Heel: a spinning kick that spends all chi and hits everything next to you.
--
-- Finisher, area 3x3 around the Monk (the engine's area rules: PvP, protection zones, summons). Damage x the
-- finisher scale of the chi spent.
dofile('data/spells/scripts/chaos/_monk.lua')

local AREA = createCombatArea({
	{1, 1, 1},
	{1, 3, 1},
	{1, 1, 1},
})

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local spent = MonkSpell.finisher(player)
	if not spent then
		return false
	end
	local min, max = MonkSpell.values(player, ChaosMonk.formula.whirlingHeel, ChaosMonk.finisherScale(spent))
	local pos = player:getPosition()
	ChaosSpell.vfxOr(pos, "whirlwind", "shockwave", CONST_ME_GROUNDSHAKER)
	doAreaCombat(player, COMBAT_PHYSICALDAMAGE, pos, AREA, -min, -max, CONST_ME_HITAREA, ORIGIN_SPELL)
	return true
end
