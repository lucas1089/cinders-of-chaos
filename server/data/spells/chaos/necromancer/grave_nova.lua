-- Grave Nova: the grave breathes out around you; every enemy within 3 sqm takes death damage.
--
-- The Necromancer's area attack (level 50, after Withering Curse; no target needed). Each hit:
-- (level / 5 + magic level x 1.8..2.8 + 25..45) (necro_config.lua graveNova), the class spell factor on top. A cursed
-- monster takes the curse's +15% / +25% like every other hit. Players are hit only where PvP allows it.
dofile('data/spells/scripts/chaos/_necro.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	if not NecroSpell.class(player) then
		return false
	end
	local L, g = ChaosNecro, NecroSpell.cfg.graveNova
	local center = player:getPosition()
	local r2 = g.radius * g.radius + 1 -- the circle of the area (the corners of the square left out)
	NecroSpell.fx(center, {"bone_burst"}, "necro_skull", CONST_ME_MORTAREA)
	-- a ring of death on the tiles of the circle (no effect under the caster: the burst is there)
	for dx = -g.radius, g.radius do
		for dy = -g.radius, g.radius do
			if (dx ~= 0 or dy ~= 0) and dx * dx + dy * dy <= r2 then
				Position(center.x + dx, center.y + dy, center.z):sendMagicEffect(CONST_ME_MORTAREA)
			end
		end
	end
	local min, max = L.values(player, g)
	for _, e in ipairs(L.enemiesAround(player, center, g.radius, true)) do
		local p = e:getPosition()
		local dx, dy = p.x - center.x, p.y - center.y
		if dx * dx + dy * dy <= r2 then
			L.damage(player, e, COMBAT_DEATHDAMAGE, min, max, CONST_ME_NONE, ORIGIN_SPELL)
		end
	end
	return true
end
