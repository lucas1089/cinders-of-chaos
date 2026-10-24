-- Premium Roulette prize pool (server/README.md "Roulette prizes against token drops", O151). Data only, no engine calls.
-- Loaded as one of ChaosRoulettePools (prizes.lua, by the script's actionId); tools/patch_roulette.py writes the `pool` lines
-- into the prizePool of the base premium roulette script. Tests: tests/roulette_pools_test.lua (luajit and lua5.3),
-- tools/patch_roulette_test.py; the numbers: tools/roulette_model.lua.
--
-- What it was: 14 prizes, five auras and nine wings, each a one-time unlock (using a second copy says "you already have
-- this"), none worth more than 98,000 gold to an NPC, and every spin broadcast (threshold 10000). The Ticket Roulette token
-- is the rarest one (only 22 bosses of level 1018 and up drop it, about 100 minutes of boss hunting per ticket), so a
-- spin gave a cosmetic that the winner often owned for the price of the rarest token. Now the cosmetics stay as a fifth of
-- the spins (the roulette's theme: a new one is still the best prize for a collector), and the rest is what the loot
-- models pay at that level: bigger stacks of crafting orbs with a real chance at the chase orbs, sockets, gold that grows
-- with the level and a unique chest of the level.
--
-- The base draw: every entry rolls its `chance` in 10000, one of the hits is picked at random, no hit rolls again
-- (ChaosPrizesCore.odds gives the exact share of each entry). `count` = {min, max} of the stack. For `gold` the count is
-- the crystal coins the tile shows (units of boss_roulette_config.lua gold). `kind` groups the entries for the tests (orb,
-- material, gold, unique, cosmetic). One line per entry, in this exact shape: tools/patch_roulette.py reads them by pattern.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
local boss = dofile("data/scripts/chaos/boss_roulette_config.lua")

return {
	actionIds = {18564},
	title = "premium",

	-- the token that pays a spin (the base script's playItem: the Ticket Roulette)
	token = 28057,
	tokenCount = 1,

	-- the base broadcasts a prize whose chance is at most this: here the chase orbs
	rareThreshold = 160,

	pool = {
		-- auras and wings: each unlocks once (the base use-scripts)
		{id = 26649, name = "Bats Aura", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 26650, name = "Fire Essence", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 26651, name = "Star Shine Aura", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 26652, name = "Electric Shock Aura", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 26653, name = "Fireflies Aura", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 27975, name = "Electric Rider Wings", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 27976, name = "Vorondor Flames", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 27977, name = "Mortis Mirage", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 27978, name = "Angelic Wings", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 27980, name = "Butterfly Wings", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 27981, name = "Dreadbone Spectre", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 27982, name = "Enslaved Wings", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 27983, name = "Bride Wings", count = {1, 1}, chance = 400, kind = "cosmetic"},
		{id = 27984, name = "Strength Wings", count = {1, 1}, chance = 400, kind = "cosmetic"},
		-- crafting orbs and sockets the loot layer drops (loot_config.lua currency.entries), in stacks
		{id = 29851, name = "Orb of Awakening", count = {2, 5}, chance = 2200, kind = "orb"},
		{id = 32256, name = "Whetstone", count = {2, 5}, chance = 2200, kind = "orb"},
		{id = 29856, name = "Orb of Upheaval", count = {2, 4}, chance = 2000, kind = "orb"},
		{id = 32251, name = "Orb of Tempering", count = {1, 3}, chance = 1800, kind = "orb"},
		{id = 29857, name = "Orb of Fate", count = {1, 3}, chance = 1200, kind = "orb"},
		{id = 24691, name = "Orb of Gilding", count = {1, 3}, chance = 900, kind = "orb"},
		{id = 24697, name = "Orb of Unmaking", count = {1, 3}, chance = 900, kind = "orb"},
		{id = 24688, name = "Orb of Erasure", count = {1, 3}, chance = 900, kind = "orb"},
		{id = 29855, name = "Orb of Grafting", count = {1, 2}, chance = 500, kind = "orb"},
		{id = 32254, name = "Orb of Reforging", count = {1, 2}, chance = 400, kind = "orb"},
		{id = 32253, name = "Orb of Excision", count = {1, 1}, chance = 300, kind = "orb"},
		{id = 32252, name = "Orb of Binding", count = {1, 1}, chance = 200, kind = "orb"},
		{id = 32258, name = "Ember Orb", count = {1, 1}, chance = 250, kind = "orb"},
		{id = 32259, name = "Crown Orb", count = {1, 1}, chance = 150, kind = "orb"},
		{id = 32260, name = "Void Orb", count = {1, 1}, chance = 90, kind = "orb"},
		{id = 32255, name = "Orb of Ruin", count = {1, 1}, chance = 25, kind = "orb"},
		{id = 24692, name = "Orb of Sockets", count = {2, 5}, chance = 1800, kind = "material"},
		-- gold: the tile shows N crystal coins, the prize is N x gold.perUnit of an hour of hunting gold at the winner's level
		{id = 2160, name = "Crystal coin (purse)", count = {2, 2}, chance = 2500, kind = "gold"},
		{id = 2160, name = "Crystal coin (heavy purse)", count = {5, 5}, chance = 2800, kind = "gold"},
		{id = 2160, name = "Crystal coin (strongbox)", count = {10, 10}, chance = 1500, kind = "gold"},
		{id = 2160, name = "Crystal coin (treasure)", count = {20, 20}, chance = 400, kind = "gold"},
		-- a chest on the tile: a unique of the winner's level (unique.band), made like a drop
		{id = 1740, name = "Unique chest", count = {1, 1}, chance = 350, kind = "unique"},
	},

	-- what the tests hold the pool to
	limits = {
		maxCosmeticShare = 0.25, -- a collector's prize, never the bulk
		minOrbShare = 0.40, -- at least this share is a crafting orb, socket orb or gold
		minGoldShare = 0.12,
		minUniqueShare = 0.005,
		maxUniqueShare = 0.03,
		maxChaseShare = 0.01, -- each chase orb (Ruin, Void, Crown, Ember, Binding, Excision) at most this share ...
		minChaseShare = 0.0015, -- ... and the rarest at least this
	},

	-- shared with the Boss Roulette: the gold per unit (the hunting gold curve) and the unique chest's level band
	gold = boss.gold,
	unique = boss.unique,
	-- never in the pool: decks, ships, belts, gloves
	retired = {27632, 27633, 27634, 27796, 27797, 27798, 27799, 27800, 27801, 27802},
}
