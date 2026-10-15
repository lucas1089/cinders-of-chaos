-- Run from the server/ folder: luajit tests/candlemarks_apis_test.lua (and lua5.3; CI runs both)
-- The Candlemarks shop's "call" offers (candlemarks_config.lua: the Rested Vial, the bounty reroll, the kill task
-- reroll) are shown only while their API exists. This loads the real catchup.lua, bounty.lua and bestiary.lua on a
-- mocked engine, then asks candlemarks_core.lua for the offers with the shop's own rule (a global table with that
-- function), and calls each API the way the shop does (candlemarks.lua deliverApi: player first, then the count).

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

-- ---------------------------------------------------------------- a forgiving engine
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then
		n = n + 1
		rawset(t, k, n)
		return n
	end
end})
loadstring = loadstring or load
local function obj()
	return setmetatable({}, {__index = function() return function() return true end end})
end
EventCallback = setmetatable({}, {__index = function(t, k) if k == "register" then return function() end end end})
CreatureEvent, GlobalEvent, TalkAction, MoveEvent, Action = obj, obj, obj, obj, obj
db = {query = function() return true end, asyncQuery = function() return true end, storeQuery = function() return false end,
	escapeString = function(v) return "'" .. tostring(v) .. "'" end}
result = {free = function() end}
addEvent = function() return 1 end
MonsterType = function() return {} end
Game = {getMonsterTypes = function() return {} end, getPlayers = function() return {} end}

dofile("data/scripts/chaos/catchup.lua")
dofile("data/scripts/chaos/bounty.lua")
dofile("data/scripts/chaos/bestiary.lua")
setmetatable(_G, nil)

dofile("data/scripts/chaos/candlemarks_core.lua")
local K = ChaosCandlemarksCore
local cfg = dofile("data/scripts/chaos/candlemarks_config.lua")

-- the shop's rule (candlemarks.lua apiFn): a global table holding that function
local function has(call)
	local t = type(call) == "table" and rawget(_G, call[1])
	return type(t) == "table" and type(t[call[2]]) == "function"
end
local list, byKey = K.offers(cfg, {has = has})
check(byKey.rested_vial ~= nil, "the Rested Vial is on sale (ChaosRested.addVials)")
check(byKey.bounty_reroll ~= nil, "the bounty reroll is on sale (ChaosBounty.addRerolls)")
check(byKey.task_reroll ~= nil, "the kill task reroll is on sale (ChaosBestiary.addRerolls)")
check(#list > 3, "the other offers stay")

-- each API, called as the shop calls it
local st, msgs = {}, {}
local player = {getStorageValue = function(_, k) return st[k] or -1 end, setStorageValue = function(_, k, v) st[k] = v end,
	sendTextMessage = function(_, _, text) msgs[#msgs + 1] = text end, getGuid = function() return 5 end,
	getId = function() return 5 end, getAccountId = function() return 9 end, getLevel = function() return 80 end,
	getStamina = function() return 2520 end}
local function call(key)
	local o = byKey[key]
	local f = rawget(_G, o.call[1])[o.call[2]]
	return f(player, o.call[3])
end
eq(call("rested_vial"), true, "a vial adds rest")
eq(st[ChaosCatchupConfig.storage.rested], ChaosCatchupConfig.rested.vialMinutes * 100, "60 minutes in the pool")
eq(call("bounty_reroll"), true, "a bounty reroll added")
eq(ChaosBounty.rerollsOf(player), 1, "one bounty reroll held")
eq(call("task_reroll"), true, "a task reroll added")
eq(ChaosBestiary.rerollsOf(player), 1, "one task reroll held")
check(#msgs == 3, "the player is told each time")

print(string.format("candlemarks_apis_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
