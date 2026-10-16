-- Rime Bloom: ice burst around the caster, chills everything it hits.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end
local M = ChaosMysticFx

local TILE = Fx("frost_burst", CONST_ME_ICEAREA)
local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_ICEDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, TILE)
combat:setArea(createCombatArea(AREA_CIRCLE3X3))

function onGetFormulaValues(player, level, magicLevel)
	local min = ((level / 5) + (magicLevel * 2.5) + 23) * 1.2
	local max = ((level / 5) + (magicLevel * 4.15) + 40) * 1.2
	return -min, -max
end

function onFrostNovaTarget(creature, target)
	ChaosSpell.slow(target, 4000, 0.4)
	if M then
		M.later(250, target:getPosition(), "ice_shatter")
	end
	return true
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")
combat:setCallback(CALLBACK_PARAM_TARGETCREATURE, "onFrostNovaTarget")

-- the pair 27 nova_frost (5x5) and a frost shockwave ring sized to the 7x7 area replace the 37 tile effects
-- (server/data/spells/README_FX.md "Mystic line effects")
function onCastSpell(creature, variant, isHotkey)
	local pos = creature:getPosition()
	local ring = M and M.known("big_shock_frost_7")
	combat:setParameter(COMBAT_PARAM_EFFECT, M and M.tileFx(ring, TILE) or TILE)
	if not combat:execute(creature, variant) then
		return false
	end
	ChaosSpell.vfx(pos, "frost_nova")
	if ring then
		M.later(250, pos, "big_shock_frost_7")
	end
	return true
end
