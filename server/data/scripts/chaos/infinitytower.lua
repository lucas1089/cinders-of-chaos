-- game_infinitytower (extended opcode 214)
--
-- Client contract (client/overlay/modules/game_infinitytower/infinity_tower.lua), flat JSON:
--   client -> server  {"action":"request"}                       -> server replies "update"
--                     {"action":"claim","milestoneIndex":N}      -> server replies "update"
--   server -> client  {"action":"open"|"update",
--                      "seasonNum":N, "seasonEnd":unix, "nextTry":unix, "playerPoints":N,
--                      "milestones":[{"points":N,"claimed":bool,
--                                     "items":[{"id":clientId,"count":N,"name":".."}]}],
--                      "rankings":[{"name":"..","floor":N,"time":seconds}]}
--   "open" shows the window, "update" refreshes it if it is already open.
--
-- Implemented: seasons, per-season points / best floor / best time, ranking top 10, milestone
-- claiming with item rewards, "!tower" to open the window, and the tower itself in
-- infinitytower_run.lua ("!tower start" / "!tower leave" / the client's Enter button), which reports each
-- finished run with ChaosTower.recordRun(player, floorsCleared, seconds).
-- NOT implemented: the season-end "top 3 chest" rewards (no script gives them out).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

local OPCODE = ChaosOpcodes.infinitytower
local cfg = Chaos.tower
local T = Chaos.tables.towerPlayers

ChaosTower = ChaosTower or {}

local function currentSeason(now)
	now = now or os.time()
	local length = cfg.seasonLengthDays * 86400
	local number = math.floor((now - cfg.seasonEpoch) / length) + 1
	if number < 1 then
		number = 1
	end
	return number, cfg.seasonEpoch + number * length
end

local function loadPlayerRow(guid, season)
	db.query("INSERT IGNORE INTO `" .. T .. "` (`player_id`, `season`) VALUES (" .. guid .. ", " .. season .. ")")
	local rows = Chaos.select(
		"SELECT `points`, `best_floor`, `best_time`, `claimed_mask`, `last_attempt` FROM `" .. T ..
			"` WHERE `player_id` = " .. guid .. " AND `season` = " .. season,
		{{"points", "n"}, {"best_floor", "n"}, {"best_time", "n"}, {"claimed_mask", "n"}, {"last_attempt", "n"}}
	)
	return rows[1] or {points = 0, best_floor = 0, best_time = 0, claimed_mask = 0, last_attempt = 0}
end

local function hasBit(mask, index)
	return math.floor(mask / (2 ^ (index - 1))) % 2 == 1
end

local function buildPayload(player)
	local season, seasonEnd = currentSeason()
	local row = loadPlayerRow(player:getGuid(), season)

	local milestones = {}
	for i, milestone in ipairs(cfg.milestones) do
		local items = {}
		for j, item in ipairs(milestone.items) do
			local itemType = ItemType(item.id)
			items[j] = {
				id = itemType:getId() ~= 0 and itemType:getClientId() or item.id,
				count = item.count,
				name = item.name or itemType:getName()
			}
		end
		milestones[i] = {points = milestone.points, claimed = hasBit(row.claimed_mask, i), items = items}
	end

	local rankings = {}
	local ranks = Chaos.select(
		"SELECT p.`name` AS `name`, t.`best_floor` AS `floor_n`, t.`best_time` AS `time_s` FROM `" .. T ..
			"` t JOIN `players` p ON p.`id` = t.`player_id` WHERE t.`season` = " .. season ..
			" AND t.`best_floor` > 0 ORDER BY t.`best_floor` DESC, t.`best_time` ASC LIMIT " .. cfg.rankingSize,
		{{"name", "s"}, {"floor_n", "n"}, {"time_s", "n"}}
	)
	for i, rank in ipairs(ranks) do
		rankings[i] = {name = rank.name, floor = rank.floor_n, time = rank.time_s}
	end

	local nextTry = 0
	if cfg.tryCooldownSeconds > 0 and row.last_attempt > 0 then
		nextTry = row.last_attempt + cfg.tryCooldownSeconds
	end

	return {
		seasonNum = season,
		seasonEnd = seasonEnd,
		nextTry = nextTry,
		playerPoints = row.points,
		milestones = milestones,
		rankings = rankings
	}
end

local function sendTower(player, action)
	local payload = buildPayload(player)
	payload.action = action
	player:sendExtendedOpcode(OPCODE, json.encode(payload))
end

function ChaosTower.open(player)
	sendTower(player, "open")
end

-- Report a finished tower run. floorsCleared >= 0, seconds = total run time.
function ChaosTower.recordRun(player, floorsCleared, seconds)
	floorsCleared = Chaos.toInt(floorsCleared, 0) or 0
	seconds = Chaos.toInt(seconds, 0) or 0
	local guid = player:getGuid()
	local season = currentSeason()
	local row = loadPlayerRow(guid, season)

	local eventMult = ChaosEvents and ChaosEvents.bonus("towerPoints") or 1
	local points = row.points + math.floor(floorsCleared * cfg.pointsPerFloor * eventMult)
	local bestFloor, bestTime = row.best_floor, row.best_time
	if floorsCleared > bestFloor or (floorsCleared == bestFloor and floorsCleared > 0 and (bestTime == 0 or seconds < bestTime)) then
		bestFloor, bestTime = floorsCleared, seconds
	end
	db.query(
		"UPDATE `" .. T .. "` SET `points` = " .. points .. ", `best_floor` = " .. bestFloor .. ", `best_time` = " .. bestTime ..
			", `last_attempt` = " .. os.time() .. " WHERE `player_id` = " .. guid .. " AND `season` = " .. season
	)
	sendTower(player, "update")
end

-- true if the player's try cooldown (if any) has elapsed
function ChaosTower.canEnter(player)
	if cfg.tryCooldownSeconds <= 0 then
		return true
	end
	local row = loadPlayerRow(player:getGuid(), (currentSeason()))
	return os.time() >= row.last_attempt + cfg.tryCooldownSeconds
end

local function claim(player, index)
	index = Chaos.toInt(index, 1, #cfg.milestones)
	if not index then
		return
	end
	local guid = player:getGuid()
	local season = currentSeason()
	local row = loadPlayerRow(guid, season)
	local milestone = cfg.milestones[index]

	if hasBit(row.claimed_mask, index) then
		player:sendCancelMessage("You already claimed this reward.")
	elseif row.points < milestone.points then
		player:sendCancelMessage("You do not have enough Tower Points yet.")
	else
		-- all-or-nothing: roll back anything already handed over if one item does not fit
		local granted = {}
		local ok = true
		for _, item in ipairs(milestone.items) do
			local given = Chaos.giveItem(player, item.id, item.count)
			if given > 0 then
				granted[#granted + 1] = {id = item.id, count = given}
			end
			if given < item.count then
				ok = false
				break
			end
		end
		if ok then
			local mask = row.claimed_mask + 2 ^ (index - 1)
			db.query(
				"UPDATE `" .. T .. "` SET `claimed_mask` = " .. string.format("%d", mask) ..
					" WHERE `player_id` = " .. guid .. " AND `season` = " .. season
			)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("You claimed the %d point Infinity Tower reward.", milestone.points))
		else
			for _, g in ipairs(granted) do
				player:removeItem(g.id, g.count)
			end
			player:sendCancelMessage("You do not have enough room or capacity for the reward.")
		end
	end
	sendTower(player, "update")
end

local LoginEvent = CreatureEvent("ChaosTowerLogin")

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosTowerExtended")
	return true
end

local ExtendedEvent = CreatureEvent("ChaosTowerExtended")

function ExtendedEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	if msg.action == "enter" then
		if ChaosTowerRun then
			ChaosTowerRun.start(player)
		end
	elseif msg.action == "request" then
		sendTower(player, "update")
	elseif msg.action == "claim" then
		claim(player, msg.milestoneIndex)
	elseif msg.action == "leave" then
		if ChaosTowerRun then
			ChaosTowerRun.leave(player)
		end
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()

-- /towerrun <floors>,<seconds> : staff test helper, records a fake run for yourself so the
-- window, ranking and milestones can be checked without the (missing) tower gameplay.
local testTalk = TalkAction("/towerrun")

function testTalk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local floors, seconds = param:match("^%s*(%d+)%s*,%s*(%d+)%s*$")
	if not floors then
		player:sendCancelMessage("Usage: /towerrun <floors>,<seconds>")
		return false
	end
	ChaosTower.recordRun(player, tonumber(floors), tonumber(seconds))
	return false
end

testTalk:separator(" ")
testTalk:register()
