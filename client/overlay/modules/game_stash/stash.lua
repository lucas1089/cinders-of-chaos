Stash = {}
local CODE = 57
local Filter = "AllItems"
local DepotId = 3502

Stash.Data = {}
Stash.Opcode = 110 -- must match ChaosOpcodes.stash on the server
Stash.CategoryData = nil
Stash.BlockList = {}

Stash.Init = function()
	ProtocolGame.registerExtendedOpcode(Stash.Opcode, Stash.OnExtended)

	connect(g_game, {
		onGameStart = Stash.OnStart,
		onGameEnd = Stash.OnEnd
	})

	connect(LocalPlayer, {
		onPositionChange = Stash.OnWalkClose,
		onWalk = Stash.OnWalkClose
	})

	StashButton = modules.game_extramenu.Menu.AddButton("Stash",  function() modules.game_stash.vipToggle() end, "stash", nil)
	Stash.Progress = g_ui.displayUI("stash_progress")
	Stash.Progress:hide()

	Keybind.new("Windows", "Toggle Stash", "", "")
	Keybind.bind("Windows", "Toggle Stash", {
		{
		  type = KEY_DOWN,
		  callback = Stash.Toggle,
		}
	})

	Stash.HookDragHint()
end

-- Monkey-patches UIItem.onDragEnter/onDragLeave to flash the stash drop hint.
-- The original handlers are captured once and restored on Terminate so that
-- module reloads don't leak wrappers on top of wrappers.
Stash.HookDragHint = function()
	if Stash._dragHookInstalled then
		return
	end
	Stash._dragHookInstalled = true
	Stash._origDragEnter = UIItem.onDragEnter
	Stash._origDragLeave = UIItem.onDragLeave

	function UIItem:onDragEnter(mousePos)
		local result = Stash._origDragEnter(self, mousePos)
		if result and Stash.UI and Stash.UI:isVisible() and Stash.UI.DropHint then
			Stash.UI.DropHint:setVisible(true)
		end
		return result
	end

	function UIItem:onDragLeave(droppedWidget, mousePos)
		if Stash.UI and Stash.UI.DropHint then
			Stash.UI.DropHint:setVisible(false)
		end
		return Stash._origDragLeave(self, droppedWidget, mousePos)
	end
end

Stash.UnhookDragHint = function()
	if not Stash._dragHookInstalled then
		return
	end
	UIItem.onDragEnter = Stash._origDragEnter
	UIItem.onDragLeave = Stash._origDragLeave
	Stash._origDragEnter = nil
	Stash._origDragLeave = nil
	Stash._dragHookInstalled = false
end

Stash.Terminate = function()
	ProtocolGame.unregisterExtendedOpcode(Stash.Opcode)
	if Stash.UI then
		Stash.UI:destroy()
		Stash.UI = nil
	end

	if Stash.Progress then
		Stash.Progress:destroy()
		Stash.Progress = nil
	end

	Keybind.delete("Windows", "Toggle Stash")

	disconnect(g_game, {
		onGameStart = Stash.OnStart,
		onGameEnd = Stash.OnEnd
	})
	-- Was passing the global `destroy` (nil) here, so the hooks were never
	-- actually disconnected. Use the same reference we connected with.
	disconnect(LocalPlayer, {
		onPositionChange = Stash.OnWalkClose,
		onWalk = Stash.OnWalkClose
	})

	Stash.UnhookDragHint()
end

Stash.CreateUI = function()
	Stash.UI = g_ui.displayUI('stash')
	Stash.UI.Overlay:setVisible(false)
	Stash.UI:hide()

	Stash.UIConfirm = g_ui.loadUI('stash_confirm', Stash.UI)
	Stash.UIConfirm:hide()
	Stash.UI.onEscape = Stash.Toggle
	Stash.UI.onDrop = Stash.OnDrop
	Stash.UI.SupplyList.onDrop = Stash.OnDrop
	Stash.Define()
end

Stash.OnDrop = function(self, widget, mousePos, forced)
	local item = widget and widget.currentDragThing
	if not item or not item.isItem or not item:isItem() then
	return false
	end
	if not item:isPickupable() then
	return false
	end
	if not item:isStackable() then
	return false
	end
	Stash.StashItem(item, 1)
	return false
end


Stash.Communicate = function(Data)
	local protocolGame = g_game.getProtocolGame()
	if protocolGame then
		protocolGame:sendExtendedOpcode(Stash.Opcode, Data)
		return true
	end
end

Stash.OnStart = function()
	Stash.CreateUI()

	scheduleEvent(function()
		Stash.Communicate(json.encode({action = "Stash", data = {
			make = "SendCategories",
			sendBlocks = true
		}}))
	end, 100)
end

Stash.OnEnd = function()
	Stash.Destroy()

	Stash.BlockList = nil
	Stash.BlockList = {}

	if Stash.Progress and Stash.Progress:isVisible() then
		Stash.Progress:hide()
	end
end


Stash.Destroy = function()
	if Stash.UI then
		Stash.UI:destroy()
		Stash.UI = nil
	end
end

-- Fecha o stash ao andar, EXCETO se o jogador tem acesso remoto (supply stash
-- remote access): nesse caso a janela fica aberta enquanto anda. A flag
-- Stash.remoteAccess vem do server no Toggle (getStorageValue VipStashStorage).
Stash.OnWalkClose = function()
	if Stash.remoteAccess then return end
	Stash.Destroy()
end


Stash.Toggle = function()
	if not Stash.UI then
		Stash.CreateUI()
	end
	if Stash.UI:isVisible() then
		Stash.UI:hide()
		Stash.UIConfirm:hide()
		Stash.UI.Overlay:setVisible(false)
		Stash.UI.SupplyList:destroyChildren()
	else
		if Stash.Progress and Stash.Progress:isVisible() then
			return false
		end
		Stash.UI.SupplyList:destroyChildren()
		Stash.UI:show()
		-- sem :focus() ao abrir: nao rouba o teclado do jogo (Escape via game_windowfocus)
		-- walk-through: andar (WASD/setas) enquanto deposita/saca na janela
		if modules.game_windowfocus and modules.game_windowfocus.enableWalkThrough then
			modules.game_windowfocus.enableWalkThrough(Stash.UI)
		end
		Stash.Data = nil
		Stash.UI.Search:clearText()
		Stash.Data = {}
		Stash.FillCategories()
		Stash.UI.Filter:setCurrentIndex(1, true)
		Stash.Communicate(json.encode({action = "Stash", data = {
			make = "SendItems", 
		}}))
	end
end

Stash.DataManager = function(protocol, opcode, buffer)
	if buffer.make == "addItems" then
		-- Batched stream: each packet carries a chunk of items plus isFirst/isLast
		-- flags. We accumulate into Stash.Data and only render once the last
		-- chunk arrives, so the list is sorted and drawn in one shot.
		if buffer.isFirst then
			Stash.Data = {}
		end
		if buffer.items then
			for i = 1, #buffer.items do
				-- Re-wrap into the legacy {itemData = ...} shape so sort/filter
				-- code below doesn't have to change.
				table.insert(Stash.Data, {itemData = buffer.items[i]})
			end
		end
		if buffer.isLast then
			table.sort(Stash.Data, function(a, b) return a.itemData.count > b.itemData.count end)
			-- UI may have been destroyed between request and response (walk,
			-- logout, etc). Bail silently — next Toggle re-fetches anyway.
			if not (Stash.UI and Stash.UI.SupplyList) then
				return
			end
			-- Wipe previous widgets here (not in StashItem/Toggle) so the
			-- old list stays visible until the refreshed one is ready to draw.
			Stash.UI.SupplyList:destroyChildren()
			-- Re-apply the active text filter so the player's search isn't
			-- silently bypassed by the refresh.
			local search = Stash.UI.Search and Stash.UI.Search:getText() or ""
			if search ~= "" and Stash.CreateItem then
				local needle = search:lower()
				for i = 1, #Stash.Data do
					if string.find(Stash.Data[i].itemData.name:lower(), needle, 1, true) then
						Stash.CreateItem(Stash.Data[i].itemData)
					end
				end
			elseif Stash.CreateList then
				Stash.CreateList(Stash.Data)
			end
		end
	elseif buffer.make == "Toggle" then
		Stash.remoteAccess = (buffer.remote == true)
		Stash.Toggle()
	elseif buffer.make == "addCategorys" then
		Stash.CategoryData = buffer
		Stash.remoteAccess = (buffer.remote == true)
		Stash.FillCategories()
	elseif buffer.make == "StashAll" then
		Stash.StashAll(buffer)
	elseif buffer.make == "addBlockItem" then
		Stash.BlockListUpdate(buffer)
	elseif buffer.make == "forceBlockList" then
		-- Full block-list snapshot (sent once on category load).
		Stash.BlockList = {}
		if buffer.items then
			for i = 1, #buffer.items do
				table.insert(Stash.BlockList, buffer.items[i])
			end
		end
	end
end

-- Replaces the donor client's client_manager: decode the JSON payload and dispatch.
Stash.OnExtended = function(protocol, opcode, buffer)
	local ok, data = pcall(json.decode, buffer)
	if ok and type(data) == "table" and type(data.data) == "table" then
		Stash.DataManager(protocol, opcode, data.data)
	end
end

Stash.Define = function()

	Stash.UI.CloseButton.onClick = function()
		Stash.Toggle()
	end
	
	Stash.UIConfirm.OkButton.onClick = function()
		Stash.UIConfirm:hide()
		Stash.UI.Overlay:setVisible(false)
		Stash.UI.SupplyList:destroyChildren()
		Stash.Data = nil
		Stash.UI.Search:clearText()
		Stash.Data = {}
		Stash.UI.Filter:setCurrentIndex(1, true)
		Stash.Communicate(json.encode({action = "Stash", data = {
			make = "Redeem",
			item = Stash.UIConfirm.SupplyIcon.serverId,
			id = Stash.UIConfirm.SupplyIcon.uniqueId,
			count = Stash.UIConfirm.quantityScroll:getValue()
		}}))	
	end	
	
	Stash.UIConfirm.CancelButton.onClick = function()
		Stash.UIConfirm:hide()
		Stash.UI.Overlay:setVisible(false)	
	end	
	
	Stash.UI.Search.onTextChange = function(self, text, oldText)
		if Stash.Data then
			Stash.UI.SupplyList:destroyChildren()
			for i = 1,#Stash.Data do
				if string.find(Stash.Data[i].itemData.name:lower(), text:lower()) then
				Stash.CreateItem(Stash.Data[i].itemData)
				end
			end
		end
	end

	Stash.UI.Filter:addOption("Amount", 1)
	Stash.UI.Filter:addOption("Name", 2)

	Stash.FillCategories = function()
		if not Stash.UI then
		return false
		end
		if Stash.CategoryData then
			Stash.UI.Filter:clearOptions()
			Stash.UI.Filter:addOption("Amount", 1)
			Stash.UI.Filter:addOption("Name", 2)
			for i = 1,#Stash.CategoryData.list do
				Stash.UI.Filter:addOption(Stash.CategoryData.list[i].name, Stash.CategoryData.list[i].value)
			end
		else
			Stash.UI.Filter:clearOptions()
			Stash.UI.Filter:addOption("Amount", 1)
			Stash.UI.Filter:addOption("Name", 2)
		end
	end

	Stash.UI.Filter.onOptionChange = function(self, option, value)
		if Stash.Data then
			Stash.UI.SupplyList:destroyChildren()
			if value == 1 then
				table.sort(Stash.Data, function(a, b) return a.itemData.count > b.itemData.count end)
			elseif value == 2 then
				table.sort(Stash.Data, function(a, b) return a.itemData.name:lower() < b.itemData.name:lower() end)
			else
				local NewList = {}
				for i = 1,#Stash.Data do
					if Stash.Data[i].itemData.typee ==  value then
						table.insert(NewList, Stash.Data[i])
					end
				end

				Stash.CreateList(NewList)
				return true
			end

			Stash.CreateList(Stash.Data)
		end
	end

	Stash.CreateList = function(Data)
		for i = 1,#Data do
			Stash.CreateItem(Data[i].itemData)
		end
	end

	Stash.CreateItem = function(Data)
		local itemWidget = g_ui.createWidget('SupplyItem', Stash.UI.SupplyList)
		itemWidget:setItemId(Data.sprite)
		itemWidget.countbase:setText(Data.count)
		-- UIItem's internal count is uint16 (see client/src/client/item.h),
		-- so passing the raw stash count overflows for any value >= 65536 and
		-- silently displays a wrong stack-art tier. The number the player sees
		-- is the `countbase` label above; the engine count is only used to
		-- pick the stack sprite (1/2/5/10/25/50/100), so capping at 100 gives
		-- the "full pile" sprite for any large stack and stays inside uint16.
		itemWidget:setItemCount(math.min(Data.count, 100))
		itemWidget:setShowCount(false)
		itemWidget:setMargin(0)
		itemWidget:setDraggable(false)
		itemWidget:buildTooltip(Data.tooltip)
		itemWidget.serverId = Data.id
		itemWidget.uniqueId = Data.uniqueId

		itemWidget.onClick = function(self)
			Stash.UI.Overlay:setVisible(true)
			Stash.UI.Overlay.background:setVisible(false)
			Stash.UI.Overlay.BlockListBase:setVisible(false)
			Stash.UIConfirm.SupplyIcon:setItemId(Data.sprite)
			Stash.UIConfirm.SupplyIcon:setItemCount(math.min(Data.count, 100))
			Stash.UIConfirm.SupplyIcon:setDraggable(false)
			-- Horizontal scrollbar takes int32, so cap at a sane redeem-per-click
			-- ceiling instead of the previous 100k magic number — players with
			-- millions of crystals still pick how many to take, just in larger
			-- steps. The label still shows the real total on the stash icon.
			local cap = math.min(Data.count, 1000000)
			Stash.UIConfirm.quantityScroll:setMinimum(1)
			Stash.UIConfirm.quantityScroll:setMaximum(cap)
			Stash.UIConfirm.quantityScroll:setValue(cap)
			Stash.UIConfirm:show()
			Stash.UIConfirm:raise()
			Stash.UIConfirm.SupplyIcon.serverId = self.serverId
			Stash.UIConfirm.SupplyIcon.uniqueId = self.uniqueId
		end
	end

	Stash.UI.ClearSearchButton.onClick = function()
		Stash.UI.Search:clearText()
	end

	Stash.UI.DisableListButton.onClick = function(self)
		Stash.UI.Overlay:setVisible(true)
		Stash.UI.Overlay.background:setVisible(true)
		Stash.UI.Overlay.BlockListBase:setVisible(true)
		Stash.UI.Overlay.BlockListBase.BlockList:destroyChildren()
		if #Stash.BlockList <= 0 then
		return false
		end
		for i = 1,#Stash.BlockList do
			local blockItem = g_ui.createWidget("SuppplyBlock", Stash.UI.Overlay.BlockListBase.BlockList)
			blockItem:setId("item" .. Stash.BlockList[i].sprite)
			blockItem.item:setItemId(Stash.BlockList[i].sprite)
			blockItem.data = Stash.BlockList[i]
			blockItem.name:setText(Stash.BlockList[i].name)
			blockItem.RemoveButton.onClick = function(self)
				Stash.Communicate(json.encode({action = "Stash", data = {
					make = "ChangeStash",
					RemoveUI = true,
					itemId = self:getParent().data.id
				}}))
				self:getParent():destroy()
			end
		end
	end

	Stash.UI.Overlay.BlockListBase.CloseButton.onClick = function(self)
		Stash.UI.Overlay:setVisible(false)
	end

end

Stash.StashAll = function(Data)
	if Data.status == true then
		if Stash.UI and Stash.UI:isVisible() then
			Stash.Toggle()
		end

		Stash.Progress:show()
		if Stash.Progress.Event then
			removeEvent(Stash.Progress.Event)
		end
		Stash.AllEvent(1)
	return true
	end

	if Stash.Progress.Event then
		removeEvent(Stash.Progress.Event)
	end
	Stash.Progress:hide()
	return false
end

Stash.AllEvent = function(Points)
	if Stash and Stash.Progress and Stash.Progress:isVisible() then
		Stash.Progress.points:setWidth(Points * 3)
		if Points + 1 > 3 then
			Points = 0
		end
		Stash.Progress.Event = scheduleEvent(function() 
			Stash.AllEvent(Points + 1)
		end, 300)
	end
end

Stash.StashItem = function(item, typed)

	if Stash.CanStash(item:getId()) == false then
		return false
	end

	local pos = item:getPosition()
	-- Don't pre-emptively clear the list. The server always echoes back a
	-- fresh `addItems` stream when UpdateList=true (even on rejection paths
	-- like soulbound or locked items), and the addItems handler clears+rebuilds
	-- on isFirst/isLast. Clearing here was making the list go blank whenever
	-- the deposit was rejected, forcing the player to reopen the window.
	local visible = Stash.UI and Stash.UI:isVisible() and true or false

	Stash.Communicate(json.encode({
		action = "Stash",
		data = {
			make       = "Stash",
			UpdateList = visible,
			Typed      = typed,
			Pos        = {x = pos.x, y = pos.y, z = pos.z, stackpos = item:getStackPos()},
		},
	}))
end

Stash.CanStash = function(Id, returnPos)
	local result = true
	local pos = 0
	if #Stash.BlockList >= 1 then
		for i = 1,#Stash.BlockList do
			if Stash.BlockList[i].sprite == Id then
				result = false
				if returnPos then
					pos = i	
				end
				break
			end
		end
	end

	if returnPos then
		return result, pos
	end
	return result
end

Stash.ChangeStashStatus = function(item, state)
	local pos = item:getPosition()
	Stash.Communicate(json.encode({  action = "Stash", data = { make = "ChangeStash", Pos = {x = pos.x, y = pos.y, z = pos.z, stackpos = item:getStackPos()}   }}))   
end

Stash.BlockListUpdate = function(Data)

	local itemData = Data.itemData
	if Data.status == false then

		for i = 1,#Stash.BlockList do
			if Stash.BlockList[i].sprite == itemData.sprite then
				table.remove(Stash.BlockList, i)
				break
			end
		end

		if Stash.UI and Stash.UI.Overlay.BlockListBase:isVisible() then
			if Stash.UI.Overlay.BlockListBase.BlockList["item" .. itemData.sprite] then
				Stash.UI.Overlay.BlockListBase.BlockList["item" .. itemData.sprite]:destroy()
			end
		end

		return true
	end

	table.insert(Stash.BlockList, itemData)

	if Stash.UI and Stash.UI.Overlay.BlockListBase:isVisible() then
		local blockItem = g_ui.createWidget("SuppplyBlock", Stash.UI.Overlay.BlockListBase.BlockList)
		blockItem:setId("item" .. itemData.sprite)
		blockItem.item:setItemId(itemData.sprite)
		blockItem.data = itemData
		blockItem.name:setText(itemData.name)
		blockItem.RemoveButton.onClick = function(self)
			Stash.Communicate(json.encode({action = "Stash", data = {
				make = "ChangeStash",
				RemoveUI = true,
				itemId = self:getParent().data.id
			}}))
			self:getParent():destroy()
		end
	end
end

function confirmOk()
	if Stash.UIConfirm then
		Stash.UIConfirm.OkButton.onClick()
	end
end

function vipToggle()
	g_game.talkChannel(11,1,"!stash")
end

function ReturnWindow()
	return Stash.UI
end

function closeWalk()
	if Stash.UI and Stash.UI:isVisible() then
		Stash.UI:hide()
		if Stash.UIConfirm then
			Stash.UIConfirm:hide()
		end
		Stash.UI.SupplyList:destroyChildren()
		Stash.UI.Overlay:setVisible(false)
	end
end