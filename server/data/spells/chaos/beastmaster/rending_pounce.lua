-- Rending Pounce: the pack pounces. Your companions leap at the target (range 7) and each rends every monster within 1 sqm of it, 2 bites apiece.
--
-- O332: the Beastmaster's cluster spell, level 240 (it took Gale Volley's place): a tight circle around the quarry, harder on
-- the ones at its side than Pack Howl. A bite is physical damage dealt as you, from your level and distance skill, times the
-- wolf factor (Pack Alpha, the Trials' minion damage): ChaosClasses.maulValuesFor, Chaos.classes.companion.spells.pounce. It
-- needs a companion out (Wild Bond). Cast: data/spells/chaos/_wolves.lua.
dofile('data/spells/scripts/chaos/_wolves.lua')

function onCastSpell(creature, variant, isHotkey)
	return Wolves.cast('pounce', creature, variant)
end
