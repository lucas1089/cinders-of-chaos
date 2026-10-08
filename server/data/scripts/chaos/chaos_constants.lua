-- chaos_constants.lua
-- Single source of truth for every opcode, storage key, DB table name and tunable value
-- used by the Chaos client-module scripts in this folder.
--
-- Every other file in this folder starts with:
--     if not Chaos then dofile("data/scripts/chaos/chaos_constants.lua") end
-- so load order inside data/scripts does not matter. This file is idempotent.
--
-- Lua dialect: TFS 1.4.2 / LuaJIT (Lua 5.1 semantics). Do not use 5.3-only syntax here.

if Chaos then
	return
end

Chaos = {}

-- ---------------------------------------------------------------------------
-- Extended opcodes
-- ---------------------------------------------------------------------------
-- Opcodes already used by the base server reference server (checked by grep):
--   1 (language), 67 (item fusion), 73 (highscores), 89 (ancestral points push),
--   91 (crafting), 92 (tasks), 99 (reputation), 106 (char stats), 107 (inspect),
--   136 (party icons), 181 (character upgrades), 201 (game store), 202 (waystone/tier maps)
-- None of the values below collide with those.
ChaosOpcodes = {
	bank = 60,
	monsterbar = 125,
	passivetree = 65,
	notifications = 79,
	dungeons = 109,
	stash = 110, -- chosen here: the client stash.lua has no fixed number (see README)
	notificationsAction = 151, -- client -> server only (party invite / catacomb start)
	notificationsQueue = 152, -- client -> server only (leave queue)
	daily = 207,
	infinitytower = 214,
	autoloot = 216,
	shop = 218, -- Chaos store (client game_shop); the base server's own store uses 201
	spellbook = 219 -- spell list window (client game_spellbook, !spells)
}

-- ---------------------------------------------------------------------------
-- Player storage keys (7100000 - 7100999 is reserved for Chaos; unused by the reference server)
-- ---------------------------------------------------------------------------
Chaos.storage = {
	-- autoloot: SAME base as the reference server's own scripts/creaturescripts/autoloot.lua
	-- (it stores item id in base+1 .. base+limit). Keeping it identical means the existing
	-- onDropLoot callback keeps working and uses the list edited from the client window.
	autolootBase = 80000,

	dailyStreakDay = 7100001, -- 1..7, the day slot that is claimable / was last claimed
	dailyLastClaim = 7100002, -- YYYYMMDD of the last claim (int32 safe)

	stashRemote = 7100010, -- >0 : player may keep the stash window open while walking
	passiveExtraPoints = 7100020, -- bonus passive points granted by quests/GM
	passiveStatsFixed = 7100021, -- 1 once the stats older passive tree versions wrote into the character are clamped
	dungeonQueueLock = 7100030, -- (os.time of the last queue join; anti spam)

	-- store: one-time cosmetics owned (base + id of the wings / aura / shader)
	shopWingsBase = 7100600,
	shopAuraBase = 7100650,
	shopShaderBase = 7100700,

	-- store services (shop_services.lua, autosell.lua): 7100100 - 7100159
	shopLootPouch = 7100100, -- 1 = Bottomless Loot Pouch unlocked (per character)
	shopAutoSeller = 7100101, -- 1 = Auto Seller unlocked (per character)
	autosellPaused = 7100102, -- 1 = auto seller switched off with !autosell off
	autosellRarity = 7100103, -- 1 = opt-in: the auto seller may sell items with a rarity / modifiers
	nameChangeTokens = 7100104, -- unused name changes bought in the store
	vocationChangeTokens = 7100105, -- unused vocation changes bought in the store
	autosellBase = 7100110 -- + 1 .. + Chaos.shopServices.autosellSlots: item ids on the auto-sell list
}

-- ---------------------------------------------------------------------------
-- Database tables (created by server/sql/chaos.sql)
-- ---------------------------------------------------------------------------
Chaos.tables = {
	bank = "chaos_bank",
	stash = "chaos_stash",
	stashBlock = "chaos_stash_block",
	passiveTree = "chaos_passive_tree",
	dungeonProgress = "chaos_dungeon_progress",
	dungeonRuns = "chaos_dungeon_runs",
	dungeonRunPlayers = "chaos_dungeon_run_players",
	towerPlayers = "chaos_tower_players",
	shopCoins = "chaos_shop_coins",
	shopHistory = "chaos_shop_history"
}

-- ---------------------------------------------------------------------------
-- Module settings
-- ---------------------------------------------------------------------------
Chaos.bank = {
	-- Gold uses the native player bank balance (players.balance), the same as the NPC banks.
	-- "star" is a second currency: carried as an item, banked in chaos_bank.stars.
	-- ASSUMPTION: 35572 is the SERVER item id of the star item and equals the client id the
	-- client hard-codes (setItemId(35572)). Set to 0 to disable the star tab server-side.
	starItemId = 35572,
	starWithdrawMax = 1000, -- the client UI caps a withdraw at 1000 per action; enforced here too
	maxAmount = 2000000000, -- sanity cap on a single operation
	transferMinLevel = 1
}

Chaos.autoloot = {
	freeLimit = 10, -- mirrors the reference autoloot.lua
	premiumLimit = 20
}

Chaos.daily = {
	-- Reward for streak day 1..7 (SERVER item ids that exist in our items.otb; client ids are looked up at send time).
	-- The window shows one item per day; the bonus below is added to day 7 on top of it.
	rewards = {
		{itemId = 2152, count = 20},  -- platinum coin
		{itemId = 29856, count = 1},  -- Chaos Orb
		{itemId = 2152, count = 50},  -- platinum coin
		{itemId = 29857, count = 1},  -- Divine Orb
		{itemId = 2160, count = 1},   -- crystal coin
		{itemId = 29856, count = 3},  -- Chaos Orb
		{itemId = 29857, count = 3}   -- Divine Orb
	},
	-- given together with day 7 (all or nothing with it): a full week of claims
	weekBonus = {
		{itemId = 2160, count = 2}    -- crystal coin
	},
	openOnLogin = true, -- send OpenDailyWindow at login when today's reward is unclaimed
	openDelayMs = 3000
}

Chaos.passive = {
	rootNode = 1,
	startLevel = 8, -- level 8 has no points; points are counted from here
	levelsPerPoint = 4, -- 1 point every 4 levels: ~248 at level 1000 for 618 nodes, so a build has to choose
	-- (planned later: a Paragon track that takes points once the tree is full)
	maxPresets = 6,
	resetCostPerLevel = 250 -- gold per level; the client text promises "level x 250"
}

Chaos.stash = {
	-- true: tell the client the stash is remote (window stays open while walking, no depot needed).
	remoteForEveryone = true,
	chunkSize = 40, -- items per addItems packet (keeps packets well under the 24 KB limit)
	maxDistance = 1, -- max Chebyshev distance to a floor item that is stashed from the map
	maxStackPerEntry = 2000000000
}

Chaos.dungeons = {
	-- how the base server DUNGEON_SYSTEM (lib/core/dungeon.lua) is reused:
	--   * list / levels / party size / DungeonPos / FromPos / ToPos / DungeonTime / cooldown storage
	-- Everything the base server table does not have is declared here, per base server dungeon id.
	exitDelayMs = 10000, -- delay between finishing and teleporting the group out
	cooldownOnSuccess = true, -- apply DUNGEON_SYSTEM.CooldownTime also after a win (the base server modal only did on failure)
	queueTickMs = 3000,
	maxDifficulty = 6, -- client has 6 difficulty buttons
	-- percentage of area monsters that must die before the "boss can be killed" notice
	progressNeeded = 100,
	extra = {
		[1] = {
			title = "Bones Dungeon",
			bossName = "prince skeletal",
			loot = {{id = 2160, count = 3}},
			challenges = {
				{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 15 minutes.", maxMs = 15 * 60 * 1000},
				{key = "flawless", title = "Flawless", points = 10, desc = "Finish without anyone dying."}
			}
		},
		[2] = {
			title = "Master of the Elements",
			bossName = "master of the elements",
			loot = {{id = 2160, count = 5}},
			challenges = {
				{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 20 minutes.", maxMs = 20 * 60 * 1000},
				{key = "flawless", title = "Flawless", points = 10, desc = "Finish without anyone dying."}
			}
		},
		[3] = {
			title = "Forbidden Chevalier",
			bossName = "forbidden chevalier",
			loot = {{id = 2160, count = 8}},
			challenges = {
				{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 20 minutes.", maxMs = 20 * 60 * 1000},
				{key = "flawless", title = "Flawless", points = 10, desc = "Finish without anyone dying."}
			}
		},
		[4] = {
			title = "Rootkraken",
			bossName = "the rootkraken",
			loot = {{id = 2160, count = 10}},
			challenges = {
				{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 10 minutes.", maxMs = 10 * 60 * 1000},
				{key = "flawless", title = "Flawless", points = 10, desc = "Finish without dying."}
			}
		}
	}
}

Chaos.tower = {
	-- Season = fixed-length window counted from seasonEpoch (unix time).
	seasonEpoch = 1735689600, -- 2025-01-01 00:00:00 UTC
	seasonLengthDays = 30,
	tryCooldownSeconds = 0, -- "Next Try Available"; 0 = always ready
	pointsPerFloor = 1000,
	rankingSize = 10,
	-- Milestones: SERVER item ids that exist in our items.otb (the client window reads the real ones from the
	-- server; its built-in fallback list is only shown before the first update).
	milestones = {
		{points = 60000, items = {{id = 2148, count = 300, name = "Gold Coin"}}},
		{points = 120000, items = {{id = 29856, count = 3, name = "Chaos Orb"}}},
		{points = 180000, items = {{id = 29857, count = 3, name = "Divine Orb"}}},
		{points = 240000, items = {{id = 29857, count = 10, name = "Divine Orb"}}},
		{points = 300000, items = {{id = 8209, count = 1, name = "Soulreaper"}}}
	}
}

-- Event schedule (events_schedule.lua). Recurring events; every event is active for whole server days.
--   weekdays = {1..7} (1 = Sunday, os.date("%w") + 1), or monthdays = {1, 2, ...}
--   bonus: xp (multiplier), loot (multiplier on the Chaos loot layer + one extra roll on normal
--          monsters), tierChance (multiplier on magic/rare/legendary spawn chance), ambush (multiplier
--          on the ambush chance after a kill), towerPoints (multiplier on Infinity Tower points)
-- colorlight / colordark are the colours of the event in the client calendar.
Chaos.events = {
	list = {
		{id = "bloodmoon", name = "Blood Moon", weekdays = {7, 1}, colorlight = "#d23a2a", colordark = "#7a1a12",
			description = "The blood moon rises over the world: +50% experience from every kill.",
			bonus = {xp = 1.5}},
		{id = "chaosrift", name = "Chaos Rift", weekdays = {4}, colorlight = "#9b59d6", colordark = "#4d2470",
			description = "Reality tears open: magic, rare and legendary monsters appear twice as often and ambushes are more likely.",
			bonus = {tierChance = 2.0, ambush = 1.5}},
		{id = "lootfrenzy", name = "Loot Frenzy", weekdays = {6}, colorlight = "#e0a526", colordark = "#7a5410",
			description = "Monsters carry more treasure: +50% Chaos loot and an extra loot roll on every monster.",
			bonus = {loot = 1.5}},
		{id = "towerascension", name = "Tower Ascension", monthdays = {1, 2, 3, 15, 16, 17}, colorlight = "#2f9fd0", colordark = "#145470",
			description = "The Infinity Tower calls: double tower points for every floor cleared.",
			bonus = {towerPoints = 2.0}}
	},
	-- how many days of the calendar are sent to the client (from the first day of the current month)
	calendarDays = 62,
	announceOnLogin = true
}

-- World boss event (worldboss.lua). Monster XMLs: data/monster/monsters/chaos/world_bosses/ (register them with
-- tools/register_monsters.py). Times are server local time. See server/README.md "World bosses".
Chaos.worldBoss = {
	enabled = true, -- automatic schedule (the GM command works either way)
	-- starts at every hour h with (h - offsetHours) % intervalHours == 0, minute 0: 03:00, 09:00, 15:00, 21:00
	intervalHours = 6,
	offsetHours = 3,
	warnMinutes = {10, 5, 1}, -- broadcasts before a scheduled start
	mode = "rotation", -- "rotation" (next boss each time) or "random" (never the same twice in a row)
	gatherSeconds = 120, -- portals open, boss appears after this
	portalMinutes = 30, -- town portals stay this long (or until the boss dies)
	fightMinutes = 45, -- the boss leaves this long after it appeared (event failed)
	exitDelaySeconds = 90, -- after the end: time to loot before everyone is sent to their temple
	minLevel = 300,
	maxPlayers = 40, -- players inside lobby + arena at once (0 = no limit)
	allowPvp = false, -- no player-vs-player damage in the lobby and the arena
	-- multi-client characters (Chaos.isMultiClient) may enter and fight, but get no participation reward
	mcReward = false,

	-- arena: built at runtime with Game.createTile. Footprint x 5000..5032 (arena) and the lobby south of it,
	-- y 5000..5048, z 7. That part of the map has no tiles (checked in the map file; the script checks again
	-- before building and refuses to build over existing tiles).
	arena = {
		origin = {x = 5000, y = 5000, z = 7}, -- top-left wall corner of the arena
		inner = 31, -- inner width/height of the arena (odd, so there is a centre tile)
		lobbyGap = 7, -- empty (tile-less) rows between the arena's south wall and the lobby's north wall
		lobbyInnerW = 13, lobbyInnerH = 7,
		groundId = 407, -- black marble floor (arena)
		lobbyGroundId = 413, -- stone floor (lobby)
		wallId = 5648, -- stone wall
		pillarId = 1514, -- stone pillar (line-of-sight cover inside the arena)
		basinId = 1481, -- coal basin (light, lobby corners and arena corners)
		portalId = 1387 -- magic forcefield (type teleport in items.xml); used without destination + action id
	},
	-- action ids of the forcefields (handled by MoveEvent onStepIn, never by the teleport destination, so monsters
	-- that step on them are not moved and the entry rules are checked)
	aid = {enter = 47201, arena = 47202, lobby = 47203, exit = 47204},
	-- town portals: next to every temple of Game.getTowns() (first free spot of portalOffsets), or exactly at
	-- portalPositions when that list is not empty. towns = {id, ...} limits the towns (nil = all).
	towns = nil,
	portalPositions = {},
	portalOffsets = {{2, 0}, {-2, 0}, {0, 2}, {0, -2}, {2, 2}, {-2, 2}, {2, -2}, {-2, -2}, {3, 0}, {-3, 0}},
	rotationStorage = 7100910, -- global storage (Game.setStorageValue, in memory): last boss index; resets on restart

	-- participation reward (everybody with at least minDamagePercent % of the boss max health in damage).
	-- share = own damage / damage of all eligible players. Delivered to the backpack, the rest to the inbox;
	-- players offline at the kill get it at their next login (kept in memory until a restart).
	reward = {
		minDamagePercent = 0.25,
		bankGold = 500000, -- deposited into the bank for every eligible player
		bankGoldPool = 10000000, -- split by damage share, deposited into the bank
		base = {{id = 29856, count = 3}, {id = 29857, count = 1}}, -- Chaos Orbs, Divine Orb for everyone
		pool = {{id = 29856, count = 60}, {id = 29857, count = 25}}, -- split by damage share (floor)
		top = { -- bonus for the top damage dealers
			{{id = 29857, count = 5}, {id = 2160, count = 50}},
			{{id = 29857, count = 3}, {id = 2160, count = 30}},
			{{id = 29857, count = 2}, {id = 2160, count = 20}}
		},
		gearChance = 1500, -- per 10000: one item of the boss gear list (rolled with rarity gearRarity)
		gearShareBonus = 3000, -- + share x this (a player with 20% of the damage: +600)
		gearRarity = {6, 9}, -- min, max rarity of that item (Game.createItemWithRarity)
		uniqueChance = 50, -- per 10000: one of the boss-only uniques that list this boss (chaos_unique_items.lua)
		uniqueShareBonus = 300 -- + share x this
	},

	-- the five bosses. adds: {name, count, health}; phases trigger once when health falls to `at` (fraction).
	-- enrage: from that phase on, `pulse` hits every player within radius every `every` seconds.
	bosses = {
		{name = "Kaelgor the Infernal Warlord", element = "fire",
			intro = "Kaelgor the Infernal Warlord marches out of the burning rift!",
			phases = {
				{at = 0.70, adds = {name = "Hellfire Fighter", count = 4, health = 150000}, yell = "LEGION, TO ME!"},
				{at = 0.40, enrage = true, yell = "I WILL BURN THIS WORLD TO THE GROUND!"},
				{at = 0.15, adds = {name = "Hellspawn", count = 4, health = 150000}, yell = "My guard dies before I do!"}
			},
			pulse = {type = "fire", min = 2500, max = 4000, radius = 6, every = 8, effect = "explosionarea"},
			gear = {29878, 29879, 29880, 29881, 29882, 29883, 29884, 29885, 29890}},
		{name = "Skaldra the Rime Queen", element = "ice",
			intro = "The sky freezes over: Skaldra the Rime Queen descends!",
			phases = {
				{at = 0.70, adds = {name = "Frost Dragon", count = 3, health = 200000}, yell = "My brood, wake!"},
				{at = 0.40, enrage = true, yell = "THE LONG WINTER BEGINS!"},
				{at = 0.15, adds = {name = "Ice Golem", count = 4, health = 120000}, yell = "Shards, protect your queen!"}
			},
			pulse = {type = "ice", min = 2000, max = 3500, radius = 7, every = 7, effect = "giantice"},
			gear = {29869, 29870, 29871, 29872, 29873, 29874, 29875, 29876, 29877}},
		{name = "The Rotmother", element = "earth",
			intro = "The ground splits and the Rotmother crawls out of the plague pits!",
			phases = {
				{at = 0.75, adds = {name = "Defiler", count = 5, health = 120000}, yell = "Children, feed!"},
				{at = 0.50, adds = {name = "Plaguesmith", count = 4, health = 150000}, yell = "More! I need MORE!"},
				{at = 0.25, enrage = true, yell = "BREATHE ME IN!"}
			},
			pulse = {type = "earth", min = 1500, max = 2500, radius = 8, every = 6, effect = "greensmoke"},
			gear = {29863, 29867, 29871, 29872, 29880, 29881}},
		{name = "Nyxareth the Void Archon", element = "death",
			intro = "Reality tears: Nyxareth the Void Archon steps out of the void!",
			phases = {
				{at = 0.70, adds = {name = "Phantasm", count = 4, health = 100000}, yell = "Echoes, consume them."},
				{at = 0.40, enrage = true, yell = "THE VOID OPENS!"},
				{at = 0.15, adds = {name = "Lost Soul", count = 4, health = 100000}, yell = "Your dead serve me now."}
			},
			pulse = {type = "death", min = 2500, max = 4000, radius = 7, every = 7, effect = "mortarea"},
			gear = {29861, 29862, 29863, 29864, 29865, 29866, 29867, 29868}},
		{name = "Vharok the Blood Colossus", element = "physical",
			intro = "The earth trembles: Vharok the Blood Colossus awakens!",
			phases = {
				{at = 0.75, adds = {name = "Blood Beast", count = 4, health = 150000}, yell = "FEED ME!"},
				{at = 0.45, enrage = true, yell = "BLOOD FOR THE COLOSSUS!"},
				{at = 0.20, adds = {name = "Juggernaut", count = 3, health = 200000}, yell = "CRUSH THEM!"}
			},
			-- every player hit by the pulse heals Vharok by healPerHit
			pulse = {type = "physical", min = 2500, max = 4500, radius = 6, every = 7, effect = "groundshaker", healPerHit = 5000},
			gear = {29878, 29879, 29880, 29886, 29887, 29888, 29889, 29869}}
	}
}

-- Boosted creature / boss of the day (clientservices.lua). The reference server already picks both at
-- startup (global storages + boostedMonsterList / boostedBossesList); these lists are only the fallback
-- when that pick is missing or names a monster that does not exist.
Chaos.boosted = {
	creatures = {"Dragon", "Dragon Lord", "Giant Spider", "Hydra", "Behemoth", "Serpent Spawn", "Warlock", "Hero",
		"Nightmare", "Grim Reaper", "Frost Dragon", "Medusa", "Sea Serpent", "Wyrm", "Lost Soul"},
	bosses = {"Ferumbras", "Orshabaal", "Ghazbaran", "Morgaroth", "Zulazza the Corruptor", "The Plasmother"},
	storageCreature = 7100900, -- global storages for the fallback pick: index into the list above
	storageBoss = 7100901,
	storageDay = 7100902 -- YYYYMMDD of the fallback pick
}

-- Store services (shop_services.lua, autosell.lua). Prices and the offers themselves are in shop_config.lua.
Chaos.shopServices = {
	maxStamina = 2520, -- minutes (42 h), what the Stamina Refill restores to

	-- Temple Teleport Scroll: an ordinary "scroll" item (6119, no other script uses it) with this action id and a
	-- custom name/description; the uses left are kept in the item's custom attribute "chaos_uses".
	templeScroll = {itemId = 6119, actionId = 47301, name = "temple teleport scroll", cooldown = 2},

	-- World buffs: one purchase adds `minutes`; buying while active extends it, never beyond `capMinutes` left
	-- (a purchase that would pass the cap is refused, no coins taken). Expiry times are global storages
	-- (globalStorage + index) and are also written to the server_config table, so they survive /reload and a
	-- restart.
	worldBuffs = {
		{id = "xp", name = "World Experience", bonus = 0.25, minutes = 60, capMinutes = 180,
			text = "+25% experience from monsters for every player"},
		{id = "loot", name = "World Loot", bonus = 0.25, minutes = 60, capMinutes = 180,
			text = "+25% Chaos loot (extra loot rolls and currency drops) for every player"},
		{id = "skill", name = "World Training", bonus = 0.25, minutes = 60, capMinutes = 180,
			text = "+25% skill and magic level training for every player"}
	},
	worldBuffStorage = 7100920, -- global storages 7100921.. (expiry unix time per buff, in list order)
	worldBuffConfigKey = "chaos_worldbuff_", -- server_config rows chaos_worldbuff_<id>

	-- Name change rules (ChaosShopServices.validateName)
	name = {
		minLength = 3, maxLength = 20, maxWords = 3, minWordLength = 2,
		-- a first word (or any word) that is one of these is refused: staff look-alikes
		staffWords = {"gm", "cm", "god", "admin", "adm", "tutor", "gamemaster", "staff", "support", "owner", "sr", "senior", "server"},
		-- refused anywhere in the name (lower case, substring match); extend as needed
		forbidden = {"admin", "gamemaster", "moderator", "fuck", "shit", "bitch", "whore", "nazi", "hitler", "cunt", "rape"}
	},

	-- Vocation change: command word -> {base id, promoted id} (data/XML/vocations.xml). A promoted character
	-- gets the promoted id of the new vocation, an unpromoted one the base id.
	vocations = {
		sorcerer = {1, 5},
		druid = {2, 6},
		paladin = {3, 7},
		knight = {4, 8},
		illusionist = {9, 10}
	},
	vocationBaseLevel = 8, -- health/mana/capacity gains are counted from this level (as the engine does)

	-- Bottomless Loot Pouch: tell the player at most once per this many seconds
	pouchNoticeSeconds = 60,
	-- Auto Seller
	autosellSlots = 40,
	-- blessings of the "All Blessings" offer (base server: 1-5, see creaturescripts login.lua)
	blessings = {1, 2, 3, 4, 5}
}

-- Client services: the login screen asks an HTTP endpoint (client/tools or server/tools/clientservices.py)
-- for the boosted creature/boss, the event calendar and the players online. The game server writes what
-- that endpoint serves into this JSON file (path relative to the server folder).
Chaos.clientServices = {
	file = "data/chaos_clientservices.json",
	refreshSeconds = 300
}

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

-- Decode a JSON buffer; returns a table or nil (never throws).
-- Multi-client: how many characters one IP may have online, and who is exempt (group id, 1 = player).
-- A character with another character online from the same IP is "multi-clienting": it cannot enter dungeons or
-- the Infinity Tower and cannot attack players (multiclient.lua, dungeons.lua, infinitytower_run.lua and
-- data/spells/chaos/_common.lua ChaosSpell.canAttack, which repeats the check in the spells' Lua state).
Chaos.multiClient = {
	maxPerIp = 2,
	exemptGroup = 4, -- group id from which on (gamemasters, gods) the limit and the blocks do not apply
	msgDungeon = "You cannot enter while another character from your connection is online.",
	msgPvp = "You cannot attack players while another character from your connection is online.",
	-- global storage: 1 turns the multi-client blocks off (events, tests); the login limit stays
	offStorage = 7100990,
}

-- other online characters sharing this player's IP (IP 0 = no connection, never matches)
function Chaos.mcSiblings(player)
	local list = {}
	local ip = player:getIp()
	if ip == 0 or player:getGroup():getId() >= Chaos.multiClient.exemptGroup
			or Game.getStorageValue(Chaos.multiClient.offStorage) == 1 then
		return list
	end
	for _, other in ipairs(Game.getPlayers()) do
		if other ~= player and other:getIp() == ip then
			list[#list + 1] = other
		end
	end
	return list
end

function Chaos.isMultiClient(player)
	return #Chaos.mcSiblings(player) > 0
end

function Chaos.decode(buffer)
	if type(buffer) ~= "string" or buffer == "" then
		return nil
	end
	local ok, decoded = pcall(json.decode, buffer)
	if ok and type(decoded) == "table" then
		return decoded
	end
	return nil
end

-- Send {"action": action, "data": data} on an extended opcode.
function Chaos.send(player, opcode, action, data)
	if not player then
		return false
	end
	local payload = {action = action}
	if data ~= nil then
		payload.data = data
	end
	player:sendExtendedOpcode(opcode, json.encode(payload))
	return true
end

-- Positive integer from client input, or nil.
function Chaos.toInt(value, minimum, maximum)
	local n = tonumber(value)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	n = math.floor(n)
	if minimum and n < minimum then
		return nil
	end
	if maximum and n > maximum then
		return nil
	end
	return n
end

-- YYYYMMDD integer for a unix time (server local time).
function Chaos.dayKey(t)
	return tonumber(os.date("%Y%m%d", t or os.time()))
end

-- dayKey of the calendar day before `t`.
function Chaos.yesterdayKey(t)
	t = t or os.time()
	local d = os.date("*t", t)
	return Chaos.dayKey(os.time({year = d.year, month = d.month, day = d.day - 1, hour = 12}))
end

-- Run a SELECT and return an array of rows (each row is a table of column -> value).
-- `columns` is a list of {name, "n"|"s"} pairs.
function Chaos.select(query, columns)
	local rows = {}
	local resultId = db.storeQuery(query)
	if not resultId then
		return rows
	end
	repeat
		local row = {}
		for _, col in ipairs(columns) do
			if col[2] == "s" then
				row[col[1]] = result.getString(resultId, col[1])
			else
				row[col[1]] = result.getNumber(resultId, col[1])
			end
		end
		rows[#rows + 1] = row
	until not result.next(resultId)
	result.free(resultId)
	return rows
end

-- Give items to a player; returns how many were really added (handles partial / no room).
function Chaos.giveItem(player, itemId, count)
	local before = player:getItemCount(itemId)
	player:addItem(itemId, count, false)
	return player:getItemCount(itemId) - before
end

-- Resolve a player name to guid (online or offline). Returns guid, canonicalName or nil.
function Chaos.findPlayer(name)
	if type(name) ~= "string" or name == "" or #name > 29 then
		return nil
	end
	local online = Player(name)
	if online then
		return online:getGuid(), online:getName(), online
	end
	local resultId = db.storeQuery("SELECT `id`, `name` FROM `players` WHERE `name` = " .. db.escapeString(name) .. " LIMIT 1")
	if not resultId then
		return nil
	end
	local guid = result.getNumber(resultId, "id")
	local canonical = result.getString(resultId, "name")
	result.free(resultId)
	return guid, canonical, nil
end

-- Lazily load a data file that sits next to the scripts (guarded by the file itself).
function Chaos.load(fileName)
	return dofile("data/scripts/chaos/" .. fileName)
end
