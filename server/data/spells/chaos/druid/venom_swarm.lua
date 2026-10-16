-- Blightswarm: toxic cloud around the caster, poisons everything it hits.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end
local M = ChaosMysticFx

-- poison_burst: the procedural spore burst (the old name poison_cloud is not in ChaosFx)
local TILE = Fx("poison_burst", CONST_ME_POISONAREA)
local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_EARTHDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, TILE)
combat:setArea(createCombatArea(AREA_CIRCLE3X3))

function onGetFormulaValues(player, level, magicLevel)
	local min = ((level / 5) + (magicLevel * 2.4) + 18) * 0.85
	local max = ((level / 5) + (magicLevel * 4.1) + 36) * 0.85
	return -min, -max
end

function onVenomSwarmTarget(creature, target)
	local dmg = math.max(2, math.floor(creature:getMagicLevel() * 0.25) + 3)
	creature:addDamageCondition(target, CONDITION_POISON, DAMAGELIST_LOGARITHMIC_DAMAGE, dmg)
	return true
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")
combat:setCallback(CALLBACK_PARAM_TARGETCREATURE, "onVenomSwarmTarget")

function onCastSpell(creature, variant, isHotkey)
	if not creature:isPlayer() then
		return false
	end
	-- a venom nova the size of the 7x7 area replaces the tile effects (server/data/spells/README_FX.md
	-- "Mystic line effects")
	local pos = creature:getPosition()
	local nova = M and M.known("big_nova_poison_7")
	combat:setParameter(COMBAT_PARAM_EFFECT, M and M.tileFx(nova, TILE) or TILE)
	if not combat:execute(creature, variant) then
		return false
	end
	ChaosSpell.vfx(pos, "toxic_burst")
	if nova then
		M.later(100, pos, "big_nova_poison_7")
	end
	return true
end
