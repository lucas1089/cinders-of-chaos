-- Corpse Explosion: up to 3 corpses within 3 sqm of the target (range 7) burst; each burst hits every enemy within
-- 1 sqm of it with death damage. Needs a usable corpse (no loot inside, yours, your party's or nobody's); without
-- one the spell fails and costs nothing. The corpses are consumed.
--
-- Each burst: (level / 5 + magic level x 2..3 + 40..80) x the level scale, Soul Hoard included
-- (necro_config.lua corpseExplosion).
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
	local L, c = ChaosNecro, NecroSpell.cfg.corpseExplosion
	local corpses = L.usableCorpses(player, target:getPosition(), c.radius, c.maxCorpses)
	if #corpses == 0 then
		return ChaosSpell.cancel(player, "There is no corpse to explode near your target.")
	end
	local min, max = L.values(player, c.hit)
	for _, corpse in ipairs(corpses) do
		local pos = corpse.pos
		L.consumeCorpse(corpse)
		ChaosSpell.fx(pos, "bone_burst", CONST_ME_MORTAREA)
		for _, e in ipairs(L.enemiesAround(player, pos, c.burstRadius, true)) do
			L.damage(player, e, COMBAT_DEATHDAMAGE, min, max, CONST_ME_MORTAREA, ORIGIN_SPELL)
		end
	end
	return true
end
