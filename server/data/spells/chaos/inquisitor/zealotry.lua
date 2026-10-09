-- Zealotry: for 20 seconds every melee weapon hit fans the Inquisitor's zeal: +4% damage per stack on everything it
-- deals, up to 10 stacks (+40%). The stacks fall away 3 seconds after the last hit (ChaosTemplar.cfg.zealotry;
-- counted by data/scripts/chaos/templar_combat.lua, which sees the buff as a timer condition).
dofile('data/spells/scripts/chaos/_templar.lua')

local T = ChaosTemplar

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	TemplarSpell.addTimer(player, T.cfg.ids.subId.zealotry, T.cfg.zealotry.durationMs)
	ChaosSpell.vfxOr(player:getPosition(), "aura_burst_gold", "holy_spiral", CONST_ME_YELLOWENERGY)
	return true
end
