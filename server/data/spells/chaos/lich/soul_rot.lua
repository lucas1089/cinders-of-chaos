-- Soul Rot: rot the target's soul (range 6): heavy death damage every second for 6 s. If the target dies before
-- the rot ends, the rest jumps to the nearest enemy within 3 sqm. A recast on the same target restarts it.
--
-- Ticks: (level / 5 + magic level x 1.2..1.6 + 20..40) x 1.15 x the level scale, Soul Hoard included
-- (necro_config.lua soulRot).
dofile('data/spells/scripts/chaos/_necro.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	if not NecroSpell.class(player) then
		return false
	end
	local target = NecroSpell.target(player, variant)
	if not target then
		return false
	end
	local r = NecroSpell.cfg.soulRot
	local min, max = ChaosNecro.values(player, r.tick)
	ChaosSpell.shoot(player:getPosition(), target:getPosition(), "skull_orb", CONST_ANI_DEATH)
	NecroSpell.fx(target:getPosition(), {"toxic_burst", "px633_green"}, "shadow_smoke", CONST_ME_SMALLCLOUDS)
	NecroSpell.dot(player:getId(), target:getId(), "soulrot", r.ticks, r.tickMs, min, max, COMBAT_DEATHDAMAGE,
		{vfx = "px633_green", fx = CONST_ME_MORTAREA}, r.jumpRadius) -- each tick: the green skull
	return true
end
