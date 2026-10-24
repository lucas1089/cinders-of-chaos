-- What a roulette spin is worth against what its token costs (server/README.md "Roulette prizes against token drops",
-- O151). Data only; read by tools/roulette_model.lua and tests/roulette_pools_test.lua (luajit and lua5.3).
--
-- Both sides are in minutes of hunting at the winner's level:
--   cost  = the time to earn the tokens of one spin
--           boss / exercise / premium tokens: dropped by bosses (the base monster files, surveyed in data/items/
--             base_item_values.csv: 43 / 43 / 22 monsters of level 509 / 509 / 1018 and up). A boss kill gives a token with
--             `chance` (the mean of their loot chances) and 1..2 of them (count 1.5); a kill (walk in, fight, loot, walk
--             out) takes `minutesPerBossKill`. Tokens per spin / (chance x count) kills x minutes per kill.
--           crystal tokens: 5 per completed Tower Defense run (the base script), a run takes `minutesPerRun`.
--   value = the prizes that can be counted: crafting orbs and sockets in kills of a level 100+ monster that the loot layer
--           needs for the same drops (loot_config.lua currency.entries, the normal tier; the Orb of Ruin by its magic chance
--           / 3), divided by the hunter's kills per hour; gold prizes in hours of hunting gold; an exercise chest by its
--           price (base_item_values.csv buy_med) against the hunting gold per hour at the level; a unique chest as
--           `uniqueMinutes`. Cards, badges, catalysts, cosmetics and Tower Defense units are not counted (their worth is
--           not a time), so the figures are a floor.
-- Computed from the config, not measured on a server.
return {
	-- walking in, fighting, looting and leaving one base boss room (the lever rooms stop a fight at 30 minutes): a guess.
	-- Everything about the cost scales with it: at 6 the boss spin is worth 1.5 tokens' time, at 10 it is worth 0.9.
	minutesPerBossKill = 8,

	-- a Tower Defense run (the entrance session lasts 20 minutes)
	minutesPerRun = 15,

	-- kills per hour of one hunter by hunting level: tools/spawn_tuning.json model.paceKillsPerHour.scaled (a test keeps
	-- them equal)
	kph = {{650, 836}, {800, 846}, {1000, 869}, {1300, 819}, {1600, 813}, {2000, 789}},

	-- the levels the figures are held at (the tokens drop from level 509 monsters up)
	levels = {650, 1000, 1500, 2000},

	-- a unique now and then is about three and a half hours of hunting Rare and Legendary monsters at level 1500 (O148:
	-- 17.4 per 1000 such kills); the chest gives one of the level
	uniqueMinutes = 200,

	-- tokens: the mean loot chance of the monsters that drop it, and the mean count (1..2)
	tokens = {
		boss = {item = 28033, bosses = 43, chance = 0.0837, count = 1.5},
		exercise = {item = 28058, bosses = 43, chance = 0.0635, count = 1.5},
		premium = {item = 28057, bosses = 22, chance = 0.0541, count = 1.5},
		crystal = {item = 28372, perRun = 5},
	},

	-- value / cost a roulette has to stay within at every level (the gold and the pace of the level move it a little)
	band = {min = 0.80, max = 1.35},
}
