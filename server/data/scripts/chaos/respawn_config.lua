-- Dynamic respawn (respawn.lua, respawn_core.lua; engine patch src-patches/0022-dynamic-respawn.patch;
-- server/README.md "Spawn density and respawn"): every number. Plain table, loaded with
--     ChaosRespawnConfig = dofile("data/scripts/chaos/respawn_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,

	-- how often the hunters are counted and the spawn intervals set (seconds)
	tickSeconds = 20,

	-- a hunter: online, not staff, not in a protection zone and, with requireInFight, in fight (the engine's
	-- in-fight condition: attacked or attacking in the last seconds), so idle and AFK characters do not count
	requireInFight = true,

	-- hunters count together when they are on the same floor within this many sqm (the larger of dx and dy)
	nearRadius = 10,

	-- characters behind one IP count once (multiclient.lua allows 2 per IP)
	onePerIp = true,

	-- respawn interval in percent of the spawntime: 100 below minHunters, then perExtraHunter less for every hunter
	-- after the first, never under minPercent. 2 hunters 85%, 3 70%, 4 55%, 5 or more 50%.
	minHunters = 2,
	perExtraHunter = 15,
	minPercent = 50,

	-- one zone per busy grid cell (cellSize x cellSize sqm, one floor); the spawns whose centre lies in the cell or
	-- within margin sqm of it get the zone's percent (the busiest zone wins where two overlap)
	cellSize = 16,
	margin = 8,

	-- every map spawn's percent when nobody hunts nearby (100 = the spawn file's spawntime); a lower value makes the
	-- whole map respawn faster, e.g. for an event
	globalPercent = 100
}
