-- Run from the server/ folder: luajit tests/guild_hall_closed_test.lua (and lua5.3; CI runs both). Mock engine API.
-- The guild hall in closed test mode (O592; guild_hall.lua buyHall, hallThink; guild_core.lua hallBuyError; server/README.md "The siege and
-- the guild boss in closed mode (O592)"): the leader of a tester guild gets the hall for nothing at any guild level (the bots cannot
-- earn 5,000,000 gold and the guild boss needs a hall), a player still pays and needs the level, a tester hall never falls due, and a
-- hall whose guild the clean-up removed is dropped from memory (its slot is free again).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function ok(v, m) eq(not not v, true, m) end

local function object()
	return setmetatable({}, {__index = function(_, k)
		if k == "register" then return function() return true end end
		return function() return true end
	end})
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = object, object, object, object, object
EventCallback = object()
function addEvent() return 1 end
function stopEvent() end
function Position(x, y, z) return {x = x, y = y, z = z} end
Game = {getPlayers = function() return {} end, getStorageValue = function() return nil end}
local writes = {}
db = {query = function(q) writes[#writes + 1] = q return true end, asyncQuery = function() end, storeQuery = function() return nil end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end}
result = {getNumber = function() return 0 end, getString = function() return "" end, free = function() end}
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.decode = function(b) return b end
Chaos.send = function() return true end
local hallRows = 0
Chaos.select = function(q)
	if q:find("COUNT(*)", 1, true) and q:find("chaos_guild_hall", 1, true) then return {{n = hallRows}} end
	return {}
end
Chaos.totalMoney = function(p) return p.gold or 0 end
ItemType = function(id) return {getId = function() return id end, getName = function() return "item" end} end
dofile("data/scripts/chaos/guild.lua")
dofile("data/scripts/chaos/guild_hall.lua")
local G = ChaosGuild
local cfg = Chaos.guildConfig

local paid, season, furnished, logs = 0, 0, {}, {}
G.spend = function() paid = paid + 1 return true end
G.payFromPlayer = function() paid = paid + 1 return true end
G.seasonBlocked = function() season = season + 1 return nil end
G.buildSlot = function() return true end
G.furnish = function(gid) furnished[#furnished + 1] = gid end
G.tellGuild = function() end
G.logRow = function(gid, _, action, amount, _, slot, text) logs[#logs + 1] = {gid = gid, action = action, amount = amount, text = text} end
G.levelOf = function() return 1 end
G.row = function() return {bank = 0, xp = 0, level = 1} end
G.exec = function(q) writes[#writes + 1] = q return 1 end
G.placePortals = function() end
G.hallsLoaded = true
G.halls = {}

local function leader(id, gid, name, tester)
	local p = {id = id, gold = 0, msgs = {}, storage = {}}
	if tester then p.storage[Chaos.storage.tester] = 1 end
	function p:getId() return self.id end
	function p:getGuid() return self.id end
	function p:getName() return "P" .. self.id end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:getGuild() return {getId = function() return gid end, getName = function() return name end} end
	function p:getGuildLevel() return 3 end
	function p:getBankBalance() return 0 end
	function p:getGroup() return {getAccess = function() return false end} end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	return p
end

-- a player's guild: the level and the price are asked as always
local pl = leader(1, 5, "Ashen Wolves", false)
local okP, why = G.buyHall(pl, "bank")
eq(okP, false, "a player at guild level 1 cannot buy a hall")
ok(why:find("guild level", 1, true), "...for the level (" .. tostring(why) .. ")")
eq(paid, 0, "nothing was paid")
eq(season, 1, "the season rule is asked of a player")

-- a tester guild: free, any level, the leader only, once
local tl = leader(2, 71, "Tester Guild Alfa", true)
local okT, text = G.buyHall(tl, "bank")
ok(okT, "the leader of a tester guild buys the hall (" .. tostring(text) .. ")")
ok(text:find("free for the test guilds", 1, true), "...and is told it is free")
eq(paid, 0, "no gold moved, from the bank or the leader")
eq(season, 1, "the season rule is not asked of a tester")
local hall = G.halls[71]
ok(hall and hall.slot >= 1, "the hall exists in memory")
ok(hall.paidUntil - os.time() > 3000 * 86400, "a tester hall never falls due")
eq(G.testerHalls[71], hall.slot, "the tester hall is remembered")
eq(furnished[#furnished], 71, "the hall is furnished")
eq(logs[#logs].amount, 0, "the guild log says 0 gold")
local insert
for _, q in ipairs(writes) do
	if q:find("INSERT IGNORE INTO `chaos_guild_hall`", 1, true) then insert = q end
end
ok(insert and insert:find("71", 1, true), "the row is written (cleaned by tester_closed.py with the guild)")
okT, text = G.buyHall(tl, "bank")
ok(okT == false and text:find("already owns", 1, true), "one hall per guild")
local vice = leader(3, 72, "Tester Guild Bravo", true)
function vice:getGuildLevel() return 2 end
okT, text = G.buyHall(vice, "bank")
ok(okT == false and text:find("Only the guild leader", 1, true), "a vice-leader of a tester guild cannot buy it")
eq(paid, 0, "still nothing paid")

-- the clean-up removed the guild: the hall goes from memory at the next minute check
hallRows = 1
G.hallThink(true)
ok(G.halls[71] ~= nil, "a hall whose row is there stays")
hallRows = 0
G.hallThink(true)
eq(G.halls[71], nil, "a hall whose row is gone is dropped")
eq(G.testerHalls[71], nil, "...and forgotten")
eq(G.built[hall.slot], nil, "its slot is free to be built again")

print(string.format("guild_hall_closed_test: %d checks OK", checks))
