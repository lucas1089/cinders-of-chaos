-- The base server's waypoints (server/README.md "Waypoints for everyone (O386)"; waypoints_core.lua). The base map has
-- a waypoint portal next to every temple (the "Waypoint" floating text; action ids 7000-7017, one per town). The base
-- script (data/scripts/customs/waypoints/waypoint.lua) unlocks a waypoint when a character first steps on it (player
-- storage = the action id, value 1) and its menu lists only the unlocked ones. tools/patch_base_waypoints.py (install
-- step `waypoints`) makes that script ask waypoints_core.lua instead. Plain table, no engine calls. Lua 5.1 / LuaJIT
-- and Lua 5.3 compatible.
--
-- Owner 2026-11-03 (pt-BR): "libere todos os waypoints pra todos os jogadores". unlockAll = true: every waypoint is
-- open for every character, new and old, at any level; nothing is written to the characters (false brings back the
-- base rule: a waypoint opens when stepped on). The base menu has no level gate and costs nothing; the hunts a
-- waypoint town leads to keep their own warnings (hunt teleports, hunt gates).
return {
	unlockAll = true,
	-- the base script's action ids (= its storage keys): the first and the last town's
	firstAid = 7000,
	lastAid = 7017
}
