-- Run from the server/ folder: luajit tests/security_test.lua (and lua5.3; CI runs both). Mock of the engine API.
-- Security fixes of the launch review (docs/LAUNCH.md, "Security review"):
--   * ratelimit.lua: per player and key, refused inside the interval, forgotten at logout
--   * stash.lua: a floor item of a house cannot be stashed from outside that house; fixed (not movable) items cannot be
--     stashed; list / redeem requests are rate limited
--   * dungeons.lua: no queueing (and no teleport into a run) while in a fight
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.decode = function(buffer) return type(buffer) == "table" and buffer or nil end
local sent = {}
function Chaos.send(player, opcode, action, data) sent[#sent + 1] = {opcode = opcode, action = action, data = data}; return true end

local events, talks = {}, {}
function CreatureEvent(name) local o = {}; function o:type() end; function o:register() events[name] = o end; return o end
function TalkAction(words) local o = {}; function o:separator() end; function o:register() talks[words] = o end; return o end
function GlobalEvent(name) local o = {}; function o:interval() end; function o:register() end; return o end
function addEvent() return 1 end
function stopEvent() end

local clock = 1000000
os.mtime = function() return clock end

-- db: nothing stored yet; queries are recorded
local queries = {}
db = {query = function(q) queries[#queries + 1] = q; return true end, storeQuery = function() return nil end,
	asyncQuery = function(q) queries[#queries + 1] = q end, escapeString = function(s) return "'" .. s .. "'" end}
result = {free = function() end}
Chaos.select = function() return {} end

-- ---------------------------------------------------------------- ratelimit.lua
dofile("data/scripts/chaos/ratelimit.lua")
local R = ChaosRateLimit
eq(R.allowAt(1, "a", 500, 1000), true, "first request")
eq(R.allowAt(1, "a", 500, 1400), false, "inside the interval")
eq(R.allowAt(1, "b", 500, 1400), true, "another key")
eq(R.allowAt(2, "a", 500, 1400), true, "another player")
eq(R.allowAt(1, "a", 500, 1500), true, "after the interval")
eq(R.allowAt(1, "a", 500, 900), true, "clock went back: allowed, not stuck")
eq(R.allowAt(nil, "a", 500, 1), false, "no id")
R.forget(1)
eq(R.last[1], nil, "forgotten at logout")

-- ---------------------------------------------------------------- map, items, player
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local tiles = {}
local function house(id) return {getId = function() return id end} end
local function tile(x, y, z, h)
	local t = {things = {}, house = h}
	function t:getHouse() return self.house end
	function t:getThing(i) return self.things[i + 1] end
	tiles[key(x, y, z)] = t
	return t
end
function Tile(a, b, c)
	if type(a) == "table" then return tiles[key(a.x, a.y, a.z)] end
	return tiles[key(a, b, c)]
end
function Position(x, y, z) return {x = x, y = y, z = z} end

local function item(id, count, movable)
	local it = {id = id, count = count, removed = false}
	local itype = {
		isStackable = function() return true end, isPickupable = function() return true end,
		isContainer = function() return false end, isMovable = function() return movable ~= false end,
		isRune = function() return false end, getWeaponType = function() return 0 end,
		getName = function() return "gold coin" end, getId = function() return id end, getClientId = function() return id end
	}
	function it:isItem() return true end
	function it:getType() return itype end
	function it:getId() return self.id end
	function it:getCount() return self.count end
	function it:hasAttribute() return false end
	function it:remove(c) self.removed = true; return true end
	return it
end
ItemType = function(id) return item(id, 1):getType() end

local function newPlayer(id, pos)
	local p = {pos = pos, cancels = {}, inFight = false, pzLocked = false}
	function p:getId() return id end
	function p:getGuid() return id * 10 end
	function p:getPosition() return self.pos end
	function p:sendCancelMessage(t) self.cancels[#self.cancels + 1] = t end
	function p:sendTextMessage() end
	function p:getStorageValue() return -1 end
	function p:getLevel() return 200 end
	function p:getIp() return 0 end
	function p:getGroup() return {getId = function() return 1 end, getAccess = function() return false end} end
	function p:isPzLocked() return self.pzLocked end
	function p:hasCondition(c) return c == CONDITION_INFIGHT and self.inFight end
	function p:registerEvent() end
	return p
end

-- ---------------------------------------------------------------- stash.lua
dofile("data/scripts/chaos/stash.lua")
local stashEvent = events.ChaosStashExtended
local OP = ChaosOpcodes.stash
local function stashAt(player, x, y, z)
	stashEvent.onExtendedOpcode(player, OP, {action = "Stash", data = {make = "Stash", Pos = {x = x, y = y, z = z, stackpos = 0}}})
end

local h5 = house(5)
tile(100, 100, 7)                                   -- the street, outside the house wall
tile(101, 101, 7, h5)                               -- inside house 5
local houseFloor = tile(101, 100, 7, h5)            -- house 5 floor, right behind the wall
local gold = item(2148, 100)
houseFloor.things[1] = gold

local outside = newPlayer(1, Position(100, 100, 7))
stashAt(outside, 101, 100, 7)
eq(gold.removed, false, "house floor item stashed from outside the house")

local inside = newPlayer(2, Position(101, 101, 7))
stashAt(inside, 101, 100, 7)
eq(gold.removed, true, "a player inside the house stashes from its floor")
local insert = queries[#queries]
eq(insert:find("INSERT INTO `" .. Chaos.tables.stash .. "`", 1, true) ~= nil, true, "stash row written")

local otherHouse = tile(99, 100, 7, house(6))       -- another house next to the street
local coins = item(2152, 3)
otherHouse.things[1] = coins
stashAt(inside, 99, 100, 7)                         -- too far anyway; and from the street:
stashAt(outside, 99, 100, 7)
eq(coins.removed, false, "an item in another house")

local street = tiles[key(100, 100, 7)]
local fixed = item(2149, 5, false)                  -- a stackable map decoration that must stay
street.things[1] = fixed
stashAt(outside, 100, 100, 7)
eq(fixed.removed, false, "a not movable item")
local loose = item(2150, 7)
street.things[1] = loose
stashAt(outside, 100, 100, 7)
eq(loose.removed, true, "a movable item on the street is stashed as before")

-- rate limit: the item list is read from the database at most every 300 ms
local before = #sent
stashEvent.onExtendedOpcode(outside, OP, {action = "Stash", data = {make = "SendItems"}})
stashEvent.onExtendedOpcode(outside, OP, {action = "Stash", data = {make = "SendItems"}})
eq(#sent - before, 1, "second list request inside 300 ms dropped")
clock = clock + 300
stashEvent.onExtendedOpcode(outside, OP, {action = "Stash", data = {make = "SendItems"}})
eq(#sent - before, 2, "allowed again after 300 ms")

-- ---------------------------------------------------------------- dungeons.lua
DUNGEON_SYSTEM = {
	Dungeons = {[1] = {Name = "Test Crypt", NeedParty = true, AmountParty = 2, NeedLevel = false,
		FromPos = {x = 500, y = 500, z = 7}, ToPos = {x = 520, y = 520, z = 7}, DungeonPos = {x = 510, y = 510, z = 7}}}
}
local byGuid = {}
Game = {getPlayerByGUID = function(g) return byGuid[g] end, getPlayers = function() return {} end,
	getSpectators = function() return {} end, getStorageValue = function() return nil end}
dofile("data/scripts/chaos/dungeons.lua")
local dungeonEvent = events.ChaosDungeonsExtended
local DOP = ChaosOpcodes.dungeons
local fighter = newPlayer(3, Position(100, 100, 7))
byGuid[fighter:getGuid()] = fighter
fighter.inFight = true
local function queue(p)
	sent = {}
	dungeonEvent.onExtendedOpcode(p, DOP, {action = "queue", data = {id = 1, difficulty = 1}})
	for _, s in ipairs(sent) do
		if s.action == "queue" then return s.data.joined end
	end
end
eq(queue(fighter), false, "queued while in a fight")
eq(fighter.cancels[#fighter.cancels]:find("fight", 1, true) ~= nil, true, "told why")
fighter.inFight, fighter.pzLocked = false, true
eq(queue(fighter), false, "queued while protection-zone locked")
fighter.pzLocked = false
eq(queue(fighter), true, "queued out of combat")

print("security_test: ok")
