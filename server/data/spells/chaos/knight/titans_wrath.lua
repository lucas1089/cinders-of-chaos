-- Colossus Fall: two crushing blows (0 / 0.6s) in a 7x7 circle; enemies are slowed 70% for 4s.
-- Cast time 1 s, a wind-up (data/lib/chaos_casting.lua): moving, a new paralysis, another spell or death interrupt it
-- and give the mana and cooldown back. Damage x1.0 (owner, 2026-10-20: no area discount; was x0.77, x0.7 before the cast time).
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosCasting then
	dofile('data/lib/chaos_casting.lua')
end

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("ground_slam", CONST_ME_GROUNDSHAKER))
combat:setParameter(COMBAT_PARAM_BLOCKARMOR, true)
combat:setParameter(COMBAT_PARAM_USECHARGES, true)
combat:setArea(createCombatArea(AREA_CIRCLE3X3))

function onGetFormulaValues(player, skill, attack, factor)
	local min = ((player:getLevel() / 5) + (skill * attack * 0.052) + 20)
	local max = ((player:getLevel() / 5) + (skill * attack * 0.093) + 40)
	return -min, -max
end

function onTitansWrathTarget(creature, target)
	ChaosSpell.slow(target, 4000, 0.7)
	return true
end

combat:setCallback(CALLBACK_PARAM_SKILLVALUE, "onGetFormulaValues")
combat:setCallback(CALLBACK_PARAM_TARGETCREATURE, "onTitansWrathTarget")

local function secondBlow(creatureId, variant)
	local c = Creature(creatureId)
	if c and c:getHealth() > 0 then
		combat:execute(c, variant)
		ChaosSpell.vfx(c:getPosition(), "blunt_smash")
	end
end

onCastSpell = ChaosCasting.spell({
	name = "Colossus Fall", spellId = 225, ms = 1000, fx = {"ground_slam", CONST_ME_GROUNDSHAKER},
	fire = function(player, ctx)
		if not combat:execute(player, ctx.variant) then
			return false
		end
		ChaosSpell.vfx(player:getPosition(), "earth_spikes")
		addEvent(secondBlow, 600, player:getId(), ctx.variant)
		return true
	end,
})
