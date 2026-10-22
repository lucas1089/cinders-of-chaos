-- Vocation Trials: settings (trials.lua, trials_core.lua, trials_effects.lua; design: TRIALS.md). Returned as a table;
-- trials_core.lua puts it in Chaos.trials. Lua 5.1 / LuaJIT and Lua 5.3 compatible. Every number of the feature is here
-- except the special nodes themselves (trials_nodes.lua).
return {
	enabled = true,

	-- storages (player): 7101700 - 7101799 are reserved for the Trials.
	--   tierBase + vocation id   highest tier cleared as that vocation (0 none .. 3 Merciless)
	--   picksBase + vocation id  the held nodes, packed: pair1 + 3 x pair2 + 9 x pair3 (each 0 none, 1 the A node, 2 the B node)
	storage = {
		tierBase = 7101700,
		picksBase = 7101730,
		tokens = 7101760, -- Trial Tokens held
		weekKey = 7101761, -- week (YYYYMMDD of its Monday, ChaosBounty.week) of the repeat rewards counted in weekCount
		weekCount = 7101762,
		runs = 7101763, -- completed runs (information, achievements)
		cooldown = 7101764, -- os.time until the next attempt after a failed one
		marker = 7101765, -- run in progress: tier x 100 + vocation id (cleared at the end; found at login = interrupted)
		weekBank = 7101766 -- repeat rewards carried from earlier weeks into weekKey's week (reward.repeatBankWeeks)
	},

	-- the three difficulties. A tier needs the one before it cleared (as the vocation you play) and its level.
	--   hp        boss health at minLevel (x (level / minLevel) ^ hpExponent, the level clamped to minLevel..maxLevel)
	--   hit       share of the player's maximum health of one boss hit / one thrall hit (the XML numbers only set the rhythm)
	--   time      seconds for the whole run; lives: shared lives (a lethal hit costs one, no real death)
	--   waveSize  thralls per wave: base + perLevelStep x steps
	tiers = {
		{key = "normal", name = "Normal", minLevel = 100, maxLevel = 250, hp = 9000, hit = 0.07, addHit = 0.025, time = 480,
			lives = 3, addHp = 0.10, wave = 4, extraWaves = 0, seals = 3, marks = 3, markSeconds = 16, pyreShare = 0.18,
			zoneShare = 0.20, stillShare = 0.18, tokenReward = 0},
		{key = "cruel", name = "Cruel", minLevel = 250, maxLevel = 500, hp = 40000, hit = 0.09, addHit = 0.035, time = 540,
			lives = 3, addHp = 0.10, wave = 5, extraWaves = 1, seals = 4, marks = 4, markSeconds = 13, pyreShare = 0.24,
			zoneShare = 0.25, stillShare = 0.22, tokenReward = 0},
		{key = "merciless", name = "Merciless", minLevel = 400, maxLevel = 1000, hp = 130000, hit = 0.12, addHit = 0.05,
			time = 600, lives = 2, addHp = 0.09, wave = 6, extraWaves = 2, seals = 5, marks = 5, markSeconds = 10,
			pyreShare = 0.30, zoneShare = 0.30, stillShare = 0.26, tokenReward = 0}
	},
	hpExponent = 1.5,
	enrageBelow = 0.30, enrageMult = 1.5, -- "enrage": the boss hits harder below this share of its health
	-- mechanics (timings in ms)
	stillWarnMs = 2000, stillMs = 3000, -- "stillness": standing on one tile this long is punished
	addEvery = 14000, addCount = 2, addMax = 4, -- "adds": during the boss fight
	zoneEvery = 6000, zoneCount = 5, zoneDelay = 1500, zoneRadius = 2, -- "zones": marked tiles burst
	pyreEvery = 11000, pyreWarn = 2600, pyreSafe = 3, -- "pyre": the fire sweeps the room except next to the safe tiles
	sealChargeMs = 2500, sealPenaltyShare = 0.25, -- "seals": time to stand on the right seal; a wrong one hurts
	markPenaltySeconds = 20, -- "marks": a mark that got away costs this much of the clock
	riseChance = 60, riseDelayMs = 2500, riseHp = 0.6, -- "rise": the dead stand up once
	shieldSeconds = 4, -- after a lost life: monsters cannot hurt the player
	tickMs = 500,
	countdownSeconds = 4,
	exitSeconds = 6, -- after the victory, back to where the run began

	-- the room: a square arena on its own grid. Nothing else uses x/y 9000 - 9400 (rifts 8192-8447, ascension trial 7000+).
	room = {
		grid = {origin = {x = 9000, y = 9000, z = 7}, cols = 4, slots = 8, spacing = 40},
		inner = 21, -- inner width / height (odd: a centre tile)
		groundId = 407, wallId = 5648, basinId = 1481,
		dark = {enabled = true, wall = "ruined_wall", basin = "brazier", style = "trial"}
	},

	-- rewards. First clear of a tier: unlocks its node pair for that vocation (once per vocation) and pays `first`.
	-- A clear of a tier already cleared pays `repeatReward` (at most repeatsPerWeek per week) and always gives one token.
	-- Gold goes to the bank: goldPerLevel x level x tier number. Orbs are the Chaos currency items.
	reward = {
		first = {goldPerLevel = 4000, chaos = {2, 4, 8}, divine = {0, 1, 3}},
		repeatReward = {goldPerLevel = 800, chaos = {1, 2, 3}, divine = {0, 0, 1}},
		repeatsPerWeek = 5,
		-- unused repeat rewards carry over: a week allows repeatsPerWeek + what earlier weeks left, at most
		-- repeatBankWeeks weeks' worth (3: 15). 2026-10-15, respect the players' time.
		repeatBankWeeks = 3,
		weekResetHour = 6, -- the week: Monday 06:00, the bounty board's (ChaosBounty.week)
		items = {chaos = 29856, divine = 29857}
	},

	-- changing a held node: the first pick of a pair is free; moving to the other node (or giving the pair up) costs one
	-- Trial Token and goldPerLevel x level gold (carried gold, then the bank). Tokens come from re-clearing a tier you
	-- already cleared (any tier, one token a clear) and are held up to maxTokens.
	switch = {goldPerLevel = 250, maxTokens = 10, tokensPerRepeat = 1},

	-- entering. Solo only; in a protection zone, out of combat, not multi-clienting.
	enter = {needProtectionZone = true, failCooldownSeconds = 60},
	-- instance limits (instance_limits.lua, server/README.md "Instance limits"): each tier's `time` is the limit;
	-- warnings at warnAt seconds left; at most maxRuns trials at once (the grid's 8 chambers); a player who finds them all
	-- in use waits in line and is told when one frees up. Solo: a logout ends the trial at once (no idle grace needed).
	limits = {warnAt = {120, 60, 10}, maxRuns = 8, waitlist = true},

	-- the NPC that tells the story and opens the same door as the tree window's Trials button
	npc = {
		name = "Keeper of Trials",
		spawn = true,
		townIds = {2}, -- the main city only: its stall in the hub (npc_booths_config.lua; 2026-10-22)
		positions = {},
		offsets = {{-2, 2}, {2, -3}, {-3, -2}, {3, 2}, {0, 4}, {-4, 0}, {4, 0}, {-2, -3}, {1, 3}},
		range = 6
	},
	modalId = 7150, -- modal window of the NPC (the tier list)

	-- the client HUD is the rift HUD (opcode ChaosOpcodes.rift, game_rift): a title, clock, lives, progress and notes.
	hud = {everySeconds = 3},

	-- the family of a vocation: a trial theme with its monsters (existing looks only) and mechanics.
	--   stages: the order of the run before the boss ("wave", "seals", "marks"); tier.extraWaves adds waves
	--   mech: "stillness" (all stages) "zones" "adds" "enrage" "pyre" (all stages) "rise" (all stages), see trials.lua
	families = {
		warrior = {name = "The Iron Gauntlet", voc = {4, 8, 14}, stages = {"wave", "wave"}, mech = {"stillness", "enrage"},
			boss = {name = "Gauntlet Champion", look = {lookType = 131, lookHead = 95, lookBody = 95, lookLegs = 95, lookFeet = 95, lookAddons = 3}},
			add = {name = "Gauntlet Thrall", look = {lookType = 298}},
			story = "Waves of iron-bound thralls, then the Champion. Do not stand still against it: it crushes whoever plants their feet."},
		ranger = {name = "The Hollow Moon Hunt", voc = {3, 7, 15}, stages = {"wave", "wave"}, mech = {"zones", "stillness"},
			boss = {name = "Moon Stalker", look = {lookType = 240}},
			add = {name = "Moon Hound", look = {lookType = 3}, speed = 40},
			story = "A fast pack, then the Stalker, whose volleys mark the ground before they land. Read the marks."},
		mystic = {name = "The Seals of the Elements", voc = {1, 5, 10}, stages = {"seals"}, mech = {"zones", "adds"},
			boss = {name = "Keeper of the Seals", look = {lookType = 130, lookHead = 0, lookBody = 94, lookLegs = 114, lookFeet = 95, lookAddons = 1}},
			add = {name = "Seal Phantasm", look = {lookType = 241, lookHead = 20}},
			story = "Four seals burn in four colours. Break them in the order the Keeper speaks, or the wrong one will punish you."},
		thief = {name = "The Night Run", voc = {11, 12, 13}, stages = {"marks"}, mech = {"zones", "stillness"},
			boss = {name = "Master of Shadows", look = {lookType = 320}},
			add = {name = "Marked Cutthroat", look = {lookType = 152, lookHead = 95, lookBody = 95, lookLegs = 95, lookFeet = 95, lookAddons = 3}, speed = 80},
			story = "Marked cutthroats come one after another, fast. Each that slips away costs you time. Then the Master."},
		monk = {name = "The Silent Ascent", voc = {17, 18, 19}, stages = {"wave", "wave"}, mech = {"stillness", "zones"},
			boss = {name = "Warden of the Still Fist", look = {lookType = 57}},
			add = {name = "Silent Acolyte", look = {lookType = 57}},
			story = "Two waves of acolytes, then the Warden. Stillness is the lesson: keep your feet moving against it."},
		necromancer = {name = "The Grave Tithe", voc = {20, 21, 22}, stages = {"wave", "wave"}, mech = {"adds", "zones", "rise"},
			boss = {name = "Tithe Collector", look = {lookType = 99}},
			add = {name = "Tithed Dead", look = {lookType = 1542}},
			story = "The dead here stand up a second time. Break them again, and the Collector who calls for more."},
		templar = {name = "The Trial of Fire", voc = {23, 24, 25}, stages = {"wave"}, mech = {"pyre", "enrage"},
			boss = {name = "Pyre Warden", look = {lookType = 73}},
			add = {name = "Ember Zealot", look = {lookType = 73}},
			story = "The fire sweeps the whole room. Stand beside a sanctuary light when it breaks, and keep fighting between the waves."}
	},

	-- small differences between the vocations of one family (health, boss hits, thrall count: multipliers)
	variants = {
		[8] = {hit = 1.15, adds = 0.8}, -- Juggernaut: hardest hits, fewer thralls
		[14] = {hit = 0.95, adds = 1.3}, -- Berserker: more thralls to cleave
		[7] = {hp = 1.1}, -- Deadeye: a sturdier stalker
		[15] = {adds = 1.2},
		[5] = {hp = 1.1}, [10] = {hit = 0.9, hp = 0.9}, -- Illusionist: a gentler keeper
		[12] = {adds = 1.1}, [13] = {hit = 1.1},
		[19] = {hit = 1.1}, [18] = {hp = 0.95},
		[21] = {hp = 1.05}, [22] = {adds = 1.3},
		[24] = {hit = 1.05}, [25] = {hit = 1.1, hp = 1.05}
	},

	-- achievements fed by trials.lua (stats; the entries are in achievements_data.lua)
	achievements = {tier = "trial_tier", runs = "trial_runs", nodes = "trial_nodes", switches = "trial_switches"}
}
