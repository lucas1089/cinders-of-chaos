-- chunkname: @/mods/game_autoloot/loot.lua

local autoLootOpcode = 216

-- donor server ships this helper in its gamelib; the base client does not, so keep a local copy.
local function sendAction(opcode, action, data)
	local protocolGame = g_game.getProtocolGame()
	if protocolGame then
		protocolGame:sendExtendedOpcode(opcode, json.encode({action = action, data = data or {}}))
	end
end
local windowAutoLoot, autoLootButton

function init()
	connect(g_game, {
		onGameStart = onGameStart,
		onGameEnd = destroy
	})

	windowAutoLoot = g_ui.displayUI("loot")

	windowAutoLoot:hide()

	autoLootButton = modules.client_topmenu.addRightGameToggleButton("AutolootButton", tr("Autoloot"), "/images/topbuttons/loot", toggle, false, 9999)

	autoLootButton:setOn(false)

	function windowAutoLoot.add.onClick()
		local text = windowAutoLoot.editItemName:getText()
		if tonumber(text) then
			sendAction(autoLootOpcode, "add", {clientId = tonumber(text)})
		else
			sendAction(autoLootOpcode, "add", {name = text})
		end

		windowAutoLoot.editItemName:clearText()
	end

	function windowAutoLoot.clear.onClick()
		sendAction(autoLootOpcode, "clear")
	end

	g_keyboard.bindKeyDown("Escape", autolootWindowHide)
	ProtocolGame.registerExtendedOpcode(autoLootOpcode, autolootOpcodeParse)
end

function terminate()
	disconnect(g_game, {
		onGameEnd = destroy
	})
	ProtocolGame.unregisterExtendedOpcode(autoLootOpcode)
end

function autolootOpcodeParse(protocol, code, buffer)
	local json_status, json_data = pcall(function()
		return json.decode(buffer)
	end)

	if not json_status then
		g_logger.error("[autoloot] JSON error: " .. tostring(json_data))

		return false
	end

	local action = json_data.action
	local data = json_data.data

	if action == "open" then
		if not windowAutoLoot:isVisible() then
			toggle()
		end

		windowAutoLoot:show()
		windowAutoLoot:raise()
		windowAutoLoot:focus()
		autoLootButton:setOn(true)
		refreshAutolootWindow(data)
	end
end

function refreshAutolootWindow(data)
	if not data then
		return
	end

	windowAutoLoot.listLoot:destroyChildren()

	for i = 1, #data.itemsTable do
		local items = g_ui.createWidget("RowListLoot", windowAutoLoot.listLoot)

		items.rowItem:setItemId(data.itemsTable[i][1])
		items.rowItemName:setText(data.itemsTable[i][2])

		function items.rowButtonRemove.onClick()
			sendAction(autoLootOpcode, "remove", {name = data.itemsTable[i][2]})
		end
	end

	windowAutoLoot.slots:setText(tr('Current Slots: %s/%s', data.currentSlot, data.maxSlot))
end

function autolootWindowHide()
	if not g_game.isOnline() then
		return
	end

	if windowAutoLoot:isVisible() then
		windowAutoLoot:setVisible(false)
	end
end

function destroy()
	return
end

function onGameStart()
	return
end

function toggle()
	if not g_game.isOnline() then
		return
	end

	if windowAutoLoot:isVisible() then
		windowAutoLoot:hide()
		autoLootButton:setOn(false)
	else
		onOpenAutoLoot()
	end
end

function onOpenAutoLoot()
	sendAction(autoLootOpcode, "open")
end
