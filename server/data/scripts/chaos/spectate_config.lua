-- Live spectator for the admin app (spectate.lua, spectate_core.lua; server/README.md "Live spectator").
-- Returned as a table, loaded as Chaos.spectateConfig (and by tests/spectate_test.lua). Data only.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,
	file = "remote.spectate", -- a bare file name in the server folder: the newest snapshot (JSON), written through .tmp
	intervalMs = 1000, -- one snapshot a second while a watch is on
	watchSeconds = 20, -- a watch ends this long after the last "spectate NAME" line (chaos-ctl.sh renews it every 5 s)
	-- the area around the watched player on its floor: the client's 15 x 11 view plus the tiles it keeps around it
	-- (1 west and north, 2 east and south: big sprites standing there reach into the view)
	left = 8,
	right = 9,
	up = 6,
	down = 7,
	maxItemsPerTile = 12, -- the top of a deep stack only (the client draws at most 10 things a tile)
	maxCreatures = 80
}
