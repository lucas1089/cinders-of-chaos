-- Pack Howl: a howl calls the pack down on the quarry. Your companions leap at the target (range 7) and each bites every monster within 2 sqm of it, 3 bites apiece.
--
-- O332: the Beastmaster's pack spell, level 220 (it took Arrowstorm's place): the wolves clear a pack, not one monster. A bite
-- is physical damage dealt as you, from your level and distance skill, times the wolf factor (Pack Alpha, the Trials' minion
-- damage): ChaosClasses.maulValuesFor, Chaos.classes.companion.spells.howl. It needs a companion out (Wild Bond). Cast:
-- data/spells/chaos/_wolves.lua.
dofile('data/spells/scripts/chaos/_wolves.lua')

function onCastSpell(creature, variant, isHotkey)
	return Wolves.cast('howl', creature, variant)
end
