-- The Weekly Challenge (O390; weekly_challenge.lua, weekly_challenge_core.lua, tests/weekly_challenge_test.lua;
-- server/README.md "The Weekly Challenge (O390)"). Plain table, loaded with
--     ChaosWeeklyChallengeConfig = dofile("data/scripts/chaos/weekly_challenge_config.lua")
-- One queue dungeon of the dungeon system, generated at startup like the Hollow Vault (areagen.lua), but its seed and
-- theme come from the ISO week: the same layout for everyone, a new one each week. Fastest clears go to two weekly
-- leaderboard boards with class tabs (solo, party). At the leaderboard reset (Monday, leaderboard_config.lua
-- resetHour) the top 3 of every class get Conquest Tokens and the Discord queue gets one "weekly_challenge" post.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,

	-- ------------------------------------------------------------------ the area (areagen_config.lua areas)
	-- the area it copies: rooms, spawns, monsters, run times and health curves of the Hollow Vault (level 800). Those
	-- numbers are the ones tests/areagen_test.lua holds to a 10 minute run; the copy keeps them.
	base = "vault",
	-- what differs from the base. origin: the free cell x 25088 of the dungeon block 24576-25599 (docs/MAP_GUIDE.md
	-- "The dungeon block"; the block holds the dungeons 6-9 at x 24576 / 24832)
	area = {
		id = "challenge",
		name = "The Weekly Challenge",
		origin = {x = 25088, y = 24576, z = 9}
	},
	-- the week's theme: one of these areagen themes, picked by the week's seed (each is a dungeon theme already)
	themes = {
		{key = "vault", name = "Hollow Vault"},
		{key = "marrow", name = "Marrow Crypts"},
		{key = "crucible", name = "Iron Crucible"},
		{key = "sanctum", name = "Fallen Sanctum"},
		{key = "throne", name = "Pyre Throne"}
	},
	-- the seed of a week: a mix of seedBase and the ISO year and week (weekly_challenge_core.lua W.seed). A seed whose
	-- layout fails areagen's checks is followed by the seed of the next try (W.seed try 1, 2, ..), at most seedTries;
	-- the same on every start of the week, so the layout stays the same for the whole week.
	seedBase = 90090,
	seedTries = 8,
	-- a layout with fewer monsters is skipped like an invalid one (the owner's rule of 2026-10-14: at least 100
	-- monsters in every queue dungeon; the Vault's seed gives 103, other seeds 95-110)
	minMonsters = 100,
	-- the run (dungeons.lua): its own dungeon id after the generated 5-9, a party of up to `party` (one player may
	-- enter alone), always at `difficulty` (the queue's choice is ignored: one rule for every time on the board)
	dungeon = {
		id = 10,
		party = 4,
		difficulty = 1,
		title = "Weekly Challenge"
	},
	-- the boss: the base boss under a name of its own (the dungeon matches the kill by that name)
	boss = {name = "The Proving Warden"},
	-- no boss chest (the base has none either): the weekly reward is the board's, below

	-- ------------------------------------------------------------------ the boards (leaderboard_config.lua boards)
	-- mode "min", format "time", byClass; party size 1 -> solo, 2+ -> party
	boards = {solo = "challenge_solo", party = "challenge_party"},

	-- ------------------------------------------------------------------ the weekly rewards
	-- At the reset: the 1st, 2nd and 3rd of every class tab (base class and its ascensions, the board's tabs) of each
	-- board get these Conquest Tokens (conquest.lua, the token log source "weekly_challenge"). An existing currency,
	-- small next to its daily caps (a dungeon clear alone gives 5-15 a clear, 90 a day): 7 classes x 2 boards x 60 is
	-- at most 840 tokens a week on the whole server, 60 for one character (two boards: 120).
	tokens = {30, 20, 10},
	rewardTop = 3,
	-- the Discord post (discord_core.lua D.weeklyChallenge; discord_config.lua events.weekly_challenge): the top 3 of
	-- each class
	discordTop = 3
}
