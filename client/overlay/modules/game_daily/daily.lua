-- chunkname: @/mods/game_daily/daily.lua

local OPCODE = 207

-- donor server ships this helper in its gamelib; the base client does not, so keep a local copy.
local function sendAction(opcode, action, data)
	local protocolGame = g_game.getProtocolGame()
	if protocolGame then
		protocolGame:sendExtendedOpcode(opcode, json.encode({action = action, data = data or {}}))
	end
end
local Time, TimerCheckEvent, dailyData, lastPos

function init()
	connect(g_game, {
		onGameEnd = offline
	})
	connect(LocalPlayer, {
		onPositionChange = onPlayerPositionChange
	})

	DailyWindow = g_ui.displayUI("daily")

	DailyWindow:hide()
	ProtocolGame.registerExtendedOpcode(OPCODE, onDailyReward)
end

function terminate()
	disconnect(g_game, {
		onGameEnd = offline
	})
	disconnect(LocalPlayer, {
		onPositionChange = onPlayerPositionChange
	})
	DailyWindow:destroy()
	ProtocolGame.unregisterExtendedOpcode(OPCODE, onDailyReward)
end

function onDailyReward(protocol, code, buffer)
	local json_status, json_data = pcall(function()
		return json.decode(buffer)
	end)

	if not json_status then
		g_logger.error("[daily reward] JSON error: " .. tostring(json_data))

		return false
	end

	local action = json_data.action
	local data = json_data.data

	if action == "OpenDailyWindow" then
		dailyData = data

		if dailyData then
			dailyData.Day = dailyData.Day + 2
			-- server midnight as a local clock instant, so the countdown follows the server day
			dailyData.ResetAt = os.time() + (tonumber(dailyData.NextIn) or 0)
		end

		CollectInfo()

		if not DailyWindow:isVisible() then
			lastPos = g_game.getLocalPlayer():getPosition()

			DailyWindow:show()
		end
	end
end

function CollectInfo()
	if dailyData == nil then
		return
	end

	if TimerCheckEvent then
		removeEvent(TimerCheckEvent)
	end

	TimerCheckEvent = scheduleEvent(CollectInfo, 1000)

	local player = g_game.getLocalPlayer()

	for i = 1, #dailyData.DAILY_REWARDS do
		local panel = DailyWindow.itemsPanel:getChildById("daily" .. i)

		panel.Timer:hide()
		panel.claim:hide()

		if dailyData.Day > 7 then
			dailyData.Day = 1
		end

		if i < dailyData.Day then
			panel.Status:setImageClip("0 20 66 20")
			panel.claim:setPhantom(true)
		elseif i == dailyData.Day then
			if dailyData.TakenReward == 1 then
				panel.Status:setImageClip("0 20 66 20")
				panel.Status:show()
				panel.claim:hide()
			elseif dailyData.TakenReward == 0 then
				panel.Timer:setPercent(100)
				panel.Timer:hide()
				panel.Status:hide()
				panel.claim:show()
			end
		elseif i == dailyData.Day + 1 and dailyData.Day < 7 then
			local remainingTime = math.max(0, os.difftime(dailyData.ResetAt or os.time(), os.time()))
			local remainingHours = math.floor(remainingTime / 3600)
			local remainingMinutes = math.floor(remainingTime % 3600 / 60)
			local valuePercent = (86400 - remainingTime) / 86400 * 100

			panel.Timer:show()
			panel.Status:hide()
			panel.Timer:setPercent(valuePercent)
			panel.Timer:setText(string.format("%02d:%02d", remainingHours, remainingMinutes))
		else
			panel.Status:setImageClip("0 40 66 20")
			panel:setPhantom(true)
		end

		panel.Item:setItemId(dailyData.DAILY_REWARDS[i].ClientID)
		panel.Item:setItemCount(dailyData.DAILY_REWARDS[i].Count)

		function panel.claim.onClick()
			sendAction(OPCODE, "calim", mapClientToServerDay(dailyData.Day))
		end
	end
end

function mapClientToServerDay(clientDay)
	local map = {
		6,
		7,
		1,
		2,
		3,
		4,
		5
	}

	return map[clientDay]
end

function offline()
	DailyWindow:hide()
end

function toggle()
	if DailyWindow:isVisible() then
		DailyWindow:hide()
	else
		-- the server answers with OpenDailyWindow, which fills and shows the window
		sendAction(OPCODE, "open")
	end
end

function Show()
	DailyWindow:show()
	DailyWindow:focus()
	DailyWindow:raise()

	lastPos = g_game.getLocalPlayer():getPosition()
end

function onPlayerPositionChange(creature, newPos, oldPos)
	if DailyWindow and DailyWindow:isVisible() and lastPos and math.max(math.abs(lastPos.x - newPos.x), math.abs(lastPos.y - newPos.y)) > 3 then
		DailyWindow:hide()

		lastPos = nil
	end
end
