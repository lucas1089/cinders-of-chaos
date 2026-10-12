-- Doomtide: three waves (fire, energy, fire) rolling out from the caster over 6x6 area.
-- Cast time 1.5 s (data/lib/chaos_casting.lua): moving, a new paralysis, another spell or death interrupt it and give
-- the mana and cooldown back. Power x1.38 (was x1.2 before the cast time).
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosCasting then
	dofile('data/lib/chaos_casting.lua')
end

local area = createCombatArea(AREA_CIRCLE6X6)
local WAVES = {
	{COMBAT_FIREDAMAGE, "fire_nova", CONST_ME_FIREAREA, "dome_blast_fire"},
	{COMBAT_ENERGYDAMAGE, "chain_lightning", CONST_ME_ENERGYAREA, "storm_ring"},
	{COMBAT_FIREDAMAGE, "fire_nova", CONST_ME_FIREAREA, "fire_explosion"},
}

onCastSpell = ChaosCasting.spell({
	name = "Doomtide", spellId = 206, ms = 1500, fx = {"fire_nova", CONST_ME_MAGIC_RED},
	fire = function(player)
		local pos = player:getPosition()
		local center = {x = pos.x, y = pos.y, z = pos.z}
		local min, max = ChaosSpell.mlValues(player, 3.5, 6.5, 80, 160, 1.38)
		ChaosSpell.pulse(player:getId(), #WAVES, 700, function(caster, step)
			local w = WAVES[step]
			ChaosSpell.vfx(center, w[4])
			doAreaCombat(caster, w[1], Position(center), area, -math.floor(min), -math.floor(max), Fx(w[2], w[3]))
			return true
		end)
		return true
	end,
})
