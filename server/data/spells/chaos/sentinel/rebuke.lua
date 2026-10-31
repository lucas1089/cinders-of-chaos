-- Rebuke: the Sentinel calls every monster within 4 sqm to face it (taunt) and slows them 25% for 6 seconds. Only monsters that are not player summons; players are never touched.
-- Numbers: ChaosTemplar.cfg.rebuke.
dofile('data/spells/scripts/chaos/_templar.lua')

local r = ChaosTemplar.cfg.rebuke

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local pos = player:getPosition()
	ChaosSpell.vfxOr(pos, "solar_flash", "holy_cross", CONST_ME_HOLYAREA)
	for _, c in ipairs(ChaosSpell.enemiesAround(player, pos, r.radius)) do
		doChallengeCreature(player, c)
		ChaosSpell.slow(c, r.durationMs, r.slow)
		c:registerEvent("ChaosTemplarCombat")
		ChaosSpell.fx(c:getPosition(), "holy_smite", CONST_ME_YELLOW_RINGS)
	end
	return true
end
