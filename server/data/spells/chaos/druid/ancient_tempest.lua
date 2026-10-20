-- Primordial Squall: three waves (earth, ice, earth) around the caster, the ice wave chills.
-- Cast time 1.5 s (data/lib/chaos_casting.lua): moving, a new paralysis, another spell or death interrupt it and give
-- the mana and cooldown back. Power x1.0 (owner, 2026-10-20: no area discount; was x0.98, x0.85 before the cast time).
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosCasting then
	dofile('data/lib/chaos_casting.lua')
end
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end

local area = createCombatArea(AREA_CIRCLE5X5)
local WAVES = {
	{COMBAT_EARTHDAMAGE, "poison_burst", CONST_ME_POISONAREA, "earth_spikes"},
	{COMBAT_ICEDAMAGE, "frost_burst", CONST_ME_ICEAREA, "frost_nova"},
	{COMBAT_EARTHDAMAGE, "poison_burst", CONST_ME_POISONAREA, "earth_spikes"},
}
-- each wave also bursts on four tiles of a ring at this radius (server/data/spells/README_FX.md "Mystic line effects")
local BURSTS = {{"earth_spikes", 3}, {"nova_frost", 3}, {"earth_spikes", 4}}

onCastSpell = ChaosCasting.spell({
	name = "Primordial Squall", spellId = 213, ms = 1500, fx = {"poison_burst", CONST_ME_MAGIC_GREEN},
	fire = function(player)
		local p = player:getPosition()
		local center = {x = p.x, y = p.y, z = p.z}
		local min, max = ChaosSpell.mlValues(player, 2.1, 3.9, 45, 90)
		ChaosSpell.pulse(player:getId(), #WAVES, 800, function(caster, step)
			local w = WAVES[step]
			local pos = Position(center)
			local M = ChaosMysticFx
			local big = M ~= nil and ChaosBigFx ~= nil and ChaosBigFx.swapFor and ChaosBigFx.swapFor(213, w[4]) ~= nil
			ChaosSpell.vfx(pos, w[4])
			if M then
				local b = BURSTS[step]
				for i, rp in ipairs(M.ring(center, b[2], 4, 0.4 + step)) do
					M.later(60 * (i - 1), rp, b[1])
				end
			end
			local tile = Fx(w[2], w[3])
			doAreaCombat(caster, w[1], pos, area, -math.floor(min), -math.floor(max), M and M.tileFx(big, tile) or tile)
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
