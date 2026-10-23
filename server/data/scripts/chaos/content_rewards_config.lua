-- Content rewards (content_rewards.lua, content_rewards_core.lua; server/README.md "Content rewards"): what each map
-- device pays on top of the loot of its monsters. Plain table: ChaosContentRewards.config = dofile(...). Lua 5.1/LuaJIT
-- and 5.3.
--
-- Player beta feedback 2026-10-23: "in the waystones the monsters are the same as outside with the same drops, the boss
-- dropped almost nothing, I don't know what they are for". Owner: rifts and waystones need separate drops. Found: the
-- waystone monsters' loot lists (data/monster/lua/waystone_portals) hold coins, potions, materials and orbs, but no
-- gear and no waystone, and the corpse rule by monster level (pace_core.lua) thins a level 1100+ boss's table to
-- nearly nothing. So:
--   * Rifts pay in CRAFTING CURRENCY: an orb trickle on every kill (Upheaval, Fate and the waystone orbs), a burst from
--     the guardian, the key ladder (rift_config.lua keyDrop), the chest. No bonus gear.
--   * Waystones pay in GEAR: a piece of the top set bases (Azure Vigil, Gildcrown, level-matched) on a share of the kills,
--     always Rare or better, a boss table (guaranteed Legendary+ pieces, unique rolls, waystones and the waystone
--     orbs), and waystone drops that keep the map loop going. Rarity find and quantity of the run's tier come on top.
-- All of it scales with the run's tier (rift 1-15, waystone 1-15) and the modifiers' quantity bonus.
-- tools/content_reward_model.lua --check keeps the per-hour gain over hunting inside `bounds`.
return {
	enabled = true,

	-- the monster tiers' multiplier on every per-kill chance below (the loot layer's tier names)
	tierMult = {normal = 1, magic = 2.5, rare = 5, legendary = 12, boss = 1},

	-- ------------------------------------------------------------------ waystones
	waystone = {
		-- chance per kill (per 10000) that a piece drops: base + perTier x (tier - 1); x tierMult x quantity (the run's
		-- modifiers and atlas), at most `maxChance`
		gear = {base = 250, perTier = 30, maxChance = 6000},
		-- the piece: a set base (data/lib/chaos_gear_sets_items.lua) of these sets whose level is at most the run's level
		-- and at least `floorShare` x it; none: the highest pieces of the sets
		sets = {"azurevigil", "gildcrown"},
		floorShare = 0.45,
		-- rarity of a trickle piece {stored id, weight}: the item level and modifiers come from the loot layer after.
		-- Always Rare or better. The Divine weight rises by rarityPerTier.divine per tier
		rarity = {{4, 70}, {5, 29}, {10, 1}},
		rarityPerTier = {divine = 0.2},
		-- rarity find (percent) added to the run's own: base + perTier x (tier - 1)
		rarityFind = {base = 20, perTier = 3.5},
		-- the quantity of the run's tier on the extra rolls (rateMult): 1 + (base + perTier x (tier - 1)) / 100
		quantity = {base = 10, perTier = 1.5},
		-- the boss table, per kill of the run's boss, into the corpse (the party shares it as any corpse):
		--   pieces: base + perTier x (tier - 1) guaranteed pieces (the fraction is a chance of one more) x quantity,
		--           Legendary or Divine (`rarity`)
		--   unique rolls over the uniques of the boss tier (L.rollUniques) at `uniqueFind` x item find
		--   waystones: `same` of the run's tier (the tier T+1 one of waystone_tiers_config.lua drops.bossNext stays)
		--   orbs {id, min, max, chance %}: the waystone orbs, so a run pays for the next map's modifiers
		boss = {
			pieces = {base = 3, perTier = 0.25},
			rarity = {{5, 85}, {10, 15}},
			uniqueRolls = {base = 2, perTier = 0.2},
			uniqueFind = 3,
			waystones = {same = 1},
			orbs = {
				{id = 29851, name = "Orb of Awakening", min = 2, max = 4, chance = 100},
				{id = 24691, name = "Orb of Gilding", min = 1, max = 2, chance = 100},
				{id = 29855, name = "Orb of Grafting", min = 1, max = 1, chance = 35},
				{id = 29857, name = "Orb of Fate", min = 1, max = 1, chance = 25}
			}
		},
		-- waystones that keep the loop going (the monsters' own tables hold none): chance per kill (per 10000) of one of
		-- the run's tier, x tierMult
		trickle = {chance = 40}
	},

	-- ------------------------------------------------------------------ rifts
	rift = {
		-- chance per kill (per 10000) of one crafting orb: base + perTier x tier; x tierMult x the run's quantity, at most
		-- maxChance. Drawn by weight from `orbs` (the waystone orbs, Upheaval and Fate weigh most)
		orb = {base = 120, perTier = 30, maxChance = 5000},
		orbs = {
			{id = 29856, name = "Orb of Upheaval", weight = 30},
			{id = 29857, name = "Orb of Fate", weight = 18},
			{id = 29851, name = "Orb of Awakening", weight = 20},
			{id = 24691, name = "Orb of Gilding", weight = 12},
			{id = 29855, name = "Orb of Grafting", weight = 8},
			{id = 24697, name = "Orb of Unmaking", weight = 6},
			{id = 24688, name = "Orb of Erasure", weight = 6}
		},
		-- the guardian's burst into its corpse: orbs = base + perTier x tier (fractions a chance of one more) x quantity,
		-- drawn the same way; unique rolls at the boss tier
		guardian = {orbs = {base = 4, perTier = 0.8}, uniqueRolls = {base = 1, perTier = 0.1}, uniqueFind = 2}
	},

	-- ------------------------------------------------------------------ the CI bounds (tools/content_reward_model.lua)
	-- Expected gain over open-world hunting at the same level, per hour: no modifiers (min) and the best tier (max).
	bounds = {
		waystoneGear = {min = 2.0, max = 14},
		riftOrbs = {min = 1.5, max = 10}
	}
}
