-- Tear in the Weave: drags monsters within 5 sqm next to the caster (monsters over 20000 max health are not moved),
-- then two arcane-death implosions at 0.6s and 1.2s.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end

local area = createCombatArea(AREA_CIRCLE3X3)
local MAX_PULLED_HEALTH = 20000

local function implode(casterId, center, min, max)
	local caster = Creature(casterId)
	if not caster then
		return
	end
	-- each implosion: the arcane nova (large effect swap, chaos_big_fx.lua: arcane_circle -> big_nova_arcane_7) and
	-- branching arcane lightning in the middle; no tile effects under the nova
	local M = ChaosMysticFx
	local nova = ChaosSpell.vfx(center, "arcane_circle")
	if M then
		M.send(center, "px195_arcane")
	end
	local tile = Fx("arcane_circle", CONST_ME_MORTAREA)
	doAreaCombat(caster, COMBAT_DEATHDAMAGE, Position(center), area, -math.floor(min), -math.floor(max), M and M.tileFx(nova, tile) or tile)
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local p = player:getPosition()
	local center = {x = p.x, y = p.y, z = p.z}
	local min, max = ChaosSpell.mlValues(player, 3.35, 6.0, 72, 132, 1.4)

	-- the rift: the large void rift (swap of void_rift) with the pair 27 vortex as its core
	ChaosSpell.vfxOr(p, "void_rift", "arcane_circle", CONST_ME_MAGIC_BLUE)
	if ChaosMysticFx then
		ChaosMysticFx.send(p, "rift_void")
	end
	for _, c in ipairs(ChaosSpell.enemiesAround(player, p, 5)) do
		if c:getMaxHealth() <= MAX_PULLED_HEALTH then
			local spots = ChaosSpell.freeAround(p, c:getPosition())
			if #spots > 0 then
				ChaosSpell.fx(c:getPosition(), "shadow_smoke", CONST_ME_POFF)
				if ChaosMysticFx then -- pair 29 only (ChaosPack29Fx): a singularity drags the foe in
					ChaosMysticFx.shoot(c:getPosition(), p, "weave_marble")
				end
				c:teleportTo(spots[1].pos)
				ChaosSpell.fx(spots[1].pos, "shadow_smoke", CONST_ME_MORTAREA)
			end
		end
	end
	addEvent(implode, 600, player:getId(), center, min, max)
	addEvent(implode, 1200, player:getId(), center, min, max)
	return true
end
