-- Doomtide: three waves (fire, energy, fire) rolling out from the caster over 6x6 area.
-- Cast time 1.5 s (data/lib/chaos_casting.lua): moving, a new paralysis, another spell or death interrupt it and give
-- the mana and cooldown back. Power x1.38 (was x1.2 before the cast time).
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosCasting then
	dofile('data/lib/chaos_casting.lua')
end
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end

local area = createCombatArea(AREA_CIRCLE6X6)
local WAVES = {
	{COMBAT_FIREDAMAGE, "fire_nova", CONST_ME_FIREAREA, "dome_blast_fire"},
	{COMBAT_ENERGYDAMAGE, "chain_lightning", CONST_ME_ENERGYAREA, "storm_ring"},
	{COMBAT_FIREDAMAGE, "fire_nova", CONST_ME_FIREAREA, "fire_explosion"},
}
-- each wave also bursts on four tiles of a ring at this radius (server/data/spells/README_FX.md "Mystic line effects")
local BURSTS = {{"fire_explosion", 3}, {"lightning_strike", 4}, {"meteor_fall", 3}}

onCastSpell = ChaosCasting.spell({
	name = "Doomtide", spellId = 206, ms = 1500, fx = {"fire_nova", CONST_ME_MAGIC_RED},
	fire = function(player)
		local pos = player:getPosition()
		local center = {x = pos.x, y = pos.y, z = pos.z}
		local min, max = ChaosSpell.mlValues(player, 3.5, 6.5, 80, 160, 1.38)
		ChaosSpell.pulse(player:getId(), #WAVES, 700, function(caster, step)
			local w = WAVES[step]
			local M = ChaosMysticFx
			local big = M ~= nil and ChaosBigFx ~= nil and ChaosBigFx.swapFor and ChaosBigFx.swapFor(206, w[4]) ~= nil
			ChaosSpell.vfx(center, w[4])
			if M then
				local b = BURSTS[step]
				for i, p in ipairs(M.ring(center, b[2], 4, 0.4 + step)) do
					M.later(60 * (i - 1), p, b[1])
				end
			end
			local tile = Fx(w[2], w[3])
			doAreaCombat(caster, w[1], Position(center), area, -math.floor(min), -math.floor(max), M and M.tileFx(big, tile) or tile)
			return true
		end)
		return true
	end,
})
