-- Soul Rot: rot the target's soul (range 6): heavy death damage every 0.4 s for 2.4 s, the first tick at once. If the target dies
-- before the rot ends, the rest moves to a nearby enemy within 3 sqm. A recast on the same target restarts it.
-- (Ticks and the jump are the shared rule of every damage over time, ChaosSpell.dotChain. Against a player: the old gap (1 s), first tick
-- (after 1 s) and size (x1/1.5) and no jump, ChaosDotConfig.pvp.necro.)
--
-- Ticks: (level / 5 + magic level x 1.2..1.6 + 20..40) x 1.725 (was 1.15, O474) x the level scale, Soul Hoard included
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
	-- Lingering Rot (the passive tree, class_tree.lua): +25%
	local min, max = ChaosNecro.values(player, r.tick, 1 + ChaosClassTree.value(player, "ctLingeringRot", "bonus"))
	ChaosSpell.pshoot(player:getPosition(), target:getPosition(), "proj_poison_dart_necrotic", nil, "skull_orb", CONST_ANI_DEATH)
	NecroSpell.fx(target:getPosition(), {"toxic_burst", "px633_green"}, "shadow_smoke", CONST_ME_SMALLCLOUDS)
	local tickMs, firstMs, radius = r.tickMs, 0, r.jumpRadius
	local D = ChaosDot
	if D and target:isPlayer() then
		local old = D.pvpNecro("soulrot")
		tickMs, firstMs, radius = old.tickMs or tickMs, old.firstMs or 0, 0
		min, max = min * old.mult, max * old.mult
	end
	NecroSpell.dot(player:getId(), target:getId(), "soulrot", r.ticks, tickMs, min, max, COMBAT_DEATHDAMAGE,
		{vfx = "px633_green", fx = CONST_ME_MORTAREA}, radius, firstMs) -- each tick: the green skull
	return true
end
