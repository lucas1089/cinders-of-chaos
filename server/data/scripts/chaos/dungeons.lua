-- game_dungeons (extended opcode 109)
--
-- Client contract (client/overlay/modules/game_dungeons/dungeons.lua), {"action":..,"data":..}:
--   client -> server  fetch                                  -> list + dungeon* + solo/group*
--                     queue {id, difficulty}                 -> join; sending it again leaves
--   server -> client  list [{id,title,level,boss=outfit,queue=N}]
--                     dungeon {id,title,difficulty,req,loot,queue={players,estimated},challenges,health?}
--                       health = {monsters = {six %}, boss = {six %}}: only a dungeon with its own health curves (the
--                       Vault, the generated dungeons 6-9; dungeons_difficulty.lua D.healthCurves); without it the
--                       client's panel shows the table's 100-1300%
--                     solo / group {id,diff,top=[{name,time,self?}]}      (time in ms)
--                     queue {id,joined}   stopQueue   queueUpdate {id,queue,estimated}
--                     prepare            start {boss,left,duration,objectives,need}
--                     killed {percent,left} | {unlocked=true,percent,left} | {boss=true}    objective {id,finished}
--                     challenge "<title>"   difficulty {id,difficulty}   finish
--                     open               (the base dungeon entry tile was stepped on: show the window)
--
-- Integration with the base server dungeon system (lib/core/dungeon.lua, global DUNGEON_SYSTEM):
-- the dungeon list, level requirement, group size (AmountParty when NeedParty), DungeonPos,
-- FromPos/ToPos, DungeonTime, SpawnMonsters/Monsters and the cooldown storage are all read from
-- DUNGEON_SYSTEM.Dungeons live. Entry here is by matchmaking queue instead of the modal window: the base
-- entry tile (movements dungeon.lua, item 26702) opens this window (ChaosDungeonsOpen below, wired in by
-- tools/patch_base_dungeon.py), so the old modal run (its own timer, box scan and clean-up) never starts.
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
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
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

local function cooldownSeconds(success)
	if success == false and tonumber(cfg.failCooldownSeconds) then
		return tonumber(cfg.failCooldownSeconds)
	end
	return tonumber(cfg.cooldownSeconds) or (DUNGEON_SYSTEM and DUNGEON_SYSTEM.CooldownTime) or 3600
end

local function extraOf(id)
	return cfg.extra[id] or {}
end

local function titleOf(id, dg)
	return extraOf(id).title or dg.Name
end

-- the largest group a dungeon takes (the base AmountParty when NeedParty, else 1). Since beta feedback 2026-10-22 it is
-- only the maximum: one player may enter alone (cfg.party; the run's monsters scale with its size, dungeons_difficulty.lua)
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

-- The area of a dungeon: the boxes of "who is inside" (the run's members, the login and shutdown checks), its monster
-- count and its clean-up. The base server table is inconsistent for some entries (e.g. Forbidden Chevalier has
-- DungeonPos z=0 but FromPos/ToPos z=7), so the floor range of the base box is widened to include DungeonPos. Where the
-- base box misses part of the dungeon (its boss room, its lower floors, even its entry point: Chaos.dungeons.extra[id].area,
-- server/README.md "dungeons"), the extra boxes are part of the area too.
local function boxOf(f, t)
	return {
		x1 = math.min(f.x, t.x), x2 = math.max(f.x, t.x),
		y1 = math.min(f.y, t.y), y2 = math.max(f.y, t.y),
		z1 = math.min(f.z, t.z), z2 = math.max(f.z, t.z)
	}
end

local function areaOf(id, dg)
	local f, t, d = dg.FromPos, dg.ToPos, dg.DungeonPos
	local base = boxOf(f, t)
	base.z1, base.z2 = math.min(base.z1, d.z), math.max(base.z2, d.z)
	local boxes = {base}
	for _, a in ipairs(extraOf(id).area or {}) do
		boxes[#boxes + 1] = boxOf(a[1], a[2])
	end
	return boxes
end

local function inAnyBox(boxes, pos, upTo)
	for i = 1, upTo or #boxes do
		local b = boxes[i]
		if pos.x >= b.x1 and pos.x <= b.x2 and pos.y >= b.y1 and pos.y <= b.y2 and pos.z >= b.z1 and pos.z <= b.z2 then
			return true
		end
	end
	return false
end

local function inBox(id, dg, pos)
	return inAnyBox(areaOf(id, dg), pos)
end

-- monsters / players inside the dungeon area. bossName is lower case.
local function scanArea(id, dg, bossName)
	local boxes = areaOf(id, dg)
	local monsters, bosses, players, monsterList = 0, 0, 0, {}
	for i, b in ipairs(boxes) do
		local rx = math.ceil((b.x2 - b.x1) / 2)
		local ry = math.ceil((b.y2 - b.y1) / 2)
		local cx, cy = b.x1 + rx, b.y1 + ry
		for z = b.z1, b.z2 do
			local list = Game.getSpectators(Position(cx, cy, z), false, false, rx, rx, ry, ry)
			for _, creature in ipairs(list) do
				local pos = creature:getPosition()
				-- in this box and not in an earlier one (boxes may overlap: every creature counts once)
				if inAnyBox({b}, pos) and not inAnyBox(boxes, pos, i - 1) then
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

-- the run's length: the base server's DungeonTime, at most cfg.maxTimeSeconds (instance limits)
local function durationOf(dg)
	local t = dg.DungeonTime or 3600
	if (cfg.maxTimeSeconds or 0) > 0 then
		t = math.min(t, cfg.maxTimeSeconds)
	end
	return t * 1000
end

local function queueInfo(id, dg)
	local waiting = queues[id] and #queues[id] or 0
	-- the longest wait for a start: a full group goes at once, anyone else after soloWaitSeconds (a partner may join)
	local estimated = (waiting >= groupSizeOf(dg)) and 0 or ((cfg.party and cfg.party.soloWaitSeconds or 0) * 1000)
	-- a run inside: the queue waits at least for its end (instance limits: the wait the window shows)
	local run = runOfDungeon[id]
	if run and not run.ended then
		estimated = math.max(estimated, run.startedAt + (run.durationMs or durationOf(dg)) - nowMs() + cfg.exitDelayMs)
	end
	return {players = waiting, estimated = math.max(0, estimated)}
end

local function bossOutfit(id)
	local bossName = extraOf(id).bossName
	local outfit = {lookType = 0}
	if bossName then
		local monsterType = MonsterType(extraOf(id).bossType or bossName) -- bossType: a boss with a shown name (areagen.lua)
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

-- The "Potential Boss Loot" panel (28 slots): what the dungeon's config lists first (the crystal coins of the clear),
-- then what the boss monster can really drop (MonsterType:getLoot(), the rarest first, each item once). Display only:
-- the real loot is what the boss drops (owner 2026-10-17: the panel showed 3 crystal coins and nothing else). Each slot
-- carries the item's name for the client's tooltip.
local LOOT_SLOTS = 28
local function bossLootPanel(extra)
	local loot, seen = {}, {}
	local function push(itemId, count)
		if #loot >= LOOT_SLOTS or seen[itemId] then
			return
		end
		local itemType = ItemType(itemId)
		if not itemType or itemType:getId() == 0 then
			return
		end
		seen[itemId] = true
		loot[#loot + 1] = {clientId = itemType:getClientId(), count = math.max(1, count or 1), name = itemType.getName and itemType:getName() or nil}
	end
	for _, item in ipairs(extra.loot or {}) do
		local itemType = ItemType(item.id)
		if itemType and itemType:getId() ~= 0 then
			seen[item.id] = true
			loot[#loot + 1] = {clientId = itemType:getClientId(), count = item.count, name = itemType.getName and itemType:getName() or nil}
		else
			loot[#loot + 1] = {clientId = item.id, count = item.count}
		end
	end
	local name = extra.bossType or extra.bossName
	local monsterType = name and MonsterType and MonsterType(name)
	if monsterType and monsterType.getLoot then
		local rows = {}
		for _, e in ipairs(monsterType:getLoot() or {}) do
			if e.itemId and (e.chance or 0) > 0 then
				rows[#rows + 1] = e
			end
		end
		table.sort(rows, function(a, b)
			if (a.chance or 0) ~= (b.chance or 0) then
				return (a.chance or 0) < (b.chance or 0)
			end
			return (a.itemId or 0) < (b.itemId or 0)
		end)
		for _, e in ipairs(rows) do
			push(e.itemId, e.maxCount)
		end
	end
	return loot
end

local function dungeonPayload(player, id, dg)
	local extra = extraOf(id)
	local progress = loadProgress(player:getGuid(), id)

	local req = {level = levelOf(dg)}
	if dg.NeedParty then
		req.party = "1-" .. groupSizeOf(dg) -- solo allowed, a group up to this size
	end

	local loot = bossLootPanel(extra)

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
		challenges = challenges,
		-- the dungeon's own health curves for the difficulty panel (nil: the table's, old clients ignore it)
		health = DIFF.healthCurves(extra.bossName and extra.bossHealth or nil, extra.trashHealth)
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

Chaos.registerInstance("dungeon", {label = "a dungeon", inside = ChaosDungeonIsInside, at = function(pos)
	for did, dg in pairs(baseDungeons()) do
		if dg.FromPos and dg.ToPos and dg.DungeonPos and inBox(did, dg, pos) then
			return true
		end
	end
	return false
end, runs = function() -- /instances (instance_limits.lua)
	local out = {}
	for id, run in pairs(runs) do
		local dg = baseDungeons()[run.dungeonId]
		local n = 0
		for _ in pairs(run.members) do
			n = n + 1
		end
		out[#out + 1] = {id = id, what = string.format("%s, difficulty %d", dg and titleOf(run.dungeonId, dg) or "?", run.difficulty),
			left = math.max(0, math.floor((run.startedAt + (run.durationMs or 0) - nowMs()) / 1000)), players = n,
			note = (queues[run.dungeonId] and #queues[run.dungeonId] or 0) .. " queued"}
	end
	return out
end, close = function(id) -- the failure rule of a time-out: everyone out where they entered, the cooldown
	local run = runs[tonumber(id) or -1]
	if not run or run.ended or not ChaosDungeons or not ChaosDungeons.endRun then
		return false, "No running dungeon run " .. tostring(id) .. "."
	end
	ChaosDungeons.endRun(run, false, "A gamemaster closed the dungeon.")
	return true, "Dungeon run " .. id .. " closed."
end})

local function entryProblem(player, id, dg, difficulty)
	local guid = player:getGuid()
	if runOfPlayer[guid] then
		return Chaos.t(player, "You are already inside a dungeon.")
	end
	if inBox(id, dg, player:getPosition()) then
		return Chaos.t(player, "You cannot queue from inside the dungeon.")
	end
	-- the run teleports from wherever the player stands: without this a fight (or a chase) could be left by queueing.
	-- Checked again on every queue tick (tryMatch), so fighting while queued drops the player from the queue
	if player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT) then
		return Chaos.t(player, "You cannot enter a dungeon while you are in a fight.")
	end
	if Chaos.isMultiClient(player) then
		return Chaos.t(player, Chaos.multiClient.msgDungeon)
	end
	if player:getLevel() < levelOf(dg) then
		return Chaos.t(player, baseMessage("MsgNeedLevel", "You need level %s."), levelOf(dg))
	end
	local storage = cooldownStorage()
	if storage and not (ChaosBetaMode and ChaosBetaMode.lifted("dungeon_cooldown")) then -- beta test mode: no cooldown
		local remaining = player:getStorageValue(storage) - os.time()
		if remaining > 0 then
			return Chaos.t(player, "You are in cooldown for dungeons. Wait %d minute(s).", math.ceil(remaining / 60))
		end
	end
	if difficulty > loadProgress(guid, id).difficulty then
		return Chaos.t(player, "That difficulty is still locked.")
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
	local ex = extraOf(run.dungeonId)
	local hp
	local partyHp = DIFF.partyHealth(run.size or 1, cfg.party)
	if ex.bossHealth and ex.bossName and monster:getName():lower() == ex.bossName:lower() then
		hp = DIFF.bossHealth(monster:getMaxHealth(), run.difficulty, ex.bossHealth)
	elseif ex.trashHealth then
		-- a generated dungeon's own trash curve (areagen_config.lua trashHealth: a run of about 10-15 minutes)
		hp = DIFF.bossHealth(monster:getMaxHealth(), run.difficulty, ex.trashHealth)
	else
		hp = DIFF.health(monster:getMaxHealth(), run.difficulty)
	end
	hp = math.max(1, math.floor(hp * partyHp + 0.5)) -- group size (solo = x1.0)
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

local function cleanArea(id, dg, bossName)
	local _, _, _, monsterList = scanArea(id, dg, bossName)
	for _, monster in ipairs(monsterList) do
		monster:remove()
	end
end

-- success: the run was cleared. Chaos.dungeons cooldownOnSuccess / cooldownOnFail decide (by default only a clear)
local function setCooldown(player, success)
	if success and cfg.cooldownOnSuccess == false or not success and not cfg.cooldownOnFail then
		return
	end
	local storage = cooldownStorage()
	if storage and not (ChaosBetaMode and ChaosBetaMode.lifted("dungeon_cooldown")) then -- beta test mode: none is set
		player:setStorageValue(storage, os.time() + cooldownSeconds(success and true or false))
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
			if dg and inBox(run.dungeonId, dg, p:getPosition()) then
				local origin = run.members[p:getGuid()]
				p:teleportTo(origin or p:getTown():getTemplePosition())
				p:getPosition():sendMagicEffect(40)
				if not success then
					p:popupFYI(Chaos.t(p, reason or baseMessage("ToFail", "You were unable to complete the dungeon in time.")))
				end
			end
			setCooldown(p, success)
		end
		for guid in pairs(run.members) do
			releasePlayer(run, guid)
		end
		runs[run.id] = nil
		if dg then
			cleanArea(run.dungeonId, dg, extra.bossName and extra.bossName:lower() or nil)
		end
		forgetRun(run)
		runOfDungeon[run.dungeonId] = nil
		broadcastQueue(run.dungeonId) -- the wait shown in the window drops
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
		if ChaosRecords and ChaosRecords.dungeonClear then
			pcall(ChaosRecords.dungeonClear, {dungeonId = run.dungeonId,
				title = dg and titleOf(run.dungeonId, dg) or ("Dungeon " .. tostring(run.dungeonId)),
				difficulty = run.difficulty, difficultyStart = run.difficultyStart or run.difficulty,
				ms = elapsed, members = memberInfo})
		end
	end

	for _, p in ipairs(memberPlayers(run)) do
		local guid = p:getGuid()
		send(p, "killed", {boss = true})
		if ChaosSeasonJourney and ChaosSeasonJourney.emit then -- Seasonal Journey (season_journey.lua)
			ChaosSeasonJourney.emit(p, "dungeon_clears", 1)
		end
		if ChaosCharms and ChaosCharms.onSource then -- a charm drop (charms.lua)
			pcall(ChaosCharms.onSource, p, "dungeon", {difficulty = run.difficulty})
		end

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
		-- item sets (itemsets.lua): a chase roll over the dungeon sets on a clear
		if ChaosItemSets and ChaosItemSets.grantChase then
			ChaosItemSets.grantChase(p, "dungeon", nil, {difficulty = run.difficulty})
		end
		-- Conquest Tokens (conquest.lua) for the clear, by the difficulty step
		if ChaosConquest and ChaosConquest.reward then
			pcall(ChaosConquest.reward, p, "dungeon_clear", {difficulty = run.difficulty}, "dungeon " .. tostring(run.dungeonId))
		end
		-- a generated dungeon's boss chest and achievement counters (areagen.lua registerDungeon)
		if extra.onClear then
			pcall(extra.onClear, p, {difficulty = run.difficulty, ms = elapsed, deaths = run.deaths})
		end
	end

	addEvent(function(runId)
		-- `run` is still referenced here; runs[] only guards the tick
		teardown()
	end, cfg.exitDelayMs, run.id)
end

ChaosDungeons = ChaosDungeons or {}
ChaosDungeons.endRun = endRun
-- true when pos lies in the area of base dungeon `id` (the boxes a run uses for "who is inside")
function ChaosDungeons.inside(id, pos)
	local dg = baseDungeons()[id]
	return dg ~= nil and dg.FromPos ~= nil and dg.ToPos ~= nil and dg.DungeonPos ~= nil and inBox(id, dg, pos)
end

-- ------------------------------------------------------------------ map spawns
-- The map's own spawn system makes monsters come back inside a running dungeon, and they were not part of the count
-- the run was started with (a dungeon never reached its percentage). So: (1) every monster the map places at the server
-- start inside a dungeon area is remembered (name and tile); (2) a run starts by clearing its area and creating all of
-- them at once; (3) while a run lasts, the map's own respawn inside its area is refused (EventCallback onSpawn: a
-- spawn that is neither the server start nor made by a script). The area spawns again when the run is over.
local mapSpawns = {} -- [dungeonId] = { {name = , pos = }, ... }

local function dungeonIdAt(pos)
	for id, dg in pairs(baseDungeons()) do
		if dg.FromPos and dg.ToPos and dg.DungeonPos and inBox(id, dg, pos) then
			return id, dg
		end
	end
	return nil
end

local function runAt(pos)
	-- a cleared run stays in runs[] until its teardown (exitDelayMs after the boss died): the players are still inside, so
	-- the map must not respawn the boss or the trash in that window either (runs[] is cleared by teardown / the tick)
	for _, run in pairs(runs) do
		local dg = baseDungeons()[run.dungeonId]
		if dg and dg.FromPos and inBox(run.dungeonId, dg, pos) then
			return run
		end
	end
	return nil
end

-- the base dungeon's own spawn list (dg.Monsters, SpawnMonsters) is created by startRun already; the map's are these
local function fillFromMap(dungeonId, dg, bossName)
	local list = mapSpawns[dungeonId]
	if not list or #list == 0 then
		return 0 -- no start-up record (scripts reloaded, or a generated dungeon): the monsters that stand there stay
	end
	cleanArea(dungeonId, dg, bossName)
	local made = 0
	for _, e in ipairs(list) do
		local m = Game.createMonster(e.name, Position(e.pos.x, e.pos.y, e.pos.z), false, true)
		if m then
			made = made + 1
			if ChaosPace and ChaosPace.mark then
				ChaosPace.mark(m)
			end
		end
	end
	return made
end

local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	if artificial then
		return true -- made by a script (the run's own monsters, summons, bosses, adds)
	end
	if startup then
		local id = dungeonIdAt(position)
		if id and not self:getMaster() then
			local list = mapSpawns[id]
			if not list then
				list = {}
				mapSpawns[id] = list
			end
			list[#list + 1] = {name = self:getName(), pos = {x = position.x, y = position.y, z = position.z}}
		end
		return true
	end
	if runAt(position) then
		return false -- no respawn inside a running dungeon
	end
	return true
end
spawnCb:register(5)

local function startRun(dungeonId, difficulty, players)
	local dg = baseDungeons()[dungeonId]
	local extra = extraOf(dungeonId)
	local bossName = extra.bossName and extra.bossName:lower() or nil

	local run = {
		id = nextRunId,
		dungeonId = dungeonId,
		difficulty = difficulty,
		difficultyStart = difficulty, -- competitive records: a run whose difficulty changed is not valid
		members = {}, -- [guid] = origin Position
		startedAt = nowMs(),
		deaths = 0,
		lastPercent = -1,
		total = 0,
		missingTicks = 0,
		bossSeen = false,
		size = #players -- party size: the monsters' health and damage scale with it (cfg.party)
	}
	nextRunId = nextRunId + 1
	runs[run.id] = run
	runOfDungeon[dungeonId] = run

	if dg.SpawnMonsters and dg.Monsters then
		for monsterName, position in pairs(dg.Monsters) do
			local m = Game.createMonster(monsterName, position)
			-- pack combat (pace.lua): a base dungeon's monsters are paced like the map's (bosses never)
			if m and ChaosPace and ChaosPace.mark then
				ChaosPace.mark(m)
			end
		end
	end
	-- the map's monsters all stand there from the first second (see "map spawns")
	fillFromMap(dungeonId, dg, bossName)
	-- a generated dungeon (areagen.lua) fills its spawn points and its boss for every run
	if extra.populate then
		pcall(extra.populate, dungeonId)
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

	local monsters, bosses, _, monsterList = scanArea(dungeonId, dg, bossName)
	run.total = monsters
	run.bossSeen = bosses > 0
	scaleList(run, monsterList)

	local durationMs = durationOf(dg)
	run.durationMs = durationMs
	local objectives = {}
	for i, ch in ipairs(extra.challenges or {}) do
		objectives[i] = ch.title
	end
	for _, p in ipairs(players) do
		send(p, "start", {
			boss = bossName and extra.bossName or "the boss",
			left = monsters,
			duration = durationMs,
			need = cfg.progressNeeded,
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

-- the run reached Chaos.dungeons.progressNeeded (85% of its monsters dead): the boss is unlocked. Every member gets
-- the line and the kill counter's "Boss unlocked!"; a generated dungeon (areagen.lua) opens its boss room gate and
-- spawns its boss now. Once unlocked, a run is won when the boss dies (adds of the boss fight do not lock it again).
local function unlockBoss(run, extra, percent, left)
	run.unlocked = true
	local boss = tostring(extra.bossName or "the boss"):gsub("(%a)([%w'%-]*)", function(a, b) return a:upper() .. b end)
	for _, p in ipairs(memberPlayers(run)) do
		send(p, "killed", {unlocked = true, percent = percent, left = left})
		p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "Boss unlocked! %d%% of the monsters are dead: %s awaits you.",
			percent, boss))
	end
	if extra.unlock then
		pcall(extra.unlock, run.dungeonId)
	end
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
	local soloWait = (cfg.party and cfg.party.soloWaitSeconds) or 0
	local byDifficulty = {}
	for _, entry in ipairs(queues[id]) do
		local bucket = byDifficulty[entry.difficulty] or {}
		byDifficulty[entry.difficulty] = bucket
		bucket[#bucket + 1] = entry
	end
	local chosenDiff, chosen
	for diff, bucket in pairs(byDifficulty) do
		-- a full group starts now; fewer (down to one player) once the first of them has waited soloWaitSeconds
		local ready = #bucket >= size or os.time() - bucket[1].joined >= soloWait
		if ready and (not chosen or bucket[1].joined < chosen[1].joined) then
			chosenDiff, chosen = diff, bucket
		end
	end
	if not chosen then
		return
	end

	-- the dungeon area must be empty of players (a leftover player means a previous run is not over)
	local _, _, playersInside = scanArea(id, dg, nil)
	if playersInside > 0 then
		return
	end

	local players = {}
	for i = 1, math.min(size, #chosen) do
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
			local monsters, bosses, playersInside, monsterList = scanArea(run.dungeonId, dg, bossName)
			scaleList(run, monsterList) -- respawns inside the box get the difficulty too

			if bosses > 0 then
				run.bossSeen = true
			end

			-- members that left the box (died, logged out, walked out) are released
			for guid in pairs(run.members) do
				local p = online(guid)
				if not p or not inBox(run.dungeonId, dg, p:getPosition()) then
					releasePlayer(run, guid)
					if p then
						send(p, "finish") -- hide the kill counter
						setCooldown(p, false) -- leaving / dying counts as a failed attempt
					end
				end
			end
			if next(run.members) == nil then
				run.ended = true
				runs[runId] = nil
				runOfDungeon[run.dungeonId] = nil
				cleanArea(run.dungeonId, dg, bossName)
				forgetRun(run)
			else
				local percent = 100
				if run.total > 0 then
					percent = math.min(100, math.floor((run.total - monsters) * 100 / run.total))
					percent = math.max(percent, 0)
				end
				-- the counter never goes back (the boss fight's adds and totems are monsters of the box too)
				percent = math.max(percent, run.lastPercent)
				if percent ~= run.lastPercent then
					run.lastPercent = percent
					for _, p in ipairs(memberPlayers(run)) do
						send(p, "killed", {percent = percent, left = monsters})
					end
				end
				if not run.unlocked and percent >= cfg.progressNeeded then
					unlockBoss(run, extra, percent, monsters)
				end
				-- boss seen earlier and gone now (killed by someone onKill did not credit)
				if run.bossSeen and bosses == 0 and run.unlocked then
					endRun(run, true)
				end
				-- warnings before the time runs out (instance limits; the client counts the clock down itself)
				if not run.ended and ChaosInstanceLimits then
					local left = math.floor((run.startedAt + (run.durationMs or 0) - nowMs()) / 1000)
					ChaosInstanceLimits.warn(run, left, memberPlayers(run), titleOf(run.dungeonId, dg), cfg.limits)
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
		if run.unlocked or run.lastPercent >= cfg.progressNeeded or run.total == 0 then
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
	if run and not run.ended and primaryType ~= COMBAT_HEALING
		and not (ChaosBossMech and ChaosBossMech.scriptedHit and ChaosBossMech.scriptedHit(attacker)) then
		-- (a boss mechanic's hit is a share of the victim's max health: not scaled again, boss_mechanics.lua)
		local party = DIFF.partyDamage(run.size or 1, cfg.party)
		primaryDamage = DIFF.damage(primaryDamage, run.difficulty, party)
		secondaryDamage = DIFF.damage(secondaryDamage, run.difficulty, party)
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
	-- A relog while the server runs: the logout already took the character out of its run (it counts as leaving, like
	-- walking out: the cooldown), so it is not left standing in the box, where it would also hold the next group's run
	-- back (instance limits).
	if not runOfPlayer[player:getGuid()] then
		local restart = (player:getLastLogout() or 0) < ChaosDungeonsBoot
		local pos = player:getPosition()
		for did, dg in pairs(baseDungeons()) do
			if dg.FromPos and dg.ToPos and dg.DungeonPos and inBox(did, dg, pos) then
				player:teleportTo(player:getTown():getTemplePosition())
				if restart then
					player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Your dungeon run was cut short by a server restart."))
				else
					setCooldown(player, false)
					player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "You logged out inside the dungeon: your run is over."))
				end
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
					if dg and inBox(run.dungeonId, dg, p:getPosition()) then
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

-- The base dungeon entry tile (data/movements/scripts/dungeon.lua, patched by tools/patch_base_dungeon.py) calls this
-- first: the window opens with the list instead of the base modal window, so every entry goes through the queue.
-- true = handled (the stock modal is not sent), also for a monster or a summon on the tile.
function ChaosDungeonsOpen(creature)
	if not creature or not creature:isPlayer() then
		return true
	end
	-- the list reads progress and rankings from the database: one read a second, as the window's own fetch
	if not ChaosRateLimit or ChaosRateLimit.allow(creature, "dungeons.fetch", 1000) then
		subscribers[creature:getGuid()] = true
		sendAll(creature)
	end
	send(creature, "open", {})
	return true
end

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
