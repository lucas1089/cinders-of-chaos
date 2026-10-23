-- Weapon coverage audit: every number and every allowance (tools/weapon_coverage.lua; server/README.md "Weapon
-- coverage"). The CI step runs `luajit tools/weapon_coverage.lua --check` from server/. Plain table, Lua 5.1 / LuaJIT
-- and 5.3.

return {
	-- level bands (from, to): a weapon sits in the band that holds its required level (from <= level < to); the last
	-- band is open ended. The labels are the owner's (2026-10-23).
	bands = {
		{1, 20, "1-20"}, {20, 50, "20-50"}, {50, 100, "50-100"}, {100, 200, "100-200"}, {200, 400, "200-400"},
		{400, 700, "400-700"}, {700, 1000, "700-1000"}, {1000, 1500, "1000-1500"}, {1500, 100000, "1500-2400+"}
	},
	-- the level a band's power is judged at: the band's top (the last band: this level)
	lastBandTop = 2400,

	-- the thresholds of --check: a class line's band needs at least `minOptions` weapons it can wield and obtain whose
	-- required level is in the band, and the best of them at least `minPower` of the tier at the top of the band.
	minOptions = 3,
	minPower = 0.80,
	-- a drop must be at least this likely to count as a way to get the weapon (loot chance per 100000: 20 = 0.02%)
	minDropChance = 20,

	-- known gaps, "Class:band label" or "Line:band label" ("Thief" = the three classes of the line): the cells
	-- --check lets stay empty. Two other agents fill these (2026-10-23): tighten the list when they are done.
	-- Anything not listed fails the build.
	handledElsewhere = {
		Thief = "dual daggers and more daggers (the Thief line)",
		Monk = "Monk weapons (the Monk line)"
	},
	-- cells that may stay below the threshold on purpose: {"Class", "band label", "why"}. Empty = none.
	knownGaps = {},

	-- the tier of a level: the attack of the equipment sets at that level (tools/install_gear_sets.py ANCHORS and
	-- CURVES; tools/weapon_sim.py calls it "one tier"; tools/weapon_coverage_test.py checks they are equal). One-handed
	-- melee = attack, two-handed = attack + 3, bow = bow, crossbow = bow + 3, wand and rod = the mean damage.
	anchors = {8, 50, 100, 200, 400, 700, 1000, 1500, 2000},
	curves = {
		attack = {16, 40, 46, 49, 53, 57, 61, 65, 69},
		bow = {31, 38, 68, 71, 73, 76, 79, 82, 85},
		wand = {16, 40, 62, 85, 98, 108, 118, 128, 138}
	},

	-- the classes (docs/CLASSES.md): line, class, weapon families it uses, and a restriction
	--   melee = sword, axe, club (one melee skill); launcher = bow, crossbow; wand = wands and rods; fist; throw
	--   hands2 = two-handed melee only (the Berserker); bowOnly = bows only (the Beastmaster)
	lines = {
		{line = "Warrior", classes = {
			{name = "Warrior", families = {"melee"}}, {name = "Juggernaut", families = {"melee"}},
			{name = "Berserker", families = {"melee"}, hands2 = true}}},
		{line = "Ranger", classes = {
			{name = "Ranger", families = {"launcher"}}, {name = "Deadeye", families = {"launcher"}},
			{name = "Beastmaster", families = {"launcher"}, bowOnly = true}}},
		{line = "Mystic", classes = {
			{name = "Mystic", families = {"wand"}}, {name = "Elementalist", families = {"wand"}},
			{name = "Illusionist", families = {"wand"}}}},
		{line = "Thief", classes = {
			{name = "Thief", families = {"melee", "throw"}}, {name = "Ninja", families = {"melee", "throw"}},
			{name = "Samurai", families = {"melee"}}}},
		{line = "Necromancer", classes = {
			{name = "Necromancer", families = {"wand"}}, {name = "Lich", families = {"wand"}},
			{name = "Bone Lord", families = {"wand"}}}},
		{line = "Monk", classes = {
			{name = "Monk", families = {"melee", "fist"}}, {name = "Shadowfist", families = {"melee", "fist"}},
			{name = "Iron Sage", families = {"melee", "fist"}}}},
		{line = "Templar", classes = {
			{name = "Templar", families = {"melee"}}, {name = "Inquisitor", families = {"melee"}},
			{name = "Sentinel", families = {"melee"}}}}
	}
}
