-- Palm Shockwave: an open palm on the target next to you sends a shockwave through every monster within 2 sqm of it.
--
-- The Monk line's pack strike (all three classes, level 50): the target takes an Ashen Fist (+2 chi), every other
-- monster within 2 sqm of it twice that (a player only as the target). Numbers and rules: _packtools.lua.
dofile('data/spells/scripts/chaos/_monk.lua')
dofile('data/spells/scripts/chaos/_packtools.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = MonkSpell.meleeTarget(player, variant)
	if not target then
		return false
	end
	ChaosPackTools.shockwave(player, target, "aura_burst_gold")
	return true
end
