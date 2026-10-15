-- Shield Wave: drive your shield forward; a wave of holy force hits your target and everything in front of you.
--
-- The Sentinel's pack spell (level 150, range 3): the target and every creature in the 3 x 3 tiles in front of you,
-- towards it, take holy damage (PvP rules as the other scripted hits). Numbers and rules: _packtools.lua.
dofile('data/spells/scripts/chaos/_templar.lua')
dofile('data/spells/scripts/chaos/_blades.lua')
dofile('data/spells/scripts/chaos/_packtools.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	if not target or target == player then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
	end
	if not ChaosSpell.canAttack(player, target) then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER)
	end
	ChaosPackTools.shieldWave(player, target, "dome_blast_holy")
	return true
end
