-- Detonate Mines: every armed mine you threw goes off, 0.1 s apart, oldest first.
-- Rules: data/scripts/chaos/snares_core.lua (detonate); the scheduler: _snares.lua.
dofile('data/spells/scripts/chaos/_common.lua')
dofile('data/spells/scripts/chaos/_snares.lua')

function onCastSpell(creature, variant, isHotkey)
	return ChaosSnares.detonate(creature)
end
