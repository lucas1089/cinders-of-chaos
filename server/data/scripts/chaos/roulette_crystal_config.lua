-- Crystal Roulette prize pool, both crystal token roulettes (server/README.md "Roulette prizes against token drops", O151).
-- Data only, no engine calls. Loaded as one of ChaosRoulettePools (prizes.lua, by the scripts' actionIds); tools/
-- patch_roulette.py writes the `pool` lines into the prizePool of both base scripts (they had the same pool). Tests:
-- tests/roulette_pools_test.lua (luajit and lua5.3), tools/patch_roulette_test.py; the numbers: tools/roulette_model.lua.
--
-- What it was: 23 prizes, 21 of them the "Moist" gear (a sword, an axe, a hammer, a wand, a bow, a crossbow, a quiver, a
-- spellbook, a shield, a helmet, an armor, legs, boots and the caster and monk versions of the armor pieces), one of them
-- listed twice, plus the two best Tower Defense units. The Moist pieces are fixed base items (a sword with 56 attack, an
-- armor of 25) that do not scale with the level, so at the level 500+ where the Tower Defense is played they are a
-- vendor sale, and most of them are for a class the winner is not. A spin costs 15 Crystal Tokens: three completed Tower
-- Defense runs (5 tokens each). The scripts also said "Premium Roulette" and "Exercise Roulette" in their messages and
-- broadcasts (copies of the other roulettes): patch_roulette.py names them the Crystal Roulette.
-- Now the Tower Defense stays the theme with its two best units (they are only useful inside the Tower Defense), and the
-- rest is what the loot models pay: crafting orbs, sockets, gold that grows with the level and a unique chest of the
-- level, the only gear that is of the winner's level.
--
-- The base draw: every entry rolls its `chance` in 10000, one of the hits is picked at random, no hit rolls again
-- (ChaosPrizesCore.odds gives the exact share of each entry). `count` = {min, max} of the stack. For `gold` the count is
-- the crystal coins the tile shows (units of boss_roulette_config.lua gold). `kind` groups the entries for the tests (orb,
-- material, gold, unique, unit). One line per entry, in this exact shape: tools/patch_roulette.py reads them by pattern.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
local boss = dofile("data/scripts/chaos/boss_roulette_config.lua")

return {
	actionIds = {18565, 18566},
	title = "crystal",

	-- the token that pays a spin (the base scripts' playItem) and how many
	token = 28372,
	tokenCount = 15,

	-- the base broadcasts a prize whose chance is at most this
	rareThreshold = 110,

	pool = {
		-- Tower Defense units: they spawn defenders in the Tower Defense, and nowhere else
		{id = 28369, name = "Grimnir Slashbaiter Unit", count = {1, 2}, chance = 1000, kind = "unit"},
		{id = 28370, name = "King Aldor Goldcrusher Unit", count = {1, 1}, chance = 500, kind = "unit"},
		-- crafting orbs and sockets the loot layer drops (loot_config.lua currency.entries), in stacks
		{id = 29851, name = "Orb of Awakening", count = {1, 3}, chance = 2500, kind = "orb"},
		{id = 32256, name = "Whetstone", count = {1, 3}, chance = 2500, kind = "orb"},
		{id = 29856, name = "Orb of Upheaval", count = {1, 2}, chance = 2200, kind = "orb"},
		{id = 32251, name = "Orb of Tempering", count = {1, 1}, chance = 1800, kind = "orb"},
		{id = 29857, name = "Orb of Fate", count = {1, 1}, chance = 700, kind = "orb"},
		{id = 24691, name = "Orb of Gilding", count = {1, 1}, chance = 500, kind = "orb"},
		{id = 24697, name = "Orb of Unmaking", count = {1, 1}, chance = 500, kind = "orb"},
		{id = 24688, name = "Orb of Erasure", count = {1, 1}, chance = 500, kind = "orb"},
		{id = 29855, name = "Orb of Grafting", count = {1, 1}, chance = 150, kind = "orb"},
		{id = 32254, name = "Orb of Reforging", count = {1, 1}, chance = 100, kind = "orb"},
		{id = 24692, name = "Orb of Sockets", count = {1, 2}, chance = 1500, kind = "material"},
		-- gold: the tile shows N crystal coins, the prize is N x gold.perUnit of an hour of hunting gold at the winner's level
		{id = 2160, name = "Crystal coin (small purse)", count = {1, 1}, chance = 3000, kind = "gold"},
		{id = 2160, name = "Crystal coin (purse)", count = {2, 2}, chance = 2200, kind = "gold"},
		{id = 2160, name = "Crystal coin (heavy purse)", count = {5, 5}, chance = 900, kind = "gold"},
		-- a chest on the tile: a unique of the winner's level (unique.band), made like a drop
		{id = 1740, name = "Unique chest", count = {1, 1}, chance = 120, kind = "unique"},
	},

	-- what the tests hold the pool to
	limits = {
		maxUnitShare = 0.12, -- the theme, never the bulk
		minOrbShare = 0.40, -- at least this share is a crafting orb, socket orb or gold
		minGoldShare = 0.12,
		minUniqueShare = 0.003,
		maxUniqueShare = 0.02,
	},

	-- shared with the Boss Roulette: the gold per unit (the hunting gold curve) and the unique chest's level band
	gold = boss.gold,
	unique = boss.unique,
	-- never in the pool: decks, ships, belts, gloves. The fixed "Moist" gear of the old pool (the base items 28373-28393, which
	-- do not scale with the level) is refused by patch_roulette.py and the tests by its id range (these ids are transmog set
	-- looks, which no script may name)
	retired = {27632, 27633, 27634, 27796, 27797, 27798, 27799, 27800, 27801, 27802}
}
