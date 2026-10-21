-- Gold payments from carried coins and the bank account (owner 2026-10-22: "todas as lojas que usam gold aceitam o
-- dinheiro diretamente do banco"). Every kill's coins go to the bank (autoloot.lua), so a price in gold is paid from
-- the coins the character carries first and the rest from the bank, like the stock removeTotalMoney.
-- server/README.md "Gold payments: carried coins, then the bank"; tests/chaos_pay_test.lua.
--
--   ChaosPay.total(player)             carried coins + bank balance (a negative balance counts as 0), carried, bank
--   ChaosPay.canPay(player, amount)    true when total >= amount (whole gold, amount >= 0)
--   ChaosPay.pay(player, amount[, quiet])
--                                      takes amount: carried coins first, then the bank. All or nothing: false and
--                                      nothing taken when the total is short or a part fails. Returns true, fromCoins,
--                                      fromBank. Says what came from the bank (Chaos.t, pt-BR) unless quiet.
--   ChaosPay.payCid(cid, amount) / ChaosPay.totalCid(cid)   the same by creature id (old style NPC scripts)
--   ChaosPay.install()                 Player.getTotalMoney / Player.removeTotalMoney become these (the base defines
--                                      them twice: data/lib/core/player.lua and data/npc/lib/npc.lua; both load this
--                                      file after their own definition, tools/patch_bank_payments.py)
--
-- The engine already sends carried + bank as the money of the NPC trade window (ProtocolGame::sendSaleItemList), and
-- the client greys the offers by that number; src-patches/0053 sends it again when a script changes the bank balance.
-- Engine calls used: Player getMoney, removeMoney, getBankBalance, setBankBalance, sendTextMessage. Pure otherwise.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Idempotent: loading it again only redefines the same functions.

ChaosPay = ChaosPay or {}
local P = ChaosPay

local floor = math.floor

local function num(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return v
end

-- a whole, non-negative amount of gold, or nil
local function amountOf(amount)
	local n = num(amount)
	if not n or n < 0 then
		return nil
	end
	return floor(n)
end

local function playerOf(cid)
	if type(cid) == "number" and Player then
		return Player(cid)
	end
	return cid
end

local function tr(player, key, ...)
	if Chaos and Chaos.t then
		return Chaos.t(player, key, ...)
	end
	if ChaosI18n and ChaosI18n.npcText then
		return ChaosI18n.npcText(player, key, ...)
	end
	return string.format(key, ...)
end

function P.total(player)
	if not player then
		return 0, 0, 0
	end
	local carried = num(player.getMoney and player:getMoney()) or 0
	local bank = num(player.getBankBalance and player:getBankBalance()) or 0
	if carried < 0 then
		carried = 0
	end
	if bank < 0 then
		bank = 0
	end
	return carried + bank, carried, bank
end

function P.canPay(player, amount)
	local n = amountOf(amount)
	if not n or not player then
		return false
	end
	return P.total(player) >= n
end

function P.pay(player, amount, quiet)
	local n = amountOf(amount)
	if not n or not player then
		return false
	end
	if n == 0 then
		return true, 0, 0
	end
	local total, carried, bank = P.total(player)
	if total < n then
		return false
	end
	local fromCoins = math.min(carried, n)
	local fromBank = n - fromCoins
	if fromBank > 0 and not player.setBankBalance then
		return false
	end
	if fromCoins > 0 and not player:removeMoney(fromCoins) then
		return false
	end
	if fromBank > 0 then
		local now = num(player:getBankBalance()) or 0
		if now < fromBank or player:setBankBalance(now - fromBank) == false then
			-- cannot happen in one script call; the coins already taken go to the bank, so nothing is lost
			if fromCoins > 0 then
				player:setBankBalance(math.max(0, now) + fromCoins)
			end
			return false
		end
		if not quiet and player.sendTextMessage and MESSAGE_INFO_DESCR then
			if fromCoins > 0 then
				player:sendTextMessage(MESSAGE_INFO_DESCR, tr(player,
					"Paid %d gold: %d carried and %d from your bank. Bank balance: %d gold.", n, fromCoins, fromBank,
					now - fromBank))
			else
				player:sendTextMessage(MESSAGE_INFO_DESCR, tr(player,
					"Paid %d gold from your bank. Bank balance: %d gold.", n, now - fromBank))
			end
		end
	end
	return true, fromCoins, fromBank
end

function P.totalCid(cid)
	return (P.total(playerOf(cid)))
end

function P.payCid(cid, amount)
	return (P.pay(playerOf(cid), amount))
end

function P.install()
	if type(Player) ~= "table" and type(Player) ~= "userdata" then
		return false
	end
	Player.getTotalMoney = function(self)
		return (P.total(self))
	end
	Player.removeTotalMoney = function(self, amount)
		return (P.pay(self, amount))
	end
	return true
end

P.install()

return P
