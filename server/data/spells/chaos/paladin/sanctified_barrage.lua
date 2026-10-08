-- Hail of Dawn: 3 volleys of 4 holy arrows, every arrow strikes the target. Scales with distance skill x weapon attack.
dofile('data/spells/scripts/chaos/_common.lua')

local VOLLEYS = 3
local ARROWS = 4

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	if not target or target == player then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
	end
	if not ChaosSpell.canAttack(player, target) then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER)
	end
	local dist = player:getEffectiveSkillLevel(SKILL_DISTANCE)
	local power = dist * ChaosSpell.distanceAttack(player)
	local level, ml = player:getLevel() / 10, player:getMagicLevel()
	local min = level + power * 0.021 + ml * 0.5 + 15
	local max = level + power * 0.034 + ml * 0.8 + 30
	local targetId = target:getId()

	ChaosSpell.pulse(player:getId(), VOLLEYS, 600, function(caster, step)
		local t = Creature(targetId)
		if not t or t:getHealth() <= 0 or t:getPosition().z ~= caster:getPosition().z then
			return false
		end
		local p = t:getPosition()
		for i = 1, ARROWS do
			ChaosSpell.shoot(Position(p.x + math.random(-3, 3), p.y - 3, p.z), p, "holy_arrow", CONST_ANI_HOLY)
			ChaosSpell.damageTarget(caster, t, COMBAT_HOLYDAMAGE, min, max, Fx("holy_smite", CONST_ME_HOLYDAMAGE))
			if t:getHealth() <= 0 then
				return false
			end
		end
		return true
	end)
	return true
end
