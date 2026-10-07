-- Warcry: taunts every monster within 4 sqm and slows them 25% for 6s.
dofile('data/spells/scripts/chaos/_common.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local pos = player:getPosition()
	ChaosSpell.fx(pos, "aura_ring", CONST_ME_SOUND_RED)
	for _, c in ipairs(ChaosSpell.enemiesAround(player, pos, 4)) do
		doChallengeCreature(player, c)
		ChaosSpell.slow(c, 6000, 0.25)
		ChaosSpell.fx(c:getPosition(), "blood_rune", CONST_ME_SOUND_RED)
	end
	return true
end
