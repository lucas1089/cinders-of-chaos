-- The Group Queue (O407; groupqueue.lua, groupqueue_core.lua; client game_groupqueue; server/README.md "Group Queue
-- (O407)"): every number. Plain table, loaded with
--     ChaosGroupQueueConfig = dofile("data/scripts/chaos/groupqueue_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- One window joins the arena, the battleground and a dungeon at once through their own queue code. The first queue
-- that finds a match pops: a party gets a ready check, then leaves the other queues. No storage, no table: the
-- groups are kept in memory (a restart empties every mode queue anyway).
return {
	enabled = true,

	-- seconds every member has to answer a ready check (Accept / Decline); no answer counts as a decline
	readyCheckSeconds = 20,

	-- an accepted ready check holds this long for the mode it was for: when the match could not start (the other
	-- side declined), the next pop of that mode inside this time starts without a second check
	confirmSeconds = 60,

	-- a player alone gets no ready check (the pop starts the match at once, as before); true asks a lone player too
	soloReadyCheck = false,

	-- the tick that times out ready checks and drops the queues a mode left on its own
	tickMs = 1000,

	-- the arena modes and the party size each needs (arena_config.lua modes; 2v2 = a party of exactly two)
	arenaModes = {["1v1"] = 1, ["2v2"] = 2, ["3v3"] = 3},
	arenaOrder = {"1v1", "2v2", "3v3"},

	-- the battleground roles a member may ask for (battleground_core.lua parseRole); none = the class default
	roles = {tank = true, healer = true, dps = true, support = true},

	-- the largest party the battleground takes (battleground_config.lua partyMax is read when it is loaded)
	bgPartyMax = 5,

	-- dungeon difficulties (Chaos.dungeons.maxDifficulty)
	maxDifficulty = 6,

	-- the raid ready check: the party leader asks, everyone accepts, then the raid opens as from the Raid window
	raid = true,

	-- client requests per player: reads (open / query) and actions (join, leave, answers)
	readMs = 500,
	actMs = 800
}
