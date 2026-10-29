-- PvP battleground "Ember Wells" and the PvP seasons (arena brackets 1v1 / 2v2 / 3v3 and the battleground).
-- Loaded with
--     Chaos.battlegroundConfig = dofile("data/scripts/chaos/battleground_config.lua")
-- by battleground.lua and arena_season.lua. Pure part: battleground_core.lua (tests/battleground_test.lua).
-- Overview: server/README.md "Battleground and PvP seasons". Lua 5.1 / LuaJIT and Lua 5.3 compatible; no engine calls.
-- Item ids are SERVER ids.

return {
	enabled = true,
	opcode = 200, -- ChaosOpcodes.battleground (client game_battleground)

	-- ------------------------------------------------------------------ who may queue
	minLevel = 100,
	-- level brackets: players only meet players of the same bracket (and the same realm: standard or the running
	-- season, ChaosSeason.realmOf). Inside a match every hit and heal between players is scaled to the bracket's `ref`
	-- level (normalise below). max = nil: no upper end.
	brackets = {
		{key = "b1", min = 100, max = 299, ref = 200, name = "Levels 100-299"},
		{key = "b2", min = 300, max = 599, ref = 450, name = "Levels 300-599"},
		{key = "b3", min = 600, max = 899, ref = 750, name = "Levels 600-899"},
		{key = "b4", min = 900, max = nil, ref = 1000, name = "Levels 900+"}
	},
	-- level normalisation: damage and healing between players x (ref / source level) ^ e x (target level / ref) ^ e,
	-- each factor clamped to [minFactor, maxFactor]. Health, damage and healing grow about linearly with the level, so
	-- e = 1 makes the level vanish; 0.8 keeps a small edge for the higher level. Gear, passive tree and skill stay.
	normalise = {exponent = 0.8, minFactor = 0.6, maxFactor = 1.6},

	-- ------------------------------------------------------------------ teams and the queue
	teamMin = 5, -- smallest match: 5v5
	teamMax = 10, -- largest: 10v10
	partyMax = 5, -- a party queues together (the leader queues it); at most this many
	-- a match smaller than teamMax per side only starts when its oldest entry waited this long
	fillSeconds = 45,
	matchmakeSeconds = 5,
	-- rating window of a match: every entry within window(waited of the oldest) of the oldest entry's rating
	window = {base = 250, step = 50, everySeconds = 15, max = 1200},
	-- the role balance (party_finder_config.lua roles / classRoles): a player queues as one of his class's roles
	-- (default its main role). Cost of a split = |avg rating 1 - avg rating 2| + roleWeight x role count differences;
	-- tanks and healers are spread first.
	roleWeight = 120,
	splitStarts = 8, -- extra pseudo-random starting splits of the local search (near the exhaustive optimum, tested)
	queueMinutes = 30, -- a queue entry leaves after this
	waitSamples = 10, -- estimated wait: average of the last waitSamples waits of the realm and bracket
	defaultWaitSeconds = 120, -- estimated wait when nothing is known yet

	-- ------------------------------------------------------------------ the match
	prepSeconds = 30, -- in the bases, gates closed (anyone outside is sent back), no damage
	matchSeconds = 900, -- then the higher score wins (equal = draw)
	-- instance limits (instance_limits.lua, server/README.md "Instance limits"): warnings at warnAt seconds before the
	-- match's end (the HUD shows the clock too). The queue is the waiting line: a match found while every field
	-- (grid.slots) is in use is told so, with the wait, and starts when one frees up.
	limits = {warnAt = {300, 60, 10}, maxRuns = 0, waitlist = false},
	endDelaySeconds = 12, -- the summary is shown, then everyone goes back where they stood
	winScore = 1000,
	-- every tickSeconds each team scores perTick[number of braziers it holds] (2 s ticks: 1 = 2/s, 2 = 5/s, 3 = 10/s)
	tickSeconds = 2,
	perTick = {[0] = 0, [1] = 4, [2] = 10, [3] = 20},
	killPoints = 5, -- a downed enemy adds this to the team score
	-- capture: progress -100 (team 2) .. +100 (team 1) per brazier. Players of one team only inside the radius move it
	-- towards their side by 100 / captureSeconds per second x (1 + perExtra x (n - 1)) up to maxRate; both teams inside
	-- = contested (no change). Full = owned; crossing 0 = neutral again (an enemy brazier takes twice as long).
	capture = {radius = 2, captureSeconds = 8, perExtra = 0.25, maxRate = 2},
	waveSeconds = 15, -- the downed come back together, every waveSeconds from the start of the fight
	-- AFK: no step, no hit, no heal, no capture for this long (alive, the fight running): a warning, then removed as a
	-- deserter
	afkWarnSeconds = 60,
	afkKickSeconds = 120,
	disconnectSeconds = 20, -- without a connection this long: left the match (a deserter)
	secureGraceSeconds = 15, -- the client turns secure mode off; a reminder every 10 s after this

	-- deserter: leaving a running match (leave, logout, lost connection, AFK). No queue for minutes[n] where n is
	-- the number of desertions in the last windowHours (the last value for more). No rewards, a loss for the rating.
	deserter = {minutes = {15, 30, 60, 120}, windowHours = 24},

	-- ------------------------------------------------------------------ rewards: honor (the PvP vendor's currency)
	honor = {
		win = 120, loss = 50, draw = 80,
		perKill = 4, killCap = 40, -- downing an enemy: the killing blow or an assist (a hit in its last 10 s)
		perCapture = 10, captureCap = 50, -- a brazier taken while you stood in it
		weeklyFirstWin = 300, -- the first win of the week (Monday 06:00) on top
		weeklyCap = 6000, -- honor from matches a week (the vendor is not limited)
		max = 50000 -- balance cap
	},
	-- weekly first win: also these items (crafting orbs, the same as the arena's first win of the day)
	firstWinItems = {{id = 29857, count = 1}, {id = 29856, count = 3}},
	minPresenceShare = 0.5, -- rewards only for players in the match for at least this share of it (late joiners none)

	-- the vendor (Battleground window > Vendor). Cosmetics, consumables. Never power above PvE gear.
	--   kind "item": {id, count}; kind "cosmetic": a cosmetics_config.lua key with source "pvp"
	vendor = {
		{key = "ghp", kind = "item", id = 7591, count = 50, cost = 60, name = "50 great health potions"},
		{key = "gmp", kind = "item", id = 7590, count = 50, cost = 60, name = "50 great mana potions"},
		{key = "gsp", kind = "item", id = 8472, count = 50, cost = 60, name = "50 great spirit potions"},
		{key = "uhp", kind = "item", id = 8473, count = 50, cost = 120, name = "50 ultimate health potions"},
		{key = "c_kill", kind = "cosmetic", cosmetic = "kill_honorbrand", cost = 3000, name = "Kill effect: Honor Brand"},
		{key = "c_loot", kind = "cosmetic", cosmetic = "loot_warbanner", cost = 2000, name = "Loot labels: Warbanner"},
		{key = "c_chat", kind = "cosmetic", cosmetic = "chat_gladiator", cost = 2500, name = "Chat name: Gladiator Steel"}
	},

	-- ------------------------------------------------------------------ the map: "Ember Wells"
	-- slot i of a grid at origin + (i % cols, i // cols) x spacing, built at runtime with Game.createTile (the real
	-- map has no tiles between x/y 3000 and 16000 except the areas of the other systems; this grid uses x/y
	-- 11264 - 11455; the footprint is checked before building).
	grid = {origin = {x = 11264, y = 11264, z = 7}, cols = 2, slots = 4, spacing = 96},
	-- the field: innerW x innerH inside the outer walls; everything else is placed by battleground_core.lua layout()
	-- with a 180-degree rotation symmetry (team 2's half is team 1's half turned around the centre)
	field = {innerW = 63, innerH = 31},
	ids = {
		ground = 407, -- black marble floor (the field)
		baseGround = 413, -- stone floor (bases, graveyards)
		ringGround = 406, -- white marble floor (the capture circle of a brazier)
		wall = 5648, -- stone wall
		pillar = 1515, -- marble pillar (cover)
		brazier = 1481, -- coal basin (the brazier itself; unwalkable)
		flag = 1436 -- castle flag (base decoration)
	},
	-- O276 look (arenalook_core.lua): the field is dressed with scorched rock, basalt and lava cracks; cover and lights come in
	-- pairs turned 180 degrees (the layout's own symmetry), so both teams get the same field. The bases, the graveyards
	-- and the capture circles keep their grounds; spawns, bases, wells (radius + 1), pillars and flags stay open of cover.
	look = {themes = {"ember"}, seed = 5, cover = 3, lights = 6},
	braziers = {"West Well", "Heart Well", "East Well"},
	teams = {
		{name = "Emberguard", color = "#ff9a3c", effect = "CONST_ME_FIREAREA"},
		{name = "Ashbound", color = "#8fb8ff", effect = "CONST_ME_ENERGYAREA"}
	},

	-- ------------------------------------------------------------------ PvP seasons (arena_season.lua)
	season = {
		weeks = 8, -- season length
		-- season 1 starts here, the launch (Fri 20 Nov 2026 15:00, server local time; owner 2026-10-29); season n =
		-- floor((now - epoch) / length) + 1. Season 1 ends Fri 15 Jan 2027 15:00. Before the epoch it is season 1 (not started).
		epoch = {year = 2026, month = 11, day = 20, hour = 15},
		brackets = {"1v1", "2v2", "3v3", "bg"},
		bracketNames = {["1v1"] = "Arena 1v1", ["2v2"] = "Arena 2v2", ["3v3"] = "Arena 3v3", bg = "Battleground"},
		-- Glicko-lite: rating r and deviation rd. One rated match = one Glicko-1 period against the other team's
		-- average rating and root-mean-square rd. rd never drops below rdMin (keeps the change near +/-20 between
		-- equals) and grows by c per week without a match (to rdMax).
		start = 1500, rdStart = 350, rdMin = 75, rdMax = 350, c = 35, floor = 100,
		placementMatches = 5, -- rated matches of a bracket before its tier shows (and counts for rewards)
		-- soft reset at the new season: r = start + (r - start) x squash, rd = max(rd, rdReset), placement again
		squash = 0.5, rdReset = 200,
		-- inactivity decay: a rating at or above decay.from loses perWeek for every full week past graceDays without a
		-- rated match of that bracket, never below decay.from
		decay = {from = 2000, graceDays = 14, perWeek = 30},
		-- tiers by rating (the best placed bracket at the season's end decides the rewards).
		-- reward: title (the name plate, "<title> (S<n>)"), frame (the plate frame of that title), cosmetics
		-- (cosmetics_config.lua keys, source "pvp", granted to the account), honor (to the character)
		tiers = {
			{key = "ashen", name = "Ashen", min = 0, color = "#9a9088", honor = 200},
			{key = "smoulder", name = "Smouldering", min = 1400, color = "#c8a07a", honor = 400, title = "Smouldering"},
			{key = "kindled", name = "Kindled", min = 1600, color = "#f0a040", honor = 700, title = "Kindled",
				frame = "ember"},
			{key = "blazing", name = "Blazing", min = 1800, color = "#ff7a2a", honor = 1000, title = "Blazing",
				frame = "crimson", cosmetics = {"loot_blazing"}},
			{key = "infernal", name = "Infernal", min = 2000, color = "#ff4a3a", honor = 1500, title = "Infernal",
				frame = "gold", cosmetics = {"loot_blazing", "chat_infernal"}},
			{key = "sovereign", name = "Cinder Sovereign", min = 2200, color = "#ffd36a", honor = 2500,
				title = "Cinder Sovereign", frame = "violet", cosmetics = {"loot_blazing", "chat_infernal", "kill_cinderthrone"}}
		},
		checkSeconds = 60, -- how often the season roll is checked
		configKey = "chaos_pvp_season_done" -- server_config: the last season whose rewards were handed out
	},

	-- ------------------------------------------------------------------ storage and tables
	-- player storages 7100380 - 7100389 are reserved for the battleground: +0 inside a match (crash marker: the next
	-- login goes back to where the match started), +1 return x, +2 return y, +3 return z.
	-- testNoPz: GLOBAL storage, TEST ONLY: 1 skips the protection-zone rule of the queue (test maps without one)
	storage = {inside = 7100380, retX = 7100381, retY = 7100382, retZ = 7100383, testNoPz = 7100389},
	tables = {
		players = "chaos_pvp_players", -- honor, battleground record, deserter state per character
		ratings = "chaos_pvp_ratings", -- season ratings per season, character and bracket
		rewards = "chaos_pvp_season_rewards", -- season end tiers and what they gave
		matches = "chaos_bg_matches", -- one row per battleground match
		purchases = "chaos_pvp_purchases" -- vendor purchases (the log)
	},
	leaderboard = "battleground", -- weekly board key (leaderboard_config.lua): wins
	staffGroup = 4 -- /bg staff commands
}
