-- Life Siphon: drain the target's life (range 5): three death strikes half a second apart; you heal for half of
-- the damage they deal.
--
-- Strikes: (level / 5 + magic level x 1.1..1.6 + 20..40) x 1.15 x the level scale, Soul Hoard included
-- (necro_config.lua lifeSiphon).
dofile('data/spells/scripts/chaos/_necro.lua')

local function pulse(playerId, targetId, min, max, left)
	local player = Player(playerId)
	local target = Creature(targetId)
	if not player or player:getHealth() <= 0 or not target or target:getHealth() <= 0 then
		return
	end
	local ppos, tpos = player:getPosition(), target:getPosition()
	if ChaosNecroCore.distance(ppos, tpos) > 7 then
		return
	end
	tpos:sendDistanceEffect(ppos, FxMissile("skull_orb", CONST_ANI_DEATH))
	local drained = NecroSpell.fx(tpos, {"lich_soul_drain", "px448_crimson"}, "shadow_smoke", CONST_ME_MAGIC_RED)
	local dealt = ChaosNecro.damage(player, target, COMBAT_DEATHDAMAGE, min, max,
		drained == "lich_soul_drain" and CONST_ME_NONE or CONST_ME_MAGIC_RED, ORIGIN_SPELL)
	local heal = ChaosNecroCore.siphonHeal(NecroSpell.cfg, dealt)
	if heal > 0 then
		ChaosSpell.healTarget(player, player, heal, heal, Fx("heal_sparkle", CONST_ME_MAGIC_GREEN))
	end
	if left > 1 then
		addEvent(pulse, NecroSpell.cfg.lifeSiphon.pulseMs, playerId, targetId, min, max, left - 1)
	end
end

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
	local s = NecroSpell.cfg.lifeSiphon
	local min, max = ChaosNecro.values(player, s.hit)
	pulse(player:getId(), target:getId(), min, max, s.pulses)
	return true
end
