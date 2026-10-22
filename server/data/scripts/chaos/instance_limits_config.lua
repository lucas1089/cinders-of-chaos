-- The shared numbers of the instance limits (instance_limits.lua, instance_limits_core.lua; server/README.md "Instance
-- limits"). Each system keeps its own time limit and a `limits` block in its own *_config.lua; what it leaves out comes
-- from `defaults` here. The base server's lever boss rooms (patched by tools/patch_base_bossrooms.py) take `bossRooms`.
-- Returned as a table: Chaos.instanceLimitsConfig = dofile("data/scripts/chaos/instance_limits_config.lua").
-- Lua 5.1 / LuaJIT and 5.3.
return {
	defaults = {
		-- seconds left at which everyone inside is told (chat line, red status line; the marks of a minute or more also
		-- as a toast). A mark already behind when a run starts is skipped.
		warnAt = {300, 60, 10},
		-- an instance with nobody inside (all left, logged out or fell without coming back) closes after this many
		-- seconds instead of waiting for its whole time. Systems that end a run at once when the last player leaves
		-- keep doing so; this is for the ones that keep a run open for players who may come back.
		idleSeconds = 180,
		-- the waiting line: a player who finds every instance busy is put in line and told when one frees up (the first
		-- in line first; nobody is moved in automatically). An entry stays waitMinutes; at most waitMax entries per type.
		waitlist = true,
		waitMinutes = 15,
		waitMax = 50,
		-- the most instances of one type at once (0 = only the grid's slots limit it). Every system sets its own.
		maxRuns = 0
	},

	-- staff: /instances (list with the time left), /instances close <type> <id>, /instances line [type]
	staffGroup = 4,

	-- ------------------------------------------------------------------ base lever boss rooms
	-- tools/patch_base_bossrooms.py adds two calls to every base lever room script it recognises (the stock boss room
	-- template: a config table with bossArea, participantsPos and kickParticipantAfterSeconds): the lever asks
	-- ChaosBossRooms.leverUse before anything happens (the room is locked while a group is inside, with the time it
	-- frees up), and ChaosBossRooms.started after the group went in. The room then has:
	bossRooms = {
		enabled = true,
		-- the time limit of a room: the script's own kickParticipantAfterSeconds (10 to 60 minutes in the stock rooms:
		-- 12 rooms 10, 4 rooms 15, 5 rooms 20, 12 rooms 25, 22 rooms 30, 1 room 35, 2 rooms 60), capped at maxSeconds
		-- (0 = always the script's). 30 minutes: one boss fight; twice the longest Chaos boss limit (18 minutes)
		maxSeconds = 1800,
		-- the time of a place without a kick time of its own (tools/patch_base_eventrooms.py; config.chaosRoom): the
		-- soul pit (5 short waves) and the tower defence (about 7 minutes of waves and walking after the lever)
		ownSeconds = {soulpit = 900, towerdefense = 1200},
		-- at the end everyone inside goes to the room's exitPosition (the script's own kick place), the boss and the
		-- other monsters are removed. A boss kill keeps the script's own exit (its teleport and its kick 60 s later).
		-- An empty room (all dead, out or logged out) unlocks after idleSeconds.
		idleSeconds = 120,
		-- a countdown bar over the room's entrance (tilebars.lua) for everyone near it
		bar = true,
		-- a character who logs in inside a room that is not its group's running fight goes to the room's exit
		loginOut = true,
		-- "Leave Boss Room" (Info & Services > Services): a player inside a running room goes to its exit, not while in
		-- a fight; at most once per leaveCooldown seconds. The last one out closes the room as the idle rule would.
		leaveCooldown = 30
	}
}
