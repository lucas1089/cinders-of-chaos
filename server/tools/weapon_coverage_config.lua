-- Weapon coverage audit: every number and every allowance (tools/weapon_coverage.lua; server/README.md "Weapon
-- coverage"). The CI step runs `luajit tools/weapon_coverage.lua --check` from server/. Plain table, Lua 5.1 / LuaJIT
-- and 5.3.

return {
	-- level bands (from, to): a weapon sits in the band that holds its required level (from <= level < to); the last
	-- band is open ended. The labels are the owner's (2026-10-23); the top two bands were split into 1000-1300, 1300-1700
	-- and 1700-2400+ on 2026-10-24 (gear beyond level 1000, server/README.md).
	bands = {
		{1, 20, "1-20"}, {20, 50, "20-50"}, {50, 100, "50-100"}, {100, 200, "100-200"}, {200, 400, "200-400"},
		{400, 700, "400-700"}, {700, 1000, "700-1000"}, {1000, 1300, "1000-1300"}, {1300, 1700, "1300-1700"},
		{1700, 100000, "1700-2400+"}
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
	-- weapons the equip access audit (C.accessProblems, `--access`) skips: id -> why. The stock rook wand lists the vocation
	-- "None" only (the old rook vocation, no Chaos class has it)
	accessExceptions = {
		[19391] = "stock rook wand: vocation None only"
	},

	-- cells that may stay below the threshold on purpose: {"Class", "band label", "why"}. Empty = none.
	knownGaps = {},

	-- Weapon families (O454, weapon_families_config.lua): sword, axe and club each have a trait, so the choice is real only when a
	-- class has weapons of at least familyMinFamilies of them in a band, each family with at least familyMinOptions (obtainable,
	-- the class may wield them). `familyLines` = the lines that get the traits (the Monk line keeps its fists). --check fails
	-- on a class and band under it that is not in familyKnownGaps, and on a known gap that is no gap any more. No item is
	-- added for a gap: it is reported (server/README.md "Weapon families (O454)").
	familyLines = {"Warrior", "Thief", "Templar"},
	familyMinOptions = 3,
	familyMinFamilies = 2,
	familyKnownGaps = {
		{"Berserker", "1-20", "two-handed only: 2 swords, 4 axes, 2 clubs at level 1-20, only the axe has 3"},
		{"Berserker", "1000-1300", "two-handed only: 8 swords, 2 axes, 2 clubs, only the sword has 3"},
		{"Berserker", "1700-2400+", "two-handed only: 2 swords, 7 axes, 2 clubs, only the axe has 3"},
	},

	-- the tier of a level: the attack of the equipment sets at that level (tools/install_gear_sets.py WEAPON_ANCHORS and
	-- WEAPON_CURVES; tools/weapon_sim.py calls it "one tier"; tests/weapon_coverage_test.lua checks they are equal). One-handed
	-- melee = attack, two-handed = attack + 3, bow = bow, crossbow = bow + 3, wand and rod = the mean damage.
	-- O472 (2026-11-10): the curves are the ones before (anchors 8, 50, 100, 200, 400, 700, 1000, 1500, 2000; attack 16, 40, 46, 49,
	-- 53, 57, 61, 65, 69; bow 31, 38, 68, 71, 73, 76, 79, 82, 85; wand 16, 40, 62, 85, 98, 108, 118, 128, 138) times the weapon
	-- growth a = 1 + (W - 1) / 0.85 of spell_scaling_config.lua `weaponGrowth`, anchors of W (300, 500, 850) added
	anchors = {8, 50, 100, 200, 300, 400, 500, 700, 850, 1000, 1500, 2000},
	curves = {
		attack = {16, 40, 46, 57, 67, 75, 81, 94, 118, 147, 168, 199},
		bow = {31, 38, 68, 83, 94, 103, 111, 125, 155, 191, 212, 245},
		wand = {16, 40, 62, 99, 119, 138, 151, 178, 226, 285, 331, 398}
	},

	-- O472 (2026-11-10): the stock weapons grow with the level (tools/patch_stock_weapon_growth.py; base_weapons.csv holds the numbers
	-- before): the audit applies the same rule. A weapon of these kinds, no charges, required level above fromLevel (attack and element
	-- damage); with `wands`, a wand or rod of a level above fromLevel (min and max damage)
	stockGrowth = {fromLevel = 100, kinds = {sword = true, axe = true, club = true, bow = true, crossbow = true}, wands = true},

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
