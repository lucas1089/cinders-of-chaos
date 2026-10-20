-- Bastion Cry: the Juggernaut's late shout. Taunts every monster within 6 sqm and slows them 35% for 6s; the Juggernaut
-- gains Iron Will for 12s (25% less damage taken, +15% shielding, data/scripts/chaos/spell_guard.lua) and heals 10% of
-- its maximum health at once. Iron Bellow's bigger sibling: 340 levels in, 40 s cooldown.
dofile('data/spells/scripts/chaos/_common.lua')

local RADIUS = 6
local TICKS = 12000
local HEAL_SHARE = 0.10

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local guard = Condition(CONDITION_ATTRIBUTES)
	guard:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.iron_will)
	guard:setParameter(CONDITION_PARAM_TICKS, TICKS)
	guard:setParameter(CONDITION_PARAM_SKILL_SHIELDPERCENT, 115)
	guard:setParameter(CONDITION_PARAM_BUFF_SPELL, true)
	player:addCondition(guard)

	local pos = player:getPosition()
	local heal = math.floor(player:getMaxHealth() * HEAL_SHARE)
	ChaosSpell.healTarget(player, player, heal, heal, Fx("blood_ring", CONST_ME_SOUND_RED))
	ChaosSpell.fx(pos, "blood_ring", CONST_ME_SOUND_RED)
	ChaosSpell.vfx(pos, "aura_burst_gold")
	for _, c in ipairs(ChaosSpell.enemiesAround(player, pos, RADIUS)) do
		doChallengeCreature(player, c)
		ChaosSpell.slow(c, 6000, 0.35)
		ChaosSpell.fx(c:getPosition(), "blood_rune", CONST_ME_SOUND_RED)
	end
	return true
end
