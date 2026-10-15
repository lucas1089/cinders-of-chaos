-- Run from the server/ folder: luajit tests/store_food_test.lua (and lua5.3; CI runs both)
-- Everfull Ration (store_food_core.lua, store_food_config.lua, store_food.lua on a mocked engine): the bite (best stock
-- food, the "You are full." cap, the exhaust, owner only, never used up), the store check (one per character, not
-- installed, owed back), the store offer (shop_config.lua: a store-bound service, not giftable, price placeholder), the
-- service registration, the delivery (backpack, inbox), death (out of the corpse, back at login).
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

dofile("data/scripts/chaos/store_food_core.lua")
local cfg = dofile("data/scripts/chaos/store_food_config.lua")
local K = ChaosStoreFoodCore

-- ---------------------------------------------------------------- config
eq(cfg.foodValue, 60, "the best stock food: dragon ham / marlin / roasted meat (60)")
eq(K.seconds(cfg), 720, "12 minutes a bite")
eq(cfg.maxSeconds, 1200, "the cap of every food")
eq(cfg.item.sourceId, 2672, "a copy of the dragon ham node")
check(cfg.item.id >= 32084 and cfg.item.id <= 32099, "server id in the free store item range after the pouches")
eq(cfg.storage.regrant >= 7100151 and cfg.storage.regrant <= 7100159, true, "storage in the free store services range")
eq(cfg.attr.storebound, "chaos_storebound", "the pouches' store-bound attribute")
eq(cfg.attr.lock, "chaos_locked", "the item lock")

-- ---------------------------------------------------------------- the bite
local r = K.bite(cfg, {ticksMs = 0, nowMs = 10000, guid = 5, owner = 5})
eq(r.ok, true, "hungry: eats")
eq(r.seconds, 720, "720 s of regeneration")
r = K.bite(cfg, {ticksMs = 479000, nowMs = 10000, guid = 5, owner = 5})
eq(r.ok, true, "479 s left + 720 = 1199: still eats")
r = K.bite(cfg, {ticksMs = 480000, nowMs = 10000, guid = 5, owner = 5})
eq(r.ok, false, "480 s left: full")
eq(r.text, "You are full.", "the stock text")
r = K.bite(cfg, {ticksMs = 0, nowMs = 10500, lastMs = 10000, guid = 5, owner = 5})
eq(r.why, "exhaust", "half a second after a bite: exhaust")
eq(r.text, nil, "silent exhaust")
eq(K.bite(cfg, {ticksMs = 0, nowMs = 11000, lastMs = 10000, guid = 5, owner = 5}).ok, true, "a second later")
eq(K.bite(cfg, {ticksMs = 0, nowMs = 1, guid = 5, owner = 6}).why, "owner", "someone else's ration")
eq(K.bite(cfg, {ticksMs = 0, nowMs = 1, guid = 5}).ok, true, "no owner on the item (GM copy): anyone")
-- how often: from empty, bites until full, then one bite every 720 s of digestion at most (like the dragon ham)
local ticks, bites = 0, 0
for _ = 1, 10 do
	local b = K.bite(cfg, {ticksMs = ticks, nowMs = bites * 2000})
	if b.ok then
		ticks, bites = ticks + b.seconds * 1000, bites + 1
	end
end
eq(bites, 1, "720 s then full: one bite from empty, as with a dragon ham (2 x 720 > 1200)")

-- ---------------------------------------------------------------- store check
eq(K.storeCheck(cfg, {installed = true}), nil, "can buy")
check(K.storeCheck(cfg, {installed = false}):find("not installed", 1, true), "not installed")
check(K.storeCheck(cfg, {installed = true, owned = true}):find("One per character", 1, true), "one per character")
check(K.storeCheck(cfg, {installed = true, owed = true}):find("next login", 1, true), "owed back")

-- ---------------------------------------------------------------- the store offer
local shop = dofile("data/scripts/chaos/shop_config.lua")
local offer
for _, c in ipairs(shop.categories) do
	for _, o in ipairs(c.offers or {}) do
		if o.service == "storeFood" then
			offer = o
			offer.category = c.name
		end
	end
end
check(offer ~= nil, "the offer is in the store")
eq(offer.kind, "service", "a service: never giftable (ChaosShopCore.GIFTABLE)")
eq(offer.category, "Convenience", "Convenience, next to the pouches")
eq(offer.icon, cfg.item.id, "its own item as the icon")
eq(offer.cost, 100, "the decided price (docs/PRICES.md, 2026-10-14)")
dofile("data/scripts/chaos/shop_core.lua")
eq(ChaosShopCore.GIFTABLE.service, nil, "services are not giftable")

-- ---------------------------------------------------------------- store_food.lua on a mocked engine
do
	MESSAGE_EVENT_ADVANCE, MESSAGE_STATUS_SMALL, TALKTYPE_MONSTER_SAY, RETURNVALUE_NOERROR = 19, 21, 36, 0
	CONDITION_REGENERATION, CONDITIONID_DEFAULT, CONST_SLOT_FIRST, CONST_SLOT_LAST = 2, -1, 1, 10
	dofile("data/scripts/chaos/chaos_constants.lua")
	local registered, actions, dbq, timers = {}, {}, {}, {}
	local installed = true
	ItemType = function(id) return {getId = function() return installed and id or 0 end} end
	local function event()
		return function(name)
			local e = {name = name}
			function e:register() registered[name or "action"] = self end
			function e:type() end
			function e:id(id) actions[id] = self end
			return e
		end
	end
	CreatureEvent, GlobalEvent = event(), event()
	Action = function() return event()(nil) end
	addEvent = function(fn) timers[#timers + 1] = fn end
	db = {query = function(q) dbq[#dbq + 1] = q return true end}
	local function mkItem(id, attrs, kids)
		local it = {attrs = attrs or {}, kids = kids, removed = false}
		function it:getId() return id end
		function it:isContainer() return kids ~= nil end
		function it:getItems() return kids or {} end
		function it:getCustomAttribute(k) return self.attrs[k] end
		function it:setCustomAttribute(k, v) self.attrs[k] = v end
		function it:remove() self.removed = true end
		return it
	end
	Game = {createItem = function(id) return mkItem(id) end, getTowns = function() return {} end}
	local ground = {}
	Tile = function() return {getItems = function() return ground end} end
	Position = function(x, y, z) return {x = x, y = y, z = z} end
	ChaosShopServices = {services = {}}
	dofile("data/scripts/chaos/store_food.lua")
	local F = ChaosStoreFood
	check(actions[cfg.item.id] ~= nil, "the eat action is registered on the item")
	check(ChaosShopServices.services.storeFood ~= nil, "the store service is registered (no edit of shop_services.lua)")

	local function mkPlayer(guid)
		local p = {guid = guid, said = {}, msgs = {}, fed = 0, storage = {}, bag = {}, inbox = {}, room = true, ticks = 0}
		function p:getGuid() return guid end
		function p:getId() return guid + 1000 end
		function p:getCondition() return self.ticks > 0 and {getTicks = function() return self.ticks end} or nil end
		function p:feed(s) self.fed = self.fed + s self.ticks = self.ticks + s * 1000 end
		function p:say(t) self.said[#self.said + 1] = t end
		function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
		function p:getSlotItem(slot) return slot == 3 and mkItem(1988, {}, self.bag) or nil end
		function p:getInbox()
			local box = mkItem(14404, {}, self.inbox)
			function box.addItemEx(_, item) table.insert(p.inbox, item) return 0 end
			return box
		end
		function p:addItemEx(item) if self.room then self.bag[#self.bag + 1] = item return 0 end return 1 end
		function p:getStorageValue(k) return self.storage[k] or -1 end
		function p:setStorageValue(k, v) self.storage[k] = v end
		function p:registerEvent() end
		function p:getPosition() return {x = 1, y = 2, z = 7} end
		return p
	end
	local svc = ChaosShopServices.services.storeFood
	local ann = mkPlayer(7)
	eq(svc.check(ann), nil, "Ann can buy")
	eq(svc.apply(ann), true, "delivered")
	local ration = ann.bag[1]
	eq(ration:getId(), cfg.item.id, "the ration in the backpack")
	eq(ration.attrs.chaos_food_owner, 7, "owner guid")
	eq(ration.attrs.chaos_storebound, 1, "store-bound")
	eq(ration.attrs.chaos_locked, 1, "locked")
	check(svc.check(ann):find("One per character", 1, true), "a second one is refused")
	-- eating: never used up
	local use = actions[cfg.item.id].onUse
	eq(use(ann, ration), true, "eat")
	eq(ann.fed, 720, "fed 720 s")
	eq(ann.said[1], "Chomp.", "the sound")
	eq(ration.removed, false, "never used up")
	use(ann, ration)
	eq(ann.fed, 720, "exhausted right after a bite (or full)")
	F.lastBite[ann:getId()] = 0
	use(ann, ration)
	eq(ann.msgs[#ann.msgs], "You are full.", "full at the food cap")
	local bob = mkPlayer(8)
	use(bob, ration)
	eq(bob.fed, 0, "someone else cannot eat it")
	eq(bob.msgs[1], "This ration belongs to someone else.", "owner text")
	-- a full backpack: the inbox
	local cid = mkPlayer(9)
	cid.room = false
	eq(svc.apply(cid), true, "delivered to the inbox")
	eq(#cid.inbox, 1, "in the inbox")
	-- death: the ration leaves the corpse, back at the next login
	ground = {mkItem(3058, {}, {mkItem(1988, {}, {ration})})}
	eq(F.afterDeath(7, {x = 1, y = 2, z = 7}), 1, "found in the corpse")
	eq(ration.removed, true, "taken out of the corpse")
	check(dbq[#dbq]:find(tostring(cfg.storage.regrant), 1, true) ~= nil, "owed back (storage written to the database)")
	local back = mkPlayer(7)
	back.storage[cfg.storage.regrant] = 1
	check(svc.check(back):find("next login", 1, true), "no second purchase while owed")
	registered.ChaosStoreFoodLogin.onLogin(back)
	eq(#back.bag, 1, "given back at login")
	eq(back.storage[cfg.storage.regrant], 0, "owed flag cleared")
	eq(F.afterDeath(8, {x = 1, y = 2, z = 7}), 0, "another character's corpse: nothing")
end

if failures > 0 then
	error(failures .. " of " .. count .. " checks failed")
end
print("store_food_test: " .. count .. " checks OK")
