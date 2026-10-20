-- mana_flow_config.lua: the numbers of the mana flow (server/README.md "Mana flow", server/data/spells/README.md
-- "Mana flow"). Pure data. Rules: mana_flow_core.lua (tested by server/tests/mana_flow_test.lua), engine glue:
-- mana_flow.lua. Beta report (Juggernaut, level 800): every skill only ran on infinite mana potions.
--
-- What the report saw: a spell's mana cost is FLAT (200-700 for the Juggernaut's kit), the pool grows 5 a level and
-- the vocation regenerates 2.5 a second, so the best rotation (44 mana a second at level 300) was never paid by the
-- regeneration. The "cost that scales" is the display scale (display_scale_core.lua): the spellbook and the mana bar
-- show a flat cost x the viewer's factor (215 at level 800, 1000 at level 1000), the pool shown is scaled the same,
-- so the cost against the pool never changed. Nothing in the engine scaled a cost.
--
-- Two rules:
--   * regen: from `regen.fromLevel` the player gets `regen` mana a second on top of the vocation's (a flat number by
--     level, the same for every class: spells cost the same flat mana for every class). Linear between
--     the points; the last value holds. Not under the rift's Parched Veins (fx.noMana).
--   * cost cap: from `cap.fromLevel` no cast costs more than `cap.share` of the maximum mana (the mana reserved by
--     vigils counts as part of it, or reserving would make casts free). Runs in ChaosSpellEvents "cost", after the
--     other discounts, so Thrift and Mana Cost Reduction still work.

ChaosManaFlowConfig = {
	regen = {
		fromLevel = 100,
		thinkMs = 1000,
		-- {level, mana a second}
		curve = {{100, 4}, {300, 24}, {600, 45}, {1000, 60}}
	},
	cap = {fromLevel = 100, share = 0.25}
}

return ChaosManaFlowConfig
