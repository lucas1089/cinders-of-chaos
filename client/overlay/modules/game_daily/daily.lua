-- chunkname: @/mods/game_daily/daily.lua

local OPCODE = 207

-- donor server ships this helper in its gamelib; the base client does not, so keep a local copy.
local function sendAction(opcode, action, data)
	local protocolGame = g_game.getProtocolGame()
	if protocolGame then
		protocolGame:sendExtendedOpcode(opcode, json.encode({action = action, data = data or {}}))
	end
end
local Time, TimerCheckEvent, dailyData, lastPos, waitEvent

-- Login order: the server opens this window by itself at login ("Login":1) through its login window queue
-- (server daily.lua, ChaosLoginWindows) and opens the next login window when this one reports "closed". Here the
-- window also waits while a server modal dialog (the new-player welcome, the tutorial) or another login window listed
-- in LOGIN_BLOCKERS is on screen, so it never opens on top of them.
local LOGIN_BLOCKERS = { 'patchNotesWindow' } -- widget ids of other windows that open by themselves at login
local WAIT_MS = 500

local function otherWindowOpen()
	local md = modules.game_modaldialog
	if md and md.modalDialog then
		return true
	end
	for _, id in ipairs(LOGIN_BLOCKERS) do
		local w = rootWidget:recursiveGetChildById(id)
		if w and w:isVisible() then
			return true
		end
	end
	return false
end

local function hideWindow()
	if waitEvent then
		removeEvent(waitEvent)
		waitEvent = nil
	end
	if DailyWindow and DailyWindow:isVisible() then
		DailyWindow:hide()
		sendAction(OPCODE, "closed") -- the server's login window queue may open the next window
	end
end

local function showWindow()
	if DailyWindow:isVisible() then
		return
	end
	lastPos = g_game.getLocalPlayer():getPosition()
	DailyWindow:show()
	DailyWindow:raise()
	DailyWindow:focus()
end

local function waitForOtherWindows()
	waitEvent = nil
	if not g_game.isOnline() or not dailyData then
		return
	end
	if otherWindowOpen() then
		waitEvent = scheduleEvent(waitForOtherWindows, WAIT_MS)
		return
	end
	showWindow()
end

-- "Streak: 12 days", grace charges, the next milestone and the title (servers without login streaks send none)
local function streakInfo()
	local panel = DailyWindow.streakPanel
	if not panel then
		return
	end
	if dailyData.Streak == nil then
		panel:hide()
		return
	end
	panel:show()
	local streak = tonumber(dailyData.Streak) or 0
	local text = tr("Streak: %d %s", streak, streak == 1 and "day" or "days")
	if dailyData.Broken == 1 and dailyData.TakenReward ~= 1 then
		text = text .. "  " .. tr("(your streak was broken: it starts again today)")
	end
	panel.streakLabel:setText(text)
	panel.bestLabel:setText(tr("Best: %d days", tonumber(dailyData.Best) or 0))
	local grace, graceMax = tonumber(dailyData.Grace) or 0, tonumber(dailyData.GraceMax) or 2
	panel.graceLabel:setText(tr("Grace charges: %d / %d", grace, graceMax))
	local tip = tr("A grace charge keeps your streak alive when you miss a single day. You earn one every 7 days in a row.")
	if (tonumber(dailyData.GraceUse) or 0) > 0 then
		tip = tip .. "\n" .. tr("You missed a day: today's claim uses a grace charge.")
		panel.graceLabel:setColor("#f6cf72")
	else
		panel.graceLabel:setColor("#d6c9ae")
	end
	panel.graceLabel:setTooltip(tip)
	local nextM = type(dailyData.Next) == "table" and dailyData.Next or nil
	if nextM then
		local inDays = tonumber(nextM.In) or 0
		panel.milestoneLabel:setText(tr("Next milestone: %d days (%s): %s", tonumber(nextM.Days) or 0,
			inDays <= 1 and tr("next claim") or tr("in %d days", inDays), nextM.Reward or ""))
	else
		panel.milestoneLabel:setText(tr("Every milestone reached. Keep the streak going!"))
	end
	panel.titleLabel:setText(dailyData.Title and tr("Your title: %s", dailyData.Title) or "")
end

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
	if waitEvent then
		removeEvent(waitEvent)
		waitEvent = nil
	end
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
			if dailyData and dailyData.Login == 1 then
				if not waitEvent then
					waitForOtherWindows()
				end
			else
				showWindow()
			end
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

	streakInfo()

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
	if waitEvent then
		removeEvent(waitEvent)
		waitEvent = nil
	end
	DailyWindow:hide()
end

function toggle()
	if DailyWindow:isVisible() then
		hideWindow()
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
	-- a jump (the placement at login, a teleport) moves the anchor; walking more than 3 tiles away closes the window
	if lastPos and newPos and (not oldPos or oldPos.z ~= newPos.z
			or math.max(math.abs(oldPos.x - newPos.x), math.abs(oldPos.y - newPos.y)) > 1) then
		lastPos = newPos
		return
	end
	if DailyWindow and DailyWindow:isVisible() and lastPos and math.max(math.abs(lastPos.x - newPos.x), math.abs(lastPos.y - newPos.y)) > 3 then
		hideWindow()

		lastPos = nil
	end
end
