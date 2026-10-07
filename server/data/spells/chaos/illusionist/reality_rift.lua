-- Reality Rift: drags monsters within 5 sqm next to the caster (monsters over 20000 max health are not moved),
-- then two arcane-death implosions at 0.6s and 1.2s.
dofile('data/spells/scripts/chaos/_common.lua')

local area = createCombatArea(AREA_CIRCLE3X3)
local MAX_PULLED_HEALTH = 20000

local function implode(casterId, center, min, max)
	local caster = Creature(casterId)
	if not caster then
		return
	end
	doAreaCombat(caster, COMBAT_DEATHDAMAGE, Position(center), area, -math.floor(min), -math.floor(max), Fx("arcane_circle", CONST_ME_MORTAREA))
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local p = player:getPosition()
	local center = {x = p.x, y = p.y, z = p.z}
	local min, max = ChaosSpell.mlValues(player, 2.8, 5.0, 60, 110)

	ChaosSpell.fx(p, "arcane_circle", CONST_ME_MAGIC_BLUE)
	for _, c in ipairs(ChaosSpell.enemiesAround(player, p, 5)) do
		if c:getMaxHealth() <= MAX_PULLED_HEALTH then
			local spots = ChaosSpell.freeAround(p, c:getPosition())
			if #spots > 0 then
				ChaosSpell.fx(c:getPosition(), "shadow_smoke", CONST_ME_POFF)
				c:teleportTo(spots[1].pos)
				ChaosSpell.fx(spots[1].pos, "shadow_smoke", CONST_ME_MORTAREA)
			end
		end
	end
	addEvent(implode, 600, player:getId(), center, min, max)
	addEvent(implode, 1200, player:getId(), center, min, max)
	return true
end
