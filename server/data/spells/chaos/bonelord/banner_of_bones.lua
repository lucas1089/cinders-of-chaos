-- Banner of Bones: for 20 s your minions deal 30% more damage, take 25% less and regenerate 3% of their health
-- every second.
--
-- A timer condition on you (necro_config.lua subId.boneAura) that data/scripts/chaos/necro_minions.lua reads.
dofile('data/spells/scripts/chaos/_necro.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	if not NecroSpell.class(player) then
		return false
	end
	local L, cfg = ChaosNecro, NecroSpell.cfg
	local list = L.minions(player)
	if #list == 0 then
		return ChaosSpell.cancel(player, "You have no minions to rally.")
	end
	L.addTimer(player, cfg.subId.boneAura, cfg.bannerOfBones.durationMs)
	NecroSpell.fx(player:getPosition(), {"bonelord_banner", "necro_seal"}, "bone_aura", CONST_ME_MAGIC_BLUE)
	for _, m in ipairs(list) do
		NecroSpell.fx(m.creature:getPosition(), {"bonelord_rally", "bone_aura"}, "bone_aura", CONST_ME_MAGIC_BLUE)
	end
	return true
end
