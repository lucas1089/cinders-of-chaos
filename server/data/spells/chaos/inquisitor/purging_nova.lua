-- Purging Nova: holy fire bursts from the Inquisitor (circle of 3 sqm). It heals the Inquisitor for 10% of the
-- damage dealt, at most 5% of its maximum health per cast (ChaosTemplar.cfg.purgingNova).
--
-- A normal area combat (the engine's PvP rules apply). The heal counts the formula average per creature hit.
dofile('data/spells/scripts/chaos/_templar.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_HOLYDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("holy_smite", CONST_ME_HOLYAREA))
combat:setArea(createCombatArea(AREA_CIRCLE3X3))

local hits = 0

function onGetFormulaValues(player, level, magicLevel)
	local min, max = TemplarSpell.values(player, 0.08, 0.13, 1.0, 1.5, 20, 40)
	return -min, -max
end

function onPurgingNovaTarget(creature, target)
	if target and target ~= creature then
		hits = hits + 1
		target:registerEvent("ChaosTemplarCombat")
	end
	return true
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")
combat:setCallback(CALLBACK_PARAM_TARGETCREATURE, "onPurgingNovaTarget")

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	hits = 0
	local ok = combat:execute(player, variant)
	if ok and hits > 0 then
		local min, max = TemplarSpell.values(player, 0.08, 0.13, 1.0, 1.5, 20, 40)
		local heal = ChaosTemplar.novaHeal(hits * (min + max) / 2, player:getMaxHealth())
		if heal > 0 then
			ChaosSpell.healTarget(player, player, heal, heal, CONST_ME_NONE)
		end
	end
	return ok
end
