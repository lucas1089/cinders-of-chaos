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
	dungeonQueueLock = 7100030, -- (os.time of the last queue join; anti spam)

	-- store: one-time cosmetics owned (base + id of the wings / aura / shader)
	shopWingsBase = 7100600,
	shopAuraBase = 7100650,
	shopShaderBase = 7100700
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
	startLevel = 8, -- first point at level startLevel+1
	pointsPerLevel = 1,
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
