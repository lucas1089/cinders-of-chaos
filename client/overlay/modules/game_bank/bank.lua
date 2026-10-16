-- chunkname: @/mods/game_bank/bank.lua
-- Bank window (server data/scripts/chaos/bank.lua, extended opcode 60). The server does the maths and checks every
-- amount; Deposit all and Withdraw all are one click. Logic without client API: bank_core.lua (bank_core_test.lua).

local B = BankCore
local bankBalanceOpCode = B.OPCODE

local function sendAction(opcode, action, data)
	local protocolGame = g_game.getProtocolGame()
	if protocolGame then
		protocolGame:sendExtendedOpcode(opcode, json.encode({action = action, data = data or {}}))
	end
end

local bankInfoTable, bankingWindow, amountWindow, bankRadioTabs, bankButton
local currencyName = "gold"

local GOLD_ITEM, STAR_ITEM = 3031, 35572

local function closeAmountWindow()
	if amountWindow then
		amountWindow:destroy()
		amountWindow = nil
	end
end

local TITLES = {
	deposit = function() return tr("Deposit") end,
	withdraw = function() return tr("Withdraw") end,
	transfer = function() return tr("Transfer") end
}

-- the amount dialog of Deposit / Withdraw / Transfer: numeric input <-> slider, quick buttons, OK / Cancel
local function openAmountWindow(mode)
	if amountWindow or not bankInfoTable then
		return
	end
	local max = B.limit(bankInfoTable, currencyName, mode)
	local w = g_ui.createWidget("BankAmountWindow", rootWidget)
	amountWindow = w
	w:setText(TITLES[mode]())

	local available = mode == "deposit" and B.limit(bankInfoTable, currencyName, "deposit") or B.limit(bankInfoTable, currencyName, "transfer")
	w.balance:setColoredText({
		tr("Your Balance Is:") .. " ", "white",
		comma_value(available), currencyName == "gold" and "yellow" or "orange"
	})

	if mode == "transfer" then
		w:setHeight(B.HEIGHT.transfer)
	else
		w.recipientRow:hide()
		w.recipientRow:setHeight(0)
		w.recipientRow:setMarginTop(0)
		w:setHeight(B.HEIGHT.amount)
	end

	local edit, slider = w.amountRow.amountEdit, w.value
	local syncing = false
	local function setAmount(amount, fromEdit)
		if syncing then
			return
		end
		syncing = true
		amount = math.max(0, math.min(max, amount))
		slider:setValue(amount)
		if not fromEdit then
			edit:setText(tostring(amount))
		end
		syncing = false
	end

	slider:setMinimum(0)
	slider:setMaximum(max)
	slider:setStep(math.max(1, math.floor(max / 100)))
	slider.onValueChange = function(_, value)
		setAmount(value, false)
	end
	edit.onTextChange = function(_, text)
		if syncing then
			return
		end
		local digits = B.digits(text)
		if digits ~= text then
			syncing = true
			edit:setText(digits)
			syncing = false
		end
		local typed = tonumber(digits) or 0
		setAmount(B.parse(digits, max), typed <= max) -- over the limit: the input shows the limit
	end
	w.quick25.onClick = function() setAmount(B.quick(max, 25)) end
	w.quick50.onClick = function() setAmount(B.quick(max, 50)) end
	w.quickAll.onClick = function() setAmount(B.quick(max, 100)) end

	local function ok()
		local name = mode == "transfer" and w.recipientRow.recipientEdit:getText() or nil
		local action, data = B.request(mode, currencyName, B.parse(edit:getText(), max), name)
		if action then
			sendAction(bankBalanceOpCode, action, data)
			closeAmountWindow()
		end
	end
	w.buttonOk.onClick = ok
	w.buttonCancel.onClick = closeAmountWindow
	w.onEnter = ok
	w.onEscape = closeAmountWindow

	setAmount(0)
	if mode == "transfer" then
		w.recipientRow.recipientEdit:focus()
	else
		edit:focus()
	end
end

local function sendAll(action)
	local a, data = B.request(action, currencyName)
	if a then
		sendAction(bankBalanceOpCode, a, data)
	end
end

function initBank()
	bankingWindow = g_ui.displayUI("bank")
	bankingWindow:hide()

	-- the gold tab only: the star tab came with the imported client, no star currency exists in this game
	bankRadioTabs = UIRadioGroup.create()
	bankRadioTabs:addWidget(bankingWindow.gold)
	bankRadioTabs.onSelectionChange = onBankTypeChange
	bankingWindow.star:hide()

	bankingWindow.depositButton.onClick = function() openAmountWindow("deposit") end
	bankingWindow.WithdrawButton.onClick = function() openAmountWindow("withdraw") end
	bankingWindow.TransferButton.onClick = function() openAmountWindow("transfer") end
	bankingWindow.depositAllButton.onClick = function() sendAll("depositAll") end
	bankingWindow.withdrawAllButton.onClick = function() sendAll("withdrawAll") end
	bankingWindow.close.onClick = function() bankWindowtoggle() end

	connect(g_game, {
		onGameStart = refresh,
		onGameEnd = offline
	})

	bankButton = modules.client_topmenu.addRightGameToggleButton("TalentsButton", tr("Bank"), "/images/topbuttons/bank", bankWindowtoggle, false, 9999)
	bankButton:setOn(false)
	ProtocolGame.registerExtendedOpcode(bankBalanceOpCode, bankOpcode)
end

function terminateBank()
	closeAmountWindow()
	bankingWindow:hide()
	disconnect(g_game, {
		onGameStart = refresh,
		onGameEnd = offline
	})
	ProtocolGame.unregisterExtendedOpcode(bankBalanceOpCode)
end

function bankOpcode(protocol, code, buffer)
	local json_status, json_data = pcall(function()
		return json.decode(buffer)
	end)
	if not json_status or type(json_data) ~= "table" then
		g_logger.error("[bank] JSON error: " .. tostring(json_data))
		return false
	end

	if json_data.action == "open" then
		bankInfoTable = json_data.data
		openBank(bankInfoTable, currencyName)
		bankingWindow:show()
		bankingWindow:focus()
		bankButton:setOn(true)
	end
end

function refresh()
	-- the tab buttons carry an item icon only when the style defines one (CustomTabButton may not)
	local goldIcon = bankingWindow.gold:getChildById("item")
	if goldIcon then
		goldIcon:setItemId(GOLD_ITEM)
	end
	bankRadioTabs:selectWidget(bankingWindow.gold)
	bankingWindow.gold:setOn(true)
end

function openBank(data, currency)
	if not data then
		return
	end
	-- balances are shown short (15.3k), exact in the tooltip; the amount dialogs stay exact
	local function showAmount(widget, amount)
		widget:setText(formatShortNumber(tonumber(amount) or 0))
		widget:setTooltip(comma_value(amount))
	end
	local carried = B.limit(data, currency, "deposit")
	local banked = B.limit(data, currency, "transfer")
	showAmount(bankingWindow.textEdit2, carried)
	showAmount(bankingWindow.textEdit3, banked)
	local itemId = currency == "gold" and GOLD_ITEM or STAR_ITEM
	bankingWindow.item:setItemId(itemId)
	bankingWindow.item2:setItemId(itemId)
	bankingWindow.depositAllButton:setEnabled(currency == "gold" and carried > 0)
	bankingWindow.withdrawAllButton:setEnabled(currency == "gold" and banked > 0)
end

function offline()
	bankingWindow:hide()
	closeAmountWindow()
end

function onBankTypeChange(radioTabs, selected, deselected)
	currencyName = selected:getId()
	closeAmountWindow()
	openBank(bankInfoTable, currencyName)
	selected:setOn(true)
	if deselected then
		deselected:setOn(false)
	end
end

function bankWindowtoggle()
	if bankingWindow:isVisible() then
		bankingWindow:hide()
		bankButton:setOn(false)
		closeAmountWindow()
	else
		bankWindowShow()
	end
end

function bankWindowShow()
	sendAction(bankBalanceOpCode, "openBank")
	refresh()
end

function bankWindowHide()
	bankingWindow:hide()
end
