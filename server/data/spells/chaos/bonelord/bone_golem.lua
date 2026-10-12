-- Bone Golem: raise the Bone Golem, a hulking construct of bone (one at a time, on top of your skeletons). It slams
-- every enemy next to it and taunts the monsters around it. With the golem out, the cast calls it back to your side
-- and heals half of its health.
--
-- Health and slams scale with your level and magic level (necro_config.lua minions.golem, golemClass); its hits
-- are dealt as you (data/scripts/chaos/necro_minions.lua).
dofile('data/spells/scripts/chaos/_necro.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local classKey = NecroSpell.class(player)
	if not classKey then
		return false
	end
	if player:getSkull() == SKULL_BLACK then
		return ChaosSpell.cancel(player)
	end
	local L, N, cfg = ChaosNecro, ChaosNecroCore, NecroSpell.cfg
	local pos = player:getPosition()
	local have = L.minions(player, "golem")
	if #have > 0 then
		for _, m in ipairs(have) do
			local g = m.creature
			if N.distance(g:getPosition(), pos) > 1 then
				local spot = L.spotAt(pos, pos)
				if spot then
					g:teleportTo(spot, true)
				end
			end
			g:addHealth("healing", math.floor(g:getMaxHealth() * cfg.boneGolem.heal)) -- (damage type, amount) on this engine
			ChaosSpell.fx(g:getPosition(), "heal_sparkle", CONST_ME_MAGIC_GREEN)
		end
		return true
	end
	if N.minionCap(cfg, classKey, "golem", player:getLevel()) <= 0 then
		return ChaosSpell.cancel(player, "Only a Bone Lord can raise the Bone Golem.")
	end
	local spots = ChaosSpell.freeAround(pos, pos)
	if not spots[1] or not L.raise(player, "golem", spots[1].pos) then
		return ChaosSpell.cancel(player, RETURNVALUE_NOTENOUGHROOM)
	end
	NecroSpell.fx(spots[1].pos, {"bonelord_golem_rise", "necro_seal"}, "ground_slam", CONST_ME_GROUNDSHAKER)
	return true
end
