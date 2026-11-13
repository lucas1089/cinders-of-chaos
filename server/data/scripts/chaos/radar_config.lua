-- Numbers of the minimap radar (radar.lua, radar_core.lua; client game_minimapdots). server/README.md "Minimap radar (O543)".
-- Owner decision 2026-11-13: monster dots on the minimap by "a radius of 30 sent by the server". The values below are that
-- decision; every mitigation of the O543 plan is a switch here that defaults to the owner's choice (off, or exact). Lua 5.1 /
-- LuaJIT and 5.3.
return {
	radius = 30, -- tiles round the player, a circle on the player's floor
	intervalMs = 1500, -- a watcher is looked at at most this often
	tickMs = 500, -- how often the scheduler runs; each tick serves the watchers that are due
	cap = 120, -- most dots in one message: bosses and party members first, then NPCs, then monsters nearest first
	maxCap = 400, -- cap is clamped to this (400 dots stay under 8192 bytes of JSON, checked by tests/radar_test.lua)
	maxPerTick = 300, -- most watchers read in one tick; the next tick goes on after the last one (round robin)
	npcs = true, -- NPCs are listed (blue dots)
	party = true, -- party members on the same floor are listed (green dots)
	bosses = true, -- a boss carries the boss flag (the client draws it bigger with a gold ring); off: bosses are plain monsters
	summons = false, -- summons and pets of other players are left out
	-- mitigations the plan listed, off because the owner chose the plain radius:
	offInInstances = false, -- true: nothing is sent inside a rift, dungeon, raid, tower or arena (Chaos.inAnyInstance)
	offAreas = {}, -- rectangles with no radar: {{from = {x = 0, y = 0, z = 7}, to = {x = 0, y = 0, z = 7}}, ...}
	round = 1, -- positions are rounded to a multiple of this many tiles (1 = exact; 2 blurs the dots a little)
	setMs = 500 -- a viewer's switch (client action `radar`) at most this often
}
