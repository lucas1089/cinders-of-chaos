-- Seeker Mine: throws a mine up to 4 sqm (onto your attack target, else straight ahead). It arms after 0.8 s and waits
-- for Detonate Mines or its 8 s fuse; then a burst hits up to 8 enemies within 2 sqm for 1.15 times a trap's hit. At
-- most 5 mines (the oldest goes). The element works as for Snare Trap (kah snar "ice").
-- Rules and numbers: data/scripts/chaos/snares_core.lua, snares_config.lua; the scheduler: _snares.lua.
dofile('data/spells/scripts/chaos/_common.lua')
dofile('data/spells/scripts/chaos/_snares.lua')

function onCastSpell(creature, variant, isHotkey)
	return ChaosSnares.cast(creature, "mine", variant)
end
