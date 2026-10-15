-- Sanctified Ground: the ground under you flares with holy light three times; everything within 2 sqm is burned.
--
-- The Templar's pack spell (level 60): 3 pulses of holy damage, one a second, on the creatures within 2 sqm of the
-- cast tile (the engine's area rules). Weapon power and magic level like Radiant Smite. Numbers: _packtools.lua.
dofile('data/spells/scripts/chaos/_templar.lua')
dofile('data/spells/scripts/chaos/_packtools.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	return ChaosPackTools.sanctified(player, "holy_seal")
end
