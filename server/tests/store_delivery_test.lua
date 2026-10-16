-- Run from the server/ folder: luajit tests/store_delivery_test.lua (and lua5.3; mock engine API, CI runs it)
-- Store delivery to the purse (data/scripts/chaos/store_delivery.lua, store_delivery_core.lua; README "Store",
-- Delivery to the purse): the route (purse, depot inbox, backpack; never the ground), capacity, a full or missing purse,
-- stacks, attributes kept, the take-back of a failed bundle, the messages. Unlocks (outfits, mounts, wings, auras,
-- services) never reach it: tests/shop_test.lua checks that a bought outfit or wings leave the purse empty.
local checks = 0
local function eq(a, b, m) checks = checks + 1 if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function ok(v, m) checks = checks + 1 if not v then error(m or "check failed", 2) end end

RETURNVALUE_NOERROR, INDEX_WHEREEVER, FLAG_NOLIMIT, FLAG_IGNOREAUTOSTACK, MESSAGE_EVENT_ADVANCE = 0, -1, 1, 128, 19

-- ------------------------------------------------------------------ pure rules
dofile("data/scripts/chaos/store_delivery_core.lua")
local K = ChaosStoreDeliveryCore
local r, why = K.route({purse = true, purseCapOk = true, inbox = true})
eq(table.concat(r, ","), "purse,inbox,backpack", "purse first, then the depot inbox, then the backpack") eq(why, nil, "no reason")
r, why = K.route({purse = true, purseCapOk = false, inbox = true})
eq(table.concat(r, ","), "inbox,backpack", "too heavy: not the purse") eq(why, "capacity", "capacity")
r, why = K.route({purse = false, inbox = false})
eq(table.concat(r, ","), "backpack", "no purse, no inbox: the backpack") eq(why, "missing", "missing")
for _, s in ipairs({{purse = true, purseCapOk = true}, {}, {inbox = true}}) do
	local route = K.route(s)
	for _, w in ipairs(route) do ok(w ~= "ground", "never the ground") end
end
eq(table.concat(K.stacks(250, true), ","), "100,100,50", "stacks of 100")
eq(table.concat(K.stacks(3, false), ","), "1,1,1", "one by one when not stackable")
eq(#K.stacks(0, true), 0, "nothing")
eq(K.text({purse = 3}), "Delivered to your purse (the button under your equipment).", "all in the purse")
eq(K.text({inbox = 2}, "missing"), "Delivered to your depot inbox (you have no purse).", "one place, why")
eq(K.text({backpack = 1}, "full"), "Delivered to your backpack (your purse could not take it).", "the backpack")
eq(K.text({purse = 1, inbox = 2}, "capacity"),
	"Delivered: 1 to your purse, 2 to your depot inbox, 0 to your backpack (not enough capacity for the purse).", "split")
eq(K.text({}), nil, "nothing placed: no line")

-- ------------------------------------------------------------------ engine glue on a mocked engine
local STACK = {[2152] = true, [7590] = true}
function ItemType(id)
	return {getId = function() return id == 99999 and 0 or id end, isStackable = function() return STACK[id] or false end}
end
local Item = {}
Item.__index = Item
local function newItem(id, n) return setmetatable({id = id, count = n or 1, attrs = {}}, Item) end
function Item:getWeight() return 10 * self.count end
function Item:getId() return self.id end
function Item:setCustomAttribute(k, v) self.attrs[k] = v end
function Item:remove()
	local box = self.box
	if box then
		for i, x in ipairs(box.items) do if x == self then table.remove(box.items, i) break end end
	end
	self.box, self.removed = nil, true
	return true
end
local created = 0
Game = {createItem = function(id, n) created = created + 1 return newItem(id, n) end}
local lastFlags
local function box(name, opts)
	opts = opts or {}
	local b = {name = name, items = {}, refuse = opts.refuse}
	function b:addItemEx(item, index, flags)
		lastFlags = flags
		if self.refuse then return 1 end
		self.items[#self.items + 1] = item
		item.box = self
		return RETURNVALUE_NOERROR
	end
	return b
end
local function newPlayer(o)
	o = o or {}
	local p = {msgs = {}, cap = o.cap or 100000}
	p.purse = not o.noPurse and box("purse", {refuse = o.purseFull}) or nil
	p.inbox = not o.noInbox and box("inbox") or nil
	p.bag = box("backpack", {refuse = o.bagFull})
	function p:getName() return "Hero" end
	function p:getStoreInbox() return self.purse end
	function p:getInbox() return self.inbox end
	-- the base engine counts the store inbox in the inventory weight
	function p:getFreeCapacity()
		local w = 0
		for _, x in ipairs(self.purse and self.purse.items or {}) do w = w + x:getWeight() end
		return self.cap - w
	end
	function p:addItemEx(item, canDrop, index, flags)
		ok(canDrop == false, "never dropped on the map")
		return self.bag:addItemEx(item, index, flags)
	end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	return p
end
dofile("data/scripts/chaos/store_delivery.lua")
local D = ChaosStoreDelivery

-- purse present: everything goes there, stacks of 100, server placement flags (no limit, no merge)
local a = newPlayer()
local rc = D.giveItems(a, 7590, 250)
ok(rc, "delivered")
eq(#a.purse.items, 3, "three stacks in the purse") eq(a.purse.items[3].count, 50, "the last stack")
eq(lastFlags, FLAG_NOLIMIT + FLAG_IGNOREAUTOSTACK, "placed without limit and without merging into a stack")
eq(rc.counts.purse, 3, "counted") eq(#a.inbox.items + #a.bag.items, 0, "nothing elsewhere")
D.tell(a, rc)
eq(a.msgs[1], "Delivered to your purse (the button under your equipment).", "one line")
D.giveItems(a, 2400, 2)
eq(#a.purse.items, 5, "not stackable: one item each")

-- an item made by the caller keeps its attributes (store-bound pouch / ration)
local pouch = newItem(32081)
pouch:setCustomAttribute("chaos_storebound", 1)
pouch:setCustomAttribute("chaos_locked", 1)
local where = D.place(a, pouch)
eq(where, "purse", "a made item into the purse")
eq(a.purse.items[#a.purse.items].attrs.chaos_storebound, 1, "store-bound kept") eq(pouch.attrs.chaos_locked, 1, "lock kept")

-- purse full (the engine refuses): the depot inbox, told why
local b = newPlayer({purseFull = true})
rc = D.giveItems(b, 2152, 100)
eq(#b.inbox.items, 1, "purse full: the depot inbox") eq(rc.reason, "full", "reason")
D.tell(b, rc)
eq(b.msgs[1], "Delivered to your depot inbox (your purse could not take it).", "told")
-- purse full and no inbox: the backpack
local b2 = newPlayer({purseFull = true, noInbox = true})
rc = D.giveItems(b2, 2152, 5)
eq(#b2.bag.items, 1, "the backpack last")

-- purse missing: the depot inbox
local c = newPlayer({noPurse = true})
rc = D.giveItems(c, 2152, 10)
eq(#c.inbox.items, 1, "no purse: the depot inbox") eq(rc.reason, "missing", "reason")
D.tell(c, rc)
ok(c.msgs[1]:find("you have no purse", 1, true), "told: no purse")
-- an engine without getStoreInbox at all
local c2 = newPlayer()
c2.getStoreInbox = nil
eq(D.place(c2, newItem(2400)), "inbox", "no store inbox call: the depot inbox")

-- capacity: the purse counts in the inventory weight, an item too heavy goes to the weight-free depot inbox
local h = newPlayer({cap = 15})
rc = D.giveItems(h, 2400, 2)
eq(#h.purse.items, 1, "the first fits (weight 10)")
eq(#h.inbox.items, 1, "the second does not (5 left): the depot inbox") eq(rc.reason, "capacity", "reason")
D.tell(h, rc)
eq(h.msgs[1], "Delivered: 1 to your purse, 1 to your depot inbox, 0 to your backpack (not enough capacity for the purse).",
	"split line")

-- nowhere at all: nothing given, everything placed in this call taken back, never on the ground
local n = newPlayer({noPurse = true, noInbox = true})
n.bag.limit = 2
function n.bag:addItemEx(item)
	if #self.items >= self.limit then return 1 end
	self.items[#self.items + 1] = item
	item.box = self
	return 0
end
local got, err = D.giveItems(n, 7590, 500)
eq(got, nil, "refused")
ok(tostring(err):find("no room", 1, true), "error text: " .. tostring(err))
eq(#n.bag.items, 0, "the two stacks placed before were taken back")
eq(D.giveItems(n, 99999, 1), nil, "an unknown item: refused")

-- a bundle: one receipt for every part, taken back together
local z = newPlayer()
local receipt = D.newReceipt()
D.giveItems(z, 7590, 100, receipt)
D.giveItems(z, 2152, 100, receipt)
eq(#receipt.items, 2, "two parts in one receipt") eq(receipt.counts.purse, 2, "counted together")
D.takeBack(receipt)
eq(#z.purse.items, 0, "taken back out of the purse")

print("store_delivery_test: " .. checks .. " checks OK")
