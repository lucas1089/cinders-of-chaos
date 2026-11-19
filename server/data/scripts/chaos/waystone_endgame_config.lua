-- Waystone endgame (O666; waystone_endgame.lua, waystone_endgame_core.lua; server/README.md "Waystone endgame (O666)"): every number.
-- Plain table: ChaosWaystoneEndgame.config = dofile("data/scripts/chaos/waystone_endgame_config.lua"). Lua 5.1 / LuaJIT and 5.3.
--
-- Owner 2026-11-19: "players from level 1500-2000 have little to do; maybe raise the waystone tiers". So the waystones go on past
-- level 2500: tiers XVI-XXV (levels 2600-3500, waystone_tiers_config.lua `tiers` / `bands`), a band boss at the end of each band, a
-- corrupted waystone (the Void Orb, 32260) and a point of the endgame atlas for the first clear of each tier. The balance model is
-- tools/waystone_endgame_model.py (limits and reasons: waystone_endgame_balance_config.lua).
return {
	enabled = true,

	-- ------------------------------------------------------------------ band bosses
	-- the last tier of each band spawns a band boss when the map's own boss dies (the first clear of that tier). One per band:
	-- tier V (low), X (mid), XV (high), XXV (deep). `monster` is the monster file name (data/monster/monsters/chaos/waystone_bosses),
	-- its look an existing boss outfit (no new art). `seconds`: the planned kill time for the median character at the tier's level
	-- (the XML health follows, tools/waystone_endgame_model.py), `dieSeconds`: the seconds the median class lives with no healing under
	-- its hits (the XML attacks follow). A band boss drops its own table (content_rewards.lua, branch `band`): `pieces` and
	-- `uniqueRolls` on top of a map boss's, `void` = {min, max, chance %} Void Orbs (the corruption orb), `bandOrbs`.
	bandBosses = {
		{tier = 5, monster = "Gravewatch Ulrim", file = "gravewatch_ulrim", seconds = 170, dieSeconds = 40, pieces = 2, uniqueRolls = 2,
			void = {1, 1, 30}},
		{tier = 10, monster = "Sister Morvane of Cinders", file = "sister_morvane_of_cinders", seconds = 190, dieSeconds = 38, pieces = 3,
			uniqueRolls = 3, void = {1, 2, 45}},
		{tier = 15, monster = "The Hollow Colossus", file = "the_hollow_colossus", seconds = 210, dieSeconds = 36, pieces = 4,
			uniqueRolls = 4, void = {1, 2, 60}},
		{tier = 25, monster = "Vharkul the Embered Tyrant", file = "vharkul_the_embered_tyrant", seconds = 240, dieSeconds = 34, pieces = 6,
			uniqueRolls = 6, void = {2, 3, 90}}
	},
	-- a band boss that nobody fights leaves after this many seconds
	bandBossSeconds = 600,
	-- orbs of the band boss table: {item id, name, min, max, chance %}
	bandOrbs = {
		{id = 29857, name = "Orb of Fate", min = 2, max = 4, chance = 60},
		{id = 29856, name = "Orb of Upheaval", min = 3, max = 6, chance = 70},
		{id = 24691, name = "Orb of Gilding", min = 1, max = 3, chance = 40}
	},
	voidOrb = {id = 32260, name = "Void Orb"},

	-- ------------------------------------------------------------------ the corrupted waystone (Void Orb on a waystone)
	-- A waystone with at least one modifier (Magic or Rare) takes a Void Orb: with `breakChance` percent the waystone breaks (gone),
	-- else it is corrupted for good: `count` strong modifiers from `pool` (the key of a normal modifier at `x` times the top of its normal
	-- range, never a key the waystone holds), plus `bonus` percent item quantity / rarity / experience for the run. No orb changes a
	-- corrupted waystone again. Custom attribute `ws_corrupt` ("key:value,..."); the modifiers merge into the run's list when the
	-- device takes the waystone (waystone_mods.lua WM.take).
	corrupt = {
		attribute = "ws_corrupt",
		orbKey = "void",
		breakChance = 15,
		count = {{2, 70}, {3, 30}},
		bonus = {quantity = 35, rarity = 30, experience = 20},
		-- the pool: {key, x, weight}
		pool = {
			{"vitality", 1.4, 10}, {"brutality", 1.4, 10}, {"haste", 1.3, 6}, {"elites", 1.4, 8}, {"warding", 1.3, 7},
			{"keen", 1.4, 8}, {"ironhide", 1.4, 8}, {"emberbrand", 1.4, 6}, {"frostbrand", 1.4, 6}, {"stormbrand", 1.4, 6},
			{"dread", 1.4, 6}, {"withering", 1, 5}, {"blight", 1.4, 6}, {"searing", 1.4, 6}, {"flaying", 1.4, 6}, {"sapping", 1.4, 6}
		}
	},

	-- ------------------------------------------------------------------ the endgame atlas (points of first clears)
	-- the first clear of each tier (the map boss dead, tier 1-25) gives the character one point (once per tier and character); the
	-- points buy ranks (`cost` points a rank, `maxRank` ranks) of four stats that shape the character's own runs (the opener's). A tier is
	-- paid once, so the 25 points buy 25 of the 20 ranks' worth of choices: not every stat can be full. `per` = percent a rank.
	atlas = {
		stats = {
			{key = "density", per = 6, maxRank = 5, text = "+%d%% chance a dead map monster is replaced by one more (at most 40 alive)"},
			{key = "bossChance", per = 8, maxRank = 5, text = "+%d%% chance the band boss of the run's band appears (always at its last tier)"},
			{key = "chestChance", per = 6, maxRank = 5, text = "+%d%% chance the map boss leaves a chest of orbs for every player in the map"},
			{key = "fragmentChance", per = 4, maxRank = 5, text = "+%d%% fragment chance of a cleared run (read by the pinnacle fragments, O667)"}
		},
		cost = 1,
		respecGold = 500000
	},
	-- the chest of the map boss (atlas chestChance): orbs, base + perTier x (tier - 1) of each, whole part and a chance for the rest
	chest = {
		orbs = {
			{id = 29856, name = "Orb of Upheaval", base = 1, perTier = 0.20},
			{id = 29857, name = "Orb of Fate", base = 1, perTier = 0.10},
			{id = 24691, name = "Orb of Gilding", base = 0, perTier = 0.06}
		}
	},
	-- density: the clone is a monster of the same type at the dead one's tile; at most `maxAlive` of them at once per map
	density = {maxAlive = 40, delayMs = 600},

	-- the storages: base 7103300 (README "Storage keys"): +0 bit mask of the tiers paid (tiers 1-25), +1 the ranks (one decimal digit a
	-- stat, in `atlas.stats` order), +2 the number of first clears (information)
	storage = {base = 7103300}
}
