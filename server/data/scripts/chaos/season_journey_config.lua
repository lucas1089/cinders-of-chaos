-- Seasonal Journey (season_journey.lua, season_journey_core.lua; client game_season, Journey tab). Every chapter,
-- objective and reward of the journey of each season. Data only, no engine calls (server/tests/season_journey_test.lua
-- reads it with plain Lua). Overview: server/README.md "Seasonal Journey".
--
-- The journey is a fixed, chaptered checklist per season and per season character: it walks a fresh character through
-- the season's content once (levels, rifts, world bosses, dungeons, the Descent, Omens, the raid, the Atlas, ...).
-- It is not the season pass (seasonpass*.lua: account-wide, repeatable pass XP and daily / weekly challenges) and not the
-- season reward track (season_config.lua `track`: account-wide milestones kept forever). A finished chapter gives pass XP
-- to the account's pass of that season, orbs, and one piece of the season's appearance set; the last chapter gives the
-- set's mount and a title.
--
-- Chapters unlock in order: the one before it finished and the character at the chapter's `level`. Stats count from the
-- join on (also while a chapter is locked); an objective is marked done once its chapter is open and its stat is at the
-- target, so a chapter that opens late completes what the character already did.
--
-- An objective: {key, text, stat, target, only?}
--   key     stable id (stored in chaos_season_journey as "o:<key>"); unique within the journey; never rename a live one
--   stat    "level" (the character's level now) or a key of `stats` below
--   flag    true: the window shows the objective as done / not done (0 / 1) instead of the number (faction ranks)
--   only    nil = every season character; "hc" Hardcore only, "ssf" Self-Found only, "nossf" all but Self-Found (things
--           Self-Found cannot do, e.g. the Orb Exchange), "nohc" all but Hardcore
-- A chapter: {key, name, level, text, objectives, rewards}
-- Rewards (given once per character, at the moment the chapter completes):
--   {kind = "passxp", amount = n}                      pass XP to the account's season pass of this season (when it runs)
--   {kind = "items", id = serverId, count = n, name}   to the backpack (the inbox when it is full)
--   {kind = "look", id = serverId, slot = "...", name} a transmog appearance (account-wide wardrobe, transmog.lua)
--   {kind = "outfit", male = lookType, female = lookType, addons = 0..3, name}   both looks (a sex change keeps it)
--   {kind = "mount", id = mounts.xml id, clientid = its look (the window), name}
--   {kind = "title", title = "..."}                    name plate title (titles.lua source "journey")
-- `piece = true` marks a reward that is a piece of the season's set (the window counts them: "set 3 / 8").
-- Every look type, mount and item exists in the base server's XML; nothing new is drawn.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

local UPHEAVAL, FATE, GRAFTING = 29856, 29857, 29855

local function orbs(id, count)
	local names = {[UPHEAVAL] = "Orb of Upheaval", [FATE] = "Orb of Fate", [GRAFTING] = "Orb of Grafting"}
	return {kind = "items", id = id, count = count, name = names[id]}
end

local function xp(n)
	return {kind = "passxp", amount = n}
end

return {
	tables = {
		stats = "chaos_season_journey_stats", -- (season, player_id, stat) -> value
		entries = "chaos_season_journey" -- (season, player_id, entry) done objectives "o:<key>" and chapters "c:<key>"
	},
	flushSeconds = 30, -- counters of online characters are written at least this often (and at logout)
	staffGroup = 4, -- staff walk no journey

	-- Journey stats: how a reported value adds up. "add" sums, "max" keeps the best.
	-- Sources (season_journey.lua; nothing else is edited unless named):
	--   achievement counters  ChaosAchievements.progress / set are wrapped: every counter listed here that the
	--                         achievements report counts for the journey too (achievements_data.lua "Stats")
	--   faction_rep, faction_rank       ChaosFactions.gain wrapped (reputation gained; rank index 1-7, 4 = Trusted)
	--   community_points      ChaosCommunity.contribute wrapped (points added to the community goal)
	--   orbx_orders           ChaosOrbExchange.place wrapped (an order placed)
	--   tower_floor           ChaosTower.recordRun wrapped (floors cleared in a run)
	--   descent_runs, descent_depth, descent_clears   one guarded line in descent.lua (a run's end per player)
	--   dungeon_clears        one guarded line in dungeons.lua (a cleared dungeon per member)
	--   atlas_points          one guarded line in atlas.lua (Rift Atlas points earned, after a credit)
	stats = {
		kills_tiered = "add",
		party_kills = "add",
		goblin_kills = "add",
		bounty_done = "add",
		bestiary_tasks = "add",
		bestiary_completed = "max",
		rift_tier = "max",
		rift_runs = "add",
		rift_flawless = "add",
		omen_kills = "add",
		ascended_kills = "add",
		cinder_kills = "add",
		wb_kills = "add",
		invasion_fought = "add",
		invasion_defended = "add",
		raid_kills = "add",
		raid_clears = "add",
		raid_flawless = "add",
		orbs_used = "add",
		orb_exalted = "add",
		unique_found = "add",
		mods_max = "max",
		power_found = "max",
		faction_exalted = "max",
		faction_rep = "add",
		faction_rank = "max",
		community_points = "add",
		orbx_orders = "add",
		tower_floor = "max",
		descent_runs = "add",
		descent_depth = "max",
		descent_clears = "add",
		dungeon_clears = "add",
		atlas_points = "max"
	},

	-- ------------------------------------------------------------------ journeys, per season id
	journeys = {
		[1] = {
			name = "The Ashen Pilgrimage",
			set = "Ashen Pilgrim", -- the season's appearance set the chapters build
			chapters = {
				{key = "embers", name = "First Embers", level = 0,
					text = "Learn the ways of the season: rifts, bounties, the hunt.",
					objectives = {
						{key = "lvl100", text = "Reach level 100", stat = "level", target = 100},
						{key = "rift1", text = "Seal a tier 1 rift", stat = "rift_tier", target = 1},
						{key = "boss1", text = "Defeat a world boss", stat = "wb_kills", target = 1},
						{key = "bounty5", text = "Complete 5 bounty contracts", stat = "bounty_done", target = 5},
						{key = "task1", text = "Finish a bestiary kill task", stat = "bestiary_tasks", target = 1},
						{key = "tiered50", text = "Slay 50 magic, rare or legendary monsters", stat = "kills_tiered", target = 50},
						{key = "orbs5", text = "Use 5 crafting orbs", stat = "orbs_used", target = 5}
					},
					rewards = {xp(1500), orbs(UPHEAVAL, 3),
						{kind = "look", id = 7900, slot = "helmet", name = "Magma Monocle appearance", piece = true}}},
				{key = "ironash", name = "Ash and Iron", level = 150,
					text = "Dungeons, factions and the hunt in numbers.",
					objectives = {
						{key = "lvl200", text = "Reach level 200", stat = "level", target = 200},
						{key = "rift4", text = "Seal a tier 4 rift", stat = "rift_tier", target = 4},
						{key = "dungeon1", text = "Clear a dungeon", stat = "dungeon_clears", target = 1},
						{key = "trusted", text = "Become Trusted by a faction", stat = "faction_rank", target = 4, flag = true},
						{key = "goblin1", text = "Slay a treasure goblin", stat = "goblin_kills", target = 1},
						{key = "invasion1", text = "Fight in an invasion", stat = "invasion_fought", target = 1},
						{key = "party500", text = "Slay 500 monsters in a party", stat = "party_kills", target = 500},
						{key = "atlas10", text = "Earn 10 Rift Atlas points", stat = "atlas_points", target = 10},
						{key = "hcflawless", text = "Hardcore: seal a rift without a death", stat = "rift_flawless", target = 1,
							only = "hc"}
					},
					rewards = {xp(2000), orbs(UPHEAVAL, 5),
						{kind = "look", id = 7899, slot = "armor", name = "Magma Coat appearance", piece = true}}},
				{key = "road", name = "The Burning Road", level = 250,
					text = "The Ember Descent, the Infinity Tower and the world's bosses.",
					objectives = {
						{key = "lvl300", text = "Reach level 300", stat = "level", target = 300},
						{key = "rift6", text = "Seal a tier 6 rift", stat = "rift_tier", target = 6},
						{key = "descent6", text = "Reach room 6 of the Ember Descent", stat = "descent_depth", target = 6},
						{key = "boss3", text = "Defeat 3 world bosses", stat = "wb_kills", target = 3},
						{key = "tower10", text = "Clear 10 floors of the Infinity Tower in one run", stat = "tower_floor",
							target = 10},
						{key = "defend1", text = "Defend a city from an invasion", stat = "invasion_defended", target = 1},
						{key = "unique1", text = "Find a unique item", stat = "unique_found", target = 1},
						{key = "community", text = "Add 500 points to the community goal", stat = "community_points",
							target = 500},
						{key = "ssforbs50", text = "Self-Found: use 50 crafting orbs", stat = "orbs_used", target = 50,
							only = "ssf"}
					},
					rewards = {xp(2500), orbs(FATE, 2),
						{kind = "look", id = 7894, slot = "legs", name = "Magma Legs appearance", piece = true}}},
				{key = "omens", name = "Omens in the Ash", level = 350,
					text = "The Omen guardians wake. Bind your craft to the market of orbs.",
					objectives = {
						{key = "lvl400", text = "Reach level 400", stat = "level", target = 400},
						{key = "omen1", text = "Slay an Omen guardian", stat = "omen_kills", target = 1},
						{key = "rift8", text = "Seal a tier 8 rift", stat = "rift_tier", target = 8},
						{key = "bounty25", text = "Complete 25 bounty contracts", stat = "bounty_done", target = 25},
						{key = "honored", text = "Become Honored by a faction", stat = "faction_rank", target = 5, flag = true},
						{key = "descentclear", text = "Clear the Ember Descent", stat = "descent_clears", target = 1},
						{key = "orbx1", text = "Place an order on the Orb Exchange", stat = "orbx_orders", target = 1,
							only = "nossf"},
						{key = "ssforbs150", text = "Self-Found: use 150 crafting orbs", stat = "orbs_used", target = 150,
							only = "ssf"},
						{key = "atlas30", text = "Earn 30 Rift Atlas points", stat = "atlas_points", target = 30}
					},
					rewards = {xp(3000), orbs(FATE, 3),
						{kind = "look", id = 7891, slot = "boots", name = "Magma Boots appearance", piece = true}}},
				{key = "sepulchre", name = "The Ashen Sepulchre", level = 450,
					text = "Gather a raid. Hunt every Omen.",
					objectives = {
						{key = "lvl500", text = "Reach level 500", stat = "level", target = 500},
						{key = "raid1", text = "Defeat a boss of the Ashen Sepulchre", stat = "raid_kills", target = 1},
						{key = "omen3", text = "Slay 3 Omen guardians", stat = "omen_kills", target = 3},
						{key = "rift10", text = "Seal a tier 10 rift", stat = "rift_tier", target = 10},
						{key = "bestiary10", text = "Complete 10 bestiary entries", stat = "bestiary_completed", target = 10},
						{key = "graft1", text = "Use an Orb of Grafting", stat = "orb_exalted", target = 1},
						{key = "tower25", text = "Clear 25 floors of the Infinity Tower in one run", stat = "tower_floor",
							target = 25},
						{key = "hc500", text = "Hardcore: reach level 550", stat = "level", target = 550, only = "hc"}
					},
					rewards = {xp(3500), orbs(GRAFTING, 1),
						{kind = "look", id = 7744, slot = "weapon", name = "Fiery Spike Sword appearance", piece = true}}},
				{key = "ascended", name = "Ascended Omens", level = 600,
					text = "The Omens ascend. Clear the Sepulchre to its last door.",
					objectives = {
						{key = "lvl650", text = "Reach level 650", stat = "level", target = 650},
						{key = "ascended1", text = "Slay an Ascended Omen", stat = "ascended_kills", target = 1},
						{key = "raidclear", text = "Clear the Ashen Sepulchre", stat = "raid_clears", target = 1},
						{key = "atlas50", text = "Earn 50 Rift Atlas points", stat = "atlas_points", target = 50},
						{key = "boss10", text = "Defeat 10 world bosses", stat = "wb_kills", target = 10},
						{key = "descent10", text = "Reach room 10 of the Ember Descent", stat = "descent_depth", target = 10},
						{key = "ssfmods5", text = "Self-Found: own an item with 5 modifiers", stat = "mods_max", target = 5,
							only = "ssf"}
					},
					rewards = {xp(4000), orbs(GRAFTING, 2),
						{kind = "look", id = 8906, slot = "shield", name = "Fiery Rainbow Shield appearance", piece = true}}},
				{key = "cinderheart", name = "The Cinderheart", level = 700,
					text = "Face the heart of the fire.",
					objectives = {
						{key = "lvl750", text = "Reach level 750", stat = "level", target = 750},
						{key = "ascended3", text = "Slay 3 Ascended Omens", stat = "ascended_kills", target = 3},
						{key = "cinder1", text = "Slay the Cinderheart", stat = "cinder_kills", target = 1},
						{key = "raid3", text = "Clear the Ashen Sepulchre 3 times", stat = "raid_clears", target = 3},
						{key = "rift12", text = "Seal a tier 12 rift", stat = "rift_tier", target = 12},
						{key = "revered", text = "Become Revered by a faction", stat = "faction_rank", target = 6, flag = true},
						{key = "tower40", text = "Clear 40 floors of the Infinity Tower in one run", stat = "tower_floor",
							target = 40},
						{key = "hcflawless5", text = "Hardcore: seal 5 rifts without a death", stat = "rift_flawless",
							target = 5, only = "hc"}
					},
					rewards = {xp(5000), orbs(FATE, 5),
						{kind = "outfit", male = 1248, female = 1249, addons = 0, name = "Retro Knight outfit", piece = true}}},
				{key = "eternal", name = "Ash Eternal", level = 850,
					text = "The end of the pilgrimage. Few walk this far.",
					objectives = {
						{key = "lvl900", text = "Reach level 900", stat = "level", target = 900},
						{key = "raidflawless", text = "Clear the Ashen Sepulchre without a death", stat = "raid_flawless",
							target = 1},
						{key = "atlas75", text = "Earn 75 Rift Atlas points", stat = "atlas_points", target = 75},
						{key = "rift15", text = "Seal a tier 15 rift", stat = "rift_tier", target = 15},
						{key = "exalted", text = "Become Exalted by a faction", stat = "faction_exalted", target = 1, flag = true},
						{key = "bounty100", text = "Complete 100 bounty contracts", stat = "bounty_done", target = 100},
						{key = "boss25", text = "Defeat 25 world bosses", stat = "wb_kills", target = 25},
						{key = "hc1000", text = "Hardcore: reach level 1000", stat = "level", target = 1000, only = "hc"},
						{key = "ssfpower", text = "Self-Found: own an item with a legendary power", stat = "power_found",
							target = 1, only = "ssf", flag = true}
					},
					rewards = {xp(6000), orbs(GRAFTING, 3),
						{kind = "mount", id = 122, clientid = 1239, name = "Fire Panther mount", piece = true},
						{kind = "title", title = "Ashen Pilgrim", piece = true}}}
			}
		}
	}
}
