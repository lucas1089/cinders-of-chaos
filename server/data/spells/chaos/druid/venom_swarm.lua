-- Blightswarm: toxic cloud around the caster, poisons everything it hits for 1.8 s; the poison moves to a nearby enemy if its target dies.
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
	local min = ((level / 5) + (magicLevel * 2.4) + 18)
	local max = ((level / 5) + (magicLevel * 4.1) + 36)
	return -min, -max
end

-- O468: the poison is scripted ticks (ChaosSpell.scriptedDot) of what the condition dealt (magic level x 0.25 + 3): they take
-- crit, supports, cards, keystones and the rest like the cloud's own hit. O474: the same total (8 old ticks) in 6 ticks 300 ms
-- apart, the first 300 ms after the cast (ChaosDotConfig.swarm); the rest moves on when the target dies. Against a player the old
-- 8 ticks 2 s apart (ChaosDotConfig.pvp).
function onVenomSwarmTarget(creature, target)
	local D = ChaosDot
	local dmg = math.max(2, math.floor(creature:getMagicLevel() * 0.25) + 3)
	local swarm = D.cfg().swarm
	ChaosSpell.scriptedDot(creature:getId(), target:getId(), "blightswarm", COMBAT_EARTHDAMAGE, swarm.ticks, swarm.tickMs,
		D.swarmTick(dmg, swarm), CONST_ME_HITBYPOISON, {pvp = D.pvpSideOpts("blightswarm", dmg)})
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
