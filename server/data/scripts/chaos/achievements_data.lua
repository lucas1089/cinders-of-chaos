-- Achievements: the list. Edit this file to add, change or retire achievements (achievements.lua loads it with
--     ChaosAchievements.data = dofile("data/scripts/chaos/achievements_data.lua")
-- and achievements_core.lua checks it at startup; problems are printed to the console and the bad entry is skipped).
--
-- An achievement:
--   id        stable key, letters, digits and "_" (stored in chaos_achievements; never rename one that is live)
--   name      shown in the window and the toast
--   desc      one line
--   cat       a key of `categories`
--   points    achievement points (5 / 10 / 15 / 25 / 50)
--   stat      the progress counter it reads (see "Stats" below); unlocked when stat >= target
--   target    the threshold (default 1)
--   all       instead of stat: a list of stats that must each be at least 1 (progress = how many are)
--   hidden    true: shown as "???" until unlocked
--   title     optional title for the name plate (titles.lua, source "achievement"; !title or the window to pick it)
--   frame     optional name plate frame of that title while it is the active one (nameplate_core.lua N.FRAMES)
--   reward    optional, given once at the unlock (backpack first, inbox when full):
--               gold   = n                       to the bank
--               items  = {{id = n, count = n}}   server item ids
--               outfit = {name, female = lookType, male = lookType, addons = 0..3}   both looks are added
--               mount  = {name, id = mount id}   data/XML/mounts.xml of the base server
--               portal = {key, name}             a Town Portal style (townportal_config.lua, route "achievement"); it is
--                                                owned while the character has the achievement (also for older unlocks)
--               exclusives = {{key, name}}       visual exclusives of exclusives_config.lua (source "achievement"; name =
--                                                "<kind> <name>"): unlocked for the whole account by exclusives.lua, also
--                                                for older unlocks; never sold
--             outfits and mounts are ones the base server already has (no new art).
--
-- Stats (per character; values only go up). Who feeds them, see server/README.md "Achievements":
--   level, paragon, ascended, tutorial, guild                        login and level up (retroactive)
--   kills_magic, kills_rare, kills_legendary, kills_tiered,          kills (kill event + monster_tiers.lua)
--   ambush_kills, party_kills, goblin_kills, goblin_escaped, rat_500, witching_legendary, deaths
--   wb_kills, wb_top, wb_kaelgor, wb_skaldra, wb_rotmother, wb_nyxareth, wb_vharok      world boss rewards
--   wb_heal_top, wb_tank_top, wb_role_podium                         world boss roles (worldboss.lua distribute)
--   trial_tier_<1-3>, trial_runs, trial_nodes, trial_switches         Vocation Trials (trials.lua)
--   rift_tier, rift_runs, rift_flawless, rift_three, rift_mod_<modifier key>           sealed rifts
--   omen_kills, omen_<kind>                                                            omen guardians (rift.lua)
--   ascended_kills, ascended_<kind>, cinder_kills, cinder_solo, cinder_flawless          Ascended Omens (uber.lua)
--   bounty_done, bounty_weeks                                        bounty board (retroactive from chaos_bounty)
--   bestiary_known, bestiary_completed, bestiary_points, bestiary_tasks   bestiary and kill tasks (bestiary.lua)
--   unique_found, rarity_max, orbs_used, orb_exalted, mods_max       loot and the crafting bench
--   orb_binding, ruin_improved, ruin_ruined, quality_max, power_found   orbs v2 and legendary powers (the crafting hook, loot)
--   arena1v1_wins, arena1v1_rating, arena2v2_wins, arena2v2_rating   arena (retroactive from chaos_arena_ratings)
--   siege_played, siege_wins                                         guild siege
--   bg_matches, bg_wins, pvp_season_tier                             battleground (battleground.lua) and the PvP season
--                                                                    end (arena_season.lua: the best tier reached, 1-6)
--   faction_exalted_<vigil|compact|choir|circle>, faction_exalted   factions (factions.lua: 1 once Exalted; how many are)
--   raid_kills, raid_<boss key>, raid_clears, raid_flawless, raid_speed   the Ashen Sepulchre (raid.lua: every raider present
--                                                                    at a kill, looted or not)
--   points                                                           the character's own achievement points
--   season_hc_level, season_ssf_level, season_hc_survived, season_ssf_finished   season modes (season_modes.lua)
--   mentor_graduates, mentor_fledged                                 mentors (mentor.lua, at a graduation)
--   pvpzone_kills, pvpzone_banked, pvpzone_haul, pvpzone_captures   the Scorched Marches (pvpzone.lua)
--   prof_<delving|wortcunning|flaying|angling>, prof_total          professions (professions.lua: the level; all four levels together)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible; no engine calls (also read by server/tests/achievements_test.lua).

local CHAOS, DIVINE, EXALTED = 29856, 29857, 29855

local function orbs(chaos, divine, exalted)
	local items = {}
	if chaos and chaos > 0 then items[#items + 1] = {id = CHAOS, count = chaos} end
	if divine and divine > 0 then items[#items + 1] = {id = DIVINE, count = divine} end
	if exalted and exalted > 0 then items[#items + 1] = {id = EXALTED, count = exalted} end
	return items
end

return {
	categories = {
		{key = "combat", name = "Combat & Leveling"},
		{key = "monsters", name = "Monsters"},
		{key = "bosses", name = "World Bosses"},
		{key = "rifts", name = "Rifts"},
		{key = "raids", name = "Raids"},
		{key = "bounties", name = "Bounties"},
		{key = "items", name = "Items & Crafting"},
		{key = "pvp", name = "PvP"},
		{key = "explore", name = "Exploration & Social"},
		{key = "secrets", name = "Secrets"}
	},

	-- category completion (reward track): an account with every achievement of a category (hidden ones too; any of its
	-- characters) holds this title (titles.lua source "achievement", key "achievement_cat:<key>", frame while active) and
	-- the cosmetic of cosmetics_config.lua with category = <key> (granted by cosmetics.lua). See server/README.md.
	categoryRewards = {
		combat = {title = "Warmaster", frame = "ember"},
		monsters = {title = "Beastwarden", frame = "verdant"},
		bosses = {title = "Titanfeller", frame = "bone"},
		rifts = {title = "Riftwarden", frame = "violet"},
		raids = {title = "Sepulchre Lord", frame = "bone"},
		bounties = {title = "the Relentless", frame = "ember"},
		items = {title = "Forgewright", frame = "frost"},
		pvp = {title = "the Unconquered", frame = "violet"},
		explore = {title = "Wayfarer", frame = "verdant"},
		secrets = {title = "Keeper of Secrets", frame = "frost"}
	},

	-- world boss name (lower case, a part of it is enough) -> its stat
	bossStats = {
		kaelgor = "wb_kaelgor", skaldra = "wb_skaldra", rotmother = "wb_rotmother", nyxareth = "wb_nyxareth", vharok = "wb_vharok"
	},

	list = {
		-- ------------------------------------------------------------------ Combat & Leveling
		{id = "level_50", cat = "combat", name = "Blooded", desc = "Reach level 50.", points = 5, stat = "level", target = 50},
		{id = "level_100", cat = "combat", name = "Ascendant's Threshold", desc = "Reach level 100.", points = 10, stat = "level", target = 100},
		{id = "level_200", cat = "combat", name = "Hardened", desc = "Reach level 200.", points = 10, stat = "level", target = 200},
		{id = "level_300", cat = "combat", name = "Veteran of the Wastes", desc = "Reach level 300.", points = 15, stat = "level", target = 300,
			title = "Veteran"},
		{id = "level_500", cat = "combat", name = "Shatterborn", desc = "Reach level 500.", points = 25, stat = "level", target = 500,
			reward = {items = orbs(5, 1)}},
		{id = "level_700", cat = "combat", name = "Into the Abyss", desc = "Reach level 700.", points = 25, stat = "level", target = 700,
			reward = {items = orbs(5, 2)}},
		{id = "level_1000", cat = "combat", name = "The Thousandth Step", desc = "Reach level 1000.", points = 50, stat = "level",
			target = 1000, title = "the Unbroken", reward = {mount = {name = "Doombringer", id = 53}}},
		{id = "ascended", cat = "combat", name = "Ascended", desc = "Ascend into one of your class's two paths.", points = 10,
			stat = "ascended"},
		-- Vocation Trials (trials.lua): trial_tier_<1-3> (a tier cleared), trial_runs (clears), trial_nodes (nodes held now),
		-- trial_switches (held nodes changed)
		{id = "trial_normal", cat = "combat", name = "Trial by Fire", desc = "Clear your vocation's trial on Normal.", points = 10,
			stat = "trial_tier_1"},
		{id = "trial_cruel", cat = "combat", name = "No Mercy Asked", desc = "Clear your vocation's trial on Cruel.", points = 25,
			stat = "trial_tier_2"},
		{id = "trial_merciless", cat = "combat", name = "Merciless", desc = "Clear your vocation's trial on Merciless.", points = 50,
			stat = "trial_tier_3", title = "the Trialbound"},
		{id = "trial_nodes_3", cat = "combat", name = "Three Choices", desc = "Hold a special node from every pair of your vocation.",
			points = 25, stat = "trial_nodes", target = 3},
		{id = "trial_runs_10", cat = "combat", name = "Pilgrim of Trials", desc = "Clear a trial 10 times.", points = 15,
			stat = "trial_runs", target = 10},
		{id = "trial_changed", cat = "combat", name = "Changed Mind", desc = "Change a held trial node for another.", points = 5,
			stat = "trial_switches"},
		{id = "paragon_1", cat = "combat", name = "Beyond the Wall", desc = "Earn your first Paragon level.", points = 10,
			stat = "paragon", target = 1},
		{id = "paragon_50", cat = "combat", name = "Paragon of Ash", desc = "Reach Paragon level 50.", points = 25, stat = "paragon",
			target = 50, reward = {items = orbs(0, 3)}},
		{id = "paragon_100", cat = "combat", name = "Paragon of Ruin", desc = "Reach Paragon level 100.", points = 50, stat = "paragon",
			target = 100, title = "Paragon"},
		{id = "paragon_282", cat = "combat", name = "Absolute", desc = "Reach Paragon level 282: every Paragon stat maxed.",
			points = 50, stat = "paragon", target = 282, title = "the Absolute", reward = {items = orbs(0, 5)}},

		-- ------------------------------------------------------------------ Monsters
		{id = "magic_1", cat = "monsters", name = "Touched by Chaos", desc = "Kill a magic monster.", points = 5, stat = "kills_magic"},
		{id = "magic_250", cat = "monsters", name = "Spellbreaker", desc = "Kill 250 magic monsters.", points = 10, stat = "kills_magic",
			target = 250},
		{id = "rare_1", cat = "monsters", name = "Rare Prey", desc = "Kill a rare monster.", points = 5, stat = "kills_rare"},
		{id = "rare_100", cat = "monsters", name = "Rare Breaker", desc = "Kill 100 rare monsters.", points = 15, stat = "kills_rare",
			target = 100},
		{id = "legendary_1", cat = "monsters", name = "Legend Slayer", desc = "Kill a legendary monster.", points = 10,
			stat = "kills_legendary"},
		{id = "legendary_25", cat = "monsters", name = "Mythbreaker", desc = "Kill 25 legendary monsters.", points = 25,
			stat = "kills_legendary", target = 25, reward = {items = orbs(3, 1)}},
		{id = "legendary_250", cat = "monsters", name = "Legend's Bane", desc = "Kill 250 legendary monsters.", points = 50,
			stat = "kills_legendary", target = 250, title = "Legendbane"},
		{id = "tiered_1000", cat = "monsters", name = "Chaos Culler", desc = "Kill 1,000 magic, rare or legendary monsters.",
			points = 25, stat = "kills_tiered", target = 1000, title = "Culler"},
		{id = "tiered_10000", cat = "monsters", name = "Harbinger of Silence", desc = "Kill 10,000 magic, rare or legendary monsters.",
			points = 50, stat = "kills_tiered", target = 10000, title = "Harbinger",
			reward = {outfit = {name = "Death Herald", female = 666, male = 667, addons = 3}}},
		{id = "ambush_1", cat = "monsters", name = "It Was a Trap", desc = "Survive an ambush: kill the monster that ambushed you.",
			points = 5, stat = "ambush_kills"},
		{id = "ambush_50", cat = "monsters", name = "Ambush Predator", desc = "Kill 50 ambushing monsters.", points = 15,
			stat = "ambush_kills", target = 50},
		{id = "ambush_250", cat = "monsters", name = "Nothing Surprises Me", desc = "Kill 250 ambushing monsters.", points = 25,
			stat = "ambush_kills", target = 250,
			reward = {exclusives = {{key = "mount_tuskhide", name = "mount Tuskhide Boar"}}}},
		{id = "goblin_1", cat = "monsters", name = "Grab the Sack", desc = "Slay a Treasure Goblin before it escapes.", points = 10,
			stat = "goblin_kills"},
		{id = "goblin_10", cat = "monsters", name = "Greed Is Good", desc = "Slay 10 Treasure Goblins.", points = 25,
			stat = "goblin_kills", target = 10, reward = {items = orbs(0, 2)}},
		{id = "goblin_50", cat = "monsters", name = "Hoardbreaker", desc = "Slay 50 Treasure Goblins.", points = 50,
			stat = "goblin_kills", target = 50, title = "Goblinbane", reward = {portal = {key = "hoarder", name = "Hoarder's Gate"}}},
		{id = "goblin_escaped", cat = "monsters", name = "Ha Ha!", desc = "Hit a Treasure Goblin and watch it escape anyway.",
			points = 5, stat = "goblin_escaped", hidden = true},
		-- bestiary (bestiary.lua: discovered / completed entries, kill tasks done)
		{id = "bestiary_25", cat = "monsters", name = "Field Notes", desc = "Discover 25 bestiary entries.", points = 5,
			stat = "bestiary_known", target = 25},
		{id = "bestiary_done_1", cat = "monsters", name = "Know Thy Enemy", desc = "Complete a bestiary entry.", points = 10,
			stat = "bestiary_completed", target = 1},
		{id = "bestiary_done_50", cat = "monsters", name = "Monster Scholar", desc = "Complete 50 bestiary entries.", points = 25,
			stat = "bestiary_completed", target = 50, title = "Lorekeeper",
			reward = {items = orbs(0, 2), exclusives = {{key = "addons_mage", name = "outfit addons Mage"}}}},
		{id = "tasks_50", cat = "monsters", name = "Exterminator", desc = "Complete 50 kill tasks.", points = 25,
			stat = "bestiary_tasks", target = 50, title = "Exterminator"},

		-- ------------------------------------------------------------------ World Bosses
		{id = "wb_kaelgor", cat = "bosses", name = "Warlord Unmade", desc = "Help slay Kaelgor the Infernal Warlord.", points = 25,
			stat = "wb_kaelgor"},
		{id = "wb_skaldra", cat = "bosses", name = "The Rime Melts", desc = "Help slay Skaldra the Rime Queen.", points = 25,
			stat = "wb_skaldra"},
		{id = "wb_rotmother", cat = "bosses", name = "Cleansing Fire", desc = "Help slay The Rotmother.", points = 25,
			stat = "wb_rotmother"},
		{id = "wb_nyxareth", cat = "bosses", name = "Light in the Void", desc = "Help slay Nyxareth the Void Archon.", points = 25,
			stat = "wb_nyxareth"},
		{id = "wb_vharok", cat = "bosses", name = "Bloodletter", desc = "Help slay Vharok the Blood Colossus.", points = 25,
			stat = "wb_vharok"},
		{id = "wb_all", cat = "bosses", name = "Colossus Hunter", desc = "Help slay each of the five world bosses.", points = 50,
			all = {"wb_kaelgor", "wb_skaldra", "wb_rotmother", "wb_nyxareth", "wb_vharok"}, title = "Colossus Hunter",
			reward = {mount = {name = "Corpsefire Skull", id = 107}, portal = {key = "abyssal", name = "Abyssal Maw"}}},
		{id = "wb_top_1", cat = "bosses", name = "Lion's Share", desc = "Deal the most damage of everyone to a world boss.",
			points = 25, stat = "wb_top", title = "Worldbreaker"},
		{id = "wb_top_5", cat = "bosses", name = "Unrivalled", desc = "Deal the most damage to a world boss 5 times.", points = 50,
			stat = "wb_top", target = 5, reward = {exclusives = {{key = "outfit_wingbound", name = "outfit Wingbound"}}}},
		{id = "wb_10", cat = "bosses", name = "Raid Regular", desc = "Be rewarded at 10 world boss kills.", points = 25,
			stat = "wb_kills", target = 10, reward = {items = orbs(5, 2)}},
		{id = "wb_50", cat = "bosses", name = "Eternal Raider", desc = "Be rewarded at 50 world boss kills.", points = 50,
			stat = "wb_kills", target = 50},
		{id = "wb_heal_top_1", cat = "bosses", name = "Lifeline", desc = "Heal the most of everyone at a world boss kill.",
			points = 25, stat = "wb_heal_top", title = "Lifeline"},
		{id = "wb_tank_top_1", cat = "bosses", name = "Immovable", desc = "Take the most boss damage and live, at a world boss kill.",
			points = 25, stat = "wb_tank_top", title = "Immovable"},
		{id = "wb_role_5", cat = "bosses", name = "Pillar of the Raid", desc = "Place in the top 3 for healing or tanking at 5 world boss kills.",
			points = 50, stat = "wb_role_podium", target = 5, reward = {items = orbs(5, 2)}},

		-- ------------------------------------------------------------------ Rifts
		{id = "rift_t1", cat = "rifts", name = "Through the Breach", desc = "Seal a rift.", points = 10, stat = "rift_tier", target = 1},
		{id = "rift_t5", cat = "rifts", name = "Deeper Wounds", desc = "Seal a tier 5 rift.", points = 15, stat = "rift_tier", target = 5},
		{id = "rift_t10", cat = "rifts", name = "Edge of Ruin", desc = "Seal a tier 10 rift.", points = 25, stat = "rift_tier",
			target = 10, reward = {items = orbs(0, 2)}},
		{id = "rift_t15", cat = "rifts", name = "Rift Sealer", desc = "Seal a tier 15 rift.", points = 50, stat = "rift_tier",
			target = 15, title = "Rift Sealer", reward = {outfit = {name = "Rift Warrior", female = 845, male = 846, addons = 3}}},
		{id = "rift_25", cat = "rifts", name = "Keybearer", desc = "Seal 25 rifts.", points = 15, stat = "rift_runs", target = 25,
			reward = {portal = {key = "riftwalker", name = "Riftwalker's Gate"}}},
		{id = "rift_100", cat = "rifts", name = "Lord of Thresholds", desc = "Seal 100 rifts.", points = 50, stat = "rift_runs",
			target = 100, title = "Threshold Lord", reward = {mount = {name = "Rift Runner", id = 87}}},
		{id = "rift_flawless", cat = "rifts", name = "Flawless Seal", desc = "Seal a rift with everyone who entered still standing.",
			points = 15, stat = "rift_flawless"},
		{id = "rift_flawless_10", cat = "rifts", name = "Untouchable", desc = "Seal 10 rifts without losing anyone.", points = 25,
			stat = "rift_flawless", target = 10, reward = {exclusives = {{key = "mount_duskcrest", name = "mount Duskcrest Drake"}}}},
		{id = "rift_three", cat = "rifts", name = "Triple Threat", desc = "Seal a rift with three modifiers.", points = 15,
			stat = "rift_three"},
		{id = "rift_reflection", cat = "rifts", name = "Mirror, Mirror", desc = "Seal a rift with the Reflection modifier.",
			points = 10, stat = "rift_mod_reflection"},
		{id = "rift_withering", cat = "rifts", name = "Withered, Not Broken", desc = "Seal a rift with the Withering modifier.",
			points = 10, stat = "rift_mod_withering"},
		{id = "rift_brutality", cat = "rifts", name = "Brute Force", desc = "Seal a rift with the Brutality modifier.", points = 10,
			stat = "rift_mod_brutality"},
		{id = "rift_swarm", cat = "rifts", name = "Swarm Breaker", desc = "Seal a rift with the Swarm modifier.", points = 10,
			stat = "rift_mod_swarm"},
		-- omen guardians (rift.lua, the Omen Key arenas): omen_kills, omen_<kind>
		{id = "omen_1", cat = "rifts", name = "Omen Breaker", desc = "Slay an omen guardian.", points = 25, stat = "omen_kills"},
		{id = "omen_bloodmoon", cat = "rifts", name = "Red Night Ends", desc = "Slay Sangrith the Bloodmoon Herald.",
			points = 15, stat = "omen_bloodmoon"},
		{id = "omen_hollow", cat = "rifts", name = "Uncrowned", desc = "Slay Morvane the Hollow Crown.", points = 15,
			stat = "omen_hollow"},
		{id = "omen_storm", cat = "rifts", name = "Eye of the Storm", desc = "Slay Thalcyra the Stormbound Seer.", points = 15,
			stat = "omen_storm"},
		{id = "omen_10", cat = "rifts", name = "Herald of Omens", desc = "Slay 10 omen guardians.", points = 50,
			stat = "omen_kills", target = 10, title = "Omenbreaker", reward = {items = orbs(10, 5), portal = {key = "hellmouth", name = "Hellmouth Gate"}}},
		-- Ascended Omens and the Cinderheart (uber.lua): ascended_kills, ascended_<kind>, cinder_kills, cinder_solo,
		-- cinder_flawless. frame = the name plate frame of the title while it is the active one (nameplate_core.lua FRAMES)
		{id = "ascended_1", cat = "rifts", name = "Beyond the Omen", desc = "Slay an Ascended Omen.", points = 25,
			stat = "ascended_kills"},
		{id = "ascended_bloodmoon", cat = "rifts", name = "The Moon Sets Red", desc = "Slay Ascended Sangrith.", points = 25,
			stat = "ascended_bloodmoon"},
		{id = "ascended_hollow", cat = "rifts", name = "Nothing Left to Crown", desc = "Slay Ascended Morvane.", points = 25,
			stat = "ascended_hollow"},
		{id = "ascended_storm", cat = "rifts", name = "The Sky Falls Silent", desc = "Slay Ascended Thalcyra.", points = 25,
			stat = "ascended_storm"},
		{id = "ascended_all", cat = "rifts", name = "Three Relics", desc = "Slay all three Ascended Omens.", points = 50,
			all = {"ascended_bloodmoon", "ascended_hollow", "ascended_storm"}, title = "the Ascendant",
			reward = {items = orbs(20, 10, 1)}},
		{id = "cinder_1", cat = "rifts", name = "Cinderbreaker", desc = "Slay Ysgrath the Cinderheart.", points = 50,
			stat = "cinder_kills", title = "Cinderbreaker", frame = "ember", reward = {items = orbs(30, 15, 2)}},
		{id = "cinder_solo", cat = "rifts", name = "Alone Against the Ember", desc = "Slay the Cinderheart alone.", points = 50,
			stat = "cinder_solo", hidden = true, title = "the Last Light", frame = "ember"},
		{id = "cinder_flawless", cat = "rifts", name = "Not One Spark Lost", desc = "Slay the Cinderheart without losing a life.",
			points = 50, stat = "cinder_flawless", hidden = true},
		{id = "cinder_10", cat = "rifts", name = "Keeper of the Ashes", desc = "Slay the Cinderheart 10 times.", points = 50,
			stat = "cinder_kills", target = 10, title = "Ashkeeper", frame = "ember"},

		-- ------------------------------------------------------------------ Raids: the Ashen Sepulchre (raid.lua)
		-- raid_sovereign unlocks the kill effect Sovereign's Pyre (cosmetics_config.lua id 109)
		{id = "raid_first", cat = "raids", name = "Into the Sepulchre", desc = "Slay a boss of the Ashen Sepulchre.", points = 10,
			stat = "raid_kills"},
		{id = "raid_ulthar", cat = "raids", name = "The First Gate Falls", desc = "Slay Gravewarden Ulthar.", points = 10,
			stat = "raid_ulthar"},
		{id = "raid_morwen", cat = "raids", name = "Lullaby's End", desc = "Slay Morwen the Ash-Sister.", points = 15,
			stat = "raid_morwen"},
		{id = "raid_colossus", cat = "raids", name = "Bone to Dust", desc = "Slay the Marrow Colossus.", points = 15,
			stat = "raid_colossus"},
		{id = "raid_hexmaw", cat = "raids", name = "No Curse Spoken", desc = "Slay Vhoss the Hexmaw.", points = 25,
			stat = "raid_hexmaw"},
		{id = "raid_sovereign", cat = "raids", name = "The Last Door", desc = "Slay Varkhul the Ashen Sovereign.", points = 50,
			stat = "raid_sovereign", title = "Sovereign's Bane", reward = {items = orbs(20, 10, 1)}},
		{id = "raid_flawless", cat = "raids", name = "Nobody Kneels", desc = "Slay Varkhul with nobody falling in the fight.",
			points = 50, stat = "raid_flawless", hidden = true, title = "the Unbowed"},
		{id = "raid_speed", cat = "raids", name = "Through Every Door", desc = "Clear the Sepulchre in one sitting in under 30 minutes.",
			points = 50, stat = "raid_speed", hidden = true},
		{id = "raid_clears_10", cat = "raids", name = "Keeper of the Sepulchre", desc = "Slay Varkhul 10 times.", points = 50,
			stat = "raid_clears", target = 10, title = "Sepulchre Keeper"},

		-- ------------------------------------------------------------------ Bounties
		{id = "bounty_1", cat = "bounties", name = "Contract Signed", desc = "Complete a bounty contract.", points = 5,
			stat = "bounty_done"},
		{id = "bounty_25", cat = "bounties", name = "Hired Blade", desc = "Complete 25 bounty contracts.", points = 10,
			stat = "bounty_done", target = 25},
		{id = "bounty_100", cat = "bounties", name = "Professional", desc = "Complete 100 bounty contracts.", points = 25,
			stat = "bounty_done", target = 100, title = "Headhunter"},
		{id = "bounty_500", cat = "bounties", name = "Death Warrant", desc = "Complete 500 bounty contracts.", points = 50,
			stat = "bounty_done", target = 500, reward = {mount = {name = "Nightstinger", id = 85}}},
		{id = "bounty_week", cat = "bounties", name = "A Full Week", desc = "Earn the weekly bounty chest.", points = 15,
			stat = "bounty_weeks", reward = {items = orbs(3)}},
		{id = "bounty_week_10", cat = "bounties", name = "Never Off Duty", desc = "Earn the weekly bounty chest 10 times.",
			points = 25, stat = "bounty_weeks", target = 10},

		-- ------------------------------------------------------------------ Items & Crafting
		{id = "unique_1", cat = "items", name = "One of a Kind", desc = "Find a unique item.", points = 10, stat = "unique_found"},
		{id = "unique_10", cat = "items", name = "Collector of Relics", desc = "Find 10 unique items.", points = 25,
			stat = "unique_found", target = 10},
		{id = "unique_50", cat = "items", name = "Reliquary", desc = "Find 50 unique items.", points = 50, stat = "unique_found",
			target = 50, title = "Relic Keeper"},
		{id = "rarity_5", cat = "items", name = "Legendary Find", desc = "Find a Legendary item.", points = 10, stat = "rarity_max",
			target = 5},
		{id = "rarity_7", cat = "items", name = "Mythic Find", desc = "Find a Mythic item.", points = 15, stat = "rarity_max", target = 7},
		{id = "rarity_9", cat = "items", name = "Eternal Find", desc = "Find an Eternal item.", points = 25, stat = "rarity_max",
			target = 9},
		{id = "rarity_12", cat = "items", name = "Celestial Find", desc = "Find a Celestial item.", points = 25, stat = "rarity_max",
			target = 12},
		{id = "rarity_15", cat = "items", name = "Transcendent", desc = "Find a Transcendent item.", points = 50, stat = "rarity_max",
			target = 15, title = "the Transcendent"},
		{id = "orbs_1", cat = "items", name = "Tinkerer", desc = "Use an orb at the Crafting Bench.", points = 5, stat = "orbs_used"},
		{id = "orbs_100", cat = "items", name = "Orbweaver", desc = "Use 100 orbs at the Crafting Bench.", points = 15,
			stat = "orbs_used", target = 100, reward = {items = orbs(0, 0, 2)}},
		{id = "orbs_1000", cat = "items", name = "Master Artificer", desc = "Use 1,000 orbs at the Crafting Bench.", points = 50,
			stat = "orbs_used", target = 1000, title = "Artificer",
			reward = {exclusives = {{key = "outfit_jadeforged", name = "outfit Jadeforged"}}}},
		{id = "exalted_25", cat = "items", name = "Grafting Hands", desc = "Use 25 Orbs of Grafting.", points = 15, stat = "orb_exalted",
			target = 25},
		-- orbs v2 (data/lib/chaos_orbs.lua) and the legendary powers (data/lib/chaos_powers.lua)
		{id = "orb_binding", cat = "items", name = "Bound by Oath", desc = "Bind a modifier with an Orb of Binding.", points = 10,
			stat = "orb_binding"},
		{id = "ruin_improved", cat = "items", name = "Fortune's Favourite", desc = "Improve an item with an Orb of Ruin.",
			points = 25, stat = "ruin_improved"},
		{id = "ruin_ruined", cat = "items", name = "Beyond Saving", desc = "Ruin an item with an Orb of Ruin.", points = 10,
			stat = "ruin_ruined", hidden = true},
		{id = "quality_20", cat = "items", name = "Honed to an Edge", desc = "Bring an item to 20% quality with Whetstones.",
			points = 25, stat = "quality_max", target = 20},
		{id = "power_found", cat = "items", name = "Legend Reborn", desc = "Own an item with a legendary power.", points = 25,
			stat = "power_found", title = "Powerbearer"},
		{id = "mods_9", cat = "items", name = "Perfection", desc = "Own an item with 6 modifiers (three prefixes, three suffixes).",
			points = 50, stat = "mods_max", target = 6},

		-- ------------------------------------------------------------------ PvP
		{id = "arena1_win", cat = "pvp", name = "Sand and Blood", desc = "Win a ranked 1v1 arena match.", points = 5,
			stat = "arena1v1_wins"},
		{id = "arena1_win50", cat = "pvp", name = "Sandstorm", desc = "Win 50 ranked 1v1 matches.", points = 25,
			stat = "arena1v1_wins", target = 50},
		{id = "arena1_1200", cat = "pvp", name = "Duelist's Edge", desc = "Reach a 1v1 rating of 1200.", points = 15,
			stat = "arena1v1_rating", target = 1200},
		{id = "arena1_1500", cat = "pvp", name = "Master Duelist", desc = "Reach a 1v1 rating of 1500.", points = 25,
			stat = "arena1v1_rating", target = 1500, title = "Bladedancer"},
		{id = "arena1_1800", cat = "pvp", name = "Arena Legend", desc = "Reach a 1v1 rating of 1800.", points = 50,
			stat = "arena1v1_rating", target = 1800, title = "Arena Legend",
			reward = {outfit = {name = "Arena Champion", female = 885, male = 884, addons = 3}}},
		{id = "arena2_win", cat = "pvp", name = "Back to Back", desc = "Win a ranked 2v2 arena match.", points = 5,
			stat = "arena2v2_wins"},
		{id = "arena2_win50", cat = "pvp", name = "Shield Brothers", desc = "Win 50 ranked 2v2 matches.", points = 25,
			stat = "arena2v2_wins", target = 50},
		{id = "arena2_1200", cat = "pvp", name = "Tag Team", desc = "Reach a 2v2 rating of 1200.", points = 15,
			stat = "arena2v2_rating", target = 1200},
		{id = "arena2_1500", cat = "pvp", name = "Twin Blades", desc = "Reach a 2v2 rating of 1500.", points = 25,
			stat = "arena2v2_rating", target = 1500, title = "Twinblade"},
		{id = "arena2_1800", cat = "pvp", name = "Unbreakable Pair", desc = "Reach a 2v2 rating of 1800.", points = 50,
			stat = "arena2v2_rating", target = 1800},
		{id = "bg_win", cat = "pvp", name = "Kindle the Wells", desc = "Win an Ember Wells battleground.", points = 5,
			stat = "bg_wins"},
		{id = "bg_win50", cat = "pvp", name = "Keeper of the Wells", desc = "Win 50 Ember Wells battlegrounds.", points = 25,
			stat = "bg_wins", target = 50, title = "Keeper of the Wells"},
		{id = "bg_play100", cat = "pvp", name = "Ashes and Honor", desc = "Fight 100 Ember Wells battlegrounds.", points = 15,
			stat = "bg_matches", target = 100},
		{id = "pvp_season_blazing", cat = "pvp", name = "Blazing Season", desc = "Finish a PvP season Blazing or higher.",
			points = 25, stat = "pvp_season_tier", target = 4},
		{id = "pvp_season_sovereign", cat = "pvp", name = "Cinder Sovereign", desc = "Finish a PvP season as a Cinder Sovereign.",
			points = 50, stat = "pvp_season_tier", target = 6, hidden = true},
		-- the Scorched Marches (pvpzone.lua)
		{id = "marches_bank", cat = "pvp", name = "Ash in Hand", desc = "Bank embers at a safe exit of the Scorched Marches.",
			points = 5, stat = "pvpzone_banked"},
		{id = "marches_bank10k", cat = "pvp", name = "Ember Hoarder", desc = "Bank 10,000 embers from the Scorched Marches.",
			points = 15, stat = "pvpzone_banked", target = 10000},
		{id = "marches_haul", cat = "pvp", name = "Heavy Pockets", desc = "Bank 1,000 embers at one exit of the Scorched Marches.",
			points = 10, stat = "pvpzone_haul", target = 1000},
		{id = "marches_kill", cat = "pvp", name = "Blood on the Ash", desc = "Defeat a player in the Scorched Marches (a defeat that counts).",
			points = 5, stat = "pvpzone_kills"},
		{id = "marches_kill100", cat = "pvp", name = "Scourge of the Marches", desc = "Defeat 100 players in the Scorched Marches.",
			points = 25, stat = "pvpzone_kills", target = 100, title = "Scourge of the Marches"},
		{id = "marches_shrine", cat = "pvp", name = "Shrinebearer", desc = "Stand in the circle when your faction takes the Cinder Shrine.",
			points = 10, stat = "pvpzone_captures"},
		{id = "siege_play", cat = "pvp", name = "Under the Banner", desc = "Score in a guild siege.", points = 10,
			stat = "siege_played"},
		{id = "siege_win", cat = "pvp", name = "Siege Champion", desc = "Win a guild siege with your guild.", points = 25,
			stat = "siege_wins", title = "Obelisk Breaker", reward = {portal = {key = "warbanner", name = "Warbanner Gate"}}},
		{id = "siege_win5", cat = "pvp", name = "Warlord of the Obelisk", desc = "Win 5 guild sieges.", points = 50,
			stat = "siege_wins", target = 5, title = "Warlord", reward = {mount = {name = "Siegebreaker", id = 56}}},

		-- ------------------------------------------------------------------ Exploration & Social
		{id = "tutorial", cat = "explore", name = "First Steps", desc = "Finish the tutorial island.", points = 5, stat = "tutorial"},
		{id = "guild", cat = "explore", name = "Sworn", desc = "Join a guild.", points = 5, stat = "guild"},
		{id = "party_100", cat = "explore", name = "Strength in Numbers", desc = "Kill 100 monsters in a party.", points = 10,
			stat = "party_kills", target = 100},
		{id = "party_1000", cat = "explore", name = "Warband", desc = "Kill 1,000 monsters in a party.", points = 25,
			stat = "party_kills", target = 1000},
		{id = "points_250", cat = "explore", name = "Chronicler", desc = "Earn 250 achievement points with this character.",
			points = 10, stat = "points", target = 250, title = "Chronicler"},
		{id = "points_750", cat = "explore", name = "Living Legend", desc = "Earn 750 achievement points with this character.",
			points = 25, stat = "points", target = 750, title = "Living Legend",
			reward = {outfit = {name = "Demon Hunter", female = 288, male = 289, addons = 3}}},
		-- factions (factions.lua, factions_config.lua): Exalted with a faction, and with all four
		{id = "faction_vigil", cat = "explore", name = "Keeper of the Pyres", desc = "Become Exalted with the Ashen Vigil.",
			points = 25, stat = "faction_exalted_vigil", reward = {items = orbs(0, 3, 1)}},
		{id = "faction_compact", cat = "explore", name = "Hammer of the Compact",
			desc = "Become Exalted with the Cinderforge Compact.", points = 25, stat = "faction_exalted_compact",
			reward = {items = orbs(0, 3, 1)}},
		{id = "faction_choir", cat = "explore", name = "Chorister of the Rift", desc = "Become Exalted with the Veiled Choir.",
			points = 25, stat = "faction_exalted_choir", reward = {items = orbs(0, 3, 1)}},
		{id = "faction_circle", cat = "explore", name = "Bound by Thorn", desc = "Become Exalted with the Thornbound Circle.",
			points = 25, stat = "faction_exalted_circle", reward = {items = orbs(0, 3, 1)}},
		{id = "faction_all", cat = "explore", name = "Oath of Four Banners", desc = "Become Exalted with all four factions.",
			points = 50, stat = "faction_exalted", target = 4, title = "Oathbound", reward = {items = orbs(0, 5, 2)}},
		-- professions (professions.lua, professions_config.lua): a profession at level 50 and 100, all four together
		{id = "prof_delving_50", cat = "explore", name = "Deep Delver", desc = "Reach Delving level 50.", points = 10,
			stat = "prof_delving", target = 50},
		{id = "prof_delving_100", cat = "explore", name = "Heart of the Mountain", desc = "Reach Delving level 100.",
			points = 25, stat = "prof_delving", target = 100, title = "Master Delver"},
		{id = "prof_wortcunning_50", cat = "explore", name = "Bitter Harvest", desc = "Reach Wortcunning level 50.",
			points = 10, stat = "prof_wortcunning", target = 50},
		{id = "prof_wortcunning_100", cat = "explore", name = "Keeper of the Wort", desc = "Reach Wortcunning level 100.",
			points = 25, stat = "prof_wortcunning", target = 100, title = "Master Herbwife"},
		{id = "prof_flaying_50", cat = "explore", name = "Hidecutter", desc = "Reach Flaying level 50.", points = 10,
			stat = "prof_flaying", target = 50},
		{id = "prof_flaying_100", cat = "explore", name = "The Skinner", desc = "Reach Flaying level 100.", points = 25,
			stat = "prof_flaying", target = 100, title = "Master Flayer"},
		{id = "prof_angling_50", cat = "explore", name = "Patient Line", desc = "Reach Angling level 50.", points = 10,
			stat = "prof_angling", target = 50},
		{id = "prof_angling_100", cat = "explore", name = "Lord of the Dark Waters", desc = "Reach Angling level 100.",
			points = 25, stat = "prof_angling", target = 100, title = "Master Angler"},
		{id = "prof_total_200", cat = "explore", name = "Jack of the Wilds", desc = "Reach 200 profession levels in total.",
			points = 25, stat = "prof_total", target = 200},
		{id = "prof_total_400", cat = "explore", name = "Master of the Wilds", desc = "Reach level 100 in all four professions.",
			points = 50, stat = "prof_total", target = 400, title = "Master of the Wilds",
			reward = {exclusives = {{key = "shader_verdant", name = "outfit shader Verdant Sparks"}}}},

		-- mentors (mentor.lua): mentor_graduates = apprentices this character mentored to graduation (with enough time
		-- hunting together); mentor_fledged = 1 once this character graduated from a mentor
		{id = "mentor_1", cat = "explore", name = "Guiding Hand", desc = "Mentor an apprentice to graduation.", points = 10,
			stat = "mentor_graduates", title = "Mentor"},
		{id = "mentor_5", cat = "explore", name = "Lamplighter", desc = "Mentor 5 apprentices to graduation.", points = 25,
			stat = "mentor_graduates", target = 5, title = "Seasoned Mentor"},
		{id = "mentor_15", cat = "explore", name = "Keeper of the Flame", desc = "Mentor 15 apprentices to graduation.",
			points = 50, stat = "mentor_graduates", target = 15, title = "Master Mentor",
			reward = {exclusives = {{key = "frame_laurel", name = "name plate frame Laurel"}}}},
		{id = "mentor_fledged", cat = "explore", name = "Fledged", desc = "Graduate from your mentor.", points = 10,
			stat = "mentor_fledged", title = "Fledgling"},

		-- ------------------------------------------------------------------ Season modes (season_modes.lua)
		-- season_hc_level / season_ssf_level: the level of a character while it plays Hardcore / Self-Found (alive);
		-- season_hc_survived / season_ssf_finished: 1 when its season ends and it still plays the mode
		{id = "season_hc_50", cat = "combat", name = "One Life", desc = "Reach level 50 in a Hardcore season.", points = 10,
			stat = "season_hc_level", target = 50},
		{id = "season_hc_100", cat = "combat", name = "Walking the Knife's Edge", desc = "Reach level 100 in a Hardcore season.",
			points = 25, stat = "season_hc_level", target = 100, title = "the Unfallen"},
		{id = "season_hc_250", cat = "combat", name = "Death Waits Elsewhere", desc = "Reach level 250 in a Hardcore season.",
			points = 50, stat = "season_hc_level", target = 250, title = "Deathless"},
		{id = "season_hc_survived", cat = "combat", name = "Survivor of the Season",
			desc = "Be alive in Hardcore when your season ends.", points = 50, stat = "season_hc_survived",
			title = "Season Survivor"},
		{id = "season_ssf_100", cat = "combat", name = "By My Own Hand", desc = "Reach level 100 in a Self-Found season.",
			points = 25, stat = "season_ssf_level", target = 100, title = "the Self-Made"},
		{id = "season_ssf_finished", cat = "combat", name = "Needed No One",
			desc = "Still be Self-Found when your season ends.", points = 25, stat = "season_ssf_finished"},

		-- >>> Depot tabs (depot.lua; the ids are depot_config.lua achievementTabs): each one, on any character, opens one
		-- more depot tab for the whole account. The store sells tabs too; these three are only earned.
		{id = "depot_tab_relics", cat = "items", name = "Cabinet of Curiosities",
			desc = "Find 25 unique items. Opens a depot tab for your account.", points = 25, stat = "unique_found", target = 25},
		{id = "depot_tab_trophies", cat = "monsters", name = "Hall of Trophies",
			desc = "Complete 100 bestiary entries. Opens a depot tab for your account.", points = 25, stat = "bestiary_completed",
			target = 100},
		{id = "depot_tab_vault", cat = "rifts", name = "Keeper of the Vault",
			desc = "Seal 50 rifts. Opens a depot tab for your account.", points = 25, stat = "rift_runs", target = 50},
		-- <<< Depot tabs

		-- ------------------------------------------------------------------ Secrets
		{id = "rat_500", cat = "secrets", name = "Overqualified", desc = "Kill a rat at level 500 or higher.", points = 10,
			stat = "rat_500", hidden = true},
		{id = "deaths_50", cat = "secrets", name = "Death Is a Teacher", desc = "Die 50 times.", points = 10, stat = "deaths",
			target = 50, hidden = true, title = "the Undying", reward = {portal = {key = "gravecall", name = "Gravecall Gate"}}},
		{id = "witching_hour", cat = "secrets", name = "Witching Hour", desc = "Kill a legendary monster between midnight and 1 am.",
			points = 10, stat = "witching_legendary", hidden = true,
			reward = {exclusives = {{key = "aura_murmuration", name = "aura Ashen Murmuration"}}}},
		{id = "ambushed_legend", cat = "secrets", name = "Out of the Frying Pan",
			desc = "Kill a legendary monster that ambushed you.", points = 15, stat = "ambush_legendary", hidden = true}
	}
}
