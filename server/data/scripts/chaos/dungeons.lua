-- game_dungeons (extended opcode 109)
--
-- Client contract (client/overlay/modules/game_dungeons/dungeons.lua), {"action":..,"data":..}:
--   client -> server  fetch                                  -> list + dungeon* + solo/group*
--                     queue {id, difficulty}                 -> join; sending it again leaves
--   server -> client  list [{id,title,level,boss=outfit,queue=N}]
--                     dungeon {id,title,difficulty,req,loot,queue={players,estimated},challenges}
--                     solo / group {id,diff,top=[{name,time,self?}]}      (time in ms)
--                     queue {id,joined}   stopQueue   queueUpdate {id,queue,estimated}
--                     prepare            start {boss,left,duration,objectives}
--                     killed {percent,left} | {boss=true}    objective {id,finished}
--                     challenge "<title>"   difficulty {id,difficulty}   finish
--
-- Integration with the base server dungeon system (lib/core/dungeon.lua, global DUNGEON_SYSTEM):
-- the dungeon list, level requirement, group size (AmountParty when NeedParty), DungeonPos,
-- FromPos/ToPos, DungeonTime, SpawnMonsters/Monsters and the cooldown storage are all read from
-- DUNGEON_SYSTEM.Dungeons live. Entry here is by matchmaking queue instead of the modal window;
-- the old modal/stairs entry keeps working untouched (it just does not know about this module).
--
-- Real: queueing, group formation, teleport in, time limit, monster-count progress, boss kill,
-- completion, per-dungeon unlocked difficulty, challenges (speed / flawless), personal and group
-- ranking in the DB, teleport out.
-- Difficulty (dungeons_difficulty.lua, the numbers of the client's difficulty panel): every monster in the
-- dungeon box during a run (seen at the start and by every queue tick, so respawns too) gets x health; its
-- damage to the run's players x damage (health and mana events registered on the members); its kills give
-- + experience, its corpse + gold coins and one more roll of every loot entry at + loot percent of its chance.
-- NOT real (see README): the loot panel is display only (real loot is whatever the boss monster XML drops),
-- bosses are assumed to exist in the map (spawned by the map/spawn system or by SpawnMonsters), dungeons are
-- one-run-at-a-time.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

local OPCODE = ChaosOpcodes.dungeons
local cfg = Chaos.dungeons
local TP = Chaos.tables.dungeonProgress
local TR = Chaos.tables.dungeonRuns
local TRP = Chaos.tables.dungeonRunPlayers

ChaosDungeonDifficulty = dofile("data/scripts/chaos/dungeons_difficulty.lua")
local DIFF = ChaosDungeonDifficulty
local scaledBy = {} -- [monster id] = run (the monster got the run's difficulty)

local queues = {} -- [dungeonId] = array of {guid=, difficulty=, joined=}
local queuedIn = {} -- [guid] = dungeonId
local subscribers = {} -- [guid] = true   (players that fetched the window data)
local runs = {} -- [runId] = run
local runOfPlayer = {} -- [guid] = run
local runOfDungeon = {} -- [dungeonId] = run
local nextRunId = 1
local tickerEvent = nil

-- ------------------------------------------------------------------ helpers

local function nowMs()
	if os.mtime then
		return os.mtime()
	end
	return os.time() * 1000
end

local function baseDungeons()
	return (DUNGEON_SYSTEM and DUNGEON_SYSTEM.Dungeons) or {}
end

local function baseMessage(key, fallback)
	local m = DUNGEON_SYSTEM and DUNGEON_SYSTEM.Messages
	return (m and m[key]) or fallback
end

local function cooldownStorage()
	local s = DUNGEON_SYSTEM and DUNGEON_SYSTEM.Storages
	-- the reference lib defines `timerCooldown`, its modal script reads `TimerCooldown`; accept both
	return s and (s.timerCooldown or s.TimerCooldown) or nil
end

local function cooldownSeconds()
	return (DUNGEON_SYSTEM and DUNGEON_SYSTEM.CooldownTime) or 3600
end

local function extraOf(id)
	return cfg.extra[id] or {}
end

local function titleOf(id, dg)
	return extraOf(id).title or dg.Name
end

local function groupSizeOf(dg)
	if dg.NeedParty then
		return math.max(1, dg.AmountParty or 1)
	end
	return 1
end

local function levelOf(dg)
	if dg.NeedLevel then
		return dg.Level or 1
	end
	return 1
end

-- the engine has no Game.getPlayerByGUID (that call made every queue tick fail): a scan of the online players
-- when this server started (kept over a /reload): a character whose last logout is older was kicked by a shutdown or
-- lost in a crash; one saved inside a dungeon box then goes to its temple at login (below)
ChaosDungeonsBoot = ChaosDungeonsBoot or os.time()

local function online(guid)
	if Game.getPlayerByGUID then
		return Game.getPlayerByGUID(guid)
	end
	for _, p in ipairs(Game.getPlayers()) do
		if p:getGuid() == guid then
			return p
		end
	end
	return nil
end

local function send(player, action, data)
	Chaos.send(player, OPCODE, action, data)
end

-- Box of a dungeon. The base server table is inconsistent for some entries (e.g. Forbidden Chevalier has
-- DungeonPos z=0 but FromPos/ToPos z=7), so the floor range is widened to include DungeonPos.
local function boundsOf(dg)
	local f, t, d = dg.FromPos, dg.ToPos, dg.DungeonPos
	return {
		x1 = math.min(f.x, t.x), x2 = math.max(f.x, t.x),
		y1 = math.min(f.y, t.y), y2 = math.max(f.y, t.y),
		z1 = math.min(f.z, t.z, d.z), z2 = math.max(f.z, t.z, d.z)
	}
end

local function inBox(dg, pos)
	local b = boundsOf(dg)
	return pos.x >= b.x1 and pos.x <= b.x2 and pos.y >= b.y1 and pos.y <= b.y2 and pos.z >= b.z1 and pos.z <= b.z2
end

-- monsters / players inside the dungeon box. bossName is lower case.
local function scanArea(dg, bossName)
	local b = boundsOf(dg)
	local rx = math.ceil((b.x2 - b.x1) / 2)
	local ry = math.ceil((b.y2 - b.y1) / 2)
	local cx, cy = b.x1 + rx, b.y1 + ry
	local monsters, bosses, players, monsterList = 0, 0, 0, {}
	for z = b.z1, b.z2 do
		local list = Game.getSpectators(Position(cx, cy, z), false, false, rx, rx, ry, ry)
		for _, creature in ipairs(list) do
			if inBox(dg, creature:getPosition()) then
				if creature:isPlayer() then
					players = players + 1
				elseif creature:isMonster() and not creature:getMaster() then
					monsterList[#monsterList + 1] = creature
					if bossName and creature:getName():lower() == bossName then
						bosses = bosses + 1
					else
						monsters = monsters + 1
					end
				end
			end
		end
	end
	return monsters, bosses, players, monsterList
end

-- ------------------------------------------------------------------ persistence

local function loadProgress(guid, dungeonId)
	local rows = Chaos.select(
		"SELECT `difficulty`, `challenges` FROM `" .. TP .. "` WHERE `player_id` = " .. guid .. " AND `dungeon_id` = " .. dungeonId,
		{{"difficulty", "n"}, {"challenges", "s"}}
	)
	local row = rows[1]
	local progress = {difficulty = 1, challenges = {}}
	if row then
		progress.difficulty = math.min(math.max(row.difficulty, 1), cfg.maxDifficulty)
		for key in (row.challenges or ""):gmatch("[%w_]+") do
			progress.challenges[key] = true
		end
	end
	return progress
end

local function saveProgress(guid, dungeonId, progress)
	local keys = {}
	for key in pairs(progress.challenges) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	db.query(
		"INSERT INTO `" .. TP .. "` (`player_id`, `dungeon_id`, `difficulty`, `challenges`) VALUES (" .. guid .. ", " .. dungeonId ..
			", " .. progress.difficulty .. ", " .. db.escapeString(table.concat(keys, ",")) ..
			") ON DUPLICATE KEY UPDATE `difficulty` = VALUES(`difficulty`), `challenges` = VALUES(`challenges`)"
	)
end

local function storeRun(dungeonId, difficulty, timeMs, members)
	local names, guids = {}, {}
	for _, m in ipairs(members) do
		names[#names + 1] = m.name
		guids[#guids + 1] = m.guid
	end
	db.query(
		"INSERT INTO `" .. TR .. "` (`dungeon_id`, `difficulty`, `time_ms`, `party_size`, `names`, `finished_at`) VALUES (" ..
			dungeonId .. ", " .. difficulty .. ", " .. timeMs .. ", " .. #members .. ", " ..
			db.escapeString(table.concat(names, "\n")) .. ", " .. os.time() .. ")"
	)
	local resultId = db.storeQuery("SELECT LAST_INSERT_ID() AS `id`")
	if not resultId then
		return
	end
	local runId = result.getNumber(resultId, "id")
	result.free(resultId)
	for _, guid in ipairs(guids) do
		db.query("INSERT IGNORE INTO `" .. TRP .. "` (`run_id`, `player_id`) VALUES (" .. runId .. ", " .. guid .. ")")
	end
end

-- top solo runners for (dungeon, difficulty); marks the viewer's row(s) with `self`
local function soloTop(dungeonId, difficulty, viewerGuid)
	local base = " FROM `" .. TR .. "` r JOIN `" .. TRP .. "` rp ON rp.`run_id` = r.`id` JOIN `players` p ON p.`id` = rp.`player_id`" ..
		" WHERE r.`dungeon_id` = " .. dungeonId .. " AND r.`difficulty` = " .. difficulty .. " AND r.`party_size` = 1"
	local rows = Chaos.select(
		"SELECT p.`id` AS `pid`, p.`name` AS `name`, MIN(r.`time_ms`) AS `best`" .. base ..
			" GROUP BY p.`id`, p.`name` ORDER BY `best` ASC LIMIT 10",
		{{"pid", "n"}, {"name", "s"}, {"best", "n"}}
	)
	local top, seen = {}, false
	for i, row in ipairs(rows) do
		local entry = {name = row.name, time = row.best}
		if row.pid == viewerGuid then
			entry.self = i
			seen = true
		end
		top[i] = entry
	end
	if not seen then
		local own = Chaos.select(
			"SELECT p.`name` AS `name`, MIN(r.`time_ms`) AS `best`" .. base .. " AND p.`id` = " .. viewerGuid .. " GROUP BY p.`name`",
			{{"name", "s"}, {"best", "n"}}
		)[1]
		if own and own.best then
			local better = Chaos.select(
				"SELECT COUNT(*) AS `c` FROM (SELECT MIN(r.`time_ms`) AS `m`" .. base ..
					" GROUP BY p.`id` HAVING `m` < " .. own.best .. ") x",
				{{"c", "n"}}
			)[1]
			top[#top + 1] = {name = own.name, time = own.best, self = ((better and better.c) or 0) + 1}
		end
	end
	return top
end

local function groupTop(dungeonId, difficulty, viewerGuid)
	local rows = Chaos.select(
		"SELECT r.`id` AS `rid`, r.`names` AS `names`, r.`time_ms` AS `t` FROM `" .. TR .. "` r WHERE r.`dungeon_id` = " ..
			dungeonId .. " AND r.`difficulty` = " .. difficulty .. " AND r.`party_size` > 1 ORDER BY r.`time_ms` ASC LIMIT 10",
		{{"rid", "n"}, {"names", "s"}, {"t", "n"}}
	)
	local top = {}
	for i, row in ipairs(rows) do
		local entry = {name = row.names, time = row.t}
		local mine = Chaos.select(
			"SELECT 1 AS `x` FROM `" .. TRP .. "` WHERE `run_id` = " .. row.rid .. " AND `player_id` = " .. viewerGuid,
			{{"x", "n"}}
		)
		if #mine > 0 then
			entry.self = i
		end
		top[i] = entry
	end
	return top
end

-- ------------------------------------------------------------------ payload builders

local function queueInfo(id, dg)
	local waiting = queues[id] and #queues[id] or 0
	local missing = math.max(0, groupSizeOf(dg) - waiting)
	return {players = waiting, estimated = missing * 30000}
end

local function bossOutfit(id)
	local bossName = extraOf(id).bossName
	local outfit = {lookType = 0}
	if bossName then
		local monsterType = MonsterType(bossName)
		if monsterType then
			local o = monsterType:getOutfit()
			if o then
				outfit = {
					lookType = o.lookType or 0,
					lookTypeEx = o.lookTypeEx or 0,
					lookHead = o.lookHead or 0,
					lookBody = o.lookBody or 0,
					lookLegs = o.lookLegs or 0,
					lookFeet = o.lookFeet or 0,
					lookAddons = o.lookAddons or 0
				}
			end
		end
	end
	return outfit
end

local function dungeonPayload(player, id, dg)
	local extra = extraOf(id)
	local progress = loadProgress(player:getGuid(), id)

	local req = {level = levelOf(dg)}
	if dg.NeedParty then
		req.party = groupSizeOf(dg)
	end

	local loot = {}
	for i, item in ipairs(extra.loot or {}) do
		local itemType = ItemType(item.id)
		loot[i] = {clientId = itemType:getId() ~= 0 and itemType:getClientId() or item.id, count = item.count}
	end

	local challenges = {}
	for i, ch in ipairs(extra.challenges or {}) do
		challenges[i] = {title = ch.title, points = ch.points, desc = ch.desc, completed = progress.challenges[ch.key] == true}
	end

	return {
		id = id,
		title = titleOf(id, dg),
		difficulty = progress.difficulty,
		req = req,
		loot = loot,
		queue = queueInfo(id, dg),
		challenges = challenges
	}
end

local function sendAll(player)
	local guid = player:getGuid()
	local list = {}
	local dungeons = baseDungeons()
	local ids = {}
	for id in pairs(dungeons) do
		ids[#ids + 1] = id
	end
	table.sort(ids)

	for _, id in ipairs(ids) do
		local dg = dungeons[id]
		send(player, "dungeon", dungeonPayload(player, id, dg))
		list[#list + 1] = {
			id = id,
			title = titleOf(id, dg),
			level = levelOf(dg),
			boss = bossOutfit(id),
			queue = queues[id] and #queues[id] or 0
		}

		local diffs = Chaos.select(
			"SELECT DISTINCT `difficulty` FROM `" .. TR .. "` WHERE `dungeon_id` = " .. id,
			{{"difficulty", "n"}}
		)
		for _, d in ipairs(diffs) do
			local solo = soloTop(id, d.difficulty, guid)
			if #solo > 0 then
				send(player, "solo", {id = id, diff = d.difficulty, top = solo})
			end
			local group = groupTop(id, d.difficulty, guid)
			if #group > 0 then
				send(player, "group", {id = id, diff = d.difficulty, top = group})
			end
		end
	end
	send(player, "list", list)
end

local function broadcastQueue(id)
	local dg = baseDungeons()[id]
	if not dg then
		return
	end
	local info = queueInfo(id, dg)
	for guid in pairs(subscribers) do
		local p = online(guid)
		if p then
			send(p, "queueUpdate", {id = id, queue = info.players, estimated = info.estimated})
		else
			subscribers[guid] = nil
		end
	end
end

-- ------------------------------------------------------------------ queue

local function leaveQueue(guid, notify)
	local id = queuedIn[guid]
	if not id then
		return false
	end
	queuedIn[guid] = nil
	local list = queues[id] or {}
	for i = #list, 1, -1 do
		if list[i].guid == guid then
			table.remove(list, i)
		end
	end
	local p = online(guid)
	if p and notify then
		send(p, "queue", {id = id, joined = false})
		send(p, "stopQueue")
	end
	broadcastQueue(id)
	return true
end

-- returns nil if the player may queue, else a reason string
-- true while the character takes part in a dungeon run (multiclient.lua refuses a second login then)
function ChaosDungeonIsInside(player)
	return runOfPlayer[player:getGuid()] ~= nil
end

local function entryProblem(player, id, dg, difficulty)
	local guid = player:getGuid()
	if runOfPlayer[guid] then
		return "You are already inside a dungeon."
	end
	if inBox(dg, player:getPosition()) then
		return "You cannot queue from inside the dungeon."
	end
	-- the run teleports from wherever the player stands: without this a fight (or a chase) could be left by queueing.
	-- Checked again on every queue tick (tryMatch), so fighting while queued drops the player from the queue
	if player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT) then
		return "You cannot enter a dungeon while you are in a fight."
	end
	if Chaos.isMultiClient(player) then
		return Chaos.multiClient.msgDungeon
	end
	if player:getLevel() < levelOf(dg) then
		return string.format(baseMessage("MsgNeedLevel", "You need level %s."), levelOf(dg))
	end
	local storage = cooldownStorage()
	if storage then
		local remaining = player:getStorageValue(storage) - os.time()
		if remaining > 0 then
			return string.format("You are in cooldown for dungeons. Wait %d minute(s).", math.ceil(remaining / 60))
		end
	end
	if difficulty > loadProgress(guid, id).difficulty then
		return "That difficulty is still locked."
	end
	return nil
end

-- ------------------------------------------------------------------ runs

local function memberPlayers(run)
	local players = {}
	for guid in pairs(run.members) do
		local p = online(guid)
		if p then
			players[#players + 1] = p
		end
	end
	return players
end

local function releasePlayer(run, guid)
	run.members[guid] = nil
	runOfPlayer[guid] = nil
	local p = online(guid)
	if p then
		p:unregisterEvent("ChaosDungeonKill")
		p:unregisterEvent("ChaosDungeonDeath")
		p:unregisterEvent("ChaosDungeonHit")
		p:unregisterEvent("ChaosDungeonMana")
	end
end

-- the run's difficulty on a monster (once per monster)
local function scaleMonster(run, monster)
	local mid = monster:getId()
	if scaledBy[mid] then
		return
	end
	scaledBy[mid] = run
	local hp = DIFF.health(monster:getMaxHealth(), run.difficulty)
	if hp ~= monster:getMaxHealth() then
		local share = monster:getHealth() / math.max(1, monster:getMaxHealth())
		monster:setMaxHealth(hp)
		monster:setHealth(math.max(1, math.floor(hp * share + 0.5)))
	end
end

local function scaleList(run, monsterList)
	for _, m in ipairs(monsterList or {}) do
		scaleMonster(run, m)
	end
end

local function forgetRun(run)
	for mid, r in pairs(scaledBy) do
		if r == run then
			scaledBy[mid] = nil
		end
	end
end

local function cleanArea(dg, bossName)
	local _, _, _, monsterList = scanArea(dg, bossName)
	for _, monster in ipairs(monsterList) do
		monster:remove()
	end
end

local function setCooldown(player)
	local storage = cooldownStorage()
	if storage then
		player:setStorageValue(storage, os.time() + cooldownSeconds())
	end
end

-- Ends the run: success=false means failure/timeout (teleport out now), success=true means the
-- boss died (teleport out after exitDelayMs so the players see the completion state).
local function endRun(run, success, reason)
	if run.ended then
		return
	end
	run.ended = true
	local dg = baseDungeons()[run.dungeonId]
	local extra = extraOf(run.dungeonId)

	local function teardown()
		for _, p in ipairs(memberPlayers(run)) do
			send(p, "finish")
			if dg and inBox(dg, p:getPosition()) then
				local origin = run.members[p:getGuid()]
				p:teleportTo(origin or p:getTown():getTemplePosition())
				p:getPosition():sendMagicEffect(40)
				if not success then
					p:popupFYI(reason or baseMessage("ToFail", "You were unable to complete the dungeon in time."))
				end
			end
			if not success or cfg.cooldownOnSuccess then
				setCooldown(p)
			end
		end
		for guid in pairs(run.members) do
			releasePlayer(run, guid)
		end
		runs[run.id] = nil
		if dg then
			cleanArea(dg, extra.bossName and extra.bossName:lower() or nil)
		end
		forgetRun(run)
		runOfDungeon[run.dungeonId] = nil
	end

	if not success then
		teardown()
		return
	end

	-- success: persist, unlock, challenges
	local elapsed = nowMs() - run.startedAt
	local memberInfo = {}
	for guid in pairs(run.members) do
		local p = online(guid)
		if p then
			memberInfo[#memberInfo + 1] = {guid = guid, name = p:getName()}
		end
	end
	if #memberInfo > 0 then
		storeRun(run.dungeonId, run.difficulty, elapsed, memberInfo)
	end

	for _, p in ipairs(memberPlayers(run)) do
		local guid = p:getGuid()
		send(p, "killed", {boss = true})

		local progress = loadProgress(guid, run.dungeonId)
		if run.difficulty >= progress.difficulty and progress.difficulty < cfg.maxDifficulty then
			progress.difficulty = progress.difficulty + 1
			send(p, "difficulty", {id = run.dungeonId, difficulty = progress.difficulty})
		end
		for k, ch in ipairs(extra.challenges or {}) do
			local achieved = false
			if ch.key == "speed" then
				achieved = elapsed <= (ch.maxMs or 0)
			elseif ch.key == "flawless" then
				achieved = run.deaths == 0
			end
			send(p, "objective", {id = k, finished = achieved})
			if achieved and not progress.challenges[ch.key] then
				progress.challenges[ch.key] = true
				send(p, "challenge", ch.title)
			end
		end
		saveProgress(guid, run.dungeonId, progress)
		send(p, "dungeon", dungeonPayload(p, run.dungeonId, dg))
	end

	addEvent(function(runId)
		-- `run` is still referenced here; runs[] only guards the tick
		teardown()
	end, cfg.exitDelayMs, run.id)
end

local function startRun(dungeonId, difficulty, players)
	local dg = baseDungeons()[dungeonId]
	local extra = extraOf(dungeonId)
	local bossName = extra.bossName and extra.bossName:lower() or nil

	local run = {
		id = nextRunId,
		dungeonId = dungeonId,
		difficulty = difficulty,
		members = {}, -- [guid] = origin Position
		startedAt = nowMs(),
		deaths = 0,
		lastPercent = -1,
		total = 0,
		missingTicks = 0,
		bossSeen = false
	}
	nextRunId = nextRunId + 1
	runs[run.id] = run
	runOfDungeon[dungeonId] = run

	if dg.SpawnMonsters and dg.Monsters then
		for monsterName, position in pairs(dg.Monsters) do
			Game.createMonster(monsterName, position)
		end
	end

	for _, p in ipairs(players) do
		local guid = p:getGuid()
		leaveQueue(guid, false)
		send(p, "prepare")
		run.members[guid] = p:getPosition()
		runOfPlayer[guid] = run
		p:registerEvent("ChaosDungeonKill")
		p:registerEvent("ChaosDungeonDeath")
		p:registerEvent("ChaosDungeonHit")
		p:registerEvent("ChaosDungeonMana")
		p:teleportTo(dg.DungeonPos)
		p:getPosition():sendMagicEffect(40)
		p:say(baseMessage("ToEntry", "Welcome to Dungeon"), TALKTYPE_MONSTER_SAY)
	end

	local monsters, bosses, _, monsterList = scanArea(dg, bossName)
	run.total = monsters
	run.bossSeen = bosses > 0
	scaleList(run, monsterList)

	local durationMs = (dg.DungeonTime or 3600) * 1000
	local objectives = {}
	for i, ch in ipairs(extra.challenges or {}) do
		objectives[i] = ch.title
	end
	for _, p in ipairs(players) do
		send(p, "start", {
			boss = bossName and extra.bossName or "the boss",
			left = monsters,
			duration = durationMs,
			objectives = #objectives > 0 and objectives or nil
		})
	end

	addEvent(function(runId)
		local r = runs[runId]
		if r and not r.ended then
			endRun(r, false, baseMessage("ToFail", "You were unable to complete the dungeon in the respective time.\n\nNext time you will do it better!"))
		end
	end, durationMs, run.id)

	broadcastQueue(dungeonId)
end

local function tryMatch(id)
	local dg = baseDungeons()[id]
	local list = queues[id]
	if not dg or not list or #list == 0 or runOfDungeon[id] then
		return
	end

	-- drop invalid entries first (offline / cooldown / level changed)
	for i = #list, 1, -1 do
		local p = online(list[i].guid)
		if not p then
			queuedIn[list[i].guid] = nil
			table.remove(list, i)
		else
			local problem = entryProblem(p, id, dg, list[i].difficulty)
			if problem then
				p:sendCancelMessage(problem)
				leaveQueue(list[i].guid, true)
			end
		end
	end

	local size = groupSizeOf(dg)
	local byDifficulty = {}
	for _, entry in ipairs(queues[id]) do
		local bucket = byDifficulty[entry.difficulty] or {}
		byDifficulty[entry.difficulty] = bucket
		bucket[#bucket + 1] = entry
	end
	local chosenDiff, chosen
	for diff, bucket in pairs(byDifficulty) do
		if #bucket >= size and (not chosen or bucket[1].joined < chosen[1].joined) then
			chosenDiff, chosen = diff, bucket
		end
	end
	if not chosen then
		return
	end

	-- the dungeon area must be empty of players (a leftover player means a previous run is not over)
	local _, _, playersInside = scanArea(dg, nil)
	if playersInside > 0 then
		return
	end

	local players = {}
	for i = 1, size do
		players[#players + 1] = online(chosen[i].guid)
	end
	startRun(id, chosenDiff, players)
end

-- ------------------------------------------------------------------ ticker

local function hasWork()
	if next(runs) ~= nil then
		return true
	end
	for _, list in pairs(queues) do
		if #list > 0 then
			return true
		end
	end
	return false
end

local tick

local function ensureTicker()
	if not tickerEvent and hasWork() then
		tickerEvent = addEvent(tick, cfg.queueTickMs)
	end
end

tick = function()
	tickerEvent = nil

	for id in pairs(queues) do
		tryMatch(id)
	end

	for runId, run in pairs(runs) do
		if not run.ended then
			local dg = baseDungeons()[run.dungeonId]
			local extra = extraOf(run.dungeonId)
			local bossName = extra.bossName and extra.bossName:lower() or nil
			local monsters, bosses, playersInside, monsterList = scanArea(dg, bossName)
			scaleList(run, monsterList) -- respawns inside the box get the difficulty too

			if bosses > 0 then
				run.bossSeen = true
			end

			-- members that left the box (died, logged out, walked out) are released
			for guid in pairs(run.members) do
				local p = online(guid)
				if not p or not inBox(dg, p:getPosition()) then
					releasePlayer(run, guid)
					if p then
						send(p, "finish") -- hide the kill counter
						setCooldown(p) -- leaving / dying counts as a failed attempt
					end
				end
			end
			if next(run.members) == nil then
				run.ended = true
				runs[runId] = nil
				runOfDungeon[run.dungeonId] = nil
				cleanArea(dg, bossName)
				forgetRun(run)
			else
				local percent = 100
				if run.total > 0 then
					percent = math.min(100, math.floor((run.total - monsters) * 100 / run.total))
					percent = math.max(percent, 0)
				end
				if percent ~= run.lastPercent then
					run.lastPercent = percent
					for _, p in ipairs(memberPlayers(run)) do
						send(p, "killed", {percent = percent, left = monsters})
					end
				end
				-- boss seen earlier and gone now (killed by someone onKill did not credit)
				if run.bossSeen and bosses == 0 and percent >= cfg.progressNeeded then
					endRun(run, true)
				end
			end
		end
	end

	ensureTicker()
end

-- ------------------------------------------------------------------ events

local KillEvent = CreatureEvent("ChaosDungeonKill")

function KillEvent.onKill(creature, target)
	local player = creature:isPlayer() and creature or nil
	if not player or not target:isMonster() then
		return true
	end
	local run = runOfPlayer[player:getGuid()]
	if not run or run.ended then
		return true
	end
	local bossName = extraOf(run.dungeonId).bossName
	if bossName and target:getName():lower() == bossName:lower() then
		if run.lastPercent >= cfg.progressNeeded or run.total == 0 then
			endRun(run, true)
		end
	end
	return true
end

KillEvent:type("kill")
KillEvent:register()

local DeathEvent = CreatureEvent("ChaosDungeonDeath")

function DeathEvent.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local run = creature:isPlayer() and runOfPlayer[creature:getGuid()] or nil
	if run and not run.ended then
		run.deaths = run.deaths + 1
	end
	return true
end

DeathEvent:type("death")
DeathEvent:register()

-- difficulty: damage of the run's monsters to its players
local function scaleHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	local run = attacker and attacker:isMonster() and scaledBy[attacker:getId()]
	if run and not run.ended and primaryType ~= COMBAT_HEALING then
		primaryDamage = DIFF.damage(primaryDamage, run.difficulty)
		secondaryDamage = DIFF.damage(secondaryDamage, run.difficulty)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

local HitEvent = CreatureEvent("ChaosDungeonHit")
function HitEvent.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	return scaleHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
end
HitEvent:register()

local ManaEvent = CreatureEvent("ChaosDungeonMana")
function ManaEvent.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	return scaleHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
end
ManaEvent:register()

-- difficulty: experience of the run's kills (for the run's players)
local xpCallback = EventCallback
xpCallback.onGainExperience = function(player, source, exp, rawExp)
	local run = source and source:isMonster() and scaledBy[source:getId()]
	if run and exp > 0 and run.members[player:getGuid()] then
		return DIFF.experience(exp, run.difficulty)
	end
	return exp
end
xpCallback:register(90) -- after the stages and Chaos bonuses, before the rift cap (100, not inside a dungeon)

-- difficulty: gold coins and extra loot rolls in the corpse (after the Chaos loot layer at 1 and the rift's Echoing
-- Spoils at 1.5, before the rift key drop at 2 and the loot snapshot at 2.5, so loot rays and autoloot see them)
local lootCallback = EventCallback
lootCallback.onDropLoot = function(monster, corpse)
	local run = scaledBy[monster:getId()]
	if not run or run.difficulty <= 1 then
		return
	end
	local ok, err = pcall(function()
		if not corpse or not corpse:isContainer() then
			return
		end
		local add = {}
		for _, item in ipairs(corpse:getItems(false) or {}) do
			if DIFF.coins[item:getId()] then
				local n = DIFF.extraGold(item:getCount(), run.difficulty, math.random)
				if n > 0 then
					add[#add + 1] = {item:getId(), n}
				end
			end
		end
		for _, e in ipairs(monster:getType():getLoot() or {}) do
			local chance = DIFF.extraLootChance(e.chance or 0, run.difficulty)
			if e.itemId and chance > 0 and math.random(1, 100000) <= chance then
				local maxC = math.max(e.maxCount or 1, 1)
				add[#add + 1] = {e.itemId, math.random(1, maxC)}
			end
		end
		for _, a in ipairs(add) do
			local id, n = a[1], a[2]
			local stackable = ItemType(id):isStackable()
			while n > 0 do
				local k = stackable and math.min(n, 100) or 1
				corpse:addItem(id, k, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
				n = n - k
			end
		end
	end)
	if not ok then
		print("[ChaosDungeons] difficulty loot failed: " .. tostring(err))
	end
end
lootCallback:register(1.7)

local LogoutEvent = CreatureEvent("ChaosDungeonsLogout")

function LogoutEvent.onLogout(player)
	local guid = player:getGuid()
	subscribers[guid] = nil
	leaveQueue(guid, false)
	local run = runOfPlayer[guid]
	if run then
		releasePlayer(run, guid) -- the tick ends the run if nobody is left
	end
	return true
end

LogoutEvent:type("logout")
LogoutEvent:register()

local LoginEvent = CreatureEvent("ChaosDungeonsLogin")

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosDungeonsExtended")
	-- the first login after a restart or a crash inside a dungeon box (a queue run here or a run of the base modal, whose
	-- exit timer died with the server): out to the temple. A relog while the server runs stays (the run may go on).
	if not runOfPlayer[player:getGuid()] and (player:getLastLogout() or 0) < ChaosDungeonsBoot then
		local pos = player:getPosition()
		for _, dg in pairs(baseDungeons()) do
			if dg.FromPos and dg.ToPos and dg.DungeonPos and inBox(dg, pos) then
				player:teleportTo(player:getTown():getTemplePosition())
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your dungeon run was cut short by a server restart.")
				break
			end
		end
	end
	return true
end

-- a clean shutdown: every queue run ends without a cooldown, the members back where they entered (saved there by the kick)
local ShutdownEvent = GlobalEvent("ChaosDungeonsShutdown")
function ShutdownEvent.onShutdown()
	for _, run in pairs(runs) do
		if not run.ended then
			run.ended = true
			local dg = baseDungeons()[run.dungeonId]
			for guid, origin in pairs(run.members) do
				local p = online(guid)
				if p then
					send(p, "finish")
					if dg and inBox(dg, p:getPosition()) then
						p:teleportTo(origin or p:getTown():getTemplePosition())
					end
				end
				releasePlayer(run, guid)
			end
		end
	end
	return true
end
ShutdownEvent:register()

local ExtendedEvent = CreatureEvent("ChaosDungeonsExtended")

function ExtendedEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local guid = player:getGuid()

	if msg.action == "fetch" then
		-- the full list reads progress and rankings from the database (ratelimit.lua)
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "dungeons.fetch", 1000) then
			return
		end
		subscribers[guid] = true
		sendAll(player)
	elseif msg.action == "queue" and type(msg.data) == "table" then
		local id = Chaos.toInt(msg.data.id, 1)
		local dg = id and baseDungeons()[id]
		if not dg then
			return
		end

		-- the same button is "Join" and "Leave"
		if queuedIn[guid] then
			leaveQueue(guid, true)
			return
		end

		local difficulty = Chaos.toInt(msg.data.difficulty, 1, cfg.maxDifficulty) or 1
		local problem = entryProblem(player, id, dg, difficulty)
		if problem then
			player:sendCancelMessage(problem)
			send(player, "queue", {id = id, joined = false})
			return
		end

		queues[id] = queues[id] or {}
		queues[id][#queues[id] + 1] = {guid = guid, difficulty = difficulty, joined = os.time()}
		queuedIn[guid] = id
		send(player, "queue", {id = id, joined = true})
		broadcastQueue(id)
		tryMatch(id)
		ensureTicker()
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()

-- opcode 152 "leave_queue" from the notifications module also leaves the dungeon queue
if ChaosNotify then
	local previous = ChaosNotify.onLeaveQueue
	ChaosNotify.onLeaveQueue = function(player)
		leaveQueue(player:getGuid(), true)
		if previous then
			previous(player)
		end
	end
end
