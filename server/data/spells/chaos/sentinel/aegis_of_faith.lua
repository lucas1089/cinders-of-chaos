-- Aegis of Faith: the Sentinel raises its shield and its faith: for 5 seconds it takes 40% less damage
-- (ChaosTemplar.cfg.aegis; applied by data/scripts/chaos/templar_combat.lua, which sees the timer condition).
-- Needs a shield in hand.
dofile('data/spells/scripts/chaos/_templar.lua')

local T = ChaosTemplar

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	if not TemplarSpell.hasShield(player) then
		player:sendCancelMessage("You need a shield for Aegis of Faith.")
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		return false
	end
	TemplarSpell.addTimer(player, T.cfg.ids.subId.aegis, T.cfg.aegis.durationMs)
	ChaosSpell.vfxOr(player:getPosition(), "dawn_aegis", "reflect_aegis", CONST_ME_BLOCKHIT)
	return true
end
