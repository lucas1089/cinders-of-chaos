-- Raise Dead: raise minions from the corpses around you (up to 4 sqm), or one from nothing for twice the mana.
--
-- The Necromancer and the Bone Lord raise Risen Skeletons (Necromancer up to 2 per cast, Bone Lord up to 3), the
-- Lich a single Lich Shade. A corpse is used only when it holds no loot and belongs to you, your party or nobody;
-- it is consumed. Caps, health and the minions' hits: data/scripts/chaos/necro_config.lua (minions), managed by
-- data/scripts/chaos/necro_minions.lua.
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
	local cfg, N, L = NecroSpell.cfg, ChaosNecroCore, ChaosNecro
	local kind = N.raiseKind(cfg, classKey)
	local pos = player:getPosition()
	local corpses = L.usableCorpses(player, pos, cfg.raiseDead.radius, cfg.raiseDead.perCast[classKey] or 1)
	local plan, why = N.raisePlan(cfg, classKey, player:getLevel(), L.count(player, kind), #corpses)
	if not plan then
		return ChaosSpell.cancel(player, why)
	end
	if plan.fromNothing then
		-- the spell's own mana is taken by the engine after this returns true; the extra is taken here
		if player:getMana() < plan.extraMana + cfg.raiseDead.mana then
			return ChaosSpell.cancel(player, RETURNVALUE_NOTENOUGHMANA)
		end
		local minion = L.raise(player, kind, pos)
		if not minion then
			return ChaosSpell.cancel(player, RETURNVALUE_NOTENOUGHROOM)
		end
		player:addMana(-plan.extraMana)
		-- the seal where the minion rises (it may be placed next to the caster)
		ChaosSpell.vfxOr(minion:getPosition(), "necro_seal", "summon_portal", CONST_ME_MORTAREA)
		return true
	end
	local raised = 0
	for i = 1, plan.fromCorpses do
		local c = corpses[i]
		local cpos = c.pos
		L.consumeCorpse(c)
		if L.raise(player, kind, cpos) then
			raised = raised + 1
			ChaosSpell.shoot(pos, cpos, "skull_orb", CONST_ANI_DEATH)
			ChaosSpell.vfxOr(cpos, "necro_seal", "summon_portal", CONST_ME_MORTAREA) -- the seal on the corpse
		end
	end
	if raised == 0 then
		return ChaosSpell.cancel(player, RETURNVALUE_NOTENOUGHROOM)
	end
	return true
end
