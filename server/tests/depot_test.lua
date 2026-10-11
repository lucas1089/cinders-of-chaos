-- Run from the server/ folder: luajit tests/depot_test.lua (and lua5.3; CI runs both)
-- Depot tabs: the rules (depot_core.lua with the real depot_config.lua and pact_config.lua: config sanity, the account's
-- tab count, counting with nested containers, where the engine puts a dropped item, which tab a container is in, the
-- move decision for locked / full / loose-in-chest targets and moves inside a tab, the migration of a depot of before
-- tabs, the look texts) and the engine part (depot.lua) against a mocked engine: the boxes made at a locker opening,
-- the old chest sorted into tabs (nothing deleted), every move path (inventory, ground, onto a box in the chest window,
-- into a bag inside a tab, a bag dragged in, onto the chest, into a locked tab, out of a locked tab, inside a tab over
-- its limit, a split stack, the inbox), a store purchase and an achievement opening tabs, the client message.

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
dofile("data/scripts/chaos/pact_core.lua")
local P = ChaosPactCore
local L = pc.limits.depotTabs

-- ---------------------------------------------------------------- config
eq(D.maxTabs(cfg), 17, "17 depot boxes")
local seen = {}
for i, id in ipairs(cfg.boxIds) do
	check(not seen[id], "box id once: " .. id)
	seen[id] = true
	eq(D.tabOf(cfg, id), i, "tab of box " .. id)
	check(not D.isChest(cfg, id), "a box is no chest")
end
eq(D.tabOf(cfg, 2594), nil, "the chest is no tab")
check(D.isChest(cfg, 2594), "depot chest")
eq(cfg.tabSize, 100, "100 items per tab")
check(cfg.boxSlots >= cfg.tabSize, "a box has a slot for every item it may hold")
eq(L.free, 4, "4 free tabs")
eq(L.pact, 1, "the Chaos Pact adds 1")
eq(L.free + L.pact + L.maxExtra + #cfg.achievementTabs, D.maxTabs(cfg), "free + Pact + bought + achievements = boxes")
check(#cfg.achievementTabs >= 2 and #cfg.achievementTabs <= 3, "2 or 3 achievement tabs")
local ach = dofile("data/scripts/chaos/achievements_data.lua")
local achById = {}
for _, a in ipairs(ach.list) do
	achById[a.id] = a
end
for _, id in ipairs(cfg.achievementTabs) do
	local a = achById[id]
	check(a ~= nil, "achievement " .. id .. " exists")
	has(a and a.desc, "depot tab", "achievement " .. id .. " says it opens a depot tab")
end
eq(pc.extras.depotTabs.limit, "depotTabs", "depot tabs are a Pact extra")
local keys = {}
for _, o in ipairs(cfg.store.offers) do
	eq(o.service, "pactExtra", "offer " .. o.name .. " is a Pact extra")
	eq(o.extra, "depotTabs", "offer " .. o.name .. " sells depot tabs")
	check(not keys[o.key], "unique key " .. o.key)
	keys[o.key] = true
	check(#o.description <= 84, "short description of " .. o.name)
	check((o.amount or 1) <= L.maxExtra, "offer " .. o.name .. " fits under the cap")
end
eq(#cfg.store.offers, 2, "a single tab and a pack")
local single, pack = cfg.store.offers[1], cfg.store.offers[2]
eq(pack.amount, 4, "pack of 4")
check(pack.cost < 4 * single.cost and pack.cost > 3 * single.cost, "the pack is cheaper per tab, not by much")
local stashTab
for _, o in ipairs(pc.store.storage.offers) do
	if o.extra == "stashTabs" then
		stashTab = o
	end
end
eq(single.cost, stashTab.cost, "a depot tab costs what a stash tab costs")
-- the store has the category once
local shop = dofile("data/scripts/chaos/shop_config.lua")
local cats = 0
for _, c in ipairs(shop.categories) do
	if c == cfg.store or c.name == cfg.store.name then
		cats = cats + 1
	end
end
eq(cats, 1, "store category Depot Tabs")

-- ---------------------------------------------------------------- the account's tabs
local NOW = 1800000000
local function tabsFor(state, achTabs)
	return D.tabCount(cfg, P.limit(pc, state, "depotTabs", NOW), achTabs)
end
eq(tabsFor({pactEnds = 0, extras = {}}, 0), 4, "free account: 4 tabs")
eq(tabsFor({pactEnds = NOW + 100, extras = {}}, 0), 5, "Chaos Pact: 5 tabs")
eq(tabsFor({pactEnds = NOW - 1, extras = {}}, 0), 4, "Pact ended: 4 tabs")
eq(tabsFor({pactEnds = 0, extras = {depotTabs = 5}}, 0), 9, "bought 5")
eq(tabsFor({pactEnds = 0, extras = {depotTabs = 5}}, 2), 11, "bought 5 + 2 achievements")
eq(tabsFor({pactEnds = NOW + 100, extras = {depotTabs = 9}}, 3), 17, "everything: 17")
eq(tabsFor({pactEnds = NOW + 100, extras = {depotTabs = 50}}, 9), 17, "never above the boxes")
eq(D.tabCount(cfg, -3, 0), 0, "never below 0")

-- ---------------------------------------------------------------- counting
-- a node: {id, items = {...} (a container), count}
local function node(id, items, extra)
	local n = {id = id, items = items}
	for k, v in pairs(extra or {}) do
		n[k] = v
	end
	return n
end
local function kids(n)
	return n.items
end
local bag2 = node(1987, {node(2160, nil, {count = 100})})
local bag = node(1987, {node(2400), node(2401), bag2})
local box = node(25453, {node(2390), bag})
eq(D.holding(bag2, kids), 1, "a bag with one stack holds 1")
eq(D.holding(bag, kids), 4, "a bag with two items and a bag of one holds 4")
eq(D.weight(bag, kids), 5, "the bag counts as 1 plus its contents")
eq(D.holding(box, kids), 6, "the tab counts every item, nested")
eq(D.weight(node(2400), kids), 1, "a plain item weighs 1")
eq(D.weight(node(1987, {}), kids), 1, "an empty bag weighs 1")
eq(D.weight(node(2160, nil, {count = 100}), kids), 1, "a stack weighs 1")

-- ---------------------------------------------------------------- engine-like tree for destination / locate
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
eq(decide({to = loc("tab", 2), from = loc("other"), tabs = 4, used = 10, weight = 1}), nil, "into an open tab")
eq(decide({to = loc("tab", 4), from = loc("other"), tabs = 4, used = 99, weight = 1}), nil, "the last item that fits")
local r = decide({to = loc("tab", 4), from = loc("other"), tabs = 4, used = 100, weight = 1})
eq(r and r.code, "full", "a full tab")
has(r and r.text, "100 of 100", "full text")
r = decide({to = loc("tab", 3), from = loc("other"), tabs = 4, used = 95, weight = 6})
eq(r and r.code, "full", "a bag of 5 into a tab with room for 5")
eq(decide({to = loc("tab", 3), from = loc("other"), tabs = 4, used = 95, weight = 5}), nil, "a bag of 4 fits exactly")
r = decide({to = loc("tab", 5), from = loc("other"), tabs = 4, used = 0, weight = 1})
eq(r and r.code, "locked", "tab 5 of 4 is locked")
has(r and r.text, "Store", "locked text names the store")
has(r and r.text, "take items out", "locked text: withdraw stays possible")
r = decide({to = loc("tab", 5), from = loc("tab", 2), tabs = 4, used = 0, weight = 1})
eq(r and r.code, "locked", "from an open tab into a locked one")
eq(decide({to = loc("tab", 6), from = loc("tab", 6), sameTab = true, sameChest = true, tabs = 4, used = 140, weight = 9}), nil,
	"moving inside a locked, over-full tab")
eq(decide({to = loc("tab", 2), from = loc("tab", 2), sameTab = true, sameChest = true, tabs = 4, used = 100, weight = 30}), nil,
	"a bag from inside a bag to the tab itself: same tab")
r = decide({to = loc("tab", 2), from = loc("tab", 2), sameTab = true, sameChest = true, tabs = 4, used = 100, weight = 1, split = true})
eq(r and r.code, "full", "splitting a stack in a full tab")
eq(decide({to = loc("tab", 2), from = loc("tab", 2), sameTab = true, sameChest = true, tabs = 4, used = 99, weight = 1, split = true}), nil,
	"splitting a stack with room for one more")
r = decide({to = loc("tab", 2), from = loc("tab", 3), tabs = 4, used = 98, weight = 3})
eq(r and r.code, "full", "tab to tab counts the moved bag")
r = decide({to = loc("chest"), from = loc("other"), tabs = 4})
eq(r and r.code, "chest", "nothing new loose into the chest")
has(r and r.text, "1 to 4", "chest text names the open tabs")
eq(decide({to = loc("chest"), from = loc("chest"), sameChest = true, tabs = 4}), nil, "a loose item moved around in the chest")
eq(decide({to = loc("loose"), from = loc("chest"), sameChest = true, tabs = 4}), nil, "a loose item into an old loose bag")
r = decide({to = loc("chest"), from = loc("tab", 1), sameChest = true, tabs = 4})
eq(r and r.code, "chest", "out of a tab into the chest itself")
r = decide({to = loc("loose"), from = loc("other"), tabs = 4})
eq(r and r.code, "chest", "nothing new into an old loose bag")
r = decide({to = loc("chest"), from = loc("chest", nil, "c2"), sameChest = false, tabs = 4})
eq(r and r.code, "chest", "a loose item of another depot")
eq(decide({to = loc("other"), from = loc("tab", 9), tabs = 4}), nil, "taking out of a locked tab")
eq(decide({to = loc("other"), from = loc("tab", 1), tabs = 4}), nil, "taking out of a tab")

-- ---------------------------------------------------------------- migration layout
local items = {}
for i = 1, 250 do
	items[i] = {key = i, weight = 1}
end
local moves, counts = D.layout(cfg, 2, {}, items)
eq(#moves, 250, "every item placed")
eq(counts.open, 200, "two open tabs filled first")
eq(counts.locked, 50, "the rest in locked tabs")
eq(moves[1].tab, 1, "first item in tab 1") eq(moves[101].tab, 2, "101st in tab 2") eq(moves[201].tab, 3, "201st in tab 3 (locked)")
moves, counts = D.layout(cfg, 4, {[1] = 98}, {{key = "a", weight = 5}, {key = "b", weight = 2}, {key = "big", weight = 150},
	{key = "c", weight = 1}})
eq(moves[1].tab, 2, "a bag of 5 skips the nearly full tab 1")
eq(moves[2].tab, 1, "a bag of 2 fills tab 1")
eq(moves[3].key, "c", "the 150 item bag is not placed")
eq(counts.loose, 1, "it stays loose in the chest")
eq(moves[3].tab, 2, "the next item goes on")
local full = {}
for t = 1, 17 do
	full[t] = 100
end
moves, counts = D.layout(cfg, 4, full, {{key = 1, weight = 1}})
eq(#moves, 0, "every tab full: nothing moves") eq(counts.loose, 1, "it stays loose")

-- ---------------------------------------------------------------- views and texts
local view = D.tabsView(cfg, 4, {[1] = 87, [6] = 12})
eq(#view, 17, "17 tabs in the view")
eq(view[1].used, 87, "used of tab 1") eq(view[4].locked, false, "tab 4 open") eq(view[5].locked, true, "tab 5 locked")
eq(D.description(cfg, 3, 4, 87), "87 of 100 items.", "open tab text")
has(D.description(cfg, 6, 4, 12), "withdraw-only", "locked tab with items")
has(D.description(cfg, 6, 4, 0), "Store", "empty locked tab")
has(D.openText(cfg, 4), "4 of 17", "open text") has(D.openText(cfg, 4), "Store", "open text hint")
has(D.openText(cfg, 17), "Every tab is open", "all open")
has(D.sortedText(cfg, {open = 3, locked = 1, loose = 2}), "2 item(s) did not fit", "sorted text with loose items")

-- ================================================================ engine part (depot.lua) against a mocked engine
CONTAINER_POSITION = 0xFFFF
RETURNVALUE_NOERROR, RETURNVALUE_NOTPOSSIBLE, RETURNVALUE_CONTAINERNOTENOUGHROOM = 0, 1, 2
MESSAGE_STATUS_WARNING, MESSAGE_INFO_DESCR, MESSAGE_STATUS_DEFAULT = 10, 11, 12
ITEM_ATTRIBUTE_DESCRIPTION = 2
INDEX_WHEREEVER, FLAG_NOLIMIT = -1, 1
local callbacks, timers, sent, loginEvent, lockerAction = {}, {}, {}, nil, nil
EventCallback = setmetatable({}, {__newindex = function(t, k, v) callbacks[k] = v end,
	__index = function(t, k) if k == "register" then return function() end end end})
CreatureEvent = function()
	local e = {register = function(self) loginEvent = self end}
	return e
end
Action = function()
	local a = {ids = {}}
	function a:id(i) self.ids[#self.ids + 1] = i end
	function a:register() lockerAction = self end
	return a
end
addEvent = function(fn) timers[#timers + 1] = fn end
-- what the engine does after the locker Action: the chests go into their lockers
local function openLockers(p)
	for _, c in pairs(p.chests) do
		c.parent = c.parent or {id = 2589}
	end
end
local function runTimers()
	local list = timers
	timers = {}
	for _, t in ipairs(list) do
		t()
	end
end
local STACKABLE = {[2160] = true}
local IMMOVABLE = {[29841] = true}
ItemType = function(id)
	return {getClientId = function() return id - 1000 end, isStackable = function() return STACKABLE[id] == true end,
		isMovable = function() return not IMMOVABLE[id] end}
end
local achRows = 0
db = {escapeString = function(s) return "'" .. s .. "'" end}
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.select = function(q)
	if q:find("chaos_achievements", 1, true) then
		return {{n = achRows}}
	end
	return {}
end
Chaos.send = function(player, op, action, data) sent[#sent + 1] = {op = op, action = action, data = data} end
-- the base locker script does not exist in the test folder: depot.lua registers its own locker Action
local realOpen = io.open
io.open = function(path, mode)
	if path:find("customs/actions", 1, true) or path:find("events/scripts/player.lua", 1, true) then
		return nil
	end
	return realOpen(path, mode)
end

-- engine items: containers hold `items` (front = index 0); a container adds at the front, as the engine does
local Item = {}
Item.__index = Item
Item.__eq = function(a, b) return rawequal(a, b) end
local function mk(id, opts)
	local it = setmetatable({id = id, count = 1, attrs = {}}, Item)
	for k, v in pairs(opts or {}) do
		it[k] = v
	end
	if it.items then
		for _, c in ipairs(it.items) do
			c.parent = it
		end
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
function Item:getAttribute(k) return self.attrs[k] end
function Item:setAttribute(k, v) self.attrs[k] = v end
local function detach(it)
	local p = it.parent
	if p then
		for i, c in ipairs(p.items) do
			if c == it then
				table.remove(p.items, i)
				break
			end
		end
	end
	it.parent = nil
end
function Item:addItem(id)
	if self.noAdd then
		return nil
	end
	local it = mk(id, {items = {}, cap = 100})
	table.insert(self.items, 1, it)
	it.parent = self
	return it
end
-- the engine treats an item whose chest is not in a locker yet (no parent) as removed: Item:moveTo does nothing
local function removed(it)
	local c = it
	while c.parent do
		c = c.parent
	end
	return c.id == 2594
end
function Item:moveTo(target)
	if removed(self) then
		return nil
	end
	detach(self)
	table.insert(target.items, 1, self)
	self.parent = target
	return true
end
local LOCKER_UID = 70001
getDepotId = function(uid) return uid == LOCKER_UID and 3 or false end

local function newPlayer(accountId)
	local p = {account = accountId, messages = {}, chests = {}, id = 268435456 + accountId}
	function p:getAccountId() return self.account end
	function p:getId() return self.id end
	function p:getName() return "Hero" .. self.account end
	function p:sendTextMessage(t, text) self.messages[#self.messages + 1] = {type = t, text = text} end
	function p:getDepotChest(depotId, create)
		if not self.chests[depotId] and create then
			self.chests[depotId] = mk(2594, {items = {}, cap = 150})
		end
		return self.chests[depotId]
	end
	return p
end
local online = {}
Player = function(x)
	if type(x) == "number" then
		return online[x]
	end
	return type(x) == "table" and x or nil
end
local pactLimit = 4
ChaosPact = {limit = function(player, key) return key == "depotTabs" and pactLimit or 0 end}

dofile("data/scripts/chaos/depot.lua")
local Dp = ChaosDepot
check(lockerAction ~= nil, "own locker Action without the base locker script")
eq(lockerAction and #lockerAction.ids, 4, "the four lockers")
check(callbacks.onItemMoved ~= nil, "onItemMoved callback")
check(loginEvent ~= nil, "login event")

-- an old depot: 130 loose items, a bag of 3, a bag of 150, a stuck old box (not movable)
local hero = newPlayer(1)
online[hero:getId()] = hero
local old = hero:getDepotChest(3, true)
for i = 1, 130 do
	old.items[#old.items + 1] = mk(2400 + (i % 5))
end
old.items[#old.items + 1] = mk(1987, {items = {mk(2401), mk(2402), mk(2403)}})
local hugeKids = {}
for i = 1, 150 do
	hugeKids[i] = mk(2404)
end
old.items[#old.items + 1] = mk(1988, {items = hugeKids})
old.items[#old.items + 1] = mk(29841, {items = {mk(2405)}})
for _, c in ipairs(old.items) do
	c.parent = old
end
local itemsBefore = 0
local function countAll(c)
	local n = 0
	for _, x in ipairs(c.items) do
		n = n + 1 + (x.items and countAll(x) or 0)
	end
	return n
end
itemsBefore = countAll(old)

local lockerItem = mk(2589, {uid = LOCKER_UID})
eq(lockerAction.onUse(hero, lockerItem), false, "the locker still opens")
eq(#hero.chests[3].items, 17 + 133, "boxes made at once, the old items wait for the open locker")
openLockers(hero)
runTimers()
local chest = hero.chests[3]
local boxes = {}
for _, c in ipairs(chest.items) do
	local t = D.tabOf(cfg, c.id)
	if t then
		boxes[t] = c
	end
end
local nBoxes = 0
for _ in pairs(boxes) do
	nBoxes = nBoxes + 1
end
eq(nBoxes, 17, "17 boxes made")
eq(chest.items[1].id, cfg.boxIds[1], "tab 1 comes first")
eq(chest.items[17].id, cfg.boxIds[17], "tab 17 is the 17th")
eq(countAll(chest) - 17, itemsBefore, "nothing deleted")
eq(#boxes[1].items, 100, "tab 1 full")
eq(#boxes[2].items, 31, "tab 2: the rest of the loose items and the bag of 3")
eq(D.holding(boxes[2], function(n) return n.items end), 34, "tab 2 holds 34")
local loose = {}
for _, c in ipairs(chest.items) do
	if not D.tabOf(cfg, c.id) then
		loose[#loose + 1] = c.id
	end
end
eq(#loose, 2, "the 150 bag and the stuck box stay loose")
local sortedMsg
for _, m in ipairs(hero.messages) do
	if m.text:find("sorted into tabs", 1, true) then
		sortedMsg = m.text
	end
end
has(sortedMsg, "131 item(s) in open tabs", "sorted message")
has(sortedMsg, "2 item(s) did not fit", "sorted message: loose")
eq(boxes[1].attrs[ITEM_ATTRIBUTE_DESCRIPTION], "100 of 100 items.", "tab 1 look text")
has(boxes[5].attrs[ITEM_ATTRIBUTE_DESCRIPTION], "Locked", "tab 5 look text")
local last = sent[#sent]
eq(last and last.op, 111, "client message on opcode 111") eq(last and last.action, "tabs", "tabs message")
eq(last and last.data.tabs, 4, "4 tabs") eq(last and last.data.max, 17, "of 17") eq(last and last.data.used[1], 100, "used of tab 1")
eq(last and last.data.ids[1], 25453 - 1000, "client id of tab 1") eq(last and last.data.chest[1], 2594 - 1000, "client id of the chest")
-- a second opening changes nothing
local before = #chest.items
hero.messages = {}
lockerAction.onUse(hero, lockerItem)
runTimers()
eq(#chest.items, before, "second opening: no new boxes, nothing moved")
eq(#hero.messages, 1, "second opening: only the tab line")
has(hero.messages[1] and hero.messages[1].text, "4 of 17 tabs open", "the tab line")

-- moves (toPosition: a container slot {x = 0xFFFF, y = 64 + cid, z = slot}; the inventory {x = 0xFFFF, y = slot})
local function cpos(slot) return {x = 0xFFFF, y = 64, z = slot} end
local INV = {x = 0xFFFF, y = 3, z = 0}
local GROUND = {x = 1000, y = 1000, z = 7}
local function move(item, n, fromCyl, toCyl, slot, fromPos)
	hero.messages = {}
	return Dp.onMoveItem(hero, item, n or item.count, fromPos or (fromCyl and cpos(0) or INV), cpos(slot), fromCyl, toCyl)
end
local function lastWarning()
	local m = hero.messages[#hero.messages]
	return m and m.text
end
local sword = mk(2400)
local backpack = mk(1988, {items = {sword}})
local function idx(box)
	for i, c in ipairs(chest.items) do
		if c == box then
			return i - 1
		end
	end
end
eq(move(sword, 1, backpack, boxes[3], 255), 0, "inventory into an open tab")
eq(move(sword, 1, backpack, chest, idx(boxes[3])), 0, "dropped on the tab 3 icon")
eq(move(sword, 1, nil, chest, idx(boxes[3]), GROUND), 0, "from the ground onto tab 3")
eq(move(sword, 1, backpack, chest, idx(boxes[1])), 2, "onto the full tab 1: no room")
has(lastWarning(), "Depot tab 1 is full", "full warning")
eq(move(sword, 1, backpack, boxes[5], 255), 1, "into locked tab 5")
has(lastWarning(), "tab 5 is locked", "locked warning")
eq(move(sword, 1, backpack, chest, 255), 1, "loose into the chest")
has(lastWarning(), "not loose", "chest warning")
local lockerC = mk(2589, {items = {mk(14405), mk(14404, {items = {}}), chest}, cap = 3})
chest.parent = lockerC
eq(move(sword, 1, backpack, lockerC, 2), 1, "onto the chest in the locker window")
eq(move(sword, 1, backpack, lockerC.items[2], 255), 0, "the inbox is not limited here")
chest.parent = nil
-- a bag of 5 into tab 2 (34 used): fits; into a bag inside tab 1 (full): refused
local bag5 = mk(1987, {items = {mk(2401), mk(2401), mk(2401), mk(2401)}})
eq(move(bag5, 1, backpack, boxes[2], 255), 0, "a bag of 5 into a tab with room")
local bagInTab1 = boxes[1].items[1]
bagInTab1.items = {}
eq(move(sword, 1, backpack, boxes[1], 0), 2, "into a bag inside a full tab")
-- tab 2 nearly full: 96 used, a bag of 5 does not fit, a sword does
while D.holding(boxes[2], function(n) return n.items end) < 96 do
	local x = mk(2402)
	x.parent = boxes[2]
	table.insert(boxes[2].items, x)
end
eq(move(bag5, 1, backpack, boxes[2], 255), 2, "a bag of 5 into a tab with room for 4")
has(lastWarning(), "this needs 5", "the warning counts the bag with its contents")
eq(move(sword, 1, backpack, boxes[2], 255), 0, "one item still fits")
-- inside a tab: rearranging is always fine, also in a locked or over-full tab
local inner = boxes[2].items[#boxes[2].items]
eq(move(inner, 1, boxes[2], boxes[2], 0), 0, "moved inside its tab")
local over = boxes[6]
for i = 1, 120 do
	local x = mk(2403)
	x.parent = over
	over.items[#over.items + 1] = x
end
local oBag = mk(1987, {items = {}})
oBag.parent = over
table.insert(over.items, 1, oBag)
eq(move(over.items[2], 1, over, over, 0), 0, "into a bag inside an over-full locked tab, same tab")
eq(move(over.items[3], 1, over, boxes[3], 255), 0, "from the locked tab into an open one")
eq(Dp.onMoveItem(hero, over.items[4], 1, cpos(3), INV, over, hero), 0, "out of a locked tab to the inventory")
eq(Dp.onMoveItem(hero, over.items[4], 1, cpos(3), GROUND, over, nil), 0, "out of a locked tab to the ground")
-- a split stack inside a full tab needs one free item
local stack = mk(2160, {count = 100})
stack.parent = boxes[1]
boxes[1].items[2] = stack
eq(move(stack, 40, boxes[1], boxes[1], 255), 2, "half a stack inside a full tab")
eq(move(stack, 100, boxes[1], boxes[1], 255), 0, "the whole stack inside its tab")
-- the store: a bought tab opens tab 5
pactLimit = 5
eq(move(sword, 1, backpack, boxes[5], 255), 0, "tab 5 after a purchase")
sent = {}
Dp.onLimitsChanged(hero)
eq(sent[1] and sent[1].data.tabs, 5, "the client hears of the new tab")
eq(sent[1] and sent[1].data.used, nil, "no counts without a chest")
-- an achievement tab on another character of the account
achRows = 2
lockerAction.onUse(hero, lockerItem)
runTimers()
eq(Dp.tabs(hero), 7, "two achievement tabs")
eq(move(sword, 1, backpack, boxes[7], 255), 0, "tab 7 after the achievements")
eq(move(sword, 1, backpack, boxes[8], 255), 1, "tab 8 still locked")
-- after a move into the depot the look texts and the client counts follow
sent = {}
callbacks.onItemMoved(hero, sword, 1, INV, cpos(0), backpack, boxes[3])
eq(sent[1] and sent[1].action, "tabs", "refresh after a depot move")
-- moves that have nothing to do with the depot
eq(Dp.onMoveItem(hero, sword, 1, INV, cpos(0), nil, backpack), 0, "into a backpack")
eq(Dp.onMoveItem(hero, sword, 1, INV, GROUND, nil, nil), 0, "onto the ground")
-- boxes that cannot be made (items.otb not patched): a warning, nothing breaks
local other = newPlayer(2)
other:getDepotChest(3, true).noAdd = true
lockerAction.onUse(other, lockerItem)
runTimers()
eq(#other.chests[3].items, 0, "no boxes without the items.otb change")
-- login sends the tab count
sent = {}
loginEvent.onLogin(hero)
runTimers()
check(#sent >= 1 and sent[#sent].action == "tabs", "tabs at login")

-- opcode 111 is free
eq(ChaosOpcodes.depotTabs, 111, "opcode constant")
for _, taken in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 120, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	check(taken ~= ChaosOpcodes.depotTabs, "opcode free of " .. taken)
end
for name, v in pairs(ChaosOpcodes) do
	check(name == "depotTabs" or v ~= ChaosOpcodes.depotTabs, "opcode not shared with " .. name)
end
io.open = realOpen

print(string.format("depot_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
