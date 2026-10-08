-- Falling Pyre: marks the target's position, the meteor lands 1.2s later (fire, 5x5) and sets enemies ablaze.
dofile('data/spells/scripts/chaos/_common.lua')

local area = createCombatArea(AREA_CIRCLE2X2)
local DELAY = 1200

local function impact(casterId, pos, min, max)
	local caster = Creature(casterId)
	if not caster then
		return
	end
	pos = Position(pos)
	doAreaCombat(caster, COMBAT_FIREDAMAGE, pos, area, -math.floor(min), -math.floor(max), Fx("fire_nova", CONST_ME_FIREAREA))
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
	local min, max = ChaosSpell.mlValues(player, 6.6, 10.8, 145, 265)

	ChaosSpell.shoot(player:getPosition(), pos, "fire_bolt", CONST_ANI_FIRE)
	ChaosSpell.fx(pos, "arcane_circle", CONST_ME_MAGIC_RED)
	addEvent(impact, DELAY, player:getId(), {x = pos.x, y = pos.y, z = pos.z}, min, max)
	return true
end
