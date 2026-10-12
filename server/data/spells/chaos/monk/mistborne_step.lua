-- Mistborne Step: roll up to 3 sqm in the direction you face; for 2 s after it you dodge more (+25%).
--
-- Stops at the first blocked tile. The dodge window is a timer condition (ChaosMonk.ids.subId.roll) that
-- data/scripts/chaos/monk_combat.lua reads.
dofile('data/spells/scripts/chaos/_monk.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local M = ChaosMonk
	local from = player:getPosition()
	local dir = player:getDirection()
	local dest
	for i = 1, M.cfg.step.maxSteps do
		local p = ChaosSpell.stepPos(from, dir, i)
		if not ChaosSpell.isFreeTile(p) then
			break
		end
		dest = p
	end
	if not dest then
		return ChaosSpell.cancel(player)
	end
	ChaosSpell.fx(from, "dodge_whoosh", CONST_ME_POFF)
	player:teleportTo(dest)
	ChaosSpell.fx(dest, "dodge_whoosh", CONST_ME_POFF)
	ChaosSpell.vfx(dest, "gale_hit")
	MonkSpell.timer(player, M.ids.subId.roll, M.cfg.evasion.rollMs)
	return true
end
