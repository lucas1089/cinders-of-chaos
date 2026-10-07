-- Titan's Wrath: two crushing blows (0 / 0.6s) in a 7x7 circle; enemies are slowed 70% for 4s.
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("ground_slam", CONST_ME_GROUNDSHAKER))
combat:setParameter(COMBAT_PARAM_BLOCKARMOR, true)
combat:setParameter(COMBAT_PARAM_USECHARGES, true)
combat:setArea(createCombatArea(AREA_CIRCLE3X3))

function onGetFormulaValues(player, skill, attack, factor)
	local min = (player:getLevel() / 5) + (skill * attack * 0.10) + 40
	local max = (player:getLevel() / 5) + (skill * attack * 0.18) + 70
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
	end
end

function onCastSpell(creature, variant, isHotkey)
	if not creature:isPlayer() then
		return false
	end
	if not combat:execute(creature, variant) then
		return false
	end
	addEvent(secondBlow, 600, creature:getId(), variant)
	return true
end
