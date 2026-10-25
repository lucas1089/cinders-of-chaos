-- Run from the server/ folder: luajit tests/bank_test.lua (and lua5.3; CI runs both). Mock engine API.
-- game_bank: bank_core.lua (amount checks, names, coin pay-out) and bank.lua (deposit all, withdraw all into what fits,
-- the rest stays in the bank, amount validation, transfer name checks, one rate limit for every money request).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
RETURNVALUE_NOERROR = 0
RETURNVALUE_NOTENOUGHROOM = 1
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

-- ---------------------------------------------------------------- bank_core.lua
dofile("data/scripts/chaos/bank_core.lua")
local K = ChaosBankCore

eq(K.checkAmount(5, 10), 5, "within the balance")
eq(K.checkAmount(10, 10), 10, "the whole balance")
eq(select(2, K.checkAmount(11, 10)), "balance", "over the balance")
eq(select(2, K.checkAmount(0, 10)), "amount", "zero")
eq(select(2, K.checkAmount(-5, 10)), "amount", "negative")
eq(select(2, K.checkAmount(2.5, 10)), "amount", "fraction")
eq(select(2, K.checkAmount(0 / 0, 10)), "amount", "NaN")
eq(select(2, K.checkAmount(math.huge, 10)), "amount", "inf")
eq(select(2, K.checkAmount("5", 10)), "amount", "a string")

eq(K.validName("Ana"), true, "plain name")
eq(K.validName("Sir Ana'th-Kor"), true, "space, apostrophe, hyphen")
eq(K.validName("A"), false, "too short")
eq(K.validName(string.rep("a", 30)), false, "too long")
eq(K.validName("Ana  Bel"), false, "double space")
eq(K.validName("Ana "), false, "trailing space")
eq(K.validName(" Ana"), false, "leading space")
eq(K.validName("Ana'; DROP TABLE"), false, "SQL")
eq(K.validName("1Ana"), false, "digit")
eq(K.validName(nil), false, "nil")
eq(K.validName({}), false, "table")

-- a backpack that holds `room` coins of any kind (capacity), counted per id
local function pack(room, perStack)
	local bag = {items = {}, room = room, calls = 0}
	bag.give = function(id, count)
		bag.calls = bag.calls + 1
		if count > bag.room or (perStack and count > perStack) then
			return 0 -- the engine adds a stack all or nothing
		end
		bag.room = bag.room - count
		bag.items[id] = (bag.items[id] or 0) + count
		return count
	end
	return bag
end
local b = pack(1000)
eq(K.payOut(1234567, b.give), 1234567, "all fits")
eq(b.items[2160], 123, "crystal coins")
eq(b.items[2152], 45, "platinum coins")
eq(b.items[2148], 67, "gold coins")
b = pack(50)
eq(K.payOut(1000000, b.give), 500000, "only 50 crystal coins fit")
eq(b.items[2160], 50, "half a stack, found by halving")
b = pack(0)
eq(K.payOut(1000, b.give), 0, "nothing fits")
b = pack(1000)
eq(K.payOut(0, b.give), 0, "zero")
eq(K.payOut(-5, b.give), 0, "negative")
eq(K.payOut(5.5, b.give), 0, "fraction")
eq(b.calls, 0, "invalid amounts give nothing")
b = pack(10 ^ 9)
eq(K.payOut(2000000000, b.give), K.MAX_CALLS * 100 * 10000, "bounded by MAX_CALLS")
eq(b.calls, K.MAX_CALLS, "at most MAX_CALLS stacks")
-- a give that lies (more than asked, NaN) is clamped
eq(K.payOut(300, function(_, c) return c * 10 end), 300, "over-report clamped")
eq(K.payOut(300, function() return 0 / 0 end), 0, "NaN is nothing")

-- ---------------------------------------------------------------- bank.lua against a mock engine
local events = {}
local function object(name)
	local o = {}
	return setmetatable(o, {__index = function(t, k)
		if k == "register" then return function() if name then events[name] = o end return true end end
		return function() return true end
	end})
end
CreatureEvent = function(name) return object(name) end
local queries = {}
db = {
	query = function(q) queries[#queries + 1] = q; return true end,
	storeQuery = function(q) queries[#queries + 1] = q; return nil end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end
}
result = {getNumber = function() return 0 end, free = function() end}
ItemType = function(id) return {getId = function() return 0 end} end

Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
eq(Chaos.bank.starItemId, 0, "no star item in this game")
local sent = {}
Chaos.decode = function(b) return b end
Chaos.send = function(_, op, action, data) sent[#sent + 1] = {op = op, action = action, data = data}; return true end
Chaos.saveCharacter = function() return true end
local players = {}
Chaos.findPlayer = function(name)
	queries[#queries + 1] = "findPlayer " .. tostring(name)
	local p = players[name]
	if p then return p.guid, p.name, p.online and p or nil end
	return nil
end
local now = 0
os.mtime = function() return now end
dofile("data/scripts/chaos/ratelimit.lua")

local WORTH = {[2160] = 10000, [2152] = 100, [2148] = 1}
Game = {createItem = function(id, count) return {id = id, count = count} end}
local function newPlayer(guid, name)
	local p = {guid = guid, name = name, bank = 0, coins = {}, room = 1000, msgs = {}, cancels = {}, online = true}
	function p:getId() return self.guid end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getLevel() return 100 end
	function p:getBankBalance() return self.bank end
	function p:setBankBalance(v)
		assert(type(v) == "number" and v >= 0 and math.floor(v) == v, "bad balance " .. tostring(v))
		self.bank = v
	end
	function p:getMoney()
		local s = 0
		for id, c in pairs(self.coins) do s = s + c * WORTH[id] end
		return s
	end
	function p:removeMoney(v)
		if self:getMoney() < v then return false end
		-- the engine takes coins and gives change; the mock keeps the value in gold coins
		local left = self:getMoney() - v
		self.coins = {[2148] = left}
		return true
	end
	function p:getItemCount(id) return self.coins[id] or 0 end
	function p:addItemEx(item)
		if item.count > self.room then return RETURNVALUE_NOTENOUGHROOM end
		self.room = self.room - item.count
		self.coins[item.id] = (self.coins[item.id] or 0) + item.count
		return RETURNVALUE_NOERROR
	end
	function p:addMoney() error("addMoney drops on the floor: not used") end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:sendCancelMessage(t) self.cancels[#self.cancels + 1] = t end
	function p:save() return true end
	function p:registerEvent() end
	return p
end

dofile("data/scripts/chaos/bank.lua")
local ev = events.ChaosBankExtended
local OP = ChaosOpcodes.bank
local function call(p, action, data)
	now = now + 10000 -- past every rate limit
	sent = {}
	ev.onExtendedOpcode(p, OP, {action = action, data = data})
end
local function last(t) return t[#t] end

local ana = newPlayer(1, "Ana")
players.Ana = ana

-- deposit all: every coin form
ana.coins = {[2160] = 3, [2152] = 48, [2148] = 7}
call(ana, "depositAll", {"gold"})
eq(ana.bank, 34807, "every carried coin deposited")
eq(ana:getMoney(), 0, "nothing carried")
eq(sent[1].action, "open", "the window is re-synced")
eq(sent[1].data[2], 34807, "new bank balance sent")
call(ana, "depositAll", {"gold"})
eq(last(ana.cancels), "You do not carry any gold.", "nothing to deposit")
call(ana, "depositAll", {"star"})
eq(last(ana.cancels), "Only gold can be deposited all at once.", "gold only")
eq(ana.bank, 34807, "unchanged")

-- withdraw all, everything fits
call(ana, "withdrawAll", {"gold"})
eq(ana.bank, 0, "balance emptied")
eq(ana:getMoney(), 34807, "all of it carried")
eq(ana.coins[2160], 3, "crystal")
eq(ana.coins[2152], 48, "platinum")
eq(ana.coins[2148], 7, "gold")
call(ana, "withdrawAll", {"gold"})
eq(last(ana.cancels), "Your bank balance is empty.", "nothing to withdraw")

-- withdraw all, only part fits: what fits is paid, the rest stays and is reported
ana.coins, ana.bank, ana.room = {}, 5000000, 120
call(ana, "withdrawAll", {"gold"})
eq(ana:getMoney(), 1200000, "120 crystal coins fit")
eq(ana.bank, 3800000, "the rest stays in the bank")
eq(ana.bank + ana:getMoney(), 5000000, "no gold made or lost")
eq(last(ana.msgs):find("did not fit", 1, true) ~= nil, true, "the rest is reported")
ana.room = 0
call(ana, "withdrawAll", {"gold"})
eq(last(ana.cancels), "You do not have room or capacity for any coins.", "no room")
eq(ana.bank, 3800000, "nothing charged")

-- withdraw an amount: validated, paid in coins, never onto the floor
ana.room = 1000
call(ana, "withdraw", {"gold", 3800001})
eq(last(ana.cancels), "Your bank balance is too low.", "over the balance")
eq(ana.bank, 3800000, "unchanged")
for _, bad in ipairs({0, -1, 2.5, "x", 0 / 0, math.huge, {}, true}) do
	local before = #ana.cancels
	call(ana, "withdraw", {"gold", bad})
	eq(ana.bank, 3800000, "bad amount " .. tostring(bad))
	eq(#sent, 0, "no answer to a bad amount " .. tostring(bad))
	eq(#ana.cancels, before, "silently dropped " .. tostring(bad))
end
call(ana, "withdraw", {"gold", 10101})
eq(ana.bank, 3789899, "exact withdraw")
call(ana, "deposit", {"gold", ana:getMoney() + 1})
eq(last(ana.cancels), "You do not carry that much gold.", "deposit over what is carried")

-- transfer: the name is checked before any lookup, the target must exist
local cara = newPlayer(2, "Cara")
players.Cara = cara
queries = {}
for _, bad in ipairs({"", "A", "Ana'; DROP TABLE players", string.rep("x", 40), 5, {}}) do
	call(ana, "transfer", {"gold", bad, 10})
	eq(last(ana.cancels), "That is not a valid character name.", "bad name " .. tostring(bad))
end
eq(#queries, 0, "no lookup for a bad name")
call(ana, "transfer", {"gold", "Nobody", 10})
eq(last(ana.cancels), "A player with that name does not exist.", "unknown target")
call(ana, "transfer", {"gold", "Ana", 10})
eq(last(ana.cancels), "You cannot transfer to yourself.", "self")
queries = {}
call(ana, "transfer", {"gold", "Cara", 99999999})
eq(last(ana.cancels), "Your bank balance is too low.", "over the balance")
eq(#queries, 0, "no lookup for a transfer that cannot happen")
call(ana, "transfer", {"gold", "  Cara ", 899})
eq(cara.bank, 899, "credited (name trimmed)")
eq(ana.bank, 3789000, "debited")

-- an offline receiver: the credit is one UPDATE whose amount and id are plain whole numbers (SQL defence in depth)
local dora = newPlayer(3, "Dora")
dora.online = false
players.Dora = dora
queries = {}
call(ana, "transfer", {"gold", "Dora", 1000})
local upd
for _, q in ipairs(queries) do if q:find("UPDATE `players`", 1, true) then upd = q end end
eq(upd, "UPDATE `players` SET `balance` = `balance` + 1000 WHERE `id` = 3", "offline credit: integers written with %d")
eq(ana.bank, 3789000 - 1000, "debited")
-- floats that are whole (1e3 style), fractions, negatives, NaN, infinity and strings never reach a query
for _, bad in ipairs({2.5, -5, 0, 0 / 0, math.huge, -math.huge, "1; DROP TABLE players", {}, true, 1e300}) do
	queries = {}
	local b = ana.bank
	call(ana, "transfer", {"gold", "Dora", bad})
	eq(ana.bank, b, "bad transfer amount " .. tostring(bad))
	eq(#queries, 0, "no query for transfer amount " .. tostring(bad))
	call(ana, "transfer", {"star", "Dora", bad})
	eq(#queries, 0, "no query for star transfer amount " .. tostring(bad))
end

-- rate limit: every money request shares one key, nothing runs on spam
local before = ana.bank
now = now + 10000
ev.onExtendedOpcode(ana, OP, {action = "withdraw", data = {"gold", 1000}})
local afterFirst = ana.bank
ev.onExtendedOpcode(ana, OP, {action = "withdraw", data = {"gold", 1000}})
ev.onExtendedOpcode(ana, OP, {action = "withdrawAll", data = {"gold"}})
ev.onExtendedOpcode(ana, OP, {action = "deposit", data = {"gold", 1}})
queries = {}
ev.onExtendedOpcode(ana, OP, {action = "transfer", data = {"gold", "Cara", 1}})
ev.onExtendedOpcode(ana, OP, {action = "made-up", data = {}})
eq(afterFirst, before - 1000, "the first request runs")
eq(ana.bank, afterFirst, "the spam right after it is dropped")
eq(#queries, 0, "no query on spam")
sent = {}
ev.onExtendedOpcode(ana, OP, {action = "openBank"})
eq(#sent, 1, "opening the window has its own key")
eq(sent[1].data[3], 0, "no star balance")

print(string.format("bank_test: %d checks passed", checks))
