Event = {}

Event.Days = {
	[1] = {name = tr("Monday")},
	[2] = {name = tr("Tuesday")},
	[3] = {name = tr("Wednesday")},
	[4] = {name = tr("Thursday")},
	[5] = {name = tr("Friday")},
	[6] = {name = tr("Saturday")},
	[7] = {name = tr("Sunday")},
}
local isdst = os.date("!*t").isdst

-- Mobile: this window goes full screen, so the walk pad overlay would sit on
-- top of it. Ask client_mobile to step the pads aside while it is open instead
-- of raising the window (raising only moves the problem to the next window).
-- Declared up here so Terminate() can see it.
local padHidden = false
local function setPadSuppressed(on)
	if not g_app.isMobile() or padHidden == on then
		return
	end

	local mobile = modules.client_mobile
	if not mobile or not mobile.suppressOverlay then
		return
	end

	padHidden = on
	mobile.suppressOverlay(on)
end

Event.Months = {
	[1] = "january",
	[2] = "february",
	[3] = "march",
	[4] = "april",
	[5] = "may",
	[6] = "june",
	[7] = "july",
	[8] = "august",
	[9] = "september",
	[10] = "october",
	[11] = "november",
	[12] = "december",
}

Event.Convert = {
	["zombie"] = "zombie", 
	["king of the hill"] = "king_of_the_hill",
	["firestorm"] = "firestorm",
	["dream of gold"] = "dream_of_gold",
	["snake"] = "snake",
	["capture the flag"] = "capture_the_flag",
	["beast invasion"] = "beast_invasion"
}

Event.DayIndex = 0
Event.CountEvent = nil
Event.BorderEvent = nil
Event.DaysData = {}
Event.VisibleDays = 7
Event.MaxCachedDays = 21
Event.HalfWindow = math.floor(Event.VisibleDays / 2)
Event.CustomEvents = {}
Event.CustomCountEvent = nil
-- Caches downloaded custom-event background images by bgImage name so we
-- don't re-download every time the Event Schedule window is opened.
-- name -> local file path (string) | false while a download is in flight.
Event.BgImageCache = {}
-- Active title marquee cycleEvents (one per card whose title overflows),
-- cleared whenever the custom-event list is rebuilt.
Event.TitleMarquees = {}

local function formatClock(seconds)
	seconds = math.max(0, seconds or 0)
	local minutes = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%02d:%02d", minutes, secs)
end

local function getToday()
	local date = os.date("!*t")
	return date.day, date.month
end

local function buildTimestamp(day, monthId, timeStr)
	if not day or not monthId or not timeStr then
		return nil
	end

	local date = os.date("!*t")
	date.day = tonumber(day)
	date.month = tonumber(monthId)
	date.hour = 0
	date.min = 0
	date.sec = 0

	local hourParts = timeStr:split(":")
	if hourParts and #hourParts >= 2 then
		date.hour = tonumber(hourParts[1]) or 0
		date.min = tonumber(hourParts[2]) or 0
	end

	date.isdst = false
	return os.time(date)
end

Event.Init = function()
	Event.UI = g_ui.displayUI('event')
	Event.UI:hide()
	Event.UI.onEscape = Event.Toggle
	Event.Tooltip = g_ui.displayUI('tooltip')
	Event.Tooltip:hide()

	-- Shortcut references for widgets inside contentPanel
	local contentPanel = Event.UI.contentPanel
	Event.UI.EventList = contentPanel.EventList
	Event.UI.CustomEventList = contentPanel.CustomEventList
	Event.UI.customScrollBar = contentPanel.customScrollBar
	Event.UI.TopBar = contentPanel.TopBar
	Event.UI.timeText = Event.UI.timeText or Event.UI:getChildById("timeText")
	Event.UI.divBar = contentPanel.divBar
	Event.UI.kothBox = contentPanel:recursiveGetChildById("kothBox")
	Event.UI.nextLabel = contentPanel:recursiveGetChildById("nextLabel")
	Event.UI.ProgressBack = contentPanel:recursiveGetChildById("ProgressBack")
	Event.UI.divProgress = contentPanel:recursiveGetChildById("divProgress")
	Event.UI.divText = contentPanel:recursiveGetChildById("divText")
	Event.UI.eventIcon = contentPanel:recursiveGetChildById("eventIcon")
	Event.UI.kothPanel = contentPanel:recursiveGetChildById("kothPanel")

	if Event.UI.CustomEventList and Event.UI.customScrollBar then
		Event.UI.CustomEventList:setHorizontalScrollBar(Event.UI.customScrollBar)
	end
	--Event.UI.beastPanel = contentPanel.beastPanel

	Event.NewButton = modules.game_extramenu.Menu.AddButton("Event Schedule",  function() modules.game_event.Event.Toggle(false) end, "eventschedule")

	Event.Define()

	-- On login the server pushes KOTH/custom-event data immediately, but the
	-- "Event" module handler may not be registered yet, so those packets are
	-- dropped and the window stays empty until relog. Pull the data ourselves
	-- once the game has started (handler guaranteed ready). Small delay lets
	-- the protocol/module finish settling before we request.
	Event.GameStart = function()
		scheduleEvent(function()
			if g_game.isOnline() and Event.RequestEvents then
				Event.RequestEvents()
				-- Reopen the Hide and Seek disguise picker if this staffer is
				-- still hiding after a relog. The server ignores non-hiders.
				if Event.RequestDisguiseList then
					Event.RequestDisguiseList()
				end
			end
		end, 1000)
	end

	connect(g_game, {
		onGameStart = Event.GameStart,
		onGameEnd = Event.GameEnd
	})
	connect(rootWidget, {onMouseMove = Event.MoveToolTip})
end

Event.Terminate = function()	
	disconnect(g_game, {
		onGameStart = Event.GameStart,
		onGameEnd = Event.GameEnd
	})

	if Event.CountEvent then
		removeEvent(Event.CountEvent)
	end
	if Event.BorderEvent then
		removeEvent(Event.BorderEvent)
	end
	if Event.CustomCountEvent then
		removeEvent(Event.CustomCountEvent)
		Event.CustomCountEvent = nil
	end
	--local BeastPanel = Event.UI and Event.UI.beastPanel
	--if BeastPanel and BeastPanel.beastEventId then
	--	removeEvent(BeastPanel.beastEventId)
	--	BeastPanel.beastEventId = nil
	--end
	--if BeastPanel then
	--	BeastPanel.Data = nil
	--	BeastPanel:setVisible(false)
	--end

	Event.DestroyConfirmBox()

	disconnect(rootWidget, {onMouseMove = Event.MoveToolTip})

	local KothPanel = Event.UI.kothPanel
	if KothPanel.kothEventId then
		removeEvent(KothPanel.kothEventId)
		KothPanel.kothEventId = nil
	end
	
	setPadSuppressed(false)

	Event.UI:destroy()
	Event.UI = nil
	Event.Tooltip:destroy()
	Event.Tooltip = nil

	Event.DestroyDisguise()
	Event.DestroyWarning()
end

Event.Toggle = function(Terminate)
	if Event.UI:isVisible() then
		setPadSuppressed(false)
		Event.UI:hide()
		Event.Tooltip:hide()
		Event.Clear()
		Event.DayIndex = 0
		Event.DaysData = {}
		Event.ClearNextEvent()
		if Event.CountEvent then
			removeEvent(Event.CountEvent)
		end
		if Event.BorderEvent then
			removeEvent(Event.BorderEvent)
		end
		if Event.ClearSubHighlight then
			Event.ClearSubHighlight()
		end
		if Event.CustomCountEvent then
			removeEvent(Event.CustomCountEvent)
			Event.CustomCountEvent = nil
		end
		if Event.UI and Event.UI.CustomEventList then
			Event.UI.CustomEventList:destroyChildren()
		end
		Event.CustomEvents = {}
		--local BeastPanel = Event.UI and Event.UI.beastPanel
		--if BeastPanel and BeastPanel.beastEventId then
		--	removeEvent(BeastPanel.beastEventId)
		--	BeastPanel.beastEventId = nil
		--end
		--if BeastPanel then
		--	BeastPanel.Data = nil
		--	BeastPanel:setVisible(false)
		--end
	else
		if Terminate == true then
			setPadSuppressed(false)
			Event.UI:hide()
			return false
		end
		Event.DayIndex = 0
		Event.DaysData = {}
		Event.UI:show()
		setPadSuppressed(true)
		if modules.game_windowfocus then modules.game_windowfocus.enableWalkThrough(Event.UI) end
		Event.Create()
		Event.ClearNextEvent()
		Event.RequestEvents()
	end
end

Event.GameEnd = function()
	Event.Toggle(true)

	Event.DestroyConfirmBox()
	Event.DestroyWarning()
	Event.DestroyDisguise()
end

Event.Define = function()

	Event.DataManager = function(protocol, opcode, buffer)
		if buffer.make == "monthData" then
			Event.DefineMonth(buffer)
		elseif buffer.make == "dayData" then
			Event.UI.timeText:setText(buffer.text)
		elseif buffer.make == "kothInfo" then
			Event.UpdateKoth(buffer)
		elseif buffer.make == "customEvents" then
			Event.SetCustomEvents(buffer.List or {})
		--elseif buffer.make == "beastInfo" then
		--	Event.UpdateBeast(buffer)
		elseif buffer.make == "enterEvent" then
			Event.EnterConfirmation(buffer)
		elseif buffer.make == "warning" then
			Event.ShowWarning(buffer)
		elseif buffer.make == "closeWarning" then
			Event.DestroyWarning()
		elseif buffer.make == "hideSeekNet" then
			Event.OnDisguiseNet(buffer)
		end
	end

	modules.client_manager.Manage.NewModule("Event", modules.game_event.Event.DataManager)

	Event.Clear = function()
		Event.UI.EventList:destroyChildren()
		Event.DayIndex = 0
		Event.DaysData = {}
	end

	Event.MonthShort = {
		[1] = "Jan", [2] = "Feb", [3] = "Mar",  [4] = "Apr",
		[5] = "May", [6] = "Jun", [7] = "Jul",  [8] = "Aug",
		[9] = "Sep", [10] = "Oct", [11] = "Nov", [12] = "Dec",
	}

	Event.FormatPeriod = function(startTime, endTime)
		local s = os.date("!*t", startTime)
		local e = os.date("!*t", endTime)
		if s.month == e.month then
			return string.format("%s %d - %d", Event.MonthShort[s.month], s.day, e.day)
		end
		return string.format("%s %d - %s %d", Event.MonthShort[s.month], s.day, Event.MonthShort[e.month], e.day)
	end

	Event.FormatDuration = function(seconds)
		seconds = math.max(0, seconds or 0)
		local days = math.floor(seconds / 86400)
		local hours = math.floor(math.mod(seconds, 86400) / 3600)
		local minutes = math.floor(math.mod(seconds, 3600) / 60)
		if days > 0 then
			return string.format("%dD %dH %dM", days, hours, minutes)
		end
		local secs = math.floor(math.mod(seconds, 60))
		return string.format("%dH %dM %dS", hours, minutes, secs)
	end

	Event.SetCustomEvents = function(list)
		Event.CustomEvents = list or {}
		Event.RefreshCustomEvents()
	end

	-- Ajusta a ALTURA da tooltip ao conteudo, no espirito do layoutToolTip da
	-- tooltip padrao (corelib/ui/tooltip.lua). A largura fica FIXA de proposito:
	-- o que sobrava era altura, e largura variavel daria a cada card uma tooltip
	-- de tamanho diferente. Os labels seguem separados porque titulo e corpo usam
	-- fontes distintas, e um label unico so aceita uma fonte.
	Event.LayoutTooltip = function()
		local t = Event.Tooltip
		if not t then
			return
		end

		local WIDTH, PAD_X, PAD_TOP, PAD_BOTTOM = 330, 10, 10, 10
		local CONTENT_W = WIDTH - PAD_X * 2

		-- Mede um widget de texto e devolve a altura dele. A largura tem que ser
		-- aplicada ANTES de (re)ligar o wrap: setWidth so re-quebra o texto no
		-- proximo ciclo do dispatcher, enquanto setTextWrap chama updateText na
		-- hora. Na ordem inversa a medida sai com a largura antiga.
		local function measure(widget, alwaysWrap)
			local text = widget:getText()
			if not text or text == "" then
				widget:setHeight(0)
				return 0
			end

			widget:setTextWrap(false)
			widget:resizeToText()
			if alwaysWrap or widget:getWidth() > CONTENT_W then
				widget:setWidth(CONTENT_W)
				widget:setTextWrap(true)
			end

			local height = widget:getTextSize().height
			widget:setHeight(height)
			return height
		end

		-- Os vaos sao as margens declaradas no tooltip.otui e entram na conta
		-- mesmo quando o texto e vazio, porque a ancora aplica o margin-top de
		-- qualquer jeito. O divBar fica de fora: ele vive dentro do vao de 10px
		-- entre o titulo e o starttime.
		local height = PAD_TOP + measure(t.name)
		for _, block in ipairs({ { t.starttime, 10 }, { t.players, 2 }, { t.commands, 2 } }) do
			height = height + block[2] + measure(block[1])
		end
		height = height + 5 + measure(t.desc, true)

		t:setWidth(WIDTH)
		t:setHeight(height + PAD_BOTTOM)
	end

	Event.ShowCustomTooltip = function(ev)
		if not ev or not Event.Tooltip then
			return
		end

		local now = os.time()
		local statusLine
		if ev.startTime and now < ev.startTime then
			statusLine = "<color=\"orange\">" .. tr("Starts in") .. "</color>: " .. Event.FormatDuration(ev.startTime - now)
		elseif ev.endTime and now < ev.endTime then
			statusLine = "<color=\"#66cc66\">" .. tr("Ends in") .. "</color>: " .. Event.FormatDuration(ev.endTime - now)
		else
			statusLine = "<color=\"#888888\">" .. tr("Ended") .. "</color>"
		end

		Event.Tooltip:show()
		Event.Tooltip:breakAnchors()
		Event.Tooltip:raise()
		Event.Tooltip.name:setText(ev.name or "")
		Event.Tooltip.starttime:setText("<color=\"orange\">" .. tr("Period") .. "</color>: " ..
			Event.FormatPeriod(ev.startTime or now, ev.endTime or now))
		Event.Tooltip.players:setText(statusLine)
		Event.Tooltip.commands:setText("")
		Event.Tooltip.desc:setText("<color=\"orange\">" .. tr("Description") .. "</color>: " ..
			(ev.description or ""))

		Event.LayoutTooltip()
		-- Posiciona AGORA. Sem isto a tooltip so era movida no onMouseMove do
		-- rootWidget, entao na primeira exibicao ela aparecia na posicao antiga
		-- (0,0 no primeiro hover) ate o mouse mexer de novo.
		Event.MoveToolTip()
	end

	-- Continuous marquee for a card title that is wider than the card.
	-- The title is duplicated with a separator ("A   -   A") and scrolled
	-- left; when one copy has fully left the view the other is already in
	-- place, so the wrap-around is seamless (no jump/reset flicker).
	-- Short titles stay centered and untouched.
	Event.StartTitleMarquee = function(card)
		if not card or not card.header or not card.header.title then
			return
		end
		local label = card.header.title
		local baseText = label:getText()

		local available = label:getWidth()
		local textWidth = label:getTextSize().width

		if textWidth <= available - 4 then
			-- Fits: keep it centered, no animation.
			label:setTextAlign(AlignCenter)
			label:setTextOffset(topoint("0 1"))
			return
		end

		-- Build the doubled string. The separator's width defines the gap
		-- between the end of one copy and the start of the next.
		local separator = "   -   "
		label:setTextAlign(AlignLeft)
		label:setText(baseText .. separator)
		-- Width of one "title + separator" unit = the scroll period. When
		-- scrollPos reaches it, copy #2 sits exactly where copy #1 started,
		-- so resetting to 0 is visually identical (seamless loop).
		local unitWidth = label:getTextSize().width
		label:setText(baseText .. separator .. baseText .. separator)

		label.scrollPos = 0
		local evId
		evId = cycleEvent(function()
			-- Stop if the window closed or the card was destroyed/rebuilt.
			if not Event.UI or not Event.UI.CustomEventList or
			   not label or label:isDestroyed() then
				removeEvent(evId)
				return
			end
			label.scrollPos = label.scrollPos + 1
			if label.scrollPos >= unitWidth then
				label.scrollPos = label.scrollPos - unitWidth
			end
			label:setTextOffset(topoint("-" .. label.scrollPos .. " 1"))
		end, 60)
		table.insert(Event.TitleMarquees, evId)
	end

	-- Cancels every running title marquee. Called before the card list is
	-- rebuilt so we don't leak cycleEvents onto destroyed widgets.
	Event.ClearTitleMarquees = function()
		for _, evId in ipairs(Event.TitleMarquees) do
			removeEvent(evId)
		end
		Event.TitleMarquees = {}
	end

	-- Loads the event artwork from the website (Services.eventImageApi) and
	-- sets it as the card background. Results are cached in Event.BgImageCache
	-- so reopening the window doesn't re-download. The card stays usable even
	-- if the image is missing/unreachable (overlay + text remain).
	Event.ApplyCardBackground = function(card, bgImage)
		if not card or not card.bgImage then
			return
		end
		if not bgImage or bgImage == "" then
			card.bgImage:setImageSource("")
			return
		end

		local cached = Event.BgImageCache[bgImage]
		if type(cached) == "string" then
			card.bgImage:setImageSource(cached)
			return
		end
		if cached == false then
			-- A download for this image is already in flight; skip duplicate.
			return
		end

		local apiUrl = (Services and Services.eventImageApi) or
			"https://blacktalon.online/api/api_event_image.php"
		local url = string.format("%s?img=%s", apiUrl, bgImage)

		Event.BgImageCache[bgImage] = false
		HTTP.downloadImage(url, function(path, err)
			if err then
				g_logger.warning("[Event] Custom event bg download error (" ..
					tostring(bgImage) .. "): " .. tostring(err))
				Event.BgImageCache[bgImage] = nil
				return
			end
			Event.BgImageCache[bgImage] = path
			-- The window may have been refreshed/closed during the download;
			-- re-apply to every visible card that wants this image.
			if Event.UI and Event.UI.CustomEventList then
				for _, c in ipairs(Event.UI.CustomEventList:getChildren()) do
					if c.Data and c.Data.bgImage == bgImage and c.bgImage then
						c.bgImage:setImageSource(path)
						c.bgImage:setImageSmooth(true)
					end
				end
			end
		end)
	end

	Event.RefreshCustomEvents = function()
		if not Event.UI or not Event.UI.CustomEventList then
			return
		end

		Event.ClearTitleMarquees()
		Event.UI.CustomEventList:destroyChildren()

		local now = os.time()
		local visible = {}
		for _, ev in ipairs(Event.CustomEvents) do
			if ev.endTime and ev.endTime > now then
				table.insert(visible, ev)
			end
		end
		table.sort(visible, function(a, b) return (a.startTime or 0) < (b.startTime or 0) end)

		local cardWidth, spacing = 150, 5
		for _, ev in ipairs(visible) do
			local card = g_ui.createWidget('CustomEventItem', Event.UI.CustomEventList)
			card:setVisible(true)
			card.Data = ev
			card.header.title:setText(ev.name or "")
			-- Defer one frame so the title widget is laid out before we
			-- measure it to decide whether the marquee is needed.
			addEvent(function()
				if card and not card:isDestroyed() then
					Event.StartTitleMarquee(card)
				end
			end)
			Event.ApplyCardBackground(card, ev.bgImage)
			card.period:setText(Event.FormatPeriod(ev.startTime or now, ev.endTime or now))

			card.onHoverChange = function(self, hovered)
				if hovered then
					Event.ShowCustomTooltip(self.Data)
				else
					Event.Tooltip:hide()
				end
			end
		end

		if Event.UI.customScrollBar then
			local count = #visible
			local totalWidth = count * cardWidth + math.max(0, count - 1) * spacing
			local needsScroll = totalWidth > Event.UI.CustomEventList:getWidth()
			Event.UI.customScrollBar:setVisible(needsScroll)
			Event.UI.customScrollBar:setHeight(needsScroll and 12 or 0)
		end

		local emptyLabel = Event.UI.contentPanel and Event.UI.contentPanel:recursiveGetChildById("customEventsEmpty")
		if emptyLabel then
			emptyLabel:setVisible(#visible == 0)
		end

		Event.UpdateCustomCountdowns()
	end

	Event.UpdateCustomCountdowns = function()
		if Event.CustomCountEvent then
			removeEvent(Event.CustomCountEvent)
			Event.CustomCountEvent = nil
		end

		if not Event.UI or not Event.UI.CustomEventList then
			return
		end

		local now = os.time()
		local hasActive = false

		for i = 1, Event.UI.CustomEventList:getChildCount() do
			local card = Event.UI.CustomEventList:getChildByIndex(i)
			if card and card.Data then
				local ev = card.Data
				if ev.startTime and now < ev.startTime then
					card.countdown:setText("Starts in " .. Event.FormatDuration(ev.startTime - now))
					card.countdown:setColor("#ffaa00")
					hasActive = true
				elseif ev.endTime and now < ev.endTime then
					card.countdown:setText("Ends in " .. Event.FormatDuration(ev.endTime - now))
					card.countdown:setColor("#66cc66")
					hasActive = true
				else
					card.countdown:setText("Ended")
					card.countdown:setColor("#888888")
				end
			end
		end

		if hasActive then
			Event.CustomCountEvent = scheduleEvent(function()
				Event.UpdateCustomCountdowns()
			end, 1000)
		end
	end

	Event.ResetCard = function(card)
		if not card then
			return
		end

		card.day = nil
		card.month = nil
		card:setVisible(false)

		if card.title then
			card.title:setText("")
			card.title:setChecked(false)
		end
		if card.Border then
			card.Border:setChecked(false)
		end
		if card.BorderFill then
			card.BorderFill:setVisible(false)
		end

		for j = 1, 6 do
			local subcard = card:getChildById("event" .. j)
			if subcard then
				subcard:setVisible(false)
				subcard.Data = nil
				subcard.time = nil
				subcard.saveColor = nil
				subcard.isChild = nil
				subcard.onHoverChange = nil
				if subcard.background then
					subcard.background:setBackgroundColor("#00000000")
				end
			end
		end
	end

	Event.StoreDayData = function(data)
		if not data then
			return
		end

		if not data.List then
			data.List = {}
		end

		local monthId = Event.ReturnMonthId(data.month)
		local dayNumber = tonumber(data.day)
		for idx, info in ipairs(data.List) do
			info.timestamp = buildTimestamp(dayNumber, monthId, info.starttime)
		end

		table.insert(Event.DaysData, data)
		if #Event.DaysData > Event.MaxCachedDays then
			table.remove(Event.DaysData, 1)
		end
	end

	Event.SelectDays = function()
		local selected = {}
		if not Event.DaysData or #Event.DaysData == 0 then
			return selected
		end

		local todayDay, todayMonth = getToday()
		local centerIndex = math.ceil(#Event.DaysData / 2)
		for i, info in ipairs(Event.DaysData) do
			if tonumber(info.day) == todayDay and Event.ReturnMonthId(info.month) == todayMonth then
				centerIndex = i
				break
			end
		end

		local startIndex = math.max(1, centerIndex - Event.HalfWindow)
		if startIndex + Event.VisibleDays - 1 > #Event.DaysData then
			startIndex = math.max(1, #Event.DaysData - Event.VisibleDays + 1)
		end
		local endIndex = math.min(#Event.DaysData, startIndex + Event.VisibleDays - 1)
		for i = startIndex, endIndex do
			table.insert(selected, Event.DaysData[i])
		end

		return selected
	end

	Event.PopulateCard = function(card, data)
		if not card or not data then
			return
		end

		Event.ResetCard(card)
		card:setVisible(true)

		local day = tonumber(data.day)
		local monthId = Event.ReturnMonthId(data.month)
		card.title:setText(day .. " " .. data.month)
		card.day = day
		card.month = monthId

		local todayDay, todayMonth = getToday()
		if day == todayDay and monthId == todayMonth then
			if Event.BorderEvent then
				removeEvent(Event.BorderEvent)
				Event.BorderEvent = nil
			end
			if card.Border then
				card.Border:setChecked(true)
			end
			if card.BorderFill then
				card.BorderFill:setVisible(true)
			end
			Event.BorderFlow(card, 1)
		end

		if data.List and #data.List >= 1 then
			for i = 1,#data.List do
				local Subcard = card:getChildById("event" .. i)
				if Subcard then
					local info = data.List[i]
					Subcard.Data = info
					Subcard.title:setText(info.starttime)
					Subcard.saveColor = info.color
					if Event.Convert[info.event] then
						Subcard.icon:setImageSource("icons/" .. Event.Convert[info.event])
					end
					if info.color then
						Subcard.background:setBackgroundColor(info.color)
					end
					local CommandList = ""

					if info.commands and #info.commands >= 1 then
						for j = 1,#info.commands do
						CommandList = CommandList .. info.commands[j]
						end
					end
					
					Subcard.time = info.timestamp or buildTimestamp(day, monthId, info.starttime)
					if info.isChild then
						Subcard.isChild = true
					end
					
					Subcard:setVisible(true)
					Subcard.onHoverChange = function(self, hovered)
						if hovered then   
							Event.Tooltip:show()
							Event.Tooltip:breakAnchors()
							Event.Tooltip:raise()
							Event.Tooltip.name:setText(info.event .. ": ")
							Event.Tooltip.starttime:setText("<color=\"orange\">"..tr("Start Time").."</color>"..": " .. info.starttimeDescription)
							Event.Tooltip.players:setText("<color=\"orange\">"..tr("Players").."</color>"..": Min: " .. info.minplayers .. " | Max: " .. info.maxplayers)
							Event.Tooltip.commands:setText("<color=\"orange\">"..tr("Informations").."</color>"..": " .. (CommandList or ""))
							Event.Tooltip.desc:setText("<color=\"orange\">"..tr("Event Description").."</color>"..": " .. (info.eventdescription or ""))
							Event.LayoutTooltip()
							Event.MoveToolTip()
						else
							Event.Tooltip:hide()
						end
					end
				end
			end
		end
	end

	Event.ClearNextEvent = function()
		if Event.CountEvent then
			removeEvent(Event.CountEvent)
			Event.CountEvent = nil
		end
		if Event.UI then
			Event.UI.divProgress:setMinimum(0)
			Event.UI.divProgress:setMaximum(100)
			Event.UI.divProgress:setValue(0)
			Event.UI.divProgress:setText("--")
			Event.UI.divText:setText(tr("No event"))
			Event.UI.eventIcon:setImageSource("")
		end
	end

	Event.RefreshCalendar = function()
		if not Event.UI or not Event.UI.EventList then
			return
		end

		if Event.BorderEvent then
			removeEvent(Event.BorderEvent)
			Event.BorderEvent = nil
		end

		for i = 1, Event.UI.EventList:getChildCount() do
			Event.ResetCard(Event.UI.EventList:getChildByIndex(i))
		end

		local selectedDays = Event.SelectDays()
		for index, dayData in ipairs(selectedDays) do
			local card = Event.UI.EventList:getChildByIndex(index)
			if card then
				Event.PopulateCard(card, dayData)
			end
		end

		Event.DefineNextEvent()
	end

	--[[ Beast Invasion disabled
	Event.GetNextScheduledBeast = function()
		if not Event.DaysData then
			return nil
		end
		local date = os.date("!*t")
		date.isdst = false
		local curTime = os.time(date)
		local nextBeast

		for _, dayInfo in ipairs(Event.DaysData) do
			local monthId = Event.ReturnMonthId(dayInfo.month)
			local dayNumber = tonumber(dayInfo.day)
			if dayNumber and monthId then
				for _, info in ipairs(dayInfo.List or {}) do
					if info.event == "beast invasion" then
						local evtTime = info.timestamp or buildTimestamp(dayNumber, monthId, info.starttime)
						if evtTime and evtTime > curTime and (not nextBeast or evtTime < nextBeast.time) then
							nextBeast = { time = evtTime, data = info }
						end
					end
				end
			end
		end

		return nextBeast
	end
	--]]

	for i = 1,7 do
		if i > 1 then
			local EventItem = g_ui.createWidget('BarItem', Event.UI.TopBar)
			EventItem:setText(Event.Days[i].name)
		else
			Event.UI.TopBar.item1:setText(Event.Days[i].name)
		end
	end

	Event.Create = function()
		for i = 1, Event.VisibleDays do
			local EventItem = g_ui.createWidget('EventItem', Event.UI.EventList)
		end
	end

	Event.UI.CloseButton.onClick = function()
		Event.Toggle()
	end

	Event.RequestEvents = function()
		g_net.Send("Event", { make = "requestEvents" })
	end

	Event.empty = function(self)
		for _, _ in pairs(self) do
			return false
		end
		return true
	end
	Event.UpdateKoth = function(Data)
		local KothPanel = Event.UI.kothPanel
		if not Data then
			Data = KothPanel.Data
			if not Data then
				return false
			end
		else	
			if KothPanel.kothEventId then
				removeEvent(KothPanel.kothEventId)
				KothPanel.kothEventId = nil
			end
		end
		local timeLeft = Data.timeLeft
		local totalTime = Data.totalTime
		KothPanel.Data = Data
		if timeLeft >= 1 then
			local days = math.floor(timeLeft/86400)
			local hours = math.floor(math.mod(timeLeft, 86400)/3600)
			local minutes = math.floor(math.mod(timeLeft,3600)/60)
			local seconds = math.floor(math.mod(timeLeft,60))
			EventTime = string.format("%02dD %02dH %02dM %02dS", days,hours,minutes,seconds)
			KothPanel.timeKoth:setText(EventTime)
			local percent = 100 - (timeLeft / totalTime) * 100
			-- if Data.state == "Started" then
			-- 	percent = 100 - percent
			-- elseif Data.state == "Next in:" then
			-- 	percent = 100 - percent
			-- end
			KothPanel.timeKoth:setPercent(percent)
			KothPanel.Data.timeLeft = timeLeft - 1
			KothPanel.kothEventId = scheduleEvent(function()
				Event.UpdateKoth()
			end, 1000)
		end
		KothPanel.state:setText(Data.state)
		KothPanel.winner.guildWinner:setText(Data.guild)

		local emblemWidget = KothPanel.winner.emblem
		if emblemWidget then
			local setEmblemFn = modules.game_guildmanagement and modules.game_guildmanagement.setGuildEmblem
			if Data.guildEmblem ~= nil and Data.guildEmblem ~= "" and setEmblemFn then
				setEmblemFn(emblemWidget, Data.guildEmblem)
			else
				emblemWidget:setVisible(false)
			end
		end

		if KothPanel.modalityLabel then
			local txt = ""
			local desc = ""
			if Data.currentModalityLabel and Data.currentModalityLabel ~= "" then
				txt = Data.currentModalityLabel
				desc = Data.currentModalityDescription or ""
			elseif Data.nextModalityLabel and Data.nextModalityLabel ~= "" then
				txt = Data.nextModalityLabel
				desc = Data.nextModalityDescription or ""
			end
			KothPanel.modalityLabel:setText(txt)
			if Data.currentModalityLabel and Data.currentModalityLabel ~= "" then
				KothPanel.modalityLabel:setColor("#66cc66")
			else
				KothPanel.modalityLabel:setColor("#ffd76a")
			end
			if KothPanel.modalityDescription then
				KothPanel.modalityDescription:setText(desc)
			end
		end
	end
	--[[ Beast Invasion disabled
	Event.UpdateBeast = function(Data)
		local BeastPanel = Event.UI.beastPanel
		if not BeastPanel then
			return false
		end
		if not Data then
			Data = BeastPanel.Data
			if not Data then
				BeastPanel:setVisible(false)
				return false
			end
			if Data.timeLeft then
				Data.timeLeft = math.max(0, Data.timeLeft - 1)
			end
			if Data.nextWave then
				Data.nextWave = math.max(0, Data.nextWave - 1)
			end
		else
			if BeastPanel.beastEventId then
				removeEvent(BeastPanel.beastEventId)
				BeastPanel.beastEventId = nil
			end
			BeastPanel.Data = Data
		end

		local state = (Data and Data.state) or "idle"
		BeastPanel:setVisible(true)

		local runningArenas = (Data and Data.running) or 0
		local idleArenas = (Data and Data.idle) or 0
		local inQueue = (Data and Data.queuePlayers) or 0

		local displayTime = 0
		local totalRef = nil
		local statusText = tr("Idle")
		local headerText = tr("No schedule")

		if state == "waiting" then
			statusText = tr("Lobby open (%d in queue)", inQueue)
			headerText = tr("Waiting to start")
		elseif state == "running" or runningArenas > 0 then
			statusText = tr("Active (%d arenas)", math.max(runningArenas, 1))
			headerText = tr("Active")
		elseif state == "closing" then
			statusText = tr("Closing")
			headerText = tr("Closing")
		end

		if Data and Data.arenas then
			for _, arena in ipairs(Data.arenas) do
				if arena.status == "running" and arena.nextWave and arena.nextWave > 0 then
					if displayTime == 0 or arena.nextWave < displayTime then
						displayTime = arena.nextWave
						totalRef = arena.nextWaveTotal or arena.nextWave
					end
				end
			end
		end

		if displayTime == 0 then
			local nextBeast = Event.GetNextScheduledBeast()
			if nextBeast and nextBeast.time then
				local nowDate = os.date("!*t")
				nowDate.isdst = false
				local curTime = os.time(nowDate)
				displayTime = math.max(0, nextBeast.time - curTime)
				totalRef = displayTime
				headerText = tr("Next in %s", formatClock(displayTime))
			end
		end

		if displayTime > 0 and (state == "running" or runningArenas > 0) then
			headerText = tr("Next wave in %s", formatClock(displayTime))
		elseif displayTime > 0 and headerText == tr("No schedule") then
			headerText = tr("Next in %s", formatClock(displayTime))
		end

		if BeastPanel.beastStatus then
			BeastPanel.beastStatus:setText(statusText)
		end
		if BeastPanel.beastEventTime then
			BeastPanel.beastEventTime:setText(headerText)
		end

		local percent = 0
		if totalRef and totalRef > 0 then
			percent = 100 - (displayTime / totalRef) * 100
		end
		percent = math.max(0, math.min(100, percent))
		BeastPanel.waveTimer:setPercent(percent)
		BeastPanel.waveTimer:setText(formatClock(displayTime))

		if BeastPanel.Data then
			BeastPanel.beastEventId = scheduleEvent(function()
				Event.UpdateBeast()
			end, 1000)
		end
	end
	--]]
	Event.DefineMonth = function(Data)
		Event.DayIndex = Event.DayIndex + 1
		Event.StoreDayData(Data)
		Event.RefreshCalendar()
	end

	Event.ReturnPercent = function(MainTime, StartTime)
		local now = MainTime or os.time()
		local window = 4 * 3600
		local windowStart = StartTime - window
		if now <= windowStart then
			return 0
		end
		if now >= StartTime then
			return 100
		end
		return math.floor(((now - windowStart) / window) * 100)
	end
	
	Event.DefineNextEvent = function()
		if Event.CountEvent then
			removeEvent(Event.CountEvent)
			Event.CountEvent = nil
		end

		if not Event.DaysData or #Event.DaysData == 0 then
			Event.ClearNextEvent()
			return
		end

		local date = os.date("!*t")
		date.isdst = false
		local curTime = os.time(date)
		local nextEvent

		for _, dayInfo in ipairs(Event.DaysData) do
			local monthId = Event.ReturnMonthId(dayInfo.month)
			local dayNumber = tonumber(dayInfo.day)
			if dayNumber and monthId then
				for slotIndex, info in ipairs(dayInfo.List or {}) do
					if not info.isChild then
						local evtTime = info.timestamp or buildTimestamp(dayNumber, monthId, info.starttime)
						if evtTime and evtTime > curTime then
							if not nextEvent or evtTime < nextEvent.time then
								nextEvent = { time = evtTime, data = info, dayNumber = dayNumber, monthId = monthId, slotIndex = slotIndex }
							end
						end
					end
				end
			end
		end

		if not nextEvent then
			Event.ClearNextEvent()
			Event.ClearSubHighlight()
			return
		end

		-- Find the matching subwidget and pulse it.
		local targetSub
		if Event.UI and Event.UI.EventList then
			for i = 1, Event.UI.EventList:getChildCount() do
				local card = Event.UI.EventList:getChildByIndex(i)
				if card and card.day == nextEvent.dayNumber and card.month == nextEvent.monthId then
					targetSub = card:getChildById("event" .. nextEvent.slotIndex)
					break
				end
			end
		end
		Event.HighlightNextSubEvent(targetSub)

		local Btime = nextEvent.time - curTime
		local days = math.floor(Btime/86400)
		local hours = math.floor(math.mod(Btime, 86400)/3600)
		local minutes = math.floor(math.mod(Btime,3600)/60)
		local seconds = math.floor(math.mod(Btime,60))
		local eventTimeStr = string.format("%02dD %02dH %02dM %02dS", days,hours,minutes,seconds)
		Event.UI.divProgress:setMinimum(0)
		Event.UI.divProgress:setMaximum(100)
		Event.UI.divProgress:setText(eventTimeStr)
		local colorSaved = nextEvent.data.color or "#ffffff"
		Event.UI.divText:setColoredText({nextEvent.data.event:upper(), colorSaved, "", "#ffffff"})
		if Event.Convert[nextEvent.data.event] then
			Event.UI.eventIcon:setImageSource("icons/" .. Event.Convert[nextEvent.data.event])
		else
			Event.UI.eventIcon:setImageSource("")
		end

		Event.UI.divProgress:setValue(Event.ReturnPercent(curTime, nextEvent.time))
		Event.Counter({ time = nextEvent.time })
	end
	
	Event.ReturnMonthId = function(month)
		local returnid = 1
		for i = 1,12 do
			if Event.Months[i] == month then
			returnid = i
			break
			end
		end
		return returnid
	end
	
	Event.Counter = function(cardSub)
		if not cardSub or not cardSub.time then
			Event.ClearNextEvent()
			return
		end

		local date = os.date("!*t")
		date.isdst = false
		local curTime = os.time(date)
		local Btime = cardSub.time - curTime
		
		if Btime >= 1 then
			local days = math.floor(Btime/86400)
			local hours = math.floor(math.mod(Btime, 86400)/3600)
			local minutes = math.floor(math.mod(Btime,3600)/60)
			local seconds = math.floor(math.mod(Btime,60))
			local eventTimeStr = string.format("%02dD %02dH %02dM %02dS", days,hours,minutes,seconds)
			Event.UI.divProgress:setText(eventTimeStr)
			Event.UI.divProgress:setValue(Event.ReturnPercent(curTime, cardSub.time))
			Event.CountEvent = scheduleEvent(function() 
				Event.Counter(cardSub)
			end, 1000)
		else
			Event.DefineNextEvent()
		end
	end

	Event.BorderFlow = function(card, fadeIn)
		if not card or not card.Border then
			return false
		end
		card.Border:setChecked(true)
		card.title:setChecked(true)
		if card.BorderFill then
			if fadeIn then
				card.BorderFill:setVisible(true)
				g_effects.fadeIn(card.BorderFill, 1200)
			else
				g_effects.fadeOut(card.BorderFill, 1200)
			end
		end

		Event.BorderEvent = scheduleEvent(function()
			Event.BorderFlow(card, not fadeIn)
		end, 1300)
	end

	Event.HighlightNextSubEvent = function(subWidget)
		if Event.SubHighlightEvent then
			removeEvent(Event.SubHighlightEvent)
			Event.SubHighlightEvent = nil
		end
		if Event.SubHighlightWidget and Event.SubHighlightWidget ~= subWidget then
			local prev = Event.SubHighlightWidget
			if prev.highlight then prev.highlight:setVisible(false) end
		end
		Event.SubHighlightWidget = subWidget
		if not subWidget or not subWidget.highlight then
			return
		end
		subWidget.highlight:setVisible(true)

		local function pulse(fadeIn)
			if not Event.SubHighlightWidget or Event.SubHighlightWidget ~= subWidget then
				return
			end
			if subWidget:isDestroyed() or not subWidget.highlight then
				return
			end
			if fadeIn then
				g_effects.fadeIn(subWidget.highlight, 1000)
			else
				g_effects.fadeOut(subWidget.highlight, 1000)
			end
			Event.SubHighlightEvent = scheduleEvent(function()
				pulse(not fadeIn)
			end, 1100)
		end
		pulse(false)
	end

	Event.ClearSubHighlight = function()
		if Event.SubHighlightEvent then
			removeEvent(Event.SubHighlightEvent)
			Event.SubHighlightEvent = nil
		end
		if Event.SubHighlightWidget and Event.SubHighlightWidget.highlight then
			Event.SubHighlightWidget.highlight:setVisible(false)
		end
		Event.SubHighlightWidget = nil
	end
	
	
	Event.MoveToolTip = function()
	local pos = g_window.getMousePosition()
	local windowSize = g_window.getSize()
	local labelSize = Event.Tooltip:getSize()
  
	pos.x = pos.x + 1
	pos.y = pos.y + 1
  
	if windowSize.width - (pos.x + labelSize.width) < 10 then
	  pos.x = pos.x - labelSize.width - 3
	else
	  pos.x = pos.x + 10
	end
  
	if windowSize.height - (pos.y + labelSize.height) < 10 then
	   pos.y = pos.y - labelSize.height - 3
	else
	  pos.y = pos.y + 10
	end    
	Event.Tooltip:setPosition(pos)
	end

	Event.DestroyConfirmBox = function()
		if Event.ConfirmBox then Event.ConfirmBox:destroy() Event.ConfirmBox = nil end
	end

	Event.EnterConfirmation = function(data)
		Event.DestroyConfirmBox()
		local confirmFunc = function()Event.DestroyConfirmBox()  g_net.Send("Event", { make = "confirmEvent", eventKey = data.eventKey, confirmed = true }) end
		local cancelFunc = function() Event.DestroyConfirmBox() end
		Event.ConfirmBox = displayGeneralBox("Event Warning",
		tr(data.text),
		{
			{text="Yes", callback=confirmFunc},
			{text="No", callback=cancelFunc},
			anchors = AnchorHorizontalCenter
		}, confirmFunc, cancelFunc)

		-- Prevent focus steal: keep gameRootPanel focused so WASD continues working
		if Event.ConfirmBox then
			Event.ConfirmBox:setFocusable(false)
			local gameRootPanel = modules.game_interface.getRootPanel()
			if gameRootPanel then
				gameRootPanel:focus()
			end
		end
	end

	Event.DestroyWarning = function()	
		if Event.WarningEvent then
			removeEvent(Event.WarningEvent)
		end
		if Event.WarningUI then
			Event.WarningUI:destroy()
			Event.WarningUI = nil
		end
	end

	Event.ShowWarning = function(data)	
		Event.DestroyWarning()	
		Event.WarningUI = g_ui.displayUI("warning")
		Event.WarningUI.layer.data = data

		Event.WarningUI.closeButton.onClick = function(self)
			Event.DestroyWarning()
		end

		-- local panelCount = modules.game_interface.getLeftVisibles()
		-- local pos = modules.game_interface.getRootPanel().removeLeftPanel:getPosition()
		-- local offsets = {
		-- 	[0] = {x = 200, y = 10},
		-- 	[1] = {x = 100, y = 10},
		-- 	[2] = {x = 30, y = 15},
		-- 	[3] = {x = 20, y = 80}
		-- }

		-- pos.x = pos.x + offsets[panelCount].x 
		-- pos.y = pos.y + offsets[panelCount].y 

		Event.UpdateWarningPos()

		if data.title then
			Event.WarningUI.title:setText(data.title)
		end
		Event.WarningUI.icon:setVisible(false)
		if data.icon then
			Event.WarningUI.icon:setImageSource("/images/ui/events/smallbanner/" .. data.icon)
			Event.WarningUI.icon:setVisible(true)
		end

		Event.WarningUI.layer.onClick = function(self)
			if self.data.eventKey then
				g_net.Send("Event", { make = "confirmEvent", eventKey = self.data.eventKey })
			end
			Event.DestroyWarning()
		end

		-- Prevent focus steal: keep gameRootPanel focused so WASD continues working
		if Event.WarningUI then
			Event.WarningUI:setFocusable(false)
			local gameRootPanel = modules.game_interface.getRootPanel()
			if gameRootPanel then
				gameRootPanel:focus()
			end
		end
	end

	Event.UpdateWarningPos = function()
		if not Event.WarningUI then
		return
		end

		local pos = modules.game_interface.getLeftActionPanel():getPosition()
		pos.x = pos.x + modules.game_interface.getLeftActionPanel():getWidth() + 10

		Event.WarningUI:breakAnchors()
		Event.WarningUI:setPosition(pos)
		Event.WarningUI:raise()
	end

end


-- =====================================================================
-- Hide and Seek :: staff disguise picker (lives inside game_event)
-- ---------------------------------------------------------------------
-- Server transport: hideAndSeekEvent/6_disguise_net.lua over the shared
-- opcode-70 "Event" channel. Every packet carries make="hideSeekNet" plus
-- an `hs` subtype. See Event.DataManager for the dispatch entry point.
-- ASCII-only strings (non-ASCII would render as mojibake).
-- =====================================================================

-- 5 columns x 4 rows = 20 disguises per page (matches the .otui grid).
local DISGUISE_PAGE_SIZE = 40

-- Tear down the picker window (idempotent).
Event.DestroyDisguise = function()
	if Event.DisguiseUI then
		Event.DisguiseUI:destroy()
		Event.DisguiseUI = nil
	end
	Event.DisguiseSelected = nil
	Event.DisguiseCurrent = nil
	Event.DisguiseItems = nil
	Event.DisguisePage = nil
end

-- Lazily build the picker window and wire its controls once.
Event.CreateDisguise = function()
	if Event.DisguiseUI then
		return
	end

	local ui = g_ui.displayUI('hideseek_disguise')
	Event.DisguiseUI = ui
	ui:hide()
	ui:setFocusable(false)  -- never steal keyboard focus from the game map

	-- No manual close (no CloseButton, no Escape): the picker stays open the
	-- whole hide so the staffer can swap disguise whenever they want. It is
	-- torn down only by the server (closeDisguise -> DestroyDisguise).

	ui.wearButton.onClick = function()
		Event.WearDisguise()
		-- Return focus to the map so movement is not blocked after clicking.
		local gameRootPanel = modules.game_interface.getRootPanel()
		if gameRootPanel then
			gameRootPanel:focus()
		end
	end

	ui.pagerPanel.prevButton.onClick = function()
		Event.ShowDisguisePage((Event.DisguisePage or 1) - 1)
	end
	ui.pagerPanel.nextButton.onClick = function()
		Event.ShowDisguisePage((Event.DisguisePage or 1) + 1)
	end

end

-- Select a cell (click). Uses a manual $checked highlight instead of keyboard
-- focus, so selecting a disguise never steals movement keys from the game map.
Event.SelectDisguiseCell = function(cell, sid)
	local ui = Event.DisguiseUI
	if ui and ui.disguiseGrid then
		for _, c in ipairs(ui.disguiseGrid:getChildren()) do
			c:setChecked(c == cell)
		end
	end
	Event.DisguiseSelected = sid
end

-- Render one page of the sliced list. Sprites use the CLIENT id (cid); each
-- cell also carries the SERVER id (sid). Re-highlights the worn disguise
-- (sid == current) whenever it lands on the visible page, and refreshes the
-- pager label / button states. Page is clamped to [1, pages].
Event.ShowDisguisePage = function(page)
	local ui = Event.DisguiseUI
	if not ui then
		return
	end

	local items = Event.DisguiseItems or {}
	local total = #items
	local pages = math.max(1, math.ceil(total / DISGUISE_PAGE_SIZE))

	page = page or 1
	if page < 1 then page = 1 end
	if page > pages then page = pages end
	Event.DisguisePage = page

	local grid = ui.disguiseGrid
	grid:destroyChildren()

	local first = (page - 1) * DISGUISE_PAGE_SIZE + 1
	local last = math.min(first + DISGUISE_PAGE_SIZE - 1, total)

	local current = Event.DisguiseCurrent or 0
	local selected = Event.DisguiseSelected
	for i = first, last do
		local entry = items[i]
		local sid = entry.sid
		local cid = entry.cid
		local cell = g_ui.createWidget('HideSeekDisguiseCell', grid)
		cell.sid = sid
		cell.cid = cid
		cell.item:setItemId(cid)
		if current ~= 0 and current == sid then
			cell:setOn(true)          -- worn disguise (green border)
		end
		if selected and selected == sid then
			cell:setChecked(true)     -- selected to wear (gold border)
		end
		-- Single-click selects (mouse only, no keyboard focus, so the game map
		-- keeps focus and movement keeps working); double-click picks now.
		cell.onClick = function()
			Event.SelectDisguiseCell(cell, sid)
		end
		cell.onDoubleClick = function()
			Event.DisguiseSelected = sid
			Event.WearDisguise()
		end
	end

	ui.pagerPanel.pageLabel:setText(tr('Page %d / %d', page, pages))
	ui.pagerPanel.prevButton:setEnabled(page > 1)
	ui.pagerPanel.nextButton:setEnabled(page < pages)

	-- Keep the game map focused so WASD/arrow movement keeps working while this
	-- overlay is open (mirrors the ConfirmBox focus-steal guard in this file).
	local gameRootPanel = modules.game_interface.getRootPanel()
	if gameRootPanel then
		gameRootPanel:focus()
	end
end

-- (Re)fill the candidate list and highlight the worn disguise. Items arrive as
-- { { sid = <serverId>, cid = <clientId> }, ... } and current is the worn
-- serverId (or 0). Opens on the page holding the worn disguise, else page 1.
Event.FillDisguise = function(items, current)
	Event.CreateDisguise()
	local ui = Event.DisguiseUI

	-- Normalize entries: accept both the new { sid, cid } shape and the older
	-- flat numeric id (in which case server id and client id are the same), so a
	-- server still sending the old format cannot crash the picker.
	local normalized = {}
	for _, entry in ipairs(items or {}) do
		if type(entry) == 'table' then
			local sid = entry.sid or entry.cid
			local cid = entry.cid or entry.sid
			if sid and cid then
				normalized[#normalized + 1] = { sid = sid, cid = cid }
			end
		elseif type(entry) == 'number' then
			normalized[#normalized + 1] = { sid = entry, cid = entry }
		end
	end

	Event.DisguiseItems = normalized
	Event.DisguiseCurrent = current or 0
	Event.DisguiseSelected = nil

	-- Jump to the page that contains the worn disguise (server-id match).
	local page = 1
	if Event.DisguiseCurrent ~= 0 then
		for i = 1, #Event.DisguiseItems do
			if Event.DisguiseItems[i].sid == Event.DisguiseCurrent then
				page = math.floor((i - 1) / DISGUISE_PAGE_SIZE) + 1
				break
			end
		end
	end

	Event.ShowDisguisePage(page)

	ui:show()
	ui:raise()

	-- Show/raise must not grab keyboard focus (movement keeps working).
	local gameRootPanel = modules.game_interface.getRootPanel()
	if gameRootPanel then
		gameRootPanel:focus()
	end
end

-- Send the currently selected SERVER id to the server as a disguise pick.
Event.WearDisguise = function()
	local id = Event.DisguiseSelected
	if not id or id == 0 then
		return
	end
	g_net.Send("Event", { make = "hideSeekNet", hs = "pickDisguise", itemId = id })
end

-- Ask the server to (re)send the list. Used on relog to reopen the picker
-- for a staffer who is still hiding; the server ignores non-hiders.
Event.RequestDisguiseList = function()
	g_net.Send("Event", { make = "hideSeekNet", hs = "requestDisguiseList" })
end

-- Dispatch entry point for make=="hideSeekNet" packets (from DataManager).
Event.OnDisguiseNet = function(buffer)
	if buffer.hs == "disguiseList" then
		Event.FillDisguise(buffer.items, buffer.current)
	elseif buffer.hs == "closeDisguise" then
		Event.DestroyDisguise()
	end
end

