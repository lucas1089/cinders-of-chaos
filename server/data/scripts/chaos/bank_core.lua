-- game_bank logic without the engine (tests/bank_test.lua; bank.lua is the engine side, Chaos.bank the numbers).
--   K.checkAmount(amount, available)       amount or nil, reason ("amount" | "balance")
--   K.validName(name)                      true for a well-formed character name (letters, space, ' and -; 2..29)
--   K.payOut(amount, give[, coins[, maxCalls]])  -> paid
--       Hands `amount` gold out as coin stacks, largest coin first, through give(id, count) -> how many coins really
--       arrived. The engine adds a stack all or nothing (capacity, free slots), so a stack that did not arrive whole
--       is tried again with half of what was missing, down to one coin; then the next smaller coin, which may still
--       merge into stacks the player carries. At most maxCalls calls of give. The caller charges only `paid`.
-- Lua 5.1 / LuaJIT / 5.3 compatible.

ChaosBankCore = ChaosBankCore or {}
local K = ChaosBankCore

-- crystal, platinum, gold coin (server ids of the 10.98 base, as autosell_core.lua and blessings.lua)
K.COINS = {{id = 2160, worth = 10000}, {id = 2152, worth = 100}, {id = 2148, worth = 1}}
K.STACK = 100
K.MAX_CALLS = 160 -- a full backpack tree holds far fewer stacks; bounds the loop

local function isInt(n)
	return type(n) == "number" and n == n and n >= 0 and n <= 9007199254740992 and math.floor(n) == n
end

function K.checkAmount(amount, available)
	if not isInt(amount) or amount < 1 then
		return nil, "amount"
	end
	if not isInt(available) or amount > available then
		return nil, "balance"
	end
	return amount
end

function K.validName(name)
	return type(name) == "string" and #name >= 2 and #name <= 29 and name:match("^[A-Za-z][A-Za-z '%-]*$") ~= nil
		and not name:find("  ", 1, true) and name:sub(-1) ~= " "
end

function K.payOut(amount, give, coins, maxCalls)
	if not isInt(amount) or amount < 1 or type(give) ~= "function" then
		return 0
	end
	coins = coins or K.COINS
	maxCalls = maxCalls or K.MAX_CALLS
	local remaining, paid, calls = amount, 0, 0
	for _, coin in ipairs(coins) do
		local want = math.min(K.STACK, math.floor(remaining / coin.worth))
		while want >= 1 and calls < maxCalls do
			local got = tonumber(give(coin.id, want)) or 0
			if got ~= got then
				got = 0
			end
			got = math.max(0, math.min(want, math.floor(got)))
			calls = calls + 1
			paid = paid + got * coin.worth
			remaining = remaining - got * coin.worth
			if got < want then
				want = math.floor((want - got) / 2)
			else
				want = math.min(K.STACK, math.floor(remaining / coin.worth))
			end
		end
	end
	return paid
end
