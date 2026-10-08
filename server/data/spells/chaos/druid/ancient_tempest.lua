-- Primordial Squall: three waves (earth, ice, earth) around the caster, the ice wave chills.
dofile('data/spells/scripts/chaos/_common.lua')

local area = createCombatArea(AREA_CIRCLE5X5)
local WAVES = {
	{COMBAT_EARTHDAMAGE, "poison_cloud", CONST_ME_POISONAREA},
	{COMBAT_ICEDAMAGE, "frost_burst", CONST_ME_ICEAREA},
	{COMBAT_EARTHDAMAGE, "poison_cloud", CONST_ME_POISONAREA},
}

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local p = player:getPosition()
	local center = {x = p.x, y = p.y, z = p.z}
	local min, max = ChaosSpell.mlValues(player, 2.1, 3.9, 45, 90)

	ChaosSpell.pulse(player:getId(), #WAVES, 800, function(caster, step)
		local w = WAVES[step]
		local pos = Position(center)
		doAreaCombat(caster, w[1], pos, area, -math.floor(min), -math.floor(max), Fx(w[2], w[3]))
		if w[1] == COMBAT_ICEDAMAGE then
			for _, c in ipairs(ChaosSpell.enemiesAround(caster, pos, 5)) do
				ChaosSpell.slow(c, 3000, 0.5)
			end
		end
		return true
	end)
	return true
end
