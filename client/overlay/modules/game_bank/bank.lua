-- chunkname: @/mods/game_bank/bank.lua

local bankBalanceOpCode = 60
local bankInfoTable, currencyName, bankingWindow, BankingAcceptWindow, BankingAcceptWindow2, BankingAcceptWindow, bankRadioTabs, bankButton

function initBank()
	bankingWindow = g_ui.displayUI("bank")

	bankingWindow:hide()

	bankRadioTabs = UIRadioGroup.create()

	bankRadioTabs:addWidget(bankingWindow.gold)
	bankRadioTabs:addWidget(bankingWindow.star)

	bankRadioTabs.onSelectionChange = onBankTypeChange

	connect(g_game, {
		onGameStart = refresh,
		onGameEnd = offline
	})

	bankButton = modules.client_topmenu.addRightGameToggleButton("TalentsButton", tr("Bank"), "/images/topbuttons/bank", bankWindowtoggle, false, 9999)

	bankButton:setOn(false)
	ProtocolGame.registerExtendedOpcode(bankBalanceOpCode, bankOpcode)
end

function terminateBank()
	bankingWindow:hide()
	disconnect(g_game, {
		onGameStart = refresh,
		onGameEnd = offline
	})
	ProtocolGame.unregisterExtendedOpcode(bankBalanceOpCode)
end

local currencyName = "gold"

function bankOpcode(protocol, code, buffer)
	local json_status, json_data = pcall(function()
		return json.decode(buffer)
	end)

	if not json_status then
		g_logger.error("[bank] JSON error: " .. data)

		return false
	end

	local action = json_data.action
	local data = json_data.data

	if action == "open" then
		openBank(data, currencyName)

		bankInfoTable = data

		bankingWindow:show()
		bankingWindow:focus()
		bankButton:setOn(true)
	end
end

function refresh()
	bankingWindow.gold.item:setItemId(3031)
	bankingWindow.star.item:setItemId(35572)
	bankRadioTabs:selectWidget(bankingWindow.gold)
	bankingWindow.gold:setOn(true)
end

function openBank(data, currencyName)
	if not data then
		return
	end

	if currencyName == "gold" then
		bankingWindow.textEdit2:setText(comma_value(data[1]))
		bankingWindow.textEdit3:setText(comma_value(data[2]))
		bankingWindow.item:setItemId(3031)
		bankingWindow.item2:setItemId(3031)
	else
		bankingWindow.textEdit2:setText(comma_value(data[4]))
		bankingWindow.textEdit3:setText(comma_value(data[3]))
		bankingWindow.item:setItemId(35572)
		bankingWindow.item2:setItemId(35572)
	end

	function bankingWindow.depositButton.onClick()
		if BankingAcceptWindow then
			return
		end

		BankingAcceptWindow = g_ui.createWidget("BankingAcceptWindow", rootWidget)

		if currencyName == "gold" then
			BankingAcceptWindow.balance:setColoredText({
				"Your Balance Is: ",
				"white",
				comma_value(data[1]),
				"yellow"
			})
		else
			BankingAcceptWindow.balance:setColoredText({
				"Your Balance Is: ",
				"white",
				comma_value(data[4]),
				"orange"
			})
		end

		BankingAcceptWindow.value:setMinimum(0)

		if currencyName == "gold" then
			BankingAcceptWindow.value:setMaximum(tonumber(data[1]))
		else
			BankingAcceptWindow.value:setMaximum(tonumber(data[4]))
		end

		BankingAcceptWindow.value:setValue(0)
		BankingAcceptWindow.shit:setText("The Amount: " .. comma_value(BankingAcceptWindow.value:getValue()))

		function BankingAcceptWindow.value.onValueChange(widget, value)
			BankingAcceptWindow.shit:setText("The Amount: " .. comma_value(value))
		end

		function BankingAcceptWindow.buttonOk.onClick()
			local amount = BankingAcceptWindow.value:getValue()

			sendAction(bankBalanceOpCode, "deposit", {
				currencyName,
				amount
			})
			BankingAcceptWindow:destroy()

			BankingAcceptWindow = nil
		end

		function BankingAcceptWindow.buttonCancel.onClick()
			BankingAcceptWindow:destroy()

			BankingAcceptWindow = nil
		end
	end

	function bankingWindow.WithdrawButton.onClick()
		if BankingAcceptWindow then
			return
		end

		BankingAcceptWindow = g_ui.createWidget("BankingAcceptWindow", rootWidget)

		if currencyName == "gold" then
			BankingAcceptWindow.balance:setColoredText({
				"Your Balance Is: ",
				"white",
				comma_value(data[2]),
				"yellow"
			})
		else
			BankingAcceptWindow.balance:setColoredText({
				"Your Balance Is: ",
				"white",
				comma_value(data[3]),
				"orange"
			})
		end

		BankingAcceptWindow.value:setMinimum(0)

		if currencyName == "gold" then
			BankingAcceptWindow.value:setMaximum(tonumber(data[2]))
		elseif data[3] > 1000 then
			BankingAcceptWindow.value:setMaximum(1000)
		else
			BankingAcceptWindow.value:setMaximum(tonumber(data[3]))
		end

		BankingAcceptWindow.value:setValue(0)
		BankingAcceptWindow.shit:setText("The Amount: " .. comma_value(BankingAcceptWindow.value:getValue()))

		function BankingAcceptWindow.value.onValueChange(widget, value)
			BankingAcceptWindow.shit:setText("The Amount: " .. comma_value(value))
		end

		function BankingAcceptWindow.buttonOk.onClick()
			local amount = BankingAcceptWindow.value:getValue()

			sendAction(bankBalanceOpCode, "withdraw", {
				currencyName,
				amount
			})
			BankingAcceptWindow:destroy()

			BankingAcceptWindow = nil
		end

		function BankingAcceptWindow.buttonCancel.onClick()
			BankingAcceptWindow:destroy()

			BankingAcceptWindow = nil
		end
	end

	function bankingWindow.TransferButton.onClick()
		if BankingAcceptWindow2 then
			return
		end

		BankingAcceptWindow2 = g_ui.createWidget("AcceptWindowTransfer", rootWidget)

		if currencyName == "gold" then
			BankingAcceptWindow2.balanceTransfer:setColoredText({
				"Your Balance Is: ",
				"white",
				comma_value(data[2]),
				"yellow"
			})
		else
			BankingAcceptWindow2.balanceTransfer:setColoredText({
				"Your Balance Is: ",
				"white",
				comma_value(data[3]),
				"orange"
			})
		end

		BankingAcceptWindow2.value:setMinimum(0)

		if currencyName == "gold" then
			BankingAcceptWindow2.value:setMaximum(tonumber(data[2]))
		else
			BankingAcceptWindow2.value:setMaximum(tonumber(data[3]))
		end

		BankingAcceptWindow2.value:setValue(0)
		BankingAcceptWindow2.sendAmount:setText("The Amount: " .. comma_value(BankingAcceptWindow2.value:getValue()))

		function BankingAcceptWindow2.value.onValueChange(widget, value)
			BankingAcceptWindow2.sendAmount:setText("The Amount: " .. comma_value(value))
		end

		function BankingAcceptWindow2.buttonOk.onClick()
			local amount = BankingAcceptWindow2.value:getValue()
			local name = BankingAcceptWindow2.senderName:getText()

			sendAction(bankBalanceOpCode, "transfer", {
				currencyName,
				name,
				amount
			})
			BankingAcceptWindow2:destroy()

			BankingAcceptWindow2 = nil
		end

		function BankingAcceptWindow2.buttonCancel.onClick()
			BankingAcceptWindow2:destroy()

			BankingAcceptWindow2 = nil
		end
	end

	function bankingWindow.close.onClick()
		bankWindowtoggle()
	end
end

function offline()
	bankingWindow:hide()

	if BankingAcceptWindow then
		BankingAcceptWindow:destroy()

		BankingAcceptWindow = nil
	end

	if BankingAcceptWindow2 then
		BankingAcceptWindow2:destroy()

		BankingAcceptWindow2 = nil
	end
end

function onBankTypeChange(radioTabs, selected, deselected)
	currencyName = selected:getId()

	openBank(bankInfoTable, selected:getId())
	selected:setOn(true)

	if deselected then
		deselected:setOn(false)
	end
end

function bankWindowtoggle()
	if bankingWindow:isVisible() then
		bankingWindow:hide()
		bankButton:setOn(false)

		if msgWindow then
			msgWindow:destroy()

			msgWindow = nil
		end
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
