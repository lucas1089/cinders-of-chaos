-- Pack Frenzy: Your companions leap at the target (range 7) and maul it in a frenzy, each for 3.3 bites at once (Feral Command: 1.5). 8 s cooldown.
-- Feral Command's late sibling; the 8 s cooldown comes from the cooldown ladder.
--
-- The Beastmaster's command. A bite is physical damage dealt as you, from your level and distance skill, times the wolf
-- factor (Pack Alpha, the Trials' minion damage, O332): ChaosClasses.maulValuesFor, Chaos.classes.companion.spells.frenzy. It
-- needs a companion out (Wild Bond). Cast: data/spells/chaos/_wolves.lua.
dofile('data/spells/scripts/chaos/_wolves.lua')

function onCastSpell(creature, variant, isHotkey)
	return Wolves.cast('frenzy', creature, variant)
end
