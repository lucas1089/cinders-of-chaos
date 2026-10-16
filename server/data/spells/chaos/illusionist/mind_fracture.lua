-- Shattered Psyche: death damage bolt, then a cursing damage-over-time and a short slow.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end
local M = ChaosMysticFx

local HIT = Fx("arcane_circle", CONST_ME_MORTAREA)
local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_DEATHDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, HIT)
-- with the animated missiles (data/lib/chaos_vfx.lua) the bolt is shot by onCastSpell instead
combat:setParameter(COMBAT_PARAM_DISTANCEEFFECT, ChaosVfxMissile and CONST_ANI_NONE or FxMissile("arcane_orb", CONST_ANI_DEATH))

function onGetFormulaValues(player, level, magicLevel)
	local min = ((level / 5) + (magicLevel * 5.7) + 55) * 1.4
	local max = ((level / 5) + (magicLevel * 9.7) + 100) * 1.4
	return -min, -max
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")

function onCastSpell(creature, variant, isHotkey)
	if not creature:isPlayer() then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	-- the impact lands when the bolt arrives: an arcane vortex ring, the arcane hit, then the curse mark (tick_curse;
	-- the Necromancer's `cursed` was reused here before); no tile effect at the cast
	-- (server/data/spells/README_FX.md "Mystic line effects")
	local delayed = target ~= nil and ChaosVfxMissile ~= nil and M ~= nil and M.known("px03_arcane")
	combat:setParameter(COMBAT_PARAM_EFFECT, delayed and CONST_ME_NONE or HIT)
	if not combat:execute(creature, variant) then
		return false
	end
	if target and ChaosVfxMissile then
		local from, to = creature:getPosition(), target:getPosition()
		VfxShoot(from, to, "arcane_bolt")
		if delayed then
			local fly = M.flightMs(from, to)
			M.later(fly, to, "px03_arcane")
			M.later(fly + 150, to, "arcane_hit")
			M.later(fly + 400, to, "tick_curse")
		end
	end
	if target and target ~= creature then
		local dmg = math.max(3, math.floor(creature:getMagicLevel() * 0.3) + 4)
		creature:addDamageCondition(target, CONDITION_CURSED, DAMAGELIST_EXPONENTIAL_DAMAGE, dmg)
		ChaosSpell.slow(target, 2500, 0.3)
	end
	return true
end
