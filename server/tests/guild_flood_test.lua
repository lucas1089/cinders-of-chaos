-- Run from the server/ folder: luajit tests/guild_flood_test.lua (and lua5.3; CI runs both). Mock engine API.
-- Crash duplication: value that leaves the character in memory and is credited to a database row (star bank, an
-- offline receiver's balance, the guild bank, the Guild Stash) is credited only after player:save() succeeded; a
-- Guild window: (1) a refused spend must not leave the cached guild bank wrong (G.spend), (2) a flood of action requests
-- must not cost a full state (database reads) each.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

-- engine objects: every registration method is a no-op; the event table keeps its handlers by name
local events = {}
local function object(name)
	local o = {}
	return setmetatable(o, {__index = function(t, k)
		if k == "register" then return function() if name then events[name] = o end return true end end
		return function() return true end
	end})
end
CreatureEvent = function(name) return object(name) end
GlobalEvent = function(name) return object(name) end
TalkAction = function(name) return object(name) end
Action = function() return object() end
MoveEvent = function() return object() end
EventCallback = object()
function addEvent() return 1 end
function stopEvent() end
Game = {getPlayers = function() return {} end, getStorageValue = function() return nil end}

local reads = 0
local bankRow = 100000 -- the database's bank
db = {
	query = function(q)
		local n = q:match("SET `bank` = `bank` %- (%d+)")
		if n and bankRow >= tonumber(n) then bankRow = bankRow - tonumber(n) end
		return true
	end,
	asyncQuery = function() end,
	storeQuery = function() return nil end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end
}
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.decode = function(b) return b end
Chaos.send = function() return true end
local lastSpend = 100000
Chaos.select = function(q)
	reads = reads + 1
	if q:find("ROW_COUNT", 1, true) then return {{n = (bankRow ~= lastSpend) and 1 or 0}} end
	if q:find("SELECT `xp`, `bank`", 1, true) then return {{xp = 0, bank = bankRow}} end
	return {}
end
ItemType = function(id) return {getId = function() return id end} end
local now = 0
os.mtime = function() return now end
dofile("data/scripts/chaos/ratelimit.lua")
dofile("data/scripts/chaos/guild.lua")
local G = ChaosGuild

local p = {}
function p:getId() return 5 end
function p:getGuid() return 5 end
function p:getName() return "Bo" end
function p:getLevel() return 500 end
function p:getBankBalance() return 0 end
function p:setBankBalance() end
function p:save() return true end
function p:sendTextMessage() end
function p:sendCancelMessage() end
function p:getStorageValue() return -1 end
function p:getGroup() return {getAccess = function() return false end} end
function p:getGuild() return {getId = function() return 9 end, getName = function() return "Wolves" end} end
function p:getGuildLevel() return 3 end

-- (1) a refused spend clears the cache; the next successful spend must leave the real bank in it
G.cache[9] = {xp = 0, bank = 100000, level = 1}
eq(G.spend(9, 500000), false, "more than the bank is refused")
eq(G.cache[9], nil, "the cache is cleared after a refusal")
lastSpend = bankRow
local okSpend = G.spend(9, 5000)
eq(okSpend, true, "a spend within the bank works")
eq(bankRow, 95000, "the database is debited once")
eq(G.cache[9].bank, 95000, "the cache holds the real bank, not a second subtraction")

-- (2) action floods
local ev = events.ChaosGuildOpcode
local OP = ChaosOpcodes.guild
ev.onExtendedOpcode(p, OP, {action = "scroll", data = {}})
reads = 0
for _ = 1, 50 do
	ev.onExtendedOpcode(p, OP, {action = "scroll", data = {}})
end
eq(reads, 0, "50 repeated requests in the same instant read nothing from the database")
now = 1000
reads = 0
ev.onExtendedOpcode(p, OP, {action = "scroll", data = {}})
eq(reads > 0, true, "a later request is answered")

print(string.format("guild_flood_test: %d checks OK", checks))
