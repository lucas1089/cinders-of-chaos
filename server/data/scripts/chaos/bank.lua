-- game_bank (extended opcode 60)
--
-- Client contract (client/overlay/modules/game_bank/bank.lua):
--   client -> server  {"action":"openBank"}
--                     {"action":"deposit",  "data":[currency, amount]}
--                     {"action":"withdraw", "data":[currency, amount]}
--                     {"action":"transfer", "data":[currency, playerName, amount]}
--                     currency is the string "gold" or "star"
--   server -> client  {"action":"open","data":[goldCarried, goldBank, starBank, starCarried]}
--                     (the client reads data[1..4] by position; for the gold tab it shows
--                      data[1] as deposit limit and data[2] as bank balance, for the star tab
--                      data[4] as deposit limit and data[3] as bank balance)
-- The client shows nothing else, so results are reported through text messages.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

local OPCODE = ChaosOpcodes.bank
local cfg = Chaos.bank
local T = Chaos.tables.bank

local function starsEnabled()
	return cfg.starItemId and cfg.starItemId > 0 and ItemType(cfg.starItemId):getId() ~= 0
end

local function getStarBank(guid)
	local resultId = db.storeQuery("SELECT `stars` FROM `" .. T .. "` WHERE `player_id` = " .. guid)
	if not resultId then
		return 0
	end
	local stars = result.getNumber(resultId, "stars")
	result.free(resultId)
	return stars
end

-- delta may be negative; callers check the balance first
local function addStarBank(guid, delta)
	db.query(
		"INSERT INTO `" .. T .. "` (`player_id`, `stars`) VALUES (" .. guid .. ", " .. delta ..
			") ON DUPLICATE KEY UPDATE `stars` = `stars` + " .. delta
	)
end

local function sendBankState(player)
	local starCarried = starsEnabled() and player:getItemCount(cfg.starItemId) or 0
	local starBank = starsEnabled() and getStarBank(player:getGuid()) or 0
	Chaos.send(player, OPCODE, "open", {
		player:getMoney(),
		player:getBankBalance(),
		starBank,
		starCarried
	})
end

local function fail(player, text)
	player:sendCancelMessage(text)
	sendBankState(player) -- re-sync the client's limits
end

local function doDeposit(player, currency, amount)
	if currency == "gold" then
		if player:getMoney() < amount then
			return fail(player, "You do not carry that much gold.")
		end
		if not player:removeMoney(amount) then
			return fail(player, "Could not take the gold from you.")
		end
		player:setBankBalance(player:getBankBalance() + amount)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("You deposited %d gold. Bank balance: %d gold.", amount, player:getBankBalance()))
	elseif currency == "star" then
		if not starsEnabled() then
			return fail(player, "Stars are not available.")
		end
		if player:getItemCount(cfg.starItemId) < amount then
			return fail(player, "You do not carry that many stars.")
		end
		if not player:removeItem(cfg.starItemId, amount) then
			return fail(player, "Could not take the stars from you.")
		end
		addStarBank(player:getGuid(), amount)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("You deposited %d stars.", amount))
	else
		return
	end
	sendBankState(player)
end

local function doWithdraw(player, currency, amount)
	if currency == "gold" then
		local balance = player:getBankBalance()
		if balance < amount then
			return fail(player, "Your bank balance is too low.")
		end
		if not player:addMoney(amount) then
			return fail(player, "You do not have room for that much gold.")
		end
		player:setBankBalance(balance - amount)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("You withdrew %d gold. Bank balance: %d gold.", amount, balance - amount))
	elseif currency == "star" then
		if not starsEnabled() then
			return fail(player, "Stars are not available.")
		end
		if amount > cfg.starWithdrawMax then
			return fail(player, string.format("You can withdraw at most %d stars at once.", cfg.starWithdrawMax))
		end
		local guid = player:getGuid()
		local banked = getStarBank(guid)
		if banked < amount then
			return fail(player, "You do not have that many stars in the bank.")
		end
		local given = Chaos.giveItem(player, cfg.starItemId, amount)
		if given <= 0 then
			return fail(player, "You do not have room or capacity for the stars.")
		end
		addStarBank(guid, -given) -- only charge for what was really handed over
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("You withdrew %d stars.", given))
	else
		return
	end
	sendBankState(player)
end

local function doTransfer(player, currency, targetName, amount)
	if currency ~= "gold" and currency ~= "star" then
		return
	end
	if player:getLevel() < cfg.transferMinLevel then
		return fail(player, string.format("You need level %d to transfer.", cfg.transferMinLevel))
	end
	local targetGuid, canonical, online = Chaos.findPlayer(targetName)
	if not targetGuid then
		return fail(player, "A player with that name does not exist.")
	end
	if targetGuid == player:getGuid() then
		return fail(player, "You cannot transfer to yourself.")
	end

	if currency == "gold" then
		local balance = player:getBankBalance()
		if balance < amount then
			return fail(player, "Your bank balance is too low.")
		end
		player:setBankBalance(balance - amount)
		if online then
			online:setBankBalance(online:getBankBalance() + amount)
			online:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s transferred %d gold to your bank account.", player:getName(), amount))
		else
			db.query("UPDATE `players` SET `balance` = `balance` + " .. amount .. " WHERE `id` = " .. targetGuid)
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("You transferred %d gold to %s.", amount, canonical))
	else
		if not starsEnabled() then
			return fail(player, "Stars are not available.")
		end
		local guid = player:getGuid()
		if getStarBank(guid) < amount then
			return fail(player, "You do not have that many stars in the bank.")
		end
		addStarBank(guid, -amount)
		addStarBank(targetGuid, amount)
		if online then
			online:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s transferred %d stars to your bank account.", player:getName(), amount))
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("You transferred %d stars to %s.", amount, canonical))
	end
	sendBankState(player)
end

local LoginEvent = CreatureEvent("ChaosBankLogin")

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosBankExtended")
	return true
end

local ExtendedEvent = CreatureEvent("ChaosBankExtended")

function ExtendedEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end

	if msg.action == "openBank" then
		sendBankState(player)
		return
	end

	local data = msg.data
	if type(data) ~= "table" then
		return
	end

	if msg.action == "deposit" or msg.action == "withdraw" then
		local currency = data[1]
		local amount = Chaos.toInt(data[2], 1, cfg.maxAmount)
		if not amount then
			return
		end
		if msg.action == "deposit" then
			doDeposit(player, currency, amount)
		else
			doWithdraw(player, currency, amount)
		end
	elseif msg.action == "transfer" then
		local amount = Chaos.toInt(data[3], 1, cfg.maxAmount)
		if not amount then
			return
		end
		doTransfer(player, data[1], data[2], amount)
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()

-- Convenience: "!bank" opens the window (the client also opens it from its top-bar button).
local talk = TalkAction("!bank")

function talk.onSay(player, words, param)
	sendBankState(player)
	return false
end

talk:separator(" ")
talk:register()
