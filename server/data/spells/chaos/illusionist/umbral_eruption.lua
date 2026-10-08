-- Nightburst: shadows gather for 0.9s, then erupt in a 7x7 circle around the cast position.
dofile('data/spells/scripts/chaos/_common.lua')

local area = createCombatArea(AREA_CIRCLE3X3)

local function erupt(casterId, center, min, max)
	local caster = Creature(casterId)
	if not caster then
		return
	end
	local pos = Position(center)
	doAreaCombat(caster, COMBAT_DEATHDAMAGE, pos, area, -math.floor(min), -math.floor(max), Fx("shadow_smoke", CONST_ME_MORTAREA))
	for _, c in ipairs(ChaosSpell.enemiesAround(caster, pos, 3)) do
		ChaosSpell.slow(c, 3000, 0.4)
	end
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local p = player:getPosition()
	local center = {x = p.x, y = p.y, z = p.z}
	local min, max = ChaosSpell.mlValues(player, 5.2, 10.4, 130, 235)
	ChaosSpell.fx(p, "arcane_circle", CONST_ME_MAGIC_RED)
	addEvent(erupt, 900, player:getId(), center, min, max)
	return true
end
