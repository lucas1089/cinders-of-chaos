-- Guild siege settings (siege.lua, siege_core.lua). Loaded with
--     Chaos.siegeConfig = dofile("data/scripts/chaos/siege_config.lua")
-- Overview, rules and numbers: server/README.md "Guild siege". Lua 5.1 / LuaJIT compatible. Item ids are SERVER ids.

return {
	enabled = true, -- automatic weekly schedule (the staff command /siege works either way)

	-- weekly start, server local time. weekday as os.date("*t").wday: 1 = Sunday, 2 = Monday ... 7 = Saturday
	weekday = 7,
	hour = 20,
	minute = 0,
	warnMinutes = {60, 15, 5, 1}, -- broadcasts before the start (the first and the last also as a toast)
	signupCloseMinutes = 5, -- sign-ups (and withdrawals) close this long before the start

	-- sign-up rules (!siege join / !siege leave)
	signupRank = 2, -- guild rank level needed: 3 = leader, 2 = vice-leader (and the leader)
	minMembers = 3, -- members the guild needs (rows in guild_membership)
	minGuilds = 2, -- fewer signed-up guilds at the start: the siege is cancelled
	perBracket = 4, -- guilds per arena (one base room per guild)
	maxBrackets = 3, -- arenas built side by side; more guilds than perBracket x maxBrackets: first come, the rest wait

	-- entry (portals next to the temples)
	minLevel = 100,
	maxPerGuild = 0, -- members of one guild inside at once (0 = no limit)

	-- timing
	gatherSeconds = 180, -- portals open, everyone waits in the guild's base; the gates open at the end of it
	matchMinutes = 25,
	-- instance limits (instance_limits.lua, server/README.md "Instance limits"): warnings to everyone inside at warnAt
	-- seconds before the match ends (the HUD shows the clock too); one siege a week, one arena per bracket
	limits = {warnAt = {300, 60, 10}},
	lateJoin = true, -- portals stay open during the match (members can still come in)
	downedSeconds = 3, -- a "dead" player lies down this long, then wakes up in the guild's base
	exitDelaySeconds = 30, -- after the end: time to read the results before everyone goes to their temple

	-- scoring
	points = {
		kill = 20, -- per enemy player "killed" (to the guild and, for the leaderboard, to the killer)
		holdPerSecond = 1 -- per second the guild holds the Chaos Obelisk (and 1 per second to each holder on the point)
	},
	capture = {
		radius = 2, -- tiles around the obelisk (Chebyshev distance) that count as "on the point"
		exclusive = false -- false: the guild with the most members on the point holds it, a tie contests it;
		                  -- true: any enemy on the point contests it
	},

	-- rewards; presence = seconds inside the arena or the base while the match ran
	minPresenceSeconds = 300,
	reward = {
		winner = {bankGold = 500000, items = {{id = 29856, count = 5}, {id = 29857, count = 2}}}, -- Orbs of Upheaval and Fate
		others = {bankGold = 150000, items = {{id = 29856, count = 2}}}
	},
	title = "Siege Champions", -- the winning guild's members, in the look text
	titleDays = 7, -- title and buff last this long after the siege that won them
	buff = {xp = 0.05}, -- +5% experience from monsters for the members of a champion guild
	leaderboard = "siege", -- ChaosLeaderboard board key (points per player; the call is skipped when the module is absent)

	-- the arena (built with Game.createTile at the start; refused if a footprint tile is already in the map)
	arena = {
		origin = {x = 5100, y = 5000, z = 7}, -- top-left corner of bracket 1's footprint (the north-west base corner area)
		inner = 31, -- inner width/height of the arena (odd: the obelisk stands on the centre tile)
		baseInnerW = 7, baseInnerH = 5, -- base rooms (outside the arena, one per side, sharing the arena wall)
		bracketGap = 8, -- empty tiles between two brackets' footprints
		groundId = 407, -- black marble floor (arena)
		pointGroundId = 406, -- white marble floor (the capture area around the obelisk)
		baseGroundId = 413, -- stone floor (bases)
		wallId = 5648, -- stone wall
		obeliskId = 1560, -- obelisk (the "Chaos Obelisk")
		pillarId = 1515, -- marble pillar (cover)
		basinId = 1481, -- coal basin (light)
		flagId = 1436, -- castle flag (base decoration)
		portalId = 1387 -- magic forcefield (type teleport in items.xml), used without destination + action id
	},
	aid = {enter = 47211, gate = 47212, exit = 47213}, -- portal next to the temple, base gate, base exit home
	portalPositions = {}, -- fixed entry portal positions; empty = next to every temple (portalOffsets)
	exitPosition = nil, -- where players leave to ({x, y, z}); nil = their town's temple
	portalOffsets = {{-2, 0}, {2, 0}, {0, -2}, {0, 2}, {-3, 0}, {3, 0}, {-2, -2}, {2, 2}, {-2, 2}, {2, -2}},

	-- HUD colours of the four base slots (north, east, south, west)
	colors = {"#d23a2a", "#3a7ad2", "#3fae4a", "#e0a526"},
	sides = {"North", "East", "South", "West"},

	-- the login-screen calendar and !events get a "Guild Siege" day (events_schedule.lua)
	calendar = {colorlight = "#c0392b", colordark = "#5e1a12"},

	tables = {signups = "chaos_siege_signups", results = "chaos_siege_results"} -- server/sql/chaos_siege.sql
}
