-- Reaping Gyre: three spinning strikes (0 / 0.4 / 0.8s) against everything adjacent. Uses weapon attack and skill.
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("aura_ring", CONST_ME_HITAREA))
combat:setParameter(COMBAT_PARAM_BLOCKARMOR, true)
combat:setParameter(COMBAT_PARAM_USECHARGES, true)
combat:setArea(createCombatArea(AREA_SQUARE1X1))

function onGetFormulaValues(player, skill, attack, factor)
	local min = (player:getLevel() / 5) + (skill * attack * 0.010) + 4
	local max = (player:getLevel() / 5) + (skill * attack * 0.019) + 7
	return -min, -max
end

combat:setCallback(CALLBACK_PARAM_SKILLVALUE, "onGetFormulaValues")

local function spin(creatureId, variant)
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
	addEvent(spin, 400, creature:getId(), variant)
	addEvent(spin, 800, creature:getId(), variant)
	return true
end
