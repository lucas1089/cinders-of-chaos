-- Run from the server/ folder: luajit tests/depot_test.lua (and lua5.3; CI runs both)
-- The depot, retired (O316; server/README.md "Depot (retired)"): depot_core.lua with the real depot_config.lua (the boxes
-- and ids the base engine needs, no tabs, no store offers, no window), where the engine puts a dropped item, which box a
-- container is in, the move rule (nothing new goes into the chest or a box, tidying inside one stays possible), and
-- depot.lua against a mocked engine: a locker opening loads the chest, moves the depot into the stash one event later,
-- opens the stash window and tells the client to close the locker; the move hook; no depot window opcode.

local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end
local function has(text, part, label)
	check(type(text) == "string" and text:find(part, 1, true) ~= nil, label .. " (" .. tostring(text) .. ")")
end

dofile("data/scripts/chaos/depot_core.lua")
local D = ChaosDepotCore
local cfg = dofile("data/scripts/chaos/depot_config.lua")
local pc = dofile("data/scripts/chaos/pact_config.lua")
local sc = dofile("data/scripts/chaos/stash_config.lua")

-- ---------------------------------------------------------------- config
eq(D.maxTabs(cfg), 17, "17 old depot boxes")
local seen = {}
for i, id in ipairs(cfg.boxIds) do
	check(not seen[id], "box id once: " .. id)
	seen[id] = true
	eq(D.tabOf(cfg, id), i, "tab of box " .. id)
	check(not D.isChest(cfg, id), "a box is no chest")
end
eq(D.tabOf(cfg, 2594), nil, "the chest is no tab")
check(D.isChest(cfg, 2594), "depot chest")
check(cfg.boxSlots >= 100 and cfg.boxSlots <= 255, "a box keeps the room the patch tool writes")
eq(cfg.store, nil, "O316: the depot sells nothing")
eq(cfg.achievementTabs, nil, "no achievement tabs") eq(cfg.palette, nil, "no tab colours") eq(cfg.limitKey, nil, "no tab limit")
eq(D.tabCount, nil, "no tab count") eq(D.layout, nil, "no sorting into tabs") eq(D.cleanName, nil, "no tab names")
eq(pc.limits.depotTabs, nil, "the Pact has no depot tab limit")
eq(pc.extras.depotTabs.retired, true, "the bought depot tabs are a retired extra")
eq(sc.depot.withdrawOnly, true, "the depot is withdraw-only") eq(sc.depot.migrate, true, "and moves into the stash")
eq(sc.depot.version, 2, "migration version 2 brings back the 2026-10-17 stash move")
eq(sc.depot.openStash, true, "a locker opens the stash")
-- the store: no depot category, no depot offers anywhere
local shop = dofile("data/scripts/chaos/shop_config.lua")
local function noDepot(text, label)
	check(type(text) ~= "string" or not text:lower():find("depot", 1, true), label .. " mentions the depot: " .. tostring(text))
end
for _, c in ipairs(shop.categories) do
	noDepot(c.name, "category")
	for _, o in ipairs(c.offers or {}) do
		noDepot(o.name, "offer name")
		noDepot(o.description, "offer " .. tostring(o.name))
		check(o.extra ~= "depotTabs", "no depot tab offer: " .. tostring(o.name))
	end
end
-- the achievements that opened depot tabs now give stash slots
local ach = dofile("data/scripts/chaos/achievements_data.lua")
local achById = {}
for _, a in ipairs(ach.list) do
	achById[a.id] = a
end
for _, id in ipairs(sc.generalAchievements) do
	local a = achById[id]
	check(a ~= nil, "achievement " .. id .. " exists (the id is stored data)")
	has(a and a.desc, "75 stash slots", "achievement " .. id .. " says what it gives now")
end

-- ---------------------------------------------------------------- engine-like tree for destination / locate
-- a node: {id, items = {...} (a container), count}
local function node(id, items, extra)
	local n = {id = id, items = items}
	for k, v in pairs(extra or {}) do
		n[k] = v
	end
	return n
end
local function link(parent)
	for i, c in ipairs(parent.items or {}) do
		c.parent = parent
		c.index = i - 1
		link(c)
	end
	return parent
end
local A = {
	id = function(n) return n.id end,
	parent = function(n) return n.parent and n.parent.items and n.parent or nil end,
	isContainer = function(n) return n.items ~= nil end,
	itemAt = function(n, slot) return n.items[slot + 1] end,
	capacity = function(n) return n.cap or 20 end,
	same = function(a, b) return a == b end
}
local tab1 = node(25453, {node(2400), node(1987, {node(2401)})})
local tab2 = node(25454, {})
local tab6 = node(25458, {node(2402)})
local oldBag = node(1988, {node(2403)})
local chest = node(2594, {tab1, tab2, tab6, oldBag, node(2404)}, {cap = 150})
local locker = link(node(2589, {node(14405), node(14404, {}), chest}, {cap = 3}))
eq(D.destination(chest, 0, A), tab1, "dropped on the tab 1 icon: into tab 1")
eq(D.destination(chest, 2, A), tab6, "dropped on tab 6")
eq(D.destination(chest, 4, A), chest, "dropped on a loose item: the chest")
eq(D.destination(chest, 255, A), chest, "anywhere: the chest")
eq(D.destination(chest, 150, A), chest, "past the end: the chest")
eq(D.destination(chest, 254, A), locker, "up: the locker")
eq(D.destination(locker, 2, A), chest, "dropped on the chest in the locker window: the chest")
eq(D.destination(tab1, 1, A), tab1.items[2], "dropped on a bag inside the tab: into the bag")
eq(D.destination(tab1, 0, A), tab1, "dropped on an item in the tab: the tab")
local l = D.locate(cfg, tab1, A)
eq(l.kind, "tab", "tab 1 is a tab") eq(l.tab, 1, "tab number") eq(l.chest, chest, "its chest")
l = D.locate(cfg, tab1.items[2], A)
eq(l.kind, "tab", "a bag in tab 1 is in a tab") eq(l.tab, 1, "same tab number") eq(l.box, tab1, "the box")
eq(D.locate(cfg, tab6, A).tab, 6, "tab 6")
eq(D.locate(cfg, chest, A).kind, "chest", "the chest")
eq(D.locate(cfg, oldBag, A).kind, "loose", "a bag loose in the chest")
eq(D.locate(cfg, locker, A).kind, "other", "the locker")
eq(D.locate(cfg, locker.items[2], A).kind, "other", "the inbox")
eq(D.locate(cfg, link(node(1988, {node(25453, {})})).items[1], A).kind, "other", "a box that is not in a chest")
eq(D.locate(cfg, nil, A).kind, "other", "inventory / ground")

-- ---------------------------------------------------------------- the move decision
local function loc(kind, tab, ch)
	return {kind = kind, tab = tab, chest = ch or "c1"}
end
local function decide(m)
	return D.decide(cfg, m)
end
local r = decide({to = loc("tab", 2), from = loc("other")})
eq(r and r.code, "closed", "nothing new into a box")
has(r and r.text, "retired", "the text says why")
r = decide({to = loc("chest"), from = loc("other")})
eq(r and r.code, "closed", "nothing new loose into the chest")
r = decide({to = loc("loose"), from = loc("other")})
eq(r and r.code, "closed", "nothing new into an old loose bag")
r = decide({to = loc("tab", 2), from = loc("tab", 3), sameTab = false})
eq(r and r.code, "closed", "from one box into another")
eq(decide({to = loc("tab", 2), from = loc("tab", 2), sameTab = true, sameChest = true}), nil, "tidying inside a box")
r = decide({to = loc("tab", 2), from = loc("tab", 2), sameTab = true, sameChest = true, split = true})
eq(r and r.code, "closed", "splitting a stack makes a new stack: refused")
eq(decide({to = loc("chest"), from = loc("chest"), sameChest = true}), nil, "a loose item moved around in the chest")
r = decide({to = loc("chest"), from = loc("chest", nil, "c2"), sameChest = false})
eq(r and r.code, "closed", "a loose item of another depot")
eq(decide({to = loc("other"), from = loc("tab", 9)}), nil, "taking out of a box stays possible")
eq(decide({to = loc("other"), from = loc("other")}), nil, "every other move is none of ours")

-- a locker opening: a line and the stash
local lo = D.lockerOpen(cfg, sc.depot)
eq(lo.stash, true, "the locker opens the stash window")
has(lo.text, "retired", "the locker line")
eq(D.lockerOpen(cfg, {openStash = false}).stash, false, "unless the config says no")

-- ================================================================ engine part (depot.lua) against a mocked engine
CONTAINER_POSITION = 0xFFFF
RETURNVALUE_NOERROR, RETURNVALUE_NOTPOSSIBLE, RETURNVALUE_CONTAINERNOTENOUGHROOM = 0, 1, 2
MESSAGE_STATUS_WARNING, MESSAGE_INFO_DESCR, MESSAGE_STATUS_DEFAULT = 10, 11, 12
local timers, lockerAction, registeredEvents = {}, nil, {}
EventCallback = setmetatable({}, {__newindex = function() end, __index = function(t, k) if k == "register" then return function() end end end})
CreatureEvent = function(name)
	local e = {name = name, type = function() end}
	function e:register() registeredEvents[#registeredEvents + 1] = name end
	return e
end
Action = function()
	local a = {ids = {}}
	function a:id(i) self.ids[#self.ids + 1] = i end
	function a:register() lockerAction = self end
	return a
end
addEvent = function(fn) timers[#timers + 1] = fn end
local function runTimers()
	local list = timers
	timers = {}
	for _, t in ipairs(list) do
		t()
	end
end
ItemType = function(id)
	return {getClientId = function() return id - 1000 end, isStackable = function() return id == 2160 end}
end
db = {escapeString = function(s) return "'" .. s .. "'" end, query = function() return true end}
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.sent = {}
Chaos.send = function(player, op, action, data) Chaos.sent[#Chaos.sent + 1] = {op = op, action = action, data = data} end
-- the base locker script does not exist in the test folder: depot.lua registers its own locker Action
local realOpen = io.open
io.open = function(path, mode)
	if path:find("customs/actions", 1, true) or path:find("events/scripts/player.lua", 1, true) then
		return nil
	end
	return realOpen(path, mode)
end
getDepotId = function(uid) return uid == 40001 and 3 or nil end

-- engine items
local Item = {}
Item.__index = Item
Item.__eq = function(a, b) return rawequal(a, b) end
local function mk(id, opts)
	local it = setmetatable({id = id, count = 1, attrs = {}}, Item)
	for k, v in pairs(opts or {}) do
		it[k] = v
	end
	for _, c in ipairs(it.items or {}) do
		c.parent = it
	end
	return it
end
function Item:getId() return self.id end
function Item:getParent() return self.parent end
function Item:isContainer() return self.items ~= nil end
function Item:getItems() local out = {} for i, c in ipairs(self.items) do out[i] = c end return out end
function Item:getItem(slot) return self.items[slot + 1] end
function Item:getCapacity() return self.cap or 20 end
function Item:getCount() return self.count end
function Item:getType() return ItemType(self.id) end
function Item:getUniqueId() return self.uid or 0 end
function Item:getPosition() return self.pos or {x = 1000, y = 1000, z = 7} end

local function newPlayer(id)
	local p = {id = id, texts = {}, chests = {}}
	function p:getId() return id end
	function p:getDepotChest(town, create) self.asked = (self.asked or 0) + 1 return self.chests[town] end
	function p:sendTextMessage(_, t) self.texts[#self.texts + 1] = t end
	return p
end
local players = {}
Player = function(id) return players[id] end

dofile("data/scripts/chaos/depot.lua")
local Depot = ChaosDepot
check(lockerAction ~= nil, "the locker Action is registered when the base script is missing")
local ids = {}
for _, i in ipairs(lockerAction.ids) do ids[i] = true end
for _, i in ipairs(cfg.lockerIds) do check(ids[i], "locker " .. i .. " has the Action") end
check(#registeredEvents == 0, "no creature events: no depot window, no opcode, no styles")
eq(ChaosOpcodes.depotTabs, 111, "the opcode number stays reserved (retired)")
eq(Depot.tabs, nil, "no tab count") eq(Depot.requestOpen, nil, "no window requests") eq(Depot.ensure, nil, "no boxes are made")
eq(Depot.migrate, nil, "no sorting of loose items into tabs")

-- a locker opening: the chest is loaded now, the rest one event later
local chest = mk(2594, {items = {mk(25453, {items = {mk(2400)}})}, cap = 150})
local locker = mk(2589, {items = {mk(14405), mk(14404, {items = {}}), chest}, uid = 40001})
local p = newPlayer(7)
p.chests[3] = chest
players[7] = p
local migrated, opened = 0, nil
ChaosStash = {migrateDepot = function(pl) migrated = migrated + 1 end,
	openWindow = function(pl, closeIds) opened = closeIds end}
local ret = lockerAction.onUse(p, locker, {}, nil, {}, false)
eq(ret, false, "the engine still opens the locker (the chest must have its parent for the migration)")
eq(p.asked, 1, "the chest is loaded")
eq(migrated, 0, "nothing yet")
runTimers()
eq(migrated, 1, "one event later the depot moves into the stash")
check(opened ~= nil and #opened == #cfg.lockerIds, "the stash window opens and the locker client ids go along")
eq(opened[1], 2589 - 1000, "the client id of the first locker")
has(p.texts[#p.texts], "retired", "the player is told")
-- migration off: the stash still opens, nothing moves
sc.depot.migrate = false
local stashCfg = Chaos.stashConfig
Chaos.stashConfig = {depot = {migrate = false, openStash = true}}
p.texts = {}
opened = nil
Depot.onOpenLocker(p, locker)
runTimers()
eq(migrated, 1, "migrate off: not again") check(opened ~= nil, "the stash still opens")
Chaos.stashConfig = {depot = {migrate = true, openStash = false}}
opened = nil
Depot.onOpenLocker(p, locker)
runTimers()
eq(migrated, 2, "migrate on") eq(opened, nil, "openStash off: only the line")
Chaos.stashConfig = stashCfg
sc.depot.migrate = true
-- a hideout locker passes the town itself (it has no unique id of a base depot)
migrated, opened = 0, nil
local hl = mk(2589, {items = {chest}})
Depot.onOpenLocker(p, hl, 3)
runTimers()
eq(migrated, 1, "the hideout locker: the same flow") check(opened ~= nil, "and the stash opens")
-- an unknown locker does nothing
migrated = 0
Depot.onOpenLocker(p, mk(2589, {items = {}, uid = 999}))
runTimers()
eq(migrated, 0, "no depot id: nothing")
-- an error in the stash never reaches the player's click
ChaosStash.migrateDepot = function() error("boom") end
Depot.onOpenLocker(p, locker)
runTimers()
check(true, "a failing migration is caught")
ChaosStash.migrateDepot = function(pl) migrated = migrated + 1 end

-- the move hook (Player:onMoveItem): nothing new into the chest or a box
local function move(item, count, toCyl, slot, fromCyl)
	return Depot.onMoveItem(p, item, count, {x = 1, y = 1, z = 1}, {x = 0xFFFF, y = 64, z = slot or 255}, fromCyl, toCyl)
end
local box1 = chest.items[1]
local sword = mk(2400)
eq(move(sword, 1, chest, 255, nil), 1, "an item dropped on the chest is refused")
p.texts = {}
eq(move(sword, 1, box1, 255, nil), 1, "an item dropped into a box is refused")
has(p.texts[#p.texts], "retired", "and told why")
eq(move(sword, 1, chest, 0, nil), 1, "dropped on the box icon in the chest window: refused")
eq(move(mk(2160), 1, mk(1987, {items = {}}), 255, nil), 0, "an ordinary bag: none of ours")
eq(move(sword, 1, nil, 255, nil), 0, "no container: none of ours")
local inbox = locker.items[2]
eq(move(sword, 1, inbox, 255, nil), 0, "the inbox takes items (the engine delivers there)")
eq(Depot.onMoveItem(p, sword, 1, {x = 1, y = 1, z = 1}, {x = 5, y = 5, z = 7}, nil, chest), 0, "a ground position: none of ours")
-- taking out of a box
eq(move(box1.items[1], 1, mk(1988, {items = {}}), 255, box1), 0, "taking an item out of a box")
-- tidying inside one box
local inner = mk(1987, {items = {}})
box1.items[#box1.items + 1] = inner
inner.parent = box1
eq(move(box1.items[1], 1, inner, 255, box1), 0, "inside the same box")
-- checkAdd for scripts
local code, text = Depot.checkAdd(p, chest, sword, 1)
eq(code, 1, "checkAdd: refused") has(text, "retired", "checkAdd: the text")
eq(Depot.checkAdd(p, inbox, sword, 1), 0, "checkAdd: the inbox is fine")

print(string.format("depot_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
