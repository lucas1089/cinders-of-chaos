-- Ranked PvP arena settings (arena.lua, arena_core.lua, client game_arena). Loaded with
--     Chaos.arenaConfig = dofile("data/scripts/chaos/arena_config.lua")
-- See server/README.md "Arena". Lua 5.1 / LuaJIT compatible. Item ids are SERVER ids.

return {
	-- mode key -> players per side, the leaderboard board key (ChaosLeaderboard.record, mode "max") and the shown name
	modes = {
		["1v1"] = {size = 1, board = "arena1v1", name = "Arena 1v1"},
		["2v2"] = {size = 2, board = "arena2v2", name = "Arena 2v2"},
		["3v3"] = {size = 3, board = "arena3v3", name = "Arena 3v3"} -- a party of exactly three (PvP seasons bracket)
	},
	modeOrder = {"1v1", "2v2", "3v3"},

	minLevel = 50,
	-- level rule (one rule for both modes, over every player of the match): the lowest level must be at least
	-- `ratio` x the highest level, or within `slack` levels of it. 800 vs 1000 fights, 300 vs 1000 never does.
	level = {ratio = 0.8, slack = 20},

	-- Elo per mode. K is kProvisional for a player's first provisionalMatches matches of that mode, then k.
	-- 2v2: every player is rated against the average rating of the other team.
	rating = {start = 1000, floor = 100, k = 24, kProvisional = 40, provisionalMatches = 10},

	-- matchmaking window: rating difference allowed = base + step for every `everySeconds` waited, at most max.
	-- Two queue entries pair when their difference fits the window of the one that waited longer.
	window = {base = 100, step = 50, everySeconds = 10, max = 600},
	matchmakeSeconds = 2, -- how often the queue is paired (the arena tick runs every second)

	countdownSeconds = 10, -- no damage between players until the fight starts
	fightSeconds = 300, -- then the side with the higher remaining health share wins
	endDelaySeconds = 4, -- result shown in the arena before everybody goes back
	-- the base PvP rules make a player with secure mode on unattackable; the client module turns it off for the
	-- match. A fighter who still has it on this long after the fight started is counted as defeated.
	secureGraceSeconds = 15,
	disconnectSeconds = 3, -- a fighter without a connection for this long has left the match (counts as a loss)

	-- rewards: every win (at most maxRewardedWinsPerDay a day) and once a day the first win on top
	reward = {
		win = {{id = 29856, count = 1}}, -- Orb of Upheaval
		firstWin = {{id = 29857, count = 1}, {id = 29856, count = 2}}, -- Orb of Fate, Orbs of Upheaval
		maxRewardedWinsPerDay = 10
	},

	-- player storages 7100340 - 7100349 are reserved for the arena
	storage = {firstWinDay = 7100340, winsDay = 7100341, winsCount = 7100342},
	-- GLOBAL storage, TEST ONLY: 1 skips the protection-zone rule of the queue (test maps without a protection zone)
	testNoPzStorage = 7100345,

	tables = {ratings = "chaos_arena_ratings", matches = "chaos_arena_matches", players = "chaos_arena_match_players"},
	historyRows = 10, -- recent matches shown in the window

	-- instances: built at runtime with Game.createTile on a grid of slots, slot i at
	-- origin + (i % cols, i // cols) x spacing. The real map has no tiles there (other runtime areas: Infinity Tower
	-- 2000-2660, world boss 5000-5048, rifts 8192-8448); the footprint is checked before building.
	grid = {origin = {x = 6000, y = 6000, z = 7}, cols = 4, slots = 8, spacing = 24},
	-- one slot: a fighting room (innerW x innerH inside its walls) and, sharing its south wall, a gallery where the
	-- defeated watch the rest of the match
	room = {innerW = 11, innerH = 9, galleryH = 2},
	groundId = 407, -- black marble floor
	galleryGroundId = 413, -- stone floor
	wallId = 5648, -- stone wall
	pillarId = 1514, -- stone pillar (line-of-sight cover)
	basinId = 1481 -- coal basin (light)
}
