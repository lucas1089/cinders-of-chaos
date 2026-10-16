-- Run from the server/ folder: luajit tests/ancestral_store_test.lua (and lua5.3; CI runs both)
-- The Ancestral Store of the Info & Services window (commands_ui.lua on a mocked engine): the store answer (points,
-- entries with price and item read from the base store scripts), and the buy path: the price and the points are the
-- server's, unknown ids and bad counts (negative, zero, huge, fractions, strings, NaN) are refused, a purchase is rate
-- limited, the points never go below zero, a full backpack gives the points back, the old "group, n" run command buys
-- here instead of running the base script, and a character that is gone buys nothing. Also the Services page state.

local checks, failures = 0, 0
local function ok(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

-- ---------------------------------------------------------------- virtual base files
local FILES = {
	["data/talkactions/talkactions.xml"] = [[
	<!-- chaos-menu (Info & Services window): <talkaction words="!ancestralstore 2, 1" script="fiery_wings.lua" /> -->
	<!-- chaos-menu (Info & Services window): <talkaction words="!ancestralstore 1, 8" script="electric_shock.lua" /> -->
	<!-- chaos-menu (Info & Services window): <talkaction words="!ancestralstore 3, 31" script="lasting_shield_chest.lua" /> -->
	<!-- chaos-menu (Info & Services window): <talkaction words="!ancestralstore 3, 32" script="broken.lua" /> -->
	<!-- chaos-menu (Info & Services window): <talkaction words="!ancestralstore 3, 33" script="../../../evil.lua" /> -->
]],
	["data/talkactions/scripts/fiery_wings.lua"] = "local ITEM_PRICE = 25 \nfunction onSay(player)\n local item = ItemType(26644) \nend",
	["data/talkactions/scripts/electric_shock.lua"] = "local ITEM_PRICE = 35\n local item = ItemType(26652)",
	["data/talkactions/scripts/lasting_shield_chest.lua"] = "local ITEM_PRICE = 750 \n local item = ItemType(27781)",
	["data/talkactions/scripts/broken.lua"] = "local ITEM_PRICE = -5\n local item = ItemType(27781)",
}
local realOpen = io.open
io.open = function(path, mode)
	if FILES[path] then
		local text = FILES[path]
		return {read = function() return text end, close = function() end}
	end
	if path:find("^data/talkactions") or path:find("^data/scripts/customs") then
		return nil
	end
	return realOpen(path, mode)
end

-- ---------------------------------------------------------------- mocked engine
MESSAGE_INFO_DESCR, MESSAGE_EVENT_ADVANCE = 22, 19
local ITEMS = {[26644] = {"Fiery Wings", 3001, 10}, [26652] = {"Electric Shock Aura", 3002, 10},
	[27781] = {"Lasting Exercise Shield Chest", 3003, 50}}
function ItemType(id)
	local d = ITEMS[id]
	return {
		getId = function() return d and id or 0 end,
		getName = function() return d and d[1] or "" end,
		getClientId = function() return d and d[2] or 0 end,
		getWeight = function(_, n) return (d and d[3] or 0) * (n or 1) end,
	}
end
local points = {[100] = 60} -- guid -> ancestral_points
local queries = {}
db = {
	query = function(q)
		queries[#queries + 1] = q
		local cost, guid, atLeast = q:match("`ancestral_points` = `ancestral_points` %- (%d+) WHERE `id` = (%d+) AND `ancestral_points` >= (%d+)")
		if cost then
			guid = tonumber(guid)
			if points[guid] >= tonumber(atLeast) then
				points[guid] = points[guid] - tonumber(cost)
			end
			return true
		end
		local back, g2 = q:match("`ancestral_points` = `ancestral_points` %+ (%d+) WHERE `id` = (%d+)")
		if back then
			points[tonumber(g2)] = points[tonumber(g2)] + tonumber(back)
			return true
		end
		return true
	end,
	escapeString = function(s) return "'" .. s .. "'" end,
}
local storages = {}
local online = {}
local allowAdds -- nil: room for everything; n: n more items fit
local function newPlayer(id, guid)
	local p = {id = id, guid = guid, items = {}, cap = 1000, level = 150}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return "Tester" end
	function p:getAccountId() return 1 end
	function p:getLevel() return self.level end
	function p:getFreeCapacity() return self.cap end
	function p:getStorageValue(k) return storages[self.id .. ":" .. k] or -1 end
	function p:setStorageValue(k, v) storages[self.id .. ":" .. k] = v end
	function p:registerEvent() end
	function p:sendTextMessage() end
	function p:addItem(itemId, count, canDrop)
		ok(canDrop == false, "items are never dropped on the floor")
		if allowAdds then
			if allowAdds <= 0 then
				return nil
			end
			allowAdds = allowAdds - 1
		end
		self.items[#self.items + 1] = itemId
		return {}
	end
	return p
end
Player = setmetatable({}, {__call = function(_, id) return online[id] end})
function Vocation(id) return {getName = function() return "Juggernaut" end} end
local events = {}
function CreatureEvent(name)
	local ev = {name = name}
	function ev:type(t) self.t = t end
	function ev:register() events[self.name] = self end
	return ev
end
json = {encode = function(t) return t end, decode = function(t) return t end}

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
local sent = {}
Chaos.send = function(player, opcode, action, data)
	sent[#sent + 1] = {opcode = opcode, action = action, data = data}
	return true
end
Chaos.decode = function(msg) return type(msg) == "table" and msg or nil end
local selects = 0
Chaos.select = function(q, cols)
	selects = selects + 1
	local guid = tonumber(q:match("FROM `players` WHERE `id` = (%d+)"))
	if guid then
		return points[guid] and {{ancestral_points = points[guid]}} or {}
	end
	if q:find("znote_shop_orders") then
		return {{n = 2}}
	end
	return {}
end
local clock = 0
os.mtime = function() return clock end -- luacheck: ignore
dofile("data/scripts/chaos/ratelimit.lua")
dofile("data/scripts/chaos/commands_ui.lua")
local ext = events.ChaosCommandsExtended
ok(ext ~= nil, "extended opcode event registered")
local OPCODE = ChaosOpcodes.info or 237

local me = newPlayer(7, 100)
online[7] = me
local function req(msg)
	sent = {}
	clock = clock + 5000 -- past every rate limit unless a test holds the clock
	ext.onExtendedOpcode(me, OPCODE, msg)
	return sent[#sent]
end

-- ---------------------------------------------------------------- the store answer
local a = req({action = "store"})
ok(a and a.action == "store", "store answered")
ok(a.data.points == 60, "points sent: " .. tostring(a.data.points))
ok(#a.data.entries == 3, "three entries (broken price and a path outside the scripts folder left out): " .. #a.data.entries)
ok(a.data.entries[1].id == 1 and a.data.entries[1].price == 25 and a.data.entries[1].item == 3001
	and a.data.entries[1].kind == "Wings" and a.data.entries[1].name == "Fiery Wings", "entry 1: id, price, client id, kind")
ok(a.data.entries[2].id == 8 and a.data.entries[2].kind == "Aura", "entry 8 is an aura")
ok(a.data.entries[3].price == 750, "lasting chest price")
local cat = req({action = "catalog"})
local hasStore = false
for _, id in ipairs(cat.data.ids) do
	hasStore = hasStore or id == "ancestralstore"
end
ok(hasStore and cat.data.store == nil, "catalog offers the store, without the old entry list")

-- ---------------------------------------------------------------- buying
a = req({action = "buy", id = 1})
ok(points[100] == 35 and me.items[1] == 26644, "bought one Fiery Wings for 25: " .. points[100])
ok(a.data.points == 35 and a.data.message:find("Bought 1x Fiery Wings for 25"), "new points and message sent")

local bad = {
	{id = 999}, {id = -1}, {id = "1; DROP"}, {id = 1.5}, {id = {}},
	{id = 1, count = -3}, {id = 1, count = 0}, {id = 1, count = 1e9}, {id = 1, count = 2.5},
	{id = 1, count = "2x"}, {id = 1, count = 0 / 0}, {id = 1, count = math.huge}, {id = 1, count = 11},
}
for i, b in ipairs(bad) do
	local before, n = points[100], #me.items
	b.action = "buy"
	selects = 0
	a = req(b)
	ok(selects == 0, "bad request " .. i .. " reads no database")
	ok(points[100] == before and #me.items == n and a and a.data.message, "bad request " .. i .. " refused")
end

a = req({action = "buy", id = 8})
ok(points[100] == 0 and #me.items == 2, "bought the aura with the last 35 points")
a = req({action = "buy", id = 1})
ok(points[100] == 0 and #me.items == 2 and a.data.message:find("You need 25"), "no points: refused")
points[100] = 100
a = req({action = "buy", id = 1, count = 5})
ok(points[100] == 100 and #me.items == 2 and a.data.message:find("You need 125"), "5 x 25 > 100: refused as a whole")
a = req({action = "buy", id = 1, count = 4})
ok(points[100] == 0 and #me.items == 6, "4 x 25 = 100: bought")

-- rate limit: a second buy in the same second is refused
points[100] = 100
req({action = "buy", id = 1})
sent = {}
selects = 0
ext.onExtendedOpcode(me, OPCODE, {action = "buy", id = 1})
ok(selects == 0, "a buy within the cooldown reads no database")
ok(points[100] == 75, "second buy within a second refused: " .. points[100])
ok(sent[1] and sent[1].data.message:find("Wait a moment"), "the wait is said")

-- capacity
points[100] = 1000
me.cap = 20
a = req({action = "buy", id = 31})
ok(points[100] == 1000 and a.data.message:find("capacity"), "no capacity: nothing taken")
me.cap = 1000

-- a full backpack: points come back
allowAdds = 1
local n = #me.items
a = req({action = "buy", id = 1, count = 2})
ok(points[100] == 975 and #me.items == n + 1, "one of two given, 25 returned: " .. points[100])
allowAdds = 0
a = req({action = "buy", id = 1})
ok(points[100] == 975 and a.data.message:find("returned"), "none given: all returned")
allowAdds = nil

-- the points changed under the purchase (the conditional UPDATE did not apply): nothing given
local realQuery = db.query
db.query = function(q)
	if q:find("AND `ancestral_points` >=") then
		return true -- another writer took the points first: the row did not change
	end
	return realQuery(q)
end
n = #me.items
a = req({action = "buy", id = 1})
ok(#me.items == n and a.data.message:find("failed"), "an UPDATE that took nothing gives nothing")
db.query = realQuery

-- the old run command ("group, n") buys here: one piece, price checked, base script never loaded
points[100] = 30
n = #me.items
a = req({action = "run", page = "ancestral", ids = {"ancestralstore"}, params = {"2, 1"}})
ok(points[100] == 5 and #me.items == n + 1, "run ancestralstore 2, 1 bought one piece: " .. points[100])
a = req({action = "run", page = "ancestral", ids = {"ancestralstore"}, params = {"9, 9"}})
ok(points[100] == 5 and #a.data.parts == 0, "an unknown param is ignored")

-- a character that is gone buys nothing
online[7] = nil
points[100] = 500
n = #me.items
req({action = "buy", id = 1})
ok(points[100] == 500 and #me.items == n, "logged out: nothing bought")
online[7] = me

-- ---------------------------------------------------------------- Services state
me:setStorageValue(Chaos.storage.nameChangeTokens, 1)
me:setStorageValue(Chaos.classes.storage.freeSwitch, 14)
local SC = ChaosShopCore or {}
ChaosShopCore = SC
SC.FRAMES = SC.FRAMES or {"violet", "frost"}
SC.frameStorage = SC.frameStorage or function(S, i) return 7100760 + i end
me:setStorageValue(SC.frameStorage(Chaos.storage, 2), 1)
me:setStorageValue(Chaos.storage.shopFrameActive, 2)
a = req({action = "services"})
ok(a.action == "services", "services answered")
ok(a.data.nameTokens == 1 and a.data.vocationTokens == 0, "tokens")
ok(a.data.freeSwitch == "Juggernaut", "free switch")
ok(a.data.familiarReady == false and a.data.familiarLevel == 200, "familiar below level 200")
ok(#a.data.frames == 1 and a.data.frames[1] == SC.FRAMES[2] and a.data.activeFrame == SC.FRAMES[2], "owned frame and the one shown")
ok(a.data.webshopOrders == -1, "web shop unknown when the base script is missing")

io.open = realOpen
print(string.format("ancestral_store_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
