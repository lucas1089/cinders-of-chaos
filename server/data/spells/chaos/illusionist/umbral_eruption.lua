-- Nightburst: shadows gather for 0.9s, then erupt in a 7x7 circle around the cast position.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end

local area = createCombatArea(AREA_CIRCLE3X3)

local function erupt(casterId, center, min, max)
	local caster = Creature(casterId)
	if not caster then
		return
	end
	local pos = Position(center)
	-- the eruption: the void nova (large effect swap, chaos_big_fx.lua: shadow_smoke -> big_nova_void_7) and four
	-- shadow eruptions round it; the gather before it is the pack void_maw. No tile effects under the nova
	-- (server/data/spells/README_FX.md "Mystic line effects")
	local M = ChaosMysticFx
	local nova = ChaosSpell.vfx(pos, "shadow_smoke")
	if M then
		for i, p in ipairs(M.ring(center, 2, 4)) do
			M.later(50 * (i - 1), p, "shadow_eruption")
		end
	end
	local tile = Fx("shadow_smoke", CONST_ME_MORTAREA)
	doAreaCombat(caster, COMBAT_DEATHDAMAGE, pos, area, -math.floor(min), -math.floor(max), M and M.tileFx(nova, tile) or tile)
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
	local min, max = ChaosSpell.mlValues(player, 5.2, 10.4, 130, 235, 1.4)
	ChaosSpell.vfxOr(p, "void_maw", "arcane_circle", CONST_ME_MAGIC_RED)
	addEvent(erupt, 900, player:getId(), center, min, max)
	return true
end
