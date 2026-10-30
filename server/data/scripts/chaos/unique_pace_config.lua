-- Limits of the unique pace model (O342; server/README.md "Unique pace", tools/unique_pace_model.lua --check).
-- Data only, read by the tool and by tests/unique_open_level_test.lua (luajit and lua5.3).
--
-- The question: how many kills of a hunt of the right level does a typical player (no item find) need for one leveling
-- unique (an entry of data/lib/chaos_unique_items.lua that is not boss-only and has no minMonsterLevel)? Computed from the
-- loot layer's own rules (loot.lua L.rollUniques, loot_config.lua unique), the tier mix of the kills (monster_tiers.lua
-- spawnChance, ambush, ambushTier), the pack factor the unique roll reads (pace_config.lua loot / notable) and the hunts
-- (bounty_pool.lua monsters with their level and spawn count; tools/hall_hunts.csv). Expected values, no random numbers.
return {
	-- kills per unique, no item find, no bad-luck protection (the figure of ChaosLootRoll / L.simulate)
	target = {min = 1500, max = 2500},
	-- --derive aims at this
	aim = 2000,

	-- the hunting bands checked: centre level, the monsters of the pool within +- share of it, and the limits of that band
	-- (starter bands are looser: few uniques, the first levels come fast)
	share = 0.15,
	bands = {
		{level = 10, min = 250, max = 3000},
		{level = 20, min = 500, max = 3000},
		{level = 40, min = 1500, max = 2500},
		{level = 60, min = 1500, max = 2500},
		{level = 100, min = 1500, max = 2500},
		{level = 150, min = 1500, max = 2500},
		{level = 200, min = 1500, max = 2500},
		{level = 300, min = 1500, max = 2500},
		{level = 400, min = 1500, max = 2500},
		{level = 500, min = 1500, max = 2500},
		{level = 600, min = 1500, max = 2500}
	},

	-- every hunt of the hall (tools/hall_hunts.csv, kind hunt, level 20 and up): the average over its monsters must lie here;
	-- a hunt of the hall lists monsters of one or two other hunts, so it is looser than a band
	-- (the hunts under level 30 list their uniques by name, 400-1000 kills: the first levels come fast, left as they were)
	hall = {minLevel = 20, min = 1200, max = 3500, starterUpTo = 30, starterMin = 400, starterMax = 5000},

	-- with the bad-luck protection (conquest_config.lua pity, group monster and set) the player sees at most this much faster
	-- than the base chance, and the pity must make it faster (a drop that never came is not the target)
	pity = {maxSpeedup = 3.2, minSpeedup = 1.1}
}
