-- mana_flow_config.lua: the numbers of the mana flow (server/README.md "Mana flow", server/data/spells/README.md
-- "Fixed spell costs"). Pure data. Rules: mana_flow_core.lua (tested by server/tests/mana_flow_test.lua), engine glue:
-- mana_flow.lua. Beta report (Juggernaut, level 800): every skill only ran on infinite mana potions.
--
-- Spell costs are FIXED (owner 2026-10-21: "Mas o custo de mana das skills ainda tá escalando com o level do char";
-- server/README.md "Fixed spell costs"): every player spell costs the one number of its spells.xml entry at every
-- level, for every class. Only percentages of that number change it (Thrift runes, Mana Cost Reduction, trial nodes).
-- The pool grows with the level, so the same cost is a smaller share of it as the character levels; the regeneration
-- below is how mana keeps up with the faster rotations of the higher levels.
--
-- One rule:
--   * regen: from `regen.fromLevel` the player gets `regen` mana a second on top of the vocation's (a flat number by
--     level, the same for every class: spells cost the same flat mana for every class). Linear between
--     the points; the last value holds. Not under the rift's Parched Veins (fx.noMana).
-- The cost cap of 2026-10-20 (from level 100 no cast cost more than 25% of the maximum mana) is gone: it made a cost
-- depend on the pool (Colossus Fall 332 at level 260, 400 from level 320). Every spell's fixed cost is under its
-- cheapest class's pool at the spell's own level (mana_flow_test.lua checks it).

ChaosManaFlowConfig = {
	regen = {
		fromLevel = 100,
		thinkMs = 1000,
		-- {level, mana a second}
		curve = {{100, 4}, {300, 24}, {600, 45}, {1000, 60}}
	}
}

return ChaosManaFlowConfig
