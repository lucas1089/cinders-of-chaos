-- Shattered Psyche: death damage bolt, then a cursing damage-over-time (30% of the bolt's damage over 1.8 s) and a short slow.
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
	-- O472: the weapon growth of a caster (ChaosSpell.casterShare: W(level) x the wand of the hands)
	min, max = ChaosSpell.casterScale(player, min, max)
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
		VfxShoot(from, to, ChaosSpell.pack29Name("missile", "arcane_bolt")) -- pair 29: psyche_prism
		if delayed then
			local fly = M.flightMs(from, to)
			M.later(fly, to, "px03_arcane")
			M.later(fly + 150, to, "arcane_hit")
			M.later(fly + 400, to, "tick_curse")
		end
	end
	if target and target ~= creature then
		-- O468: the curse is scripted ticks (ChaosSpell.scriptedDot): they take crit, supports, cards, keystones and the rest like
		-- the bolt. O474: 6 ticks 300 ms apart, together 0.30 x the bolt's own hit (ChaosDotConfig.side; the class spell factor is
		-- not taken off); the rest moves on when the target dies. Against a player the old 5 ticks 2 s apart of what the condition
		-- dealt (magic level x 0.3 + 4).
		local D = ChaosDot
		local lo, hi = onGetFormulaValues(creature, creature:getLevel(), creature:getMagicLevel())
		local side = D.cfg().side
		local old = math.max(3, math.floor(creature:getMagicLevel() * 0.3) + 4) * ChaosSpell.casterShare(creature) -- O472
		ChaosSpell.scriptedDot(creature:getId(), target:getId(), "shatteredpsyche", COMBAT_DEATHDAMAGE, side.ticks, side.tickMs,
			D.sideTick(-lo, -hi, side), CONST_ME_SMALLCLOUDS, {raw = true, pvp = D.pvpSideOpts("shatteredpsyche", old)})
		ChaosSpell.slow(target, 2500, 0.3)
	end
	return true
end
