-- Auto Loot window (server data/scripts/chaos/autoloot.lua, extended opcode 216, JSON {action, data}).
--   client -> server  open | add {name} | add {clientId, quiet} | remove {name} | remove {clientId, quiet} | clear | sync
--   server -> client  open {itemsTable, currentSlot, maxSlot} (the window shows it) | list {...} (kept only)
--
-- The item right-click menu of game_interface has three entries of the base client's Quick Loot (game_quickloot):
-- "Manage Loot containers", "Add to Loot List" / "Remove from Loot List". That module talks the Quick Loot packets of
-- newer protocols, which a 10.98 server does not have: its window set containers nobody used, and its list stayed in
-- the client (live test winpkg-35). hookQuickLoot() points those entries at the real systems: the Loot Bag rules
-- (game_pouches, the store pouch that collects the loot) and this server-side autoloot list.

local autoLootOpcode = 216

-- donor server ships this helper in its gamelib; the base client does not, so keep a local copy.
local function sendAction(opcode, action, data)
	local protocolGame = g_game.getProtocolGame()
	if protocolGame then
		protocolGame:sendExtendedOpcode(opcode, json.encode({action = action, data = data or {}}))
	end
end
local windowAutoLoot, autoLootButton
local known = {} -- client ids on the server's autoloot list (the last "open" or "list")

local function remember(data)
	known = {}
	for _, row in ipairs(type(data) == "table" and type(data.itemsTable) == "table" and data.itemsTable or {}) do
		local cid = tonumber(row[1])
		if cid then
			known[cid] = true
		end
	end
end

function isOnList(clientId)
	return known[tonumber(clientId) or 0] == true
end

-- the item menu: add or remove one item by client id; the window stays closed (the server answers "list")
function addItem(clientId)
	clientId = tonumber(clientId)
	if not clientId or not g_game.isOnline() then
		return false
	end
	sendAction(autoLootOpcode, "add", {clientId = clientId, quiet = true})
	return true
end

function removeItem(clientId)
	clientId = tonumber(clientId)
	if not clientId or not g_game.isOnline() then
		return false
	end
	sendAction(autoLootOpcode, "remove", {clientId = clientId, quiet = true})
	return true
end

-- "Manage Loot containers": the Loot Bag rules (what goes into the bag); without game_pouches, this window
function manageLootContainers()
	local pouches = modules.game_pouches
	if pouches and pouches.showSettings then
		pouches.showSettings()
	else
		onOpenAutoLoot()
	end
end

local quickLootOriginal = {}

-- the base Quick Loot module's menu entry points, pointed at this module (the module env is shared, so its own calls
-- follow too). Safe to call again; terminate() puts the originals back.
function hookQuickLoot()
	local q = modules.game_quickloot
	if type(q) ~= "table" or q.chaosHooked then
		return
	end
	local replace = {
		showQuickLoot = function() manageLootContainers() end,
		inWhiteList = function(clientId) return isOnList(clientId) end,
		addToQuickLoot = function(clientId) addItem(clientId) end,
		removeItemInList = function(clientId) removeItem(clientId) end
	}
	for name, fn in pairs(replace) do
		quickLootOriginal[name] = rawget(q, name)
		q[name] = fn
	end
	q.chaosHooked = true
end

local function unhookQuickLoot()
	local q = modules.game_quickloot
	if type(q) ~= "table" or not q.chaosHooked then
		return
	end
	for name, fn in pairs(quickLootOriginal) do
		q[name] = fn
	end
	q.chaosHooked = nil
	quickLootOriginal = {}
end

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
	pcall(hookQuickLoot)
	if g_game.isOnline() then
		onGameStart()
	end
end

function terminate()
	disconnect(g_game, {
		onGameStart = onGameStart,
		onGameEnd = destroy
	})
	ProtocolGame.unregisterExtendedOpcode(autoLootOpcode)
	pcall(unhookQuickLoot)
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

	if action == "open" or action == "list" then
		remember(data)
	end
	if action == "open" then
		windowAutoLoot:show()
		windowAutoLoot:raise()
		windowAutoLoot:focus()
		autoLootButton:setOn(true)
		refreshAutolootWindow(data)
	elseif action == "list" and windowAutoLoot:isVisible() then
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
		autoLootButton:setOn(false)
	end
end

function destroy()
	known = {}
end

function onGameStart()
	known = {}
	pcall(hookQuickLoot)
	sendAction(autoLootOpcode, "sync")
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
