-- game_daily (extended opcode 207)
--
-- Client contract (client/overlay/modules/game_daily/daily.lua):
--   server -> client  {"action":"OpenDailyWindow",
--                      "data":{"Day":d, "TakenReward":0|1,
--                              "DAILY_REWARDS":[{"ClientID":id,"Count":n} x7]}}
--   client -> server  {"action":"calim","data":v}      ("calim" is the client's spelling)
--
-- Quirks of the shipped client that this file compensates for:
--   * the client does Day = Day + 2 on receipt, so we send Day = slot - 2.
--   * the client answers a claim with v = map[slot] where map = {6,7,1,2,3,4,5}; we invert
--     that to get the slot back: slot = ((v + 1) % 7) + 1.
--   * DAILY_REWARDS[i] is drawn in slot i, so it is sent in plain slot order 1..7.
--
-- State (player storages): streak slot 1..7 of the last claim, and YYYYMMDD of that claim.
-- Claiming on consecutive days advances the slot (7 wraps to 1); missing a day restarts at 1.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

local OPCODE = ChaosOpcodes.daily
local cfg = Chaos.daily
local S = Chaos.storage

-- returns slot (1..7) that is claimable today or was claimed today, and whether it was taken
local function getState(player)
	local today = Chaos.dayKey()
	local last = player:getStorageValue(S.dailyLastClaim)
	local stored = player:getStorageValue(S.dailyStreakDay)
	if stored < 1 or stored > 7 then
		stored = 0
	end
	if last == today and stored > 0 then
		return stored, true
	end
	if last == Chaos.yesterdayKey() and stored > 0 then
		return (stored % 7) + 1, false
	end
	return 1, false
end

local function sendWindow(player)
	local slot, taken = getState(player)
	local rewards = {}
	for i = 1, 7 do
		local reward = cfg.rewards[i]
		local itemType = ItemType(reward.itemId)
		rewards[i] = {ClientID = itemType:getClientId(), Count = reward.count}
	end
	Chaos.send(player, OPCODE, "OpenDailyWindow", {
		Day = slot - 2,
		TakenReward = taken and 1 or 0,
		DAILY_REWARDS = rewards
	})
end

local function claim(player, value)
	local v = Chaos.toInt(value, 1, 7)
	if not v then
		return
	end
	local claimedSlot = ((v + 1) % 7) + 1
	local slot, taken = getState(player)

	if taken then
		player:sendCancelMessage("You already collected today's daily reward.")
		sendWindow(player)
		return
	end
	if claimedSlot ~= slot then
		-- stale window (e.g. opened before midnight): resync instead of paying the wrong day
		sendWindow(player)
		return
	end

	local reward = cfg.rewards[slot]
	local list = {reward}
	if slot == 7 then
		for _, bonus in ipairs(cfg.weekBonus or {}) do
			list[#list + 1] = bonus
		end
	end
	-- all or nothing: if any stack does not fit, take back what was already given
	local givenList, ok = {}, true
	for _, r in ipairs(list) do
		local given = Chaos.giveItem(player, r.itemId, r.count)
		givenList[#givenList + 1] = {itemId = r.itemId, given = given}
		if given < r.count then
			ok = false
			break
		end
	end
	if not ok then
		for _, g in ipairs(givenList) do
			if g.given > 0 then
				player:removeItem(g.itemId, g.given)
			end
		end
		player:sendCancelMessage("You do not have enough room or capacity for the reward.")
		sendWindow(player)
		return
	end

	player:setStorageValue(S.dailyStreakDay, slot)
	player:setStorageValue(S.dailyLastClaim, Chaos.dayKey())
	player:sendTextMessage(
		MESSAGE_EVENT_ADVANCE,
		string.format("Daily reward (day %d): %dx %s.", slot, reward.count, ItemType(reward.itemId):getName())
	)
	if slot == 7 and #list > 1 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Week completed! Bonus reward collected.")
	end
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	sendWindow(player)
end

local LoginEvent = CreatureEvent("ChaosDailyLogin")

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosDailyExtended")
	if cfg.openOnLogin then
		local playerId = player:getId()
		addEvent(function(pid)
			local p = Player(pid)
			if p then
				local _, taken = getState(p)
				if not taken then
					sendWindow(p)
				end
			end
		end, cfg.openDelayMs, playerId)
	end
	return true
end

local ExtendedEvent = CreatureEvent("ChaosDailyExtended")

function ExtendedEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	if msg.action == "calim" then
		claim(player, msg.data)
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()

local talk = TalkAction("!daily")

function talk.onSay(player, words, param)
	sendWindow(player)
	return false
end

talk:register()
