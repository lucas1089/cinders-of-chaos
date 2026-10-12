-- Primordial Squall: three waves (earth, ice, earth) around the caster, the ice wave chills.
-- Cast time 1.5 s (data/lib/chaos_casting.lua): moving, a new paralysis, another spell or death interrupt it and give
-- the mana and cooldown back. Power x0.98 (was x0.85 before the cast time).
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosCasting then
	dofile('data/lib/chaos_casting.lua')
end

local area = createCombatArea(AREA_CIRCLE5X5)
local WAVES = {
	{COMBAT_EARTHDAMAGE, "poison_cloud", CONST_ME_POISONAREA, "earth_spikes"},
	{COMBAT_ICEDAMAGE, "frost_burst", CONST_ME_ICEAREA, "frost_nova"},
	{COMBAT_EARTHDAMAGE, "poison_cloud", CONST_ME_POISONAREA, "earth_spikes"},
}

onCastSpell = ChaosCasting.spell({
	name = "Primordial Squall", spellId = 213, ms = 1500, fx = {"poison_cloud", CONST_ME_MAGIC_GREEN},
	fire = function(player)
		local p = player:getPosition()
		local center = {x = p.x, y = p.y, z = p.z}
		local min, max = ChaosSpell.mlValues(player, 2.1, 3.9, 45, 90, 0.98)
		ChaosSpell.pulse(player:getId(), #WAVES, 800, function(caster, step)
			local w = WAVES[step]
			local pos = Position(center)
			ChaosSpell.vfx(pos, w[4])
			doAreaCombat(caster, w[1], pos, area, -math.floor(min), -math.floor(max), Fx(w[2], w[3]))
			if w[1] == COMBAT_ICEDAMAGE then
				for _, c in ipairs(ChaosSpell.enemiesAround(caster, pos, 5)) do
					ChaosSpell.slow(c, 3000, 0.5)
				end
			end
			return true
		end)
		return true
	end,
})
