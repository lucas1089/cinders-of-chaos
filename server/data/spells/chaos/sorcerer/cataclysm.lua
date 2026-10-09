-- Doomtide: three waves (fire, energy, fire) rolling out from the caster over 6x6 area.
dofile('data/spells/scripts/chaos/_common.lua')

local area = createCombatArea(AREA_CIRCLE6X6)
local WAVES = {
	{COMBAT_FIREDAMAGE, "fire_nova", CONST_ME_FIREAREA, "dome_blast_fire"},
	{COMBAT_ENERGYDAMAGE, "chain_lightning", CONST_ME_ENERGYAREA, "storm_ring"},
	{COMBAT_FIREDAMAGE, "fire_nova", CONST_ME_FIREAREA, "fire_explosion"},
}

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local pos = player:getPosition()
	local center = {x = pos.x, y = pos.y, z = pos.z}
	local min, max = ChaosSpell.mlValues(player, 3.5, 6.5, 80, 160, 1.2)

	ChaosSpell.pulse(player:getId(), #WAVES, 700, function(caster, step)
		local w = WAVES[step]
		ChaosSpell.vfx(center, w[4])
		doAreaCombat(caster, w[1], Position(center), area, -math.floor(min), -math.floor(max), Fx(w[2], w[3]))
		return true
	end)
	return true
end
