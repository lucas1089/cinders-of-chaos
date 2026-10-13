-- Run from the server/ folder: luajit tests/save_before_credit_test.lua (and lua5.3; CI runs both). Mock engine API.
-- Crash duplication: value that leaves the character in memory and is credited to a database row (star bank, an
-- offline receiver's balance, the guild bank, the guild depot) is credited only after player:save() succeeded; a
-- failed save gives it back and credits nothing (chaos_constants.lua Chaos.saveCharacter). The stash and the guild
-- boss stone are checked in security_test.lua and guildboss_test.lua.
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

-- the database: every write is recorded
local writes = {}
local stars = {}
db = {
	query = function(q) writes[#writes + 1] = q; return true end,
	asyncQuery = function(q) writes[#writes + 1] = q end,
	storeQuery = function(q)
		local g = q:match("SELECT `stars` FROM `[%w_]+` WHERE `player_id` = (%d+)")
		if g and stars[tonumber(g)] then
			return {stars = stars[tonumber(g)]}
		end
		return nil
	end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end
}
result = {getNumber = function(r, k) return r[k] end, getString = function(r, k) return r[k] end, free = function() end}
local function wrote(pattern)
	for _, q in ipairs(writes) do
		if q:find(pattern) then return true end
	end
	return false
end

Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.decode = function(b) return b end
Chaos.send = function() return true end
local rowCount = 1
Chaos.select = function(q)
	if q:find("ROW_COUNT", 1, true) then return {{n = rowCount}} end
	if q:find("SELECT `xp`, `bank`", 1, true) then return {{xp = 0, bank = 0}} end
	return {}
end
ItemType = function(id) return {getId = function() return id end, getName = function() return "item" .. id end} end

local function newPlayer(guid, name)
	local p = {guid = guid, name = name, bank = 0, money = 0, items = {}, msgs = {}, saveOk = true, saves = 0}
	function p:getId() return self.guid end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getLevel() return 500 end
	function p:getBankBalance() return self.bank end
	function p:setBankBalance(v) self.bank = v end
	function p:getMoney() return self.money end
	function p:removeMoney(v) if self.money < v then return false end self.money = self.money - v return true end
	function p:removeTotalMoney(v)
		if self.money + self.bank < v then return false end
		local fromBag = math.min(self.money, v)
		self.money, self.bank = self.money - fromBag, self.bank - (v - fromBag)
		return true
	end
	function p:getItemCount(id) return self.items[id] or 0 end
	function p:removeItem(id, c) if (self.items[id] or 0) < c then return false end self.items[id] = self.items[id] - c return true end
	function p:addItem(id, c) self.items[id] = (self.items[id] or 0) + c return true end
	function p:save() self.saves = self.saves + 1 return self.saveOk end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:sendCancelMessage(t) self.msgs[#self.msgs + 1] = t end
	function p:getGroup() return {getAccess = function() return false end, getId = function() return 1 end} end
	function p:registerEvent() end
	return p
end

-- ---------------------------------------------------------------- bank.lua: star deposit, offline gold transfer
Chaos.bank.starItemId = 5000
Chaos.bank.transferMinLevel = 1
ChaosRateLimit = nil
local online = {}
Chaos.findPlayer = function(name) if name == "Offline" then return 77, "Offline", nil end return nil end
dofile("data/scripts/chaos/bank.lua")
local bankEvent = events.ChaosBankExtended
local OP = ChaosOpcodes.bank
local ana = newPlayer(1, "Ana")

ana.items[5000] = 10
ana.saveOk = false
writes = {}
bankEvent.onExtendedOpcode(ana, OP, {action = "deposit", data = {"star", 4}})
eq(wrote("`stars` = `stars` %+"), false, "no star bank credit when the save fails")
eq(ana.items[5000], 10, "the stars are given back")
ana.saveOk = true
bankEvent.onExtendedOpcode(ana, OP, {action = "deposit", data = {"star", 4}})
eq(wrote("`stars` = `stars` %+ 4"), true, "star bank credited after the save")
eq(ana.items[5000], 6, "the stars left the character")
eq(ana.saves >= 2, true, "saved before the credit")

ana.bank = 1000
ana.saveOk = false
writes = {}
bankEvent.onExtendedOpcode(ana, OP, {action = "transfer", data = {"gold", "Offline", 300}})
eq(wrote("UPDATE `players` SET `balance`"), false, "no offline credit when the save fails")
eq(ana.bank, 1000, "the gold is back")
ana.saveOk = true
bankEvent.onExtendedOpcode(ana, OP, {action = "transfer", data = {"gold", "Offline", 300}})
eq(wrote("UPDATE `players` SET `balance` = `balance` %+ 300 WHERE `id` = 77"), true, "offline receiver credited after the save")
eq(ana.bank, 700, "taken from the sender")
-- an online receiver: credited in memory only after the sender's save (the receiver may be saved first at its logout)
local cara = newPlayer(78, "Cara")
Chaos.findPlayer = function(name) if name == "Cara" then return 78, "Cara", cara end return nil end
ana.saveOk = false
bankEvent.onExtendedOpcode(ana, OP, {action = "transfer", data = {"gold", "Cara", 200}})
eq(cara.bank, 0, "no online credit when the sender's save fails")
eq(ana.bank, 700, "the gold is back")
ana.saveOk = true
local savesBefore = ana.saves
bankEvent.onExtendedOpcode(ana, OP, {action = "transfer", data = {"gold", "Cara", 200}})
eq(cara.bank, 200, "online receiver credited after the save")
eq(ana.bank, 500, "taken from the sender")
eq(ana.saves, savesBefore + 1, "the sender was saved")

-- ---------------------------------------------------------------- guild.lua: the guild bank deposit
dofile("data/scripts/chaos/guild.lua")
local G = ChaosGuild
local bo = newPlayer(2, "Bo")
function bo:getGuild() return {getId = function() return 9 end, getName = function() return "Wolves" end} end
function bo:getGuildLevel() return 3 end
bo.money = 50000
bo.saveOk = false
writes = {}
local ok = G.deposit(bo, 20000)
eq(ok, false, "no guild bank deposit when the save fails")
eq(wrote("SET `bank` = `bank` %+"), false, "the guild bank is not credited")
eq(bo.money + bo.bank, 50000, "Bo keeps the gold")
bo.saveOk = true
G.cache[9] = nil
ok = G.deposit(bo, 20000)
eq(ok, true, "deposit after the save")
eq(wrote("SET `bank` = `bank` %+ 20000"), true, "credited")
eq(bo.money + bo.bank, 30000, "taken")

-- ---------------------------------------------------------------- guild_hall.lua: the guild depot
function Position(x, y, z) return {x = x, y = y, z = z} end
dofile("data/scripts/chaos/guild_hall.lua")
G.inHall = function() return 1, 9 end
G.activeOf = function() return {depot = 1} end
G.levelOf = function() return 10 end
local created = {}
Game.createItem = function(id, c)
	local it = {id = id, count = c, attrs = {}}
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:setCustomAttribute(k, v) self.attrs[k] = v end
	created[#created + 1] = it
	return it
end
local function depotItem(id)
	local it = {id = id, removed = false}
	function it:getId() return self.id end
	function it:getCount() return 1 end
	function it:getName() return "a sword" end
	function it:isContainer() return false end
	function it:hasAttribute() return false end
	function it:getCustomAttribute() return nil end
	function it:remove() self.removed = true return true end
	return it
end
ItemType = function(id) return {getId = function() return id end, isStackable = function() return false end,
	isPickupable = function() return true end, getName = function() return "a sword" end} end
local given = {}
function bo:getPosition() return Position(1, 1, 7) end
function bo:addItemEx(it) given[#given + 1] = it return RETURNVALUE_NOERROR end
bo.saveOk = false
writes = {}
local sword = depotItem(3000)
ok = G.depotPut(bo, sword)
eq(ok, false, "no depot row when the save fails")
eq(wrote("INSERT INTO `[%w_]*depot"), false, "nothing inserted")
eq(#given, 1, "a copy goes back to the character")
eq(given[1].id, 3000, "the same item id")
bo.saveOk = true
local savesBefore = bo.saves
sword = depotItem(3000)
ok = G.depotPut(bo, sword)
eq(ok, true, "stored after the save")
eq(sword.removed, true, "the item left the character")
eq(bo.saves, savesBefore + 1, "saved")
eq(wrote("INSERT INTO `[%w_]*depot"), true, "row written")

print(string.format("save_before_credit_test: %d checks OK", checks))
