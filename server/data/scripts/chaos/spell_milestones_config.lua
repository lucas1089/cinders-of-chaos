-- Spell path milestones (O752, owner 2026-11-24 "Buraco de magias"): every number. Plain table, loaded with
--     ChaosSpellMilestonesConfig = dofile("data/scripts/chaos/spell_milestones_config.lua")
-- Logic: spell_milestones_core.lua; engine: spell_milestones.lua (the toast, the state field), spell_forms.lua (the Form gate),
-- spell_awakening.lua (the awakening gates); model view: tools/progression_model.lua --spells, rule: --check; tests:
-- tests/spell_milestones_test.lua. Design: docs/SPELL_UPGRADES.md section 2.6; server/README.md "Spell path milestones (O752)".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- The problem: no new attack spell (13 a class, check_attack_counts.py) after level 1200, and up to 310 levels without one
-- between 190 and 500. The fix adds no spell: it puts level gates on what is already built, so every class sees an unlock at
-- least every `limit` levels from `from` to `to`. A milestone is one of
--   spell     a new spell (spells.xml / stock_spells.csv level)
--   socket2   the 2nd support socket of a spell (chaos_supports_config.lua second: spell level + 60, at least 80)
--   socket3   the 3rd support socket (third: spell level + 150, at least 200)
--   form1     the Form I tier of a spell opens (below: the spell's level + formI.add); the rank 10 of spell_ranks_config.lua stays
--   form2     the Form II tier opens (formII by the spell's level); the rank 20 stays
--   awaken    the spell may be awakened (awaken by the spell's level; only listed when above the first slot)
--   slot      an awakening slot opens (slots)
-- A gate never takes back what a character has: it holds only the FIRST pick of a tier and a new awakening. The typical
-- character of spell_upgrade_model.py reaches the rank (or the Seals) after the gate, so no balance model moves: the main spell's
-- Form II gate (at most 1050) is below its typical rank 20 (level 1740), slot 1 and 2 (1800, 1950) below the model's first and
-- second awakening (1900 to 2100, spell_upgrade_balance_config.lua awakening).
return {
	enabled = true,

	-- the rule of tools/progression_model.lua --check: no class goes more than `limit` levels without a milestone between `from`
	-- (the first spell drought, Iron Sage 190 to 500) and `to` (the level cap, O672); the stretch from the last milestone to `to`
	-- counts too
	limit = 150,
	from = 190,
	to = 2500,

	-- Form I of a spell opens `add` levels after the spell (like the support sockets): an early spell at 308 to 490, the level 500
	-- line spell at 800, the level 1200 ultimate at 1500
	formI = {add = 300},
	-- Form II by the level of the spell: the first row whose `below` is above it (a row with no `below` takes the rest). Never
	-- before the spell's Form I.
	formII = {
		{below = 500, level = 1050}, -- every spell learned before 500
		{below = 1200, level = 1650}, -- the line spells (500)
		{level = 2400}, -- the ultimates (1200)
	},
	-- the awakening of a spell by its level (0: only the slot decides); listed as a milestone when above slot 1
	awaken = {
		{below = 500, level = 0},
		{below = 1200, level = 2100},
		{level = 2500}, -- an ultimate awakens at the cap
	},
	-- awakening slot n (spell_awakening_config.lua `slots`: the Seals stay) needs this level
	slots = {1800, 1950, 2250},

	-- the toast at a level-up (ChaosNotify kind "milestone"): the kinds that toast. A new spell and the sockets have their own windows.
	toastKinds = {form1 = true, form2 = true, awaken = true, slot = true},
	-- at most this many names in one toast (the rest: "and N more")
	toastNames = 3,
}
