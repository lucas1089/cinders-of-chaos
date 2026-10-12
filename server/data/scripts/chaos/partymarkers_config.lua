-- Numbers of the party markers (partymarkers.lua, partymarkers_core.lua; client game_mapmarkers).
-- server/README.md "Map markers" explains them. Lua 5.1 / LuaJIT and 5.3.
return {
	tickMs = 1000, -- how often the parties are looked at; a party is sent only when something changed
	hpStep = 10, -- health is sent in steps of this many percent (a smaller change is no change)
	maxMembers = 30, -- more members than this are never listed
	-- the throttle: at most this many parties are looked at in one tick and at most this many messages go out; the rest
	-- waits for the next tick, in turn (round robin), so a crowded server spreads the work instead of stalling a tick.
	-- Measured (server/README.md "Map markers"): about 2.5 ms per tick to read 100 parties of 4 and about 30 us per
	-- message sent, so 600 messages cap a tick near 20 ms; 100 parties of 4 that all moved fit in one tick.
	maxPartiesPerTick = 300,
	maxSendsPerTick = 600,
	-- a viewer's "set" (the client option switched) at most this often
	setMs = 500
}
