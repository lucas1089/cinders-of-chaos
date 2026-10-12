-- Hail of Dawn: 3 volleys of 4 holy arrows, every arrow strikes the target. Scales with distance skill x weapon attack.
-- Cast time 1 s (data/lib/chaos_casting.lua): moving, a new paralysis, another spell or death interrupt it and give
-- the mana and cooldown back; at the end the target must still be alive, attackable, within 7 sqm and in sight.
-- Damage x1.1 since the cast time.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosCasting then
	dofile('data/lib/chaos_casting.lua')
end

local VOLLEYS = 3
local ARROWS = 4
local RANGE = 7
local POWER = 1.1

onCastSpell = ChaosCasting.spell({
	name = "Hail of Dawn", spellId = 219, ms = 1000, fx = {"holy_smite", CONST_ME_HOLYAREA},
	prepare = function(player, variant)
		local target = ChaosSpell.targetOf(variant)
		if not target or target == player then
			return nil, RETURNVALUE_YOUCANONLYUSEITONCREATURES
		end
		if not ChaosSpell.canAttack(player, target) then
			return nil, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
		end
		return {targetId = target:getId()}
	end,
	check = function(player, ctx)
		return ChaosCasting.targetCheck(player, ctx.targetId, RANGE, true)
	end,
	fire = function(player, ctx)
		local dist = player:getEffectiveSkillLevel(SKILL_DISTANCE)
		local power = dist * ChaosSpell.distanceAttack(player)
		local level, ml = player:getLevel() / 10, player:getMagicLevel()
		local min = (level + power * 0.021 + ml * 0.5 + 15) * POWER
		local max = (level + power * 0.034 + ml * 0.8 + 30) * POWER
		local targetId = ctx.targetId
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
	end,
})
