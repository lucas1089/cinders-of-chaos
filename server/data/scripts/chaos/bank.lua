-- game_bank (extended opcode 60)
--
-- Client contract (client/overlay/modules/game_bank/bank.lua):
--   client -> server  {"action":"openBank"}
--                     {"action":"deposit",     "data":[currency, amount]}
--                     {"action":"withdraw",    "data":[currency, amount]}
--                     {"action":"depositAll",  "data":[currency]}   every carried coin (gold, platinum, crystal)
--                     {"action":"withdrawAll", "data":[currency]}   the whole balance, as much as fits
--                     {"action":"transfer",    "data":[currency, playerName, amount]}
--                     currency is the string "gold" or "star" (the client shows the gold tab only: no star item
--                     exists in this game, Chaos.bank.starItemId = 0)
--   server -> client  {"action":"open","data":[goldCarried, goldBank, starBank, starCarried]}
--                     (the client reads data[1..4] by position; for the gold tab it shows
--                      data[1] as deposit limit and data[2] as bank balance, for the star tab
--                      data[4] as deposit limit and data[3] as bank balance)
-- The client shows nothing else, so results are reported through text messages.
--
-- The server does all the maths: amounts are integers in 1..balance (bank_core.lua K.checkAmount), withdrawals are paid
-- out as coin stacks that really fit (capacity, free slots; K.payOut) and only what arrived is charged, the rest stays
-- in the bank. Gold moves between the character's coins and its in-memory bank balance inside one dispatcher call, so
-- two requests can never both spend the same balance. Every money request shares one rate limit key, checked before
-- anything else (no database query on spam: tests/opcode_fuzz_test.lua).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/bank_core.lua")

local K = ChaosBankCore
local OPCODE = ChaosOpcodes.bank
local cfg = Chaos.bank
local T = Chaos.tables.bank

local function starsEnabled()
	return cfg.starItemId and cfg.starItemId > 0 and ItemType(cfg.starItemId):getId() ~= 0
end

-- SQL defence in depth: an id or an amount goes into a query only as a whole number written with %d (never "1e+15" or
-- "1000.0"); anything else raises an error and the request dies there. The values already come from Chaos.toInt and
-- the database; this keeps one bad caller from reaching the query text.
local function sqlInt(n)
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge or math.floor(n) ~= n then
		error("bank: not a whole number for a query: " .. tostring(n), 2)
	end
	return string.format("%d", n)
end

local function getStarBank(guid)
	local resultId = db.storeQuery("SELECT `stars` FROM `" .. T .. "` WHERE `player_id` = " .. sqlInt(guid))
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
		"INSERT INTO `" .. T .. "` (`player_id`, `stars`) VALUES (" .. sqlInt(guid) .. ", " .. sqlInt(delta) ..
			") ON DUPLICATE KEY UPDATE `stars` = `stars` + " .. sqlInt(delta)
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

local function fail(player, text, ...)
	player:sendCancelMessage(Chaos.t(player, text, ...))
	sendBankState(player) -- re-sync the client's limits
end

-- give(id, count) for K.payOut: one stack into the backpack or nothing (never onto the floor); how many coins arrived
local function coinGiver(player)
	return function(id, count)
		local before = player:getItemCount(id)
		local item = Game.createItem(id, count)
		if not item then
			return 0
		end
		player:addItemEx(item, false)
		return player:getItemCount(id) - before
	end
end

-- pays `amount` of the bank balance out in coins; charges what arrived and says what stayed
local function payGold(player, amount)
	local balance = player:getBankBalance()
	if not K.checkAmount(amount, balance) then
		return fail(player, "Your bank balance is too low.")
	end
	local paid = K.payOut(amount, coinGiver(player))
	if paid <= 0 then
		return fail(player, "You do not have room or capacity for any coins.")
	end
	player:setBankBalance(balance - paid)
	if paid < amount then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player,
			"You withdrew %d gold; %d gold did not fit (capacity or free slots) and stays in the bank. Bank balance: %d gold.",
			paid, amount - paid, balance - paid))
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "You withdrew %d gold. Bank balance: %d gold.",
			paid, balance - paid))
	end
	sendBankState(player)
end

local function depositGold(player, amount)
	if not K.checkAmount(amount, player:getMoney()) then
		return fail(player, "You do not carry that much gold.")
	end
	if not player:removeMoney(amount) then
		return fail(player, "Could not take the gold from you.")
	end
	player:setBankBalance(player:getBankBalance() + amount)
	player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "You deposited %d gold. Bank balance: %d gold.", amount, player:getBankBalance()))
	sendBankState(player)
end

local function doDeposit(player, currency, amount)
	if currency == "gold" then
		return depositGold(player, amount)
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
		-- saved before the bank row is credited: a crash in between cannot leave the stars in both places
		if not Chaos.saveCharacter(player) then
			player:addItem(cfg.starItemId, amount)
			return fail(player, "The bank is busy. Try again in a moment.")
		end
		addStarBank(player:getGuid(), amount)
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "You deposited %d stars.", amount))
	else
		return
	end
	sendBankState(player)
end

local function doWithdraw(player, currency, amount)
	if currency == "gold" then
		return payGold(player, amount)
	elseif currency == "star" then
		if not starsEnabled() then
			return fail(player, "Stars are not available.")
		end
		if amount > cfg.starWithdrawMax then
			return fail(player, "You can withdraw at most %d stars at once.", cfg.starWithdrawMax)
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
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "You withdrew %d stars.", given))
	else
		return
	end
	sendBankState(player)
end

-- "Deposit all": every coin the character carries (getMoney counts gold, platinum and crystal coins)
local function doDepositAll(player, currency)
	if currency ~= "gold" then
		return fail(player, "Only gold can be deposited all at once.")
	end
	local carried = player:getMoney()
	if carried < 1 then
		return fail(player, "You do not carry any gold.")
	end
	depositGold(player, math.min(carried, cfg.maxAmount))
end

-- "Withdraw all": the whole balance, as much as fits; the rest stays in the bank
local function doWithdrawAll(player, currency)
	if currency ~= "gold" then
		return fail(player, "Only gold can be withdrawn all at once.")
	end
	local balance = player:getBankBalance()
	if balance < 1 then
		return fail(player, "Your bank balance is empty.")
	end
	payGold(player, math.min(balance, cfg.maxAmount))
end

local function doTransfer(player, currency, targetName, amount)
	if currency ~= "gold" and currency ~= "star" then
		return
	end
	-- a whole number of 1..maxAmount, whatever the caller: no float, negative, NaN or infinity reaches a query
	if not K.checkAmount(amount, cfg.maxAmount) then
		return
	end
	if player:getLevel() < cfg.transferMinLevel then
		return fail(player, "You need level %d to transfer.", cfg.transferMinLevel)
	end
	if type(targetName) == "string" then
		targetName = targetName:match("^%s*(.-)%s*$")
	end
	if not K.validName(targetName) then
		return fail(player, "That is not a valid character name.")
	end
	if currency == "gold" and not K.checkAmount(amount, player:getBankBalance()) then
		return fail(player, "Your bank balance is too low.") -- before the name lookup: no query for a transfer that cannot happen
	end
	local targetGuid, canonical, online = Chaos.findPlayer(targetName)
	if not targetGuid then
		return fail(player, "A player with that name does not exist.")
	end
	if targetGuid == player:getGuid() then
		return fail(player, "You cannot transfer to yourself.")
	end
	if ChaosSeason and ChaosSeason.transferBlocked and ChaosSeason.transferBlocked(player, targetGuid) then -- season.lua
		return fail(player, ChaosSeason.transferBlockedText)
	end

	if currency == "gold" then
		local balance = player:getBankBalance()
		if not K.checkAmount(amount, balance) then
			return fail(player, "Your bank balance is too low.")
		end
		player:setBankBalance(balance - amount)
		-- the sender is saved before the receiver is credited (online: the receiver may be saved first at its logout;
		-- offline: the database row): a crash in between cannot leave the gold on both characters. An online receiver
		-- is saved right after the credit: else a crash before its next save lost the gold the saved sender gave
		-- (server/README.md "Stress test": about 10,000 gold per kill -9 under transfer spam)
		if not Chaos.saveCharacter(player) then
			player:setBankBalance(balance)
			return fail(player, "The bank is busy. Try again in a moment.")
		end
		if online then
			online:setBankBalance(online:getBankBalance() + amount)
			Chaos.saveCharacter(online)
			online:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(online, "%s transferred %d gold to your bank account.", player:getName(), amount))
		else
			db.query("UPDATE `players` SET `balance` = `balance` + " .. sqlInt(amount) .. " WHERE `id` = " .. sqlInt(targetGuid))
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "You transferred %d gold to %s.", amount, canonical))
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
			online:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(online, "%s transferred %d stars to your bank account.", player:getName(), amount))
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "You transferred %d stars to %s.", amount, canonical))
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
	-- before anything else (ratelimit.lua). Opening the window has its own key, so the open and the request that
	-- follows it are never dropped together; every request that moves money shares one key (also unknown actions:
	-- no new key per made-up action), so alternating deposit / withdraw / transfer spam is limited as one.
	local key = msg.action == "openBank" and "bank.open" or "bank.move"
	if ChaosRateLimit and not ChaosRateLimit.allow(player, key, cfg.rateLimitMs or 300) then
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
		if not amount or tonumber(data[2]) ~= amount then -- an integer, not 12.5 rounded down
			return
		end
		if msg.action == "deposit" then
			doDeposit(player, currency, amount)
		else
			doWithdraw(player, currency, amount)
		end
	elseif msg.action == "depositAll" then
		doDepositAll(player, data[1])
	elseif msg.action == "withdrawAll" then
		doWithdrawAll(player, data[1])
	elseif msg.action == "transfer" then
		local amount = Chaos.toInt(data[3], 1, cfg.maxAmount)
		if not amount or tonumber(data[3]) ~= amount then
			return
		end
		doTransfer(player, data[1], data[2], amount)
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()
