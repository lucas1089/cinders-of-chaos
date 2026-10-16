-- Falling Pyre: marks the target's position, the meteor lands 1.2s later (fire, 5x5) and sets enemies ablaze.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end

local area = createCombatArea(AREA_CIRCLE2X2)
local DELAY = 1200

local function impact(casterId, pos, min, max)
	local caster = Creature(casterId)
	if not caster then
		return
	end
	pos = Position(pos)
	-- a fire shockwave ring over the landing covers the 5x5 area: no tile effects then
	local M = ChaosMysticFx
	local ring = M ~= nil and M.send(pos, "big_shock_fire_7")
	local tile = Fx("fire_nova", CONST_ME_FIREAREA)
	doAreaCombat(caster, COMBAT_FIREDAMAGE, pos, area, -math.floor(min), -math.floor(max), M and M.tileFx(ring, tile) or tile)
	local dmg = math.max(3, math.floor(caster:getMagicLevel() * 0.2) + 5)
	for _, c in ipairs(ChaosSpell.enemiesAround(caster, pos, 2)) do
		caster:addDamageCondition(c, CONDITION_FIRE, DAMAGELIST_VARYING_PERIOD, dmg, {10, 12}, 5)
	end
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	if not target then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
	end
	local pos = target:getPosition()
	local min, max = ChaosSpell.mlValues(player, 6.6, 10.8, 145, 265, 1.2)

	ChaosSpell.vshoot(player:getPosition(), pos, "fireball", "fire_bolt", CONST_ANI_FIRE)
	if ChaosSpell.vfx(pos, "infernal_seal") then
		-- the meteor art falls for about 0.66 s before it hits the ground
		addEvent(function(p) ChaosSpell.vfx(p, "meteor_strike") end, DELAY - 660, {x = pos.x, y = pos.y, z = pos.z})
	else
		ChaosSpell.fx(pos, "arcane_circle", CONST_ME_MAGIC_RED)
	end
	addEvent(impact, DELAY, player:getId(), {x = pos.x, y = pos.y, z = pos.z}, min, max)
	return true
end
