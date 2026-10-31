-- Snare Trap: throws a trap up to 4 sqm (onto your attack target, else straight ahead). It arms after 0.6 s; the first
-- monster within 1 sqm sets it off: a burst hits up to 8 enemies within 2 sqm. At most 3 traps (the oldest goes); a trap lasts 20 s.
-- Say an element after the words (drai snar "fire"; also ice, energy, earth, death, holy, physical) to choose what it carries; it is remembered.
-- Without one, a brand rune in the spell picks it.
-- Rules and numbers: data/scripts/chaos/snares_core.lua, snares_config.lua; the scheduler: _snares.lua.
dofile('data/spells/scripts/chaos/_common.lua')
dofile('data/spells/scripts/chaos/_snares.lua')

function onCastSpell(creature, variant, isHotkey)
	return ChaosSnares.cast(creature, "trap", variant)
end
