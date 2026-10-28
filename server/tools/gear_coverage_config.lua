-- Gear coverage audit: every number and every allowance (tools/gear_coverage.lua; server/README.md "Gear coverage"). The
-- CI step runs `luajit tools/gear_coverage.lua --check` from server/. Plain table, Lua 5.1 / LuaJIT and 5.3. The level
-- bands, the class lines and the tiers are the weapon audit's (tools/weapon_coverage_config.lua).

return {
	-- the slots the audit covers: key, label, the least options a class needs in every band, and the class group that
	-- wears it. Weapons, wands, rods and the Monk fist weapons are the weapon audit's (weapon_coverage.lua). Ammunition
	-- is not audited: bows and crossbows fire without it (server/README.md "Infinite arrows and quivers"), and the
	-- throwing weapons of the Thief line are weapons.
	slots = {
		{key = "helmet", label = "Helmet", min = 3},
		{key = "armor", label = "Armor", min = 3},
		{key = "legs", label = "Legs", min = 3},
		{key = "boots", label = "Boots", min = 3},
		{key = "shield", label = "Shield", min = 3, who = "shield"},
		{key = "book", label = "Spellbook", min = 3, who = "book"},
		{key = "quiver", label = "Quiver", min = 2, who = "quiver"}, -- three launcher classes, 12 stock quivers
		{key = "amulet", label = "Amulet", min = 3},
		{key = "ring", label = "Ring", min = 3}
	},
	-- the classes of the three hand-held groups (docs/CLASSES.md, server/README.md "Gear coverage"): everyone else has no
	-- off-hand item. The Berserker fights two-handed, the Beastmaster and the rest of the launcher line have the quiver.
	who = {
		shield = {"Warrior", "Juggernaut", "Templar", "Inquisitor", "Sentinel"},
		book = {"Mystic", "Elementalist", "Illusionist", "Necromancer", "Lich", "Bone Lord"},
		quiver = {"Ranger", "Deadeye", "Beastmaster"}
	},
	-- the armour weight each class wears (the equipment sets' H, M and C pieces): the power of a piece is judged against
	-- the sets' armour curve of its weight
	weight = {
		heavy = {"Warrior", "Juggernaut", "Berserker", "Templar", "Inquisitor", "Sentinel"},
		medium = {"Ranger", "Deadeye", "Beastmaster", "Thief", "Ninja", "Samurai", "Monk", "Shadowfist", "Iron Sage"},
		cloth = {"Mystic", "Elementalist", "Illusionist", "Necromancer", "Lich", "Bone Lord"}
	},

	-- the thresholds of --check (the weapon audit's numbers, tools/weapon_coverage_config.lua, are minPower 0.80)
	minPower = 0.80,
	-- a drop must be at least this likely to count (loot chance per 100000; 10 = 0.01%, the floor of the set rows; the
	-- weapon audit takes 20)
	minDropChance = 10,
	-- a drop counts from the level its monster is hunted at (pace_config.lua baseLevelMult, 1 since 2026-10-28: the "fair
	-- hunt" level of a base monster; maxBaseRaw = the highest base monster of the bounty pool, above it the level is a
	-- scaled monster's)
	baseLevelMult = 1,
	maxBaseRaw = 657,

	-- fairness of the weapon drops (--fairness; owner, 2026-10-28: "they must all be equal"): the hunting bands that are
	-- compared (a band is +-15% around the number; above the highest base monster, 657, only the sets' level gear drops
	-- and it is counted for 1000 kills of a normal monster), the power a weapon needs to count as usable (a share of the
	-- weapon audit's curve), the levels around the band a weapon may require (below: a club of level 25 is no drop at
	-- hunting level 300; the class loot window of data/lib/chaos_class_loot.lua is 150 below and 20 above), and the rule:
	-- the class that finds the fewest usable weapons per kill has at least fairRatio of what the class that finds the
	-- most does, in every band
	fairEdges = {100, 300, 500, 800, 1000, 1200},
	fairRatio = 0.90,
	-- what the class loot rows are derived for (--derive): usable weapons per 1000 kills of one loadout in a fitted band
	fairFit = {100, 300, 500},
	-- ... and in the bands of the scaled hunts (class loot config.scaled; no monster of the pool is hunted there)
	fairFitScaled = {800, 1000, 1200},
	fairTarget = {[100] = 28, [300] = 28, [500] = 28, [800] = 28, [1000] = 28, [1200] = 28},
	fairPower = 0.60,
	fairWindow = {below = 150, above = 20},

	-- the loadouts of each class: a build wields one kind of weapon at a time, so the weapons a class can wield are counted
	-- per loadout (melee1h / melee2h by hands, fist, bow, crossbow, wand, rod) and every loadout of every class must find
	-- the same number of weapons (fairRatio): a Warrior's one-handed weapons and a Berserker's two-handed ones, a Ranger's
	-- bows and its crossbows, a Monk's fists. The sets split the casters: the wands are the Elementalist's (and the
	-- Mystic's and the Necromancer line's), the rods the Illusionist's (the same). A stock wand-type item is a wand when
	-- the Elementalist wields it, else a rod (class lists of data/items/base_weapons.csv: the Elementalist wields 36 of the
	-- 62, the Illusionist 59 but its sets are rods). The Monk line wields melee weapons too (docs/CLASSES.md "Skills and
	-- weapons") and fists are what it fights with, so both count. The Thief line has no throwing weapon loadout:
	-- stackable throwing weapons are out of the game (data/lib/chaos_throwables.lua; the shurikens are spells).
	loadouts = {
		{classes = {"Warrior", "Juggernaut", "Templar", "Inquisitor", "Sentinel", "Samurai"}, keys = {"melee1h", "melee2h"}},
		{classes = {"Berserker"}, keys = {"melee2h"}},
		{classes = {"Thief", "Ninja"}, keys = {"melee1h", "melee2h"}},
		{classes = {"Monk", "Shadowfist", "Iron Sage"}, keys = {"fist", "melee1h", "melee2h"}},
		{classes = {"Ranger", "Deadeye"}, keys = {"bow", "crossbow"}},
		{classes = {"Beastmaster"}, keys = {"bow"}},
		{classes = {"Mystic", "Necromancer", "Lich", "Bone Lord"}, keys = {"wand", "rod"}},
		{classes = {"Elementalist"}, keys = {"wand"}},
		{classes = {"Illusionist"}, keys = {"rod"}}
	},

	-- the stock spellbooks (items.xml has no names to tell them apart: the base names are not ours): ids of the stock
	-- items in the shield slot that only casters wear. The Gambler's pool (gamble_config.lua) names the same ones.
	books = {2175, 8900, 8901, 8902, 8903, 8904, 8918, 16112, 22423, 22424, 22474, 28111, 29572, 29865},
	-- how many hands the Gambler's `choices` count as sellers of a base: every pool entry counts as a way to get the item
	-- at its level (the Gambler sells the best bases the character can wear)
	gambleCounts = true,

	-- known gaps, "Class:band label" for a slot: {"slot", "Class", "band label", "why"}. Empty = none: every gap is filled.
	knownGaps = {}
}
