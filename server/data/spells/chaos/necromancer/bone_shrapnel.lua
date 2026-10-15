-- Bone Shrapnel: the bones of your target burst outward; it and every monster next to it are cut by the shards.
--
-- The Necromancer's pack spell (level 60, range 7): physical damage on the target and on every monster within 1 sqm of
-- it, each a Bone Spear's hit. Players are only hit when they are the target. Numbers and rules: _packtools.lua.
dofile('data/spells/scripts/chaos/_necro.lua')
dofile('data/spells/scripts/chaos/_packtools.lua')

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
	ChaosPackTools.shrapnel(player, target, "bone_burst")
	return true
end
