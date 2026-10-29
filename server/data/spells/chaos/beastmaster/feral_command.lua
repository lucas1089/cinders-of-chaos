-- Feral Command: your companions leap at the target (range 7) and maul it, each for 1.5 bites at once.
--
-- The Beastmaster's command. A bite is physical damage dealt as you, from your level and distance skill, times the wolf
-- factor (Pack Alpha, the Trials' minion damage, O332): ChaosClasses.maulValuesFor, Chaos.classes.companion.spells.feral. It
-- needs a companion out (Wild Bond). Cast: data/spells/chaos/_wolves.lua.
dofile('data/spells/scripts/chaos/_wolves.lua')

function onCastSpell(creature, variant, isHotkey)
	return Wolves.cast('feral', creature, variant)
end
