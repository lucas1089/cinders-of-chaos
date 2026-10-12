-- Bone Offering: the skeleton nearest to the target (range 7) bursts apart: physical damage to every enemy within
-- 2 sqm of it, plus 15% of the skeleton's remaining health; you take 20% less damage for 6 s. The skeleton is gone
-- (raise another one). Needs a skeleton; the Bone Golem is never offered.
--
-- (level / 5 + magic level x 4.5..6.5 + 80..160) x the level scale (necro_config.lua boneOffering); the shield is a
-- timer condition read by data/scripts/chaos/necromancer_combat.lua.
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
	local L, N, cfg = ChaosNecro, ChaosNecroCore, NecroSpell.cfg
	local list = {}
	for _, m in ipairs(L.minions(player, "skeleton")) do
		list[#list + 1] = {kind = m.kind, pos = m.creature:getPosition(), id = m.creature:getId(), creature = m.creature}
	end
	local pick = N.pickSacrifice(list, target:getPosition())
	if not pick then
		return ChaosSpell.cancel(player, "You have no skeleton to offer.")
	end
	local o = cfg.boneOffering
	local min, max = N.offeringValues(cfg, player:getLevel(), player:getMagicLevel(), pick.creature:getHealth())
	-- Covenant of the Grave: a spell of the owner (the bigger skeleton's health already raised it)
	local own = L.ownSpellFactor(player)
	min, max = math.floor(min * own), math.floor(max * own)
	local pos = pick.pos
	L.dismiss(pick.creature)
	if NecroSpell.fx(pos, {"bonelord_offering", "bone_burst"}, "bone_burst", CONST_ME_GROUNDSHAKER) ~= "bonelord_offering" then
		ChaosSpell.vfx(pos, "px633_indigo")
	end
	for _, e in ipairs(L.enemiesAround(player, pos, o.radius, true)) do
		L.damage(player, e, COMBAT_PHYSICALDAMAGE, min, max, CONST_ME_HITAREA, ORIGIN_SPELL)
	end
	L.addTimer(player, cfg.subId.boneShield, o.shieldMs)
	NecroSpell.fx(player:getPosition(), {"bonelord_ward", "bone_aura"}, "bone_aura", CONST_ME_BLOCKHIT)
	return true
end
