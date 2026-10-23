-- game_infinitytower (extended opcode 214)
--
-- Client contract (client/overlay/modules/game_infinitytower/infinity_tower.lua), flat JSON:
--   client -> server  {"action":"request"}                       -> server replies "update"
--                     {"action":"claim","milestoneIndex":N}      -> server replies "update"
--   server -> client  {"action":"open"|"update",
--                      "seasonNum":N, "seasonEnd":unix, "nextTry":unix, "playerPoints":N,
--                      "milestones":[{"points":N,"claimed":bool,
--                                     "items":[{"id":clientId,"count":N,"name":".."}]}],
--                      "rankings":[{"name":"..","floor":N,"time":seconds}],
--                      "topRewards":[{"place":N,"name":"Gold Tower Chest","id":clientId,"text":"..",
--                                     "items":[{"name":"..","count":N}]}],
--                      "floorRewards":{"every":5,"paid":N,"nextFloor":N,"text":"Next reward: floor 15, ...",
--                                      "first":[{"id":clientId,"count":N,"name":".."}],"repeatable":[..]}}
--   floorRewards (O144): the next milestone floor above the highest one this character was paid this tower season, what
--   its first clear pays (and what it pays every time), and the text in the player's language.
--   "open" shows the window, "update" refreshes it if it is already open.
--
-- Implemented: seasons, per-season points / best floor / best time, ranking top 10, milestone
-- claiming with item rewards, "!tower" to open the window, and the tower itself in
-- infinitytower_run.lua ("!tower start" / "!tower leave" / the client's Enter button), which reports each
-- finished run with ChaosTower.recordRun(player, floorsCleared, seconds).
-- Season end (ChaosTower.checkSeasons, pure part infinitytower_core.lua, numbers Chaos.tower.seasonEnd): the top 3
-- of each ended season get the "Top Rank Rewards" chest of their place once (chaos_tower_season_rewards, server_config
-- chaos_tower_season_done), into the inbox at once or at the next login. Staff: /towerseason status | pay.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end

dofile("data/scripts/chaos/infinitytower_core.lua")
if not ChaosTowerBalanceCore then
	dofile("data/scripts/chaos/infinitytower_balance_core.lua")
end
ChaosTowerBalance = ChaosTowerBalance or dofile("data/scripts/chaos/infinitytower_balance_config.lua")

local OPCODE = ChaosOpcodes.infinitytower
local cfg = Chaos.tower
local T = Chaos.tables.towerPlayers
local T_REWARDS = Chaos.tables.towerSeasonRewards or "chaos_tower_season_rewards"
local K = ChaosTowerCore

ChaosTower = ChaosTower or {}
ChaosTower.lastCheck = ChaosTower.lastCheck or 0

local function log(text)
	print("[Chaos tower] " .. text)
end

local function currentSeason(now)
	local number, _, finish = K.seasonOf(cfg, now or os.time())
	return number, finish
end
ChaosTower.currentSeason = currentSeason

local function clientIdOf(id)
	local it = ItemType(id)
	return it and it:getId() ~= 0 and it:getClientId() or id
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

	local floorRewards
	if ChaosTowerBalance and ChaosTowerBalanceCore then
		local BC, B = ChaosTowerBalance, ChaosTowerBalanceCore
		local okv, value = pcall(player.getStorageValue, player, BC.rewards.storage)
		local paid = B.stored(okv and value or 0, season)
		local nm = B.nextMilestone(BC, paid)
		local function listOf(items)
			local out = {}
			for i, it in ipairs(items) do
				out[i] = {id = clientIdOf(it.id), count = it.count, name = it.name}
			end
			return out
		end
		floorRewards = {every = BC.milestoneEvery, paid = paid, nextFloor = nm}
		if nm then
			floorRewards.first = listOf(B.rewardItems(BC.rewards.firstClear, nm))
			floorRewards.repeatable = listOf(B.rewardItems(BC.rewards.repeatable, nm))
			local okt, text = pcall(function()
				return ChaosTowerRun and ChaosTowerRun.nextRewardText and ChaosTowerRun.nextRewardText(player, paid)
			end)
			floorRewards.text = okt and text or nil
		end
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
		rankings = rankings,
		topRewards = cfg.seasonEnd and K.topRewards(cfg.seasonEnd, clientIdOf) or nil,
		floorRewards = floorRewards
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
		player:sendCancelMessage(Chaos.t(player, "You already claimed this reward."))
	elseif row.points < milestone.points then
		player:sendCancelMessage(Chaos.t(player, "You do not have enough Tower Points yet."))
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
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "You claimed the %d point Infinity Tower reward.", milestone.points))
		else
			for _, g in ipairs(granted) do
				player:removeItem(g.id, g.count)
			end
			player:sendCancelMessage(Chaos.t(player, "You do not have enough room or capacity for the reward."))
		end
	end
	sendTower(player, "update")
end

-- ---------------------------------------------------------------- season end: the top 3 chests
function ChaosTower.ensureTable()
	db.query("CREATE TABLE IF NOT EXISTS `" .. T_REWARDS .. "` (`season` int(10) unsigned NOT NULL, `player_id` int(11) " ..
		"NOT NULL, `place` tinyint(3) unsigned NOT NULL, `best_floor` int(10) unsigned NOT NULL DEFAULT 0, `best_time` " ..
		"int(10) unsigned NOT NULL DEFAULT 0, `chest` varchar(32) NOT NULL DEFAULT '', `rewarded` tinyint(1) unsigned NOT " ..
		"NULL DEFAULT 0, `awarded_at` int(10) unsigned NOT NULL DEFAULT 0, `delivered_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`season`, `player_id`), KEY `chaos_tower_season_rewards_pending` (`player_id`, `rewarded`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8")
end

local function getConfig(key)
	local id = db.storeQuery("SELECT `value` FROM `server_config` WHERE `config` = " .. db.escapeString(key))
	if not id then
		return nil
	end
	local v = result.getString(id, "value")
	result.free(id)
	return tonumber(v)
end

local function setConfig(key, value)
	db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s) ON DUPLICATE KEY UPDATE " ..
		"`value` = VALUES(`value`)", db.escapeString(key), db.escapeString(tostring(value))))
end

local function chestByName(name)
	for place, chest in ipairs(cfg.seasonEnd.chests) do
		if chest.name == name then
			return chest, place
		end
	end
	return nil
end

-- the chest item with its contents; what does not fit the chest goes into the inbox loose
local function packChest(chest, season, place)
	local item = Game.createItem(chest.chestId, 1)
	if not item then
		return nil, chest.items
	end
	item:setAttribute(ITEM_ATTRIBUTE_NAME, chest.name)
	if ITEM_ATTRIBUTE_DESCRIPTION then
		item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, string.format("Infinity Tower Season %d, %s place.", season,
			K.placeNames[place] or ("#" .. place)))
	end
	local container = Container(item:getUniqueId())
	local loose = {}
	for _, it in ipairs(chest.items) do
		if not (container and container:addItem(it.id, it.count)) then
			loose[#loose + 1] = it
		end
	end
	return item, loose
end

-- deliver every unpaid chest of this character (any season) into its inbox
function ChaosTower.deliverPending(player)
	local guid = player:getGuid()
	local rows = Chaos.select(string.format("SELECT `season`, `place`, `best_floor`, `chest` FROM `%s` WHERE `player_id` = %d " ..
		"AND `rewarded` = 0 ORDER BY `season`", T_REWARDS, guid), {{"season", "n"}, {"place", "n"}, {"best_floor", "n"},
		{"chest", "s"}})
	local inbox = #rows > 0 and player:getInbox() or nil
	local n = 0
	for _, r in ipairs(rows) do
		local chest = chestByName(r.chest) or cfg.seasonEnd.chests[r.place]
		if not inbox or not chest then
			break -- left unpaid: the next login tries again
		end
		-- marked first: a failure below never pays twice (the log names what was lost)
		db.query(string.format("UPDATE `%s` SET `rewarded` = 1, `delivered_at` = %d WHERE `season` = %d AND `player_id` = %d " ..
			"AND `rewarded` = 0", T_REWARDS, os.time(), r.season, guid))
		local item, loose = packChest(chest, r.season, r.place)
		if item then
			inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		end
		for _, it in ipairs(loose) do
			local rest = it.count
			while rest > 0 do
				local c = math.min(rest, 100)
				inbox:addItem(it.id, c, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
				rest = rest - c
			end
		end
		n = n + 1
		local text = string.format("Infinity Tower Season %d has ended: %s place with floor %d. Your %s is in your inbox.",
			r.season, K.placeNames[r.place] or ("#" .. r.place), r.best_floor, K.chestText(chest))
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
		if ChaosNotify and ChaosNotify.send then
			pcall(ChaosNotify.send, player, "Infinity Tower", text, "achievement")
		end
		pcall(function()
			player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
		end)
		log(string.format("season %d: %s delivered to %s", r.season, chest.name, player:getName()))
	end
	return n
end

-- the awards of an ended season, written once (INSERT IGNORE on season + character)
function ChaosTower.processSeason(season)
	local rows = Chaos.select(string.format("SELECT t.`player_id`, p.`name`, p.`group_id`, t.`best_floor`, t.`best_time` " ..
		"FROM `%s` t JOIN `players` p ON p.`id` = t.`player_id` WHERE t.`season` = %d AND t.`best_floor` > 0", T, season),
		{{"player_id", "n"}, {"name", "s"}, {"group_id", "n"}, {"best_floor", "n"}, {"best_time", "n"}})
	local list = {}
	for _, r in ipairs(rows) do
		list[#list + 1] = {guid = r.player_id, name = r.name, group = r.group_id, floor = r.best_floor, time = r.best_time}
	end
	-- characters held for an anti-bot review get nothing (antibot.lua; off unless log.holdLeaderboards)
	if ChaosAntibot and ChaosAntibot.filterRanked then
		list = ChaosAntibot.filterRanked(list)
	end
	local awards = K.awards(K.places(list, cfg.seasonEnd.staffGroup), cfg.seasonEnd)
	for _, a in ipairs(awards) do
		db.query(string.format("INSERT IGNORE INTO `%s` (`season`, `player_id`, `place`, `best_floor`, `best_time`, `chest`, " ..
			"`rewarded`, `awarded_at`) VALUES (%d, %d, %d, %d, %d, %s, 0, %d)", T_REWARDS, season, a.guid, a.place, a.floor,
			a.time, db.escapeString(a.chest.name), os.time()))
	end
	return awards
end

-- pays every ended season not paid yet (server_config configKey); startup = no broadcast
function ChaosTower.checkSeasons(startup, now)
	local se = cfg.seasonEnd
	local current = currentSeason(now)
	local done = getConfig(se.configKey)
	local pending = K.pendingSeasons(done, current)
	if not pending then
		setConfig(se.configKey, current - 1) -- a new server: nothing earlier to pay out
		return 0
	end
	local paid = 0
	for _, s in ipairs(pending) do
		local ok, awards = pcall(ChaosTower.processSeason, s)
		if not ok then
			log("season " .. s .. " end failed: " .. tostring(awards))
			return paid
		end
		setConfig(se.configKey, s)
		paid = paid + 1
		local names = {}
		for _, a in ipairs(awards) do
			names[#names + 1] = string.format("%s %s (floor %d)", K.placeNames[a.place] or ("#" .. a.place), a.name, a.floor)
		end
		local text = string.format("Infinity Tower Season %d has ended.%s Season %d begins.", s,
			#names > 0 and (" Top Rank Rewards: " .. table.concat(names, ", ") .. ".") or "", s + 1)
		log(text)
		if not startup then
			Chaos.broadcast(MESSAGE_EVENT_ADVANCE, text)
		end
	end
	if paid > 0 then
		for _, p in ipairs(Game.getPlayers()) do
			ChaosTower.deliverPending(p)
		end
	end
	return paid
end

local LoginEvent = CreatureEvent("ChaosTowerLogin")

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosTowerExtended")
	if cfg.seasonEnd then
		local ok, err = pcall(ChaosTower.deliverPending, player)
		if not ok then
			log("delivery at login: " .. tostring(err))
		end
	end
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
	-- per action (ratelimit.lua): requests that hit the database cannot be flooded
	if Chaos.limited and Chaos.limited(player, "tower." .. tostring(msg.action), 300) then
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

-- /towerseason [status | pay] : staff. status = the season, its end and the last season paid out; pay = run the
-- season-end check now (pays only seasons that have ended; idempotent).
local seasonTalk = TalkAction("/towerseason")

function seasonTalk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	param = (param or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if param == "pay" then
		local n = ChaosTower.checkSeasons(false)
		player:sendTextMessage(MESSAGE_INFO_DESCR, n > 0 and (n .. " ended season(s) paid out.") or "No ended season to pay out.")
	else
		local season, finish = currentSeason()
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Tower Season %d ends %s. Last season paid out: %s.",
			season, os.date("%Y-%m-%d %H:%M", finish), tostring(getConfig(cfg.seasonEnd.configKey) or Chaos.t(player, "none"))))
	end
	return false
end

seasonTalk:separator(" ")
seasonTalk:register()

if cfg.seasonEnd then
	local startup = GlobalEvent("ChaosTowerSeasonStartup")
	function startup.onStartup()
		local ok, err = pcall(function()
			ChaosTower.ensureTable()
			ChaosTower.checkSeasons(true)
		end)
		if not ok then
			log("season startup: " .. tostring(err))
		end
		return true
	end
	startup:type("startup")
	startup:register()

	local think = GlobalEvent("ChaosTowerSeasonThink")
	function think.onThink(interval)
		local now = os.time()
		if now - ChaosTower.lastCheck >= (cfg.seasonEnd.checkSeconds or 60) then
			ChaosTower.lastCheck = now
			local ok, err = pcall(ChaosTower.checkSeasons, false)
			if not ok then
				log("season check: " .. tostring(err))
			end
		end
		return true
	end
	think:interval(10000)
	think:register()
end
