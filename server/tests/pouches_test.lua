-- Run from the server/ folder: luajit tests/pouches_test.lua (and lua5.3; mock engine API, CI runs it)
-- The store pouches (data/scripts/chaos/pouches.lua, pouches_core.lua, pouches_config.lua): the routing rules per
-- pouch, the Loot Bag rules, the onDropLoot step (right pouch, owner only, full pouch -> next pouch -> backpack ->
-- corpse), never auto-sold, the store (one per character, delivery, attributes), the move / trade refusals, death
-- and the login grants (former Bottomless Loot Pouch owners, pouches lost with a dropped backpack).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, 1000 + n); return 1000 + n end
end})
RETURNVALUE_NOERROR, RETURNVALUE_NOTPOSSIBLE, CONTAINER_POSITION = 0, 1, 0xFFFF
CONST_SLOT_FIRST, CONST_SLOT_LAST, CONST_SLOT_BACKPACK = 1, 10, 3
INDEX_WHEREEVER, FLAG_NOLIMIT = -1, 1

local checks = 0
local function eq(a, b, m) checks = checks + 1 if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function ok(v, m) checks = checks + 1 if not v then error(m or "check failed", 2) end end

-- ------------------------------------------------------------------ engine mocks
local registry, callbacks, pendingCb = {}, {}, nil
local function obj(name)
	local o = {}
	function o:register() registry[name] = o end
	function o:type() end
	return o
end
function CreatureEvent(name) return obj(name) end
local actions = {}
function Action()
	local o = obj("action")
	function o:id(i) actions[i] = o end
	return o
end
EventCallback = setmetatable({}, {
	__index = function(_, k)
		if k == "register" then
			return function(_, index) callbacks[#callbacks + 1] = {name = pendingCb[1], fn = pendingCb[2], index = index or 0} end
		end
	end,
	__newindex = function(_, k, v) pendingCb = {k, v} end
})
local function callback(name, index)
	for _, c in ipairs(callbacks) do
		if c.name == name and c.index == index then return c.fn end
	end
end
local queries = {}
db = {query = function(q) queries[#queries + 1] = q; return true end}
local events = {}
function addEvent(fn, ms, ...) events[#events + 1] = {fn = fn, ms = ms, args = {...}} end
local sent = {}
json = {encode = function(t) return t end, decode = function(t) return t end}

-- item types: id -> {container, stackable, capacity}
local TYPES = {
	[1988] = {container = true, capacity = 20}, -- backpack
	[1987] = {container = true, capacity = 8}, -- bag
	[3058] = {container = true, capacity = 30}, -- a corpse
	[32081] = {container = true, capacity = 60}, [32082] = {container = true, capacity = 3}, [32083] = {container = true, capacity = 30},
	[29856] = {stackable = true}, [32256] = {stackable = true}, [2148] = {stackable = true}, [32071] = {stackable = true},
}
function ItemType(id)
	local t = TYPES[id]
	return {getId = function() return (t or id < 40000) and id or 0 end, isContainer = function() return t and t.container or false end,
		getClientId = function() return id + 1 end}
end

local nextUid = 0
local Item = {}
Item.__index = Item
Item.__eq = function(a, b) return rawequal(a, b) end
local function item(id, o)
	o = o or {}
	nextUid = nextUid + 1
	local t = TYPES[id] or {}
	local it = setmetatable({id = id, count = o.count or 1, aid = o.aid or 0, custom = o.custom or {}, uid = nextUid,
		cat = o.cat, rarity = o.rarity, unique = o.unique, items = {}, cap = t.capacity or 0, isCont = t.container,
		stack = t.stackable, weight = o.weight or 1}, Item)
	return it
end
function Item:getId() return self.id end
function Item:getCount() return self.count end
function Item:getActionId() return self.aid end
function Item:getName() return "item" .. self.id end
function Item:getType()
	local s = self
	return {isContainer = function() return s.isCont or false end, isStackable = function() return s.stack or false end,
		getName = function() return "item" .. s.id end}
end
function Item:isItem() return true end
function Item:isContainer() return self.isCont or false end
function Item:getItems() local out = {} for i, x in ipairs(self.items) do out[i] = x end return out end
function Item:getSize() return #self.items end
function Item:getCapacity() return self.cap end
function Item:getParent() return self.parent end
function Item:getCustomAttribute(k) return self.custom[k] end
function Item:setCustomAttribute(k, v) self.custom[k] = v end
function Item:getPosition() return {x = 100, y = 100, z = 7} end
function Item:getWeight() local w = self.weight * (self.count or 1) for _, x in ipairs(self.items or {}) do w = w + x:getWeight() end return w end
local function detach(it)
	local p = it.parent
	if p and p.items then
		for i, x in ipairs(p.items) do
			if rawequal(x, it) then table.remove(p.items, i) break end
		end
	end
	it.parent = nil
end
function Item:remove() detach(self); self.removed = true; return true end
local function holder(c)
	while c and not c.isPlayerMock do c = c.parent end
	return c
end
local function weightOf(it)
	local w = it.weight * (it.count or 1)
	for _, x in ipairs(it.items or {}) do w = w + weightOf(x) end
	return w
end
-- moveTo(container[, flags]): room checked when flags == 0 (as the engine with flags 0), capacity of the carrier too;
-- stackables merge into a stack with room
function Item:moveTo(target, flags)
	if not target or not target.items then return false end
	if self.stack then
		for _, x in ipairs(target.items) do
			if x.id == self.id and x.count + self.count <= 100 then
				local p = holder(target)
				if flags == 0 and p and p.freeCap < weightOf(self) then return false end
				x.count = x.count + self.count
				detach(self)
				self.removed = true
				return true
			end
		end
	end
	if flags == 0 and #target.items >= target.cap then return false end
	local p = holder(target)
	if flags == 0 and p and not holder(self) and p.freeCap < weightOf(self) then return false end
	detach(self)
	target.items[#target.items + 1] = self
	self.parent = target
	return true
end

local players = {}
local function newPlayer(guid, o)
	o = o or {}
	local p = {isPlayerMock = true, guid = guid, id = 1000 + guid, storage = {}, msgs = {}, cancels = {}, slots = {},
		freeCap = o.cap or 100000, premium = true}
	p.inbox = item(1988)
	p.inbox.cap = 1000
	function p:getGuid() return self.guid end
	function p:getId() return self.id end
	function p:isPlayer() return true end
	function p:isPremium() return self.premium end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:sendCancelMessage(t) self.cancels[#self.cancels + 1] = t end
	function p:getSlotItem(slot) return self.slots[slot] end
	function p:getInbox() return self.inbox end
	function p:getDepotChest() return self.depot end
	function p:getContainerById() return nil end
	function p:registerEvent() end
	function p:addItemEx(it)
		local bp = self.slots[CONST_SLOT_BACKPACK]
		if bp and it:moveTo(bp, 0) then return RETURNVALUE_NOERROR end
		return 2
	end
	function p:getPosition() return {x = 100, y = 100, z = 7} end
	p.inbox.parent = nil
	function p.inbox:addItemEx(it) self.items[#self.items + 1] = it; it.parent = self; return RETURNVALUE_NOERROR end
	-- the purse (the engine's store inbox, store_delivery.lua delivers there)
	p.purse = item(1988)
	p.purse.cap = 1000
	function p.purse:addItemEx(it) self.items[#self.items + 1] = it; it.parent = self; return RETURNVALUE_NOERROR end
	function p:getStoreInbox() if self.noPurse then return nil end return self.purse end
	function p:getFreeCapacity() return self.freeCap end
	players[guid] = p
	return p
end
function Player(v)
	if type(v) == "table" then return v end
	for _, p in pairs(players) do
		if p.id == v or p.guid == v then return p end
	end
	return nil
end
local created = {}
local weightlessIds = {} -- Game.setWeightlessContainer (engine src-patch 0038)
Game = {
	createItem = function(id, count) local it = item(id, {count = count}); created[#created + 1] = it; return it end,
	getTowns = function() return {} end,
	setWeightlessContainer = function(id) weightlessIds[#weightlessIds + 1] = id return true end
}
local tiles = {}
function Position(x, y, z) return {x = x, y = y, z = z} end
function Tile(pos) return tiles[pos.x .. ":" .. pos.y .. ":" .. pos.z] end

-- the rest of the Chaos world the glue reads
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.send = function(player, opcode, action, data) sent[#sent + 1] = {player = player, opcode = opcode, action = action, data = data} end
Chaos.decode = function(b) return b end
ChaosGems = {isGem = function(id) return id >= 32001 and id <= 32035 end}
ChaosLootFilter = {itemInfo = function(it) return {category = it.cat or "other", rarity = it.rarity or 0, unique = it.unique or false} end,
	RARITY = {{name = "Common"}, {name = "Uncommon"}}}
local finalized = 0
ChaosLoot = {finalizeRarity = function(it) finalized = finalized + 1; return it end}

dofile("data/scripts/chaos/pouches.lua")
local PO, P, cfg = ChaosPouches, ChaosPouchesCore, ChaosPouchesConfig
local ST = cfg.storage

-- the Loot Bag (2026-10-13): bottomless (255 slots, the protocol's most), weightless (src-patch 0038), every rule on
eq(cfg.kinds.loot.title, "Loot Bag", "the Loot Bag") eq(cfg.kinds.loot.capacity, 255, "the most slots a container can have")
eq(cfg.kinds.loot.weightless, true, "weightless")
eq(#weightlessIds >= 1 and weightlessIds[1], 32081, "registered as a weightless container at load")
PO.registerWeightless()
eq(#weightlessIds, 1, "registered once")
eq(cfg.kinds.orbs.weightless, nil, "the other pouches keep their weight")

-- ------------------------------------------------------------------ config sanity
eq(ChaosOpcodes.pouches, 226, "opcode")
eq(cfg.storage.lootRules, 7100107, "rules storage") eq(cfg.legacyUnlock, Chaos.storage.shopLootPouch, "legacy unlock key kept")
for _, key in pairs(cfg.storage) do
	ok(key >= 7100100 and key <= 7100159, "pouch storages in the store services range")
	for name, v in pairs(Chaos.storage) do
		ok(v ~= key, "pouch storage " .. key .. " collides with Chaos.storage." .. name)
	end
end
local seenIds = {}
for kind, k in pairs(cfg.kinds) do
	ok(k.id >= 32081 and k.id <= 32083 and not seenIds[k.id], "pouch ids 32081..32083, distinct: " .. kind)
	seenIds[k.id] = true
	ok(k.capacity >= 30 and k.capacity <= 255, "capacity fits the protocol byte")
	ok(k.description:find("^Store item: cannot be traded"), "description says store item: " .. kind)
end

-- ------------------------------------------------------------------ rules (pure)
local d = P.defaults(cfg)
eq(d.list, true, "default: autoloot list") eq(d.gold, true, "default: gold") eq(d.gear, true, "default: all gear (the Loot Bag takes everything)")
eq(d.other, true, "default: everything else") eq(d.supplies, true, "default: supplies") eq(d.gems, true, "default: gems") eq(d.minRarity, 1, "default: any rarity")
local packed = P.packRules({list = false, gold = false, uniques = false, gear = true, minRarity = 4, supplies = true})
local r = P.unpackRules(cfg, packed)
eq(r.list, false, "packed list off") eq(r.gear, true, "packed gear") eq(r.minRarity, 4, "packed rarity (Rare)") eq(r.supplies, true, "supplies")
eq(P.unpackRules(cfg, -1).list, true, "unset = defaults")
local none = P.unpackRules(cfg, P.packRules({minRarity = 1}))
eq(none.list, false, "everything off is kept (not the defaults)")
eq(P.sanitizeRules(cfg, {gear = true, minRarity = 99}).minRarity, 1, "an id out of range: any rarity")
eq(P.sanitizeRules(cfg, {gear = true, minRarity = 12}).minRarity, 10, "an old Celestial is Divine")
eq(P.unpackRules(cfg, P.packRules({minRarity = 7})).minRarity, 5, "an old Mythic is saved as Legendary")
eq(P.sanitizeRules(cfg, {list = "yes"}).list, false, "only true / 1 switch a rule on")
eq(P.sanitizeRules(cfg, "junk").list, true, "junk input = defaults")
eq(d.overflow, true, "default: the Loot Bag takes the specialist pouches' overflow")
eq(P.unpackRules(cfg, P.packRules({list = true, overflow = false})).overflow, false, "overflow off is kept")
eq(P.unpackRules(cfg, P.packRules({list = true, overflow = true})).overflow, true, "overflow on is kept")
eq(P.unpackRules(cfg, 32768 + 1 + 5 * 256).overflow, true, "rules saved before the overflow rule: overflow on")
eq(P.sanitizeRules(cfg, {list = true}).overflow, true, "overflow missing from client input: the default")
ok(P.packRules({list = true, gold = true, uniques = true, gear = true, supplies = true, gems = true, other = true,
	minRarity = 15}) < 2 ^ 31, "packed rules fit a storage value")

local sets = P.sets(cfg, {12345})
local dNoSpill = P.sanitizeRules(cfg, {list = true, gold = true, uniques = true, overflow = false, gear = false, supplies = false,
	gems = false, other = false, minRarity = 5})
-- the kinds that collect the item (overflow off unless the rules say so)
local function route(info, rules) return table.concat(P.route(info, rules or dNoSpill, sets, cfg), ",") end
eq(route({id = 29856, category = "currency"}), "orbs", "orb -> Orbs Pouch")
eq(route({id = 12345, category = "currency"}), "orbs", "loot_config currency entry -> Orbs Pouch")
eq(route({id = 32051}), "orbs", "rune shard -> Orbs Pouch")
eq(route({id = 32010, gem = true}), "orbs", "gem -> Orbs Pouch")
eq(route({id = 10155, actionId = 47401}), "keys", "Rift Key -> Rift Key Pouch")
eq(route({id = 10155, actionId = 0}), "", "the stock item behind the key is not a key")
eq(route({id = 32071}), "keys", "omen fragment -> Rift Key Pouch")
eq(route({id = 32072}), "keys", "Omen Key -> Rift Key Pouch")
eq(route({id = 29856, onList = true}), "orbs", "orb on the autoloot list, overflow off: the Orbs Pouch only")
eq(route({id = 29856, onList = true}, d), "orbs,loot", "orb on the autoloot list: Orbs Pouch, then the Loot Bag (overflow)")
eq(route({id = 29856}, d), "orbs,loot", "any orb: Orbs Pouch first, the Loot Bag only as overflow")
eq(route({id = 2148, category = "currency"}), "loot", "gold -> Loot Bag (default)")
eq(route({id = 2400, category = "other", onList = true}), "loot", "autoloot list item -> Loot Bag")
eq(route({id = 2400, category = "other"}), "", "other loot: off when its rule is off")
eq(route({id = 2400, category = "other"}, d), "loot", "other loot: the Loot Bag by default")
eq(route({id = 2400, category = "equipment", rarity = 0}, d), "loot", "plain gear: the Loot Bag by default")
eq(route({id = 2400}, d), "loot", "an item without a category: the Loot Bag (everything else)")
eq(route({id = 2400, category = "equipment", rarity = 9}), "", "gear: off when its rule is off")
eq(route({id = 2400, category = "equipment", unique = true}), "loot", "unique -> Loot Bag (default)")
local gearRules = P.sanitizeRules(cfg, {gear = true, minRarity = 5, overflow = false})
eq(route({id = 2400, category = "equipment", rarity = 5}, gearRules), "loot", "gear at the minimum rarity")
eq(route({id = 2400, category = "equipment", rarity = 4}, gearRules), "", "gear below the minimum")
eq(route({id = 1988, container = true, onList = true}), "", "a container is never collected")
eq(route({id = 32082, pouch = true, container = true, onList = true}), "", "a pouch is never collected")

-- priority (pure): the Orbs Pouch and the Rift Key Pouch always first, the Loot Bag only as their overflow
local all = {loot = true, orbs = true, keys = true}
local function plan(info, rules, carried)
	local kinds, spill = P.plan(info, rules or d, sets, cfg, carried or all)
	return table.concat(kinds, ",") .. (spill and (" <" .. spill) or "")
end
eq(cfg.priority[1], "orbs", "Orbs Pouch first") eq(cfg.priority[2], "keys", "then the Rift Key Pouch")
eq(cfg.order[#cfg.order], "loot", "the Loot Bag last")
local gemsRules = P.sanitizeRules(cfg, {gems = true, list = true})
eq(plan({id = 32010, gem = true}, gemsRules), "orbs,loot <orbs", "gem with the Loot Bag gems rule: Orbs Pouch first")
eq(plan({id = 32010, gem = true, onList = true}, gemsRules), "orbs,loot <orbs", "a gem on the autoloot list: Orbs Pouch first")
eq(plan({id = 10155, actionId = 47401, onList = true}), "keys,loot <keys", "a listed Rift Key: Rift Key Pouch first")
local noSpill = P.sanitizeRules(cfg, {gems = true, list = true, overflow = false})
eq(plan({id = 32010, gem = true, onList = true}, noSpill), "orbs", "overflow off: never the Loot Bag, even if its rules match")
eq(plan({id = 32071}, noSpill), "keys", "overflow off: omen fragment only to the Rift Key Pouch")
eq(plan({id = 32010, gem = true}, d, {orbs = true}), "orbs", "no Loot Bag carried: Orbs Pouch only")
eq(plan({id = 32010, gem = true}, gemsRules, {loot = true}), "loot", "no Orbs Pouch: the Loot Bag gems rule decides")
eq(plan({id = 32010, gem = true}, d, {loot = true}), "loot", "no Orbs Pouch: the Loot Bag takes the gem (gems on by default)")
eq(plan({id = 29856, onList = true}, d, {loot = true, keys = true}), "loot", "no Orbs Pouch: a listed orb to the Loot Bag")
eq(plan({id = 29856}, d, {loot = true, keys = true}), "", "no Orbs Pouch: an unlisted orb is not the Loot Bag's")
eq(plan({id = 2148, category = "currency"}), "loot", "gold: the Loot Bag")
eq(plan({id = 2148, category = "currency"}, d, {orbs = true, keys = true}), "", "gold without a Loot Bag: nothing")
eq(plan({id = 32071}, d, {loot = true, orbs = true}), "", "no Rift Key Pouch: omen items are not the Loot Bag's")

-- move rules (pure)
eq(P.moveRefusal({holdsPouch = false, toGround = true}), nil, "other items: no rule")
ok(P.moveRefusal({holdsPouch = true, toGround = true}):find("cannot be dropped"), "ground / mailbox / trash refused")
eq(P.moveRefusal({holdsPouch = true, chain = {"item", "self"}}), nil, "into a bag in the own backpack")
eq(P.moveRefusal({holdsPouch = true, chain = {"self"}}), nil, "into an own slot")
eq(P.moveRefusal({holdsPouch = true, chain = {"item", "depot", "tile"}}), nil, "into the depot")
ok(P.moveRefusal({holdsPouch = true, chain = {"item", "tile"}}), "a bag on the ground (house, corpse) refused")
ok(P.moveRefusal({holdsPouch = true, chain = {"item", "player"}}), "another player's container refused")
ok(P.moveRefusal({holdsPouch = true, chain = {"pouch", "self"}}):find("another pouch"), "pouch into pouch refused")
ok(P.moveRefusal({holdsPouch = true, chain = {"item", "pouch", "self"}}), "a bag holding a pouch into a pouch refused")

-- loot line (owner 2026-10-16: list what was looted, not the pouch)
local function e(id, name, count, o)
	o = o or {}
	return {id = id, name = name, plural = o.plural, count = count or 1, rarity = o.rarity or 0, rarityName = o.rn,
		unique = o.unique or false}
end
eq(P.summary(cfg, {}, 0, 0), nil, "nothing happened: no line")
eq(P.summary(cfg, {e(2148, "gold coin", 10, {plural = "gold coins"}), e(5877, "dragon scale", 1, {plural = "dragon scales"}),
	e(5877, "dragon scale", 1, {plural = "dragon scales"}), e(2475, "wyrmscale helmet")}, 0, 0),
	"Looted: 10 gold coins, 2 dragon scales, wyrmscale helmet.", "grouped by item, counts, no pouch name")
eq(P.lootList({e(2475, "helmet", 1, {rarity = 1, rn = "Common"}), e(2475, "helmet", 1, {rarity = 3, rn = "Rare"}),
	e(2400, "sword", 1, {unique = true}), e(2148, "gold coin", 5)}),
	"{sword}, {[Rare] helmet}, [Common] helmet, 5 gold coin", "uniques then rarity first, flagged from Rare; same id other rarity apart; no plural -> name")
local many = {}
for i = 1, 8 do many[i] = e(3000 + i, "thing" .. i) end
eq(P.lootList(many), "thing1, thing2, thing3, thing4, thing5 and 3 more", "cap of 5 entries plus and N more")
eq(P.lootList(many, {maxEntries = 8}), "thing1, thing2, thing3, thing4, thing5, thing6, thing7, thing8", "cap from the config")
eq(P.lootList({}), nil, "empty list")
eq(cfg.lootLine.maxEntries, 5, "config cap")
ok(P.summary(cfg, {}, 2, 1, {loot = true}):find("^Looted: nothing %(Loot Bag is full; 2 to your backpack; 1 left"), "full / backpack / corpse")
eq(P.summary(cfg, {e(29856, "orb", 2, {plural = "orbs"})}, 0, 0, {orbs = true}, 2),
	"Looted: 2 orbs (Orbs Pouch is full; 2 to your Loot Bag).", "overflow told in the short notes")

-- ------------------------------------------------------------------ engine glue: items
local hero = newPlayer(7)
local bp = item(1988)
bp.parent = hero
hero.slots[CONST_SLOT_BACKPACK] = bp
eq(PO.storeCheck(hero, "orbs"), nil, "orbs pouch can be bought")
eq(PO.storeGive(hero, "orbs"), true, "orbs pouch delivered")
-- owner 2026-10-16: store items go to the purse (store_delivery.lua)
local orbsPouch = hero.purse.items[1]
eq(orbsPouch.id, 32082, "orbs pouch in the purse")
eq(#bp.items, 0, "not in the backpack")
eq(orbsPouch.custom.chaos_pouch_owner, 7, "owner") eq(orbsPouch.custom.chaos_storebound, 1, "store-bound kept in the purse")
eq(orbsPouch.custom.chaos_locked, 2, "item lock (never sold to NPCs, no stock market, no trash), bound: not drawn grey")
eq(P.bindLock(cfg), 2, "bindLock 2: the client greys only 1 (a player's own lock)")
eq(P.needsRebind(cfg, 1), true, "an old pouch with 1 is rebound") eq(P.needsRebind(cfg, nil), true, "no lock: rebound")
eq(P.needsRebind(cfg, 2), false, "2 stays") eq(P.needsRebind(cfg, "2"), false, "a string 2 stays")
ok(hero.msgs[#hero.msgs]:find("purse") and hero.msgs[#hero.msgs]:find("from now on, there or in your backpack"),
	"player told it is in the purse and collects there")
eq(PO.carried(hero).orbs, orbsPouch, "a pouch in the purse counts as carried (collects without moving it)")
ok(PO.storeCheck(hero, "orbs"):find("already have"), "a second Orbs Pouch is refused (one in the purse counts)")
eq(PO.isPouch(orbsPouch), true, "isPouch (the player market's check)")
eq(PO.isPouch(item(1987, {custom = {chaos_storebound = 1}})), true, "anything store-bound counts")
eq(PO.isPouch(item(1987)), false, "a bag is not a pouch")
ok(PO.storeCheck(hero, "nope"), "unknown kind refused")
-- too heavy to carry: the purse counts in the inventory weight, so the depot inbox
hero.freeCap = 0
eq(PO.storeGive(hero, "keys"), true, "keys pouch delivered")
local keysPouch = hero.inbox.items[1]
eq(keysPouch.id, 32083, "no capacity: the depot inbox")
ok(hero.msgs[#hero.msgs]:find("depot inbox") and hero.msgs[#hero.msgs]:find("Move it to your backpack"),
	"told: depot inbox, move it to collect")
eq(PO.carried(hero).keys, nil, "a pouch in the depot inbox does not collect")
hero.freeCap = 100000
-- no purse: the depot inbox, as before
hero.noPurse = true
eq(PO.storeGive(hero, "loot"), true, "loot pouch delivered")
eq(hero.inbox.items[2].id, 32081, "no purse: into the depot inbox")
ok(PO.storeCheck(hero, "loot"):find("already have"), "a pouch in the inbox counts as owned")
hero.noPurse = nil
-- the player takes them out into the backpack
local lootPouch = table.remove(hero.inbox.items, 2)
table.remove(hero.inbox.items, 1)
table.remove(hero.purse.items, 1)
for _, pz in ipairs({orbsPouch, keysPouch, lootPouch}) do pz.parent = nil; pz:moveTo(bp, 0) end
eq(#bp.items, 3, "three pouches in the backpack")
local store, collects = PO.tooltipLines(orbsPouch)
eq(store, "Store item: cannot be traded", "tooltip store line") ok(collects:find("orbs"), "tooltip collects line")
eq(PO.tooltipLines(item(1987)), nil, "no tooltip lines on a bag")
eq(PO.neverSell(29856), true, "orbs never auto-sold") eq(PO.neverSell(32071), true, "omen fragments never auto-sold")
eq(PO.neverSell(32010), true, "gems never auto-sold") eq(PO.neverSell(2400), false, "other loot may be sold")
eq(PO.neverSell(10155, item(10155, {aid = 0})), false, "the plain stock item behind the key may be sold")
eq(PO.neverSell(10155, item(10155, {aid = 47401})), true, "a Rift Key is never sold")

-- ------------------------------------------------------------------ onDropLoot step
local drop = callback("onDropLoot", cfg.dropIndex)
ok(drop, "onDropLoot registered at " .. cfg.dropIndex)
ok(cfg.dropIndex > 2 and cfg.dropIndex < 3, "after the auto seller (2), before the base autoloot (3)")
local function corpse(ownerId, items)
	local c = item(3058)
	c.cap = 100
	for _, it in ipairs(items) do it.parent = nil; it:moveTo(c, 1) end
	c.getCorpseOwner = function() return ownerId end
	return c
end
hero.storage[Chaos.storage.autolootBase + 1] = 2400
-- the rules of before the Loot Bag (2026-10-13) for these checks; the defaults (everything) are checked further down
local oldRules = {list = true, gold = true, uniques = true, gear = false, minRarity = 5, supplies = false, gems = false,
	other = false, overflow = true}
hero.storage[ST.lootRules] = P.packRules(oldRules)
local orb, key, frag, gem, coins, listed, junk, rare = item(29856, {count = 2}), item(10155, {aid = 47401, custom = {rift_tier = 4}}),
	item(32071, {count = 3}), item(32010), item(2148, {count = 50, cat = "currency"}), item(2400, {cat = "equipment", rarity = 2}),
	item(2401), item(2402, {cat = "equipment", rarity = 9})
local c1 = corpse(hero.id, {orb, key, frag, gem, coins, listed, junk, rare})
drop(nil, c1)
eq(orbsPouch.items[1].id, 29856, "orb -> Orbs Pouch") eq(orbsPouch.items[1].count, 2, "stack kept")
eq(orbsPouch.items[2].id, 32010, "gem -> Orbs Pouch")
eq(keysPouch.items[1].id, 10155, "Rift Key -> Rift Key Pouch")
eq(keysPouch.items[1].custom.rift_tier, 4, "the key keeps its attributes")
eq(keysPouch.items[2].id, 32071, "omen fragments -> Rift Key Pouch")
eq(lootPouch.items[1].id, 2148, "gold -> Loot Bag")
eq(lootPouch.items[2].id, 2400, "autoloot-list gear -> Loot Bag")
eq(finalized, 1, "gear rolled on the way out (ChaosLoot.finalizeRarity)")
eq(junk.parent, c1, "other loot stays in the corpse") eq(rare.parent, c1, "gear without a rule stays")
eq(hero.msgs[#hero.msgs], "Looted: [Uncommon] item2400, 2 item29856, item10155, 3 item32071, item32010 and 1 more.",
	"one loot line per kill: the items, rarity gear first, capped")
-- the Loot Bag's defaults: all the loot (other loot, plain and rare gear) goes into it
hero.storage[ST.lootRules] = -1
local junk2, rare2, plain2 = item(2401), item(2402, {cat = "equipment", rarity = 9}), item(2403, {cat = "equipment"})
local cAll = corpse(hero.id, {junk2, rare2, plain2})
drop(nil, cAll)
eq(junk2.parent, lootPouch, "defaults: other loot -> Loot Bag") eq(rare2.parent, lootPouch, "defaults: rare gear -> Loot Bag")
eq(plain2.parent, lootPouch, "defaults: plain gear -> Loot Bag")
-- the stow and the sort of one kill are one held batch of container updates (engine patch 0054, Chaos.containerBatch)
do
	local begins, ends, depth, maxDepth = 0, 0, 0, 0
	hero.beginContainerBatch = function() begins = begins + 1 depth = depth + 1 maxDepth = math.max(maxDepth, depth) return true end
	hero.endContainerBatch = function() ends = ends + 1 depth = depth - 1 return true end
	local a, b = item(2401), item(2403, {cat = "equipment"})
	drop(nil, corpse(hero.id, {a, b}))
	eq(a.parent, lootPouch, "batched kill: still stowed")
	-- the batch of the kill is closed; the burst's outer batch stays held for the window (Chaos.containerBurst)
	eq(begins, 2, "burst batch + kill batch") eq(ends, 1, "the kill's batch is closed") eq(depth, 1, "the burst batch is still held")
	-- three more kills in the same tick: no second burst, one release for all of them
	local more = {}
	for i = 1, 3 do more[i] = item(2401) drop(nil, corpse(hero.id, {more[i]})) end
	eq(begins, 5, "each kill batches, the burst is not begun again") eq(ends, 4, "each kill's batch closed") eq(depth, 1, "still one held batch")
	local timers = 0
	for _, e in ipairs(events) do
		if e.ms == Chaos.burstWindowMs then timers = timers + 1 end
	end
	eq(timers, 1, "one release timer for the whole burst")
	for _, e in ipairs(events) do
		if e.ms == Chaos.burstWindowMs then e.fn() e.ms = -1 end
	end
	eq(ends, 5, "the timer releases the burst") eq(depth, 0, "balanced after the window")
	-- the next burst starts a new hold
	drop(nil, corpse(hero.id, {item(2401)}))
	eq(depth, 1, "a later kill holds again")
	for _, e in ipairs(events) do
		if e.ms == Chaos.burstWindowMs then e.fn() e.ms = -1 end
	end
	eq(depth, 0, "and releases again")
	for _, m in ipairs(more) do
		for i = #lootPouch.items, 1, -1 do if lootPouch.items[i] == m then table.remove(lootPouch.items, i) end end
		m.parent = nil
	end
	for _, it in ipairs({a, b}) do
		for i = #lootPouch.items, 1, -1 do if lootPouch.items[i] == it then table.remove(lootPouch.items, i) end end
		it.parent = nil
	end
	hero.beginContainerBatch, hero.endContainerBatch = nil, nil
end
for _, it in ipairs({junk2, rare2, plain2}) do
	for i = #lootPouch.items, 1, -1 do if lootPouch.items[i] == it then table.remove(lootPouch.items, i) end end
	it.parent = nil
end
hero.storage[ST.lootRules] = P.packRules(oldRules)

-- orbs merge into the stack
drop(nil, corpse(hero.id, {item(29856, {count = 5})}))
eq(orbsPouch.items[1].count, 7, "orbs stack in the pouch")

-- the Orbs Pouch (3 slots here) is full and the Loot Bag overflow rule is off: the orb goes to the backpack
orbsPouch.items[3] = item(32256, {count = 100}); orbsPouch.items[3].parent = orbsPouch
hero.storage[ST.lootRules] = P.packRules(P.sanitizeRules(cfg, {overflow = false}))
local whet, other = item(32253), item(32254)
drop(nil, corpse(hero.id, {whet}))
eq(whet.parent, bp, "full Orbs Pouch: the orb goes to the backpack")
ok(hero.msgs[#hero.msgs]:find("Orbs Pouch is full") and hero.msgs[#hero.msgs]:find("1 to your backpack"), "player told")
drop(nil, corpse(hero.id, {other}))
eq(other.parent, bp, "again to the backpack")
ok(not hero.msgs[#hero.msgs]:find("is full"), "the 'is full' note at most once a minute")
-- backpack full too: stays in the corpse
for i = #bp.items + 1, bp.cap do bp.items[i] = item(2401); bp.items[i].parent = bp end
local last = item(32252)
local c3 = corpse(hero.id, {last})
drop(nil, c3)
eq(last.parent, c3, "no room anywhere: stays in the corpse")
ok(hero.msgs[#hero.msgs]:find("left in the corpse"), "player told")
for i = #bp.items, 4, -1 do table.remove(bp.items, i) end

-- overflow off: an orb on the autoloot list, a gem with the gems rule: never the Loot Bag while the Orbs Pouch is full
hero.storage[Chaos.storage.autolootBase + 2] = 32251
hero.storage[ST.lootRules] = P.packRules(P.sanitizeRules(cfg, {list = true, gems = true, overflow = false}))
local listedOrb, fullGem = item(32251), item(32011)
drop(nil, corpse(hero.id, {listedOrb, fullGem}))
eq(listedOrb.parent, bp, "overflow off: a listed orb goes to the backpack, not the Loot Bag")
eq(fullGem.parent, bp, "overflow off: a gem goes to the backpack despite the gems rule")
for i = #bp.items, 4, -1 do table.remove(bp.items, i) end
-- overflow on (the default): the Loot Bag takes what the full Orbs Pouch passes on
hero.storage[ST.lootRules] = nil
local spillOrb, spillGem = item(32251), item(32012)
drop(nil, corpse(hero.id, {spillOrb, spillGem}))
eq(spillOrb.parent, lootPouch, "full Orbs Pouch: the orb overflows into the Loot Bag")
eq(spillGem.parent, lootPouch, "full Orbs Pouch: the gem overflows into the Loot Bag")
ok(hero.msgs[#hero.msgs]:find("2 to your Loot Bag"), "overflow told: " .. hero.msgs[#hero.msgs])
-- room again in the Orbs Pouch: a gem goes there first even though the Loot Bag gems rule is on
hero.storage[ST.lootRules] = P.packRules(P.sanitizeRules(cfg, {list = true, gold = true, gems = true}))
local o3slot = table.remove(orbsPouch.items, 3); o3slot.parent = nil
local firstGem = item(32013)
drop(nil, corpse(hero.id, {firstGem}))
eq(firstGem.parent, orbsPouch, "Orbs Pouch before the Loot Bag gems rule")
table.remove(orbsPouch.items, 3); firstGem.parent = nil
orbsPouch.items[3] = o3slot; o3slot.parent = orbsPouch
hero.storage[ST.lootRules] = nil

-- capacity: the engine refuses (too heavy) -> backpack refuses too -> corpse
hero.freeCap = 0
local heavy = item(32071, {count = 1})
local c4 = corpse(hero.id, {heavy})
drop(nil, c4)
eq(heavy.parent, c4, "no capacity: stays in the corpse")
hero.freeCap = 100000

-- owner only: another character's corpse, another character's pouch
local other2 = newPlayer(8)
local bp2 = item(1988); bp2.parent = other2; other2.slots[CONST_SLOT_BACKPACK] = bp2
local stolen = item(32082, {custom = {chaos_pouch_owner = 7}}) -- hero's pouch (cannot happen; tested anyway)
stolen:moveTo(bp2, 0)
local o2 = item(29856)
local c5 = corpse(other2.id, {o2})
drop(nil, c5)
eq(o2.parent, c5, "a pouch owned by someone else does not collect")
eq(#stolen.items, 0, "nothing went into it")
local o3 = item(29856)
local c6 = corpse(0, {o3})
drop(nil, c6)
eq(o3.parent, c6, "no corpse owner: nothing")
-- the pouch must be carried: in the depot it does nothing
local depotOnly = newPlayer(9)
local bp3 = item(1988); bp3.parent = depotOnly; depotOnly.slots[CONST_SLOT_BACKPACK] = bp3
local o4 = item(29856)
local c7 = corpse(depotOnly.id, {o4})
drop(nil, c7)
eq(o4.parent, c7, "no carried pouch: nothing")

-- Loot Bag rules from the window
local set = registry.ChaosPouchesExtended
set.onExtendedOpcode(hero, 226, {action = "set", data = {rules = {list = false, gold = false, gear = true, minRarity = 9}}})
eq(PO.rulesOf(hero).gear, true, "rules saved") eq(PO.rulesOf(hero).list, false, "list off")
eq(sent[#sent].action, "settings", "settings sent back")
local rare2, listed2 = item(2402, {cat = "equipment", rarity = 9}), item(2400, {cat = "equipment"})
local c8 = corpse(hero.id, {rare2, listed2})
drop(nil, c8)
eq(rare2.parent, lootPouch, "gear rule: rarity 9 taken") eq(listed2.parent, c8, "list rule off: left for the base autoloot")
set.onExtendedOpcode(hero, 226, {action = "open"})
eq(sent[#sent].data.open, true, "open") eq(sent[#sent].data.owned.loot, true, "owned kinds sent")
eq(sent[#sent].data.ids.loot, 32082, "client id of the Loot Bag (mock: id + 1)")
-- the Auto Seller window's actions go to autosell.lua (ChaosAutoSell.handleAction) and come back as `autoseller`
for _, a in ipairs({"as_open", "as_sync", "sell", "asrar", "aslist", "aspause", "asevery"}) do
	eq(PO.AUTOSELL_ACTIONS[a], true, "Auto Seller action routed: " .. a)
end
do
	local saved = ChaosAutoSell
	local seen
	ChaosAutoSell = {handleAction = function(p, action, data) seen = {action, data} return {unlocked = true} end}
	local n0 = #sent
	set.onExtendedOpcode(hero, 226, {action = "asrar", data = {tier = "rare", on = true}})
	eq(seen and seen[1], "asrar", "handed to autosell.lua") eq(seen and seen[2].tier, "rare", "with its data")
	eq(#sent, n0 + 1, "one answer") eq(sent[#sent].action, "autoseller", "the window state")
	ChaosAutoSell = {handleAction = function() return nil end}
	set.onExtendedOpcode(hero, 226, {action = "aspause", data = {on = true}})
	eq(#sent, n0 + 1, "no state: nothing sent")
	ChaosAutoSell = saved
end

-- click-to-loot of the loot channel
local clicked = item(29856, {count = 1})
corpse(hero.id, {clicked})
eq(PO.stow(hero, clicked), true, "stow: a clicked orb goes to the Orbs Pouch (merged)")
eq(clicked.parent == orbsPouch or orbsPouch.items[1].count == 8, true, "into the Orbs Pouch")
-- click-to-loot follows the same priority: a clicked gem with the Loot Bag gems rule on goes to the Orbs Pouch;
-- with the Orbs Pouch full and overflow off it is not stowed (lootfilter.lua then tries the backpack)
hero.storage[ST.lootRules] = P.packRules(P.sanitizeRules(cfg, {list = true, gems = true, overflow = false}))
local clickedGem = item(32014)
corpse(hero.id, {clickedGem})
eq(PO.stow(hero, clickedGem), false, "stow: Orbs Pouch full, overflow off: not into the Loot Bag")
eq(clickedGem.parent == lootPouch, false, "the Loot Bag did not take it")
hero.storage[ST.lootRules] = nil
eq(PO.stow(hero, clickedGem), true, "stow: overflow on (default): the Loot Bag takes it")
eq(clickedGem.parent, lootPouch, "into the Loot Bag as overflow")

-- ------------------------------------------------------------------ Loot Bag order (rarest first)
local function sortedRanks(r, limit)
	local order = P.sortPlan(r, limit)
	-- apply: each listed index moves to the front, in order
	local cur = {}
	for i = 1, #r do cur[i] = i end
	for _, idx in ipairs(order) do
		for pos, v in ipairs(cur) do
			if v == idx then table.remove(cur, pos) break end
		end
		table.insert(cur, 1, idx)
	end
	local out = {}
	for i, v in ipairs(cur) do out[i] = r[v] end
	return out, order
end
eq(P.rank(0, false), 0, "rank: plain") eq(P.rank(5, false), 5, "rank: rarity") eq(P.rank(2, true), 102, "rank: uniques above rarity")
eq(#P.sortPlan({}), 0, "sort: empty bag") eq(#P.sortPlan({3}), 0, "sort: one item")
eq(#P.sortPlan({9, 5, 5, 0, 0}), 0, "sort: already sorted: nothing moves")
local out, order = sortedRanks({0, 0, 5, 9, 0, 2})
eq(table.concat(out, ","), "9,5,2,0,0,0", "sort: rarest first")
eq(#order, 3, "sort: only the items ahead of the sorted tail move")
out, order = sortedRanks({0, 9, 5, 5, 0, 0})
eq(table.concat(out, ","), "9,5,5,0,0,0", "sort: a plain item in front of the sorted rest moves nothing but the rarer ones")
eq(#order, 3, "sort: the 3 rarer items move, not the 3 plain ones")
out = sortedRanks({1, 2, 3, 4, 5, 6, 7, 8})
eq(table.concat(out, ","), "8,7,6,5,4,3,2,1", "sort: reversed bag")
out, order = sortedRanks({1, 2, 3, 4, 5, 6, 7, 8}, 3)
eq(#order, 3, "sort: limited to 3 moves")
local out2 = sortedRanks({102, 7, 0, 3, 0, 11})
eq(table.concat(out2, ","), "102,11,7,3,0,0", "sort: a unique rank leads")
out = sortedRanks({4, 4, 4})
eq(#P.sortPlan({4, 4, 4}), 0, "sort: ties keep their order")
-- engine glue: the engine adds at the FRONT of a container; the mock adds at the back, so use a front-adding mover
do
	local saved = Item.moveTo
	function Item:moveTo(target, flags)
		if self.parent == target then
			for i, x in ipairs(target.items) do if x == self then table.remove(target.items, i) break end end
			table.insert(target.items, 1, self)
			return true
		end
		return saved(self, target, flags)
	end
	local bag = item(32081); bag.cap = 255
	local function mkRare(id, r, uniq)
		local it = item(id, {cat = "equipment", rarity = r})
		it.custom = it.custom or {}
		it.custom.rarity = r
		if uniq then it.custom.chaos_unique = 1 end
		it.parent = bag; bag.items[#bag.items + 1] = it
		return it
	end
	local a, b, c2, d = mkRare(2400, 0), mkRare(2401, 5), mkRare(2402, 2), mkRare(2403, 3, true)
	bag.items = {a, b, c2, d}
	local n = PO.sortBag(bag)
	eq(bag.items[1], d, "bag: the unique first") eq(bag.items[2], b, "bag: then rarity 5")
	eq(bag.items[3], c2, "bag: then rarity 2") eq(bag.items[4], a, "bag: plain last")
	eq(n > 0, true, "bag: moves counted")
	eq(PO.sortBag(bag), 0, "bag: a sorted bag costs no move")
	eq(PO.sortBag(nil), 0, "bag: nil is fine")
	local actionBag = actions[cfg.kinds.loot.id]
	ok(actionBag, "an Action on the Loot Bag id sorts it when opened")
	bag.items = {a, b, c2, d}
	eq(actionBag.onUse(hero, bag), false, "opening: the engine's default use goes on")
	eq(bag.items[1], d, "opening: the bag is sorted")
	Item.moveTo = saved
end

-- ------------------------------------------------------------------ moves and trade
local function move(it, toPos, toCyl) return PO.onMoveItem(hero, it, 1, {x = CONTAINER_POSITION}, toPos, nil, toCyl) end
eq(move(orbsPouch, {x = 100, y = 100, z = 7}), RETURNVALUE_NOTPOSSIBLE, "pouch to the ground refused")
ok(hero.msgs[#hero.msgs]:find("cannot be dropped"), "reason told")
eq(move(bp, {x = 100, y = 100, z = 7}), RETURNVALUE_NOTPOSSIBLE, "a backpack holding a pouch cannot be dropped")
eq(move(item(2400), {x = 100, y = 100, z = 7}), RETURNVALUE_NOERROR, "other items move as usual")
local bag = item(1987); bag.parent = bp
eq(move(orbsPouch, {x = CONTAINER_POSITION, y = 0x40}, bag), RETURNVALUE_NOERROR, "into a bag in the own backpack")
eq(move(orbsPouch, {x = CONTAINER_POSITION, y = 1}, hero), RETURNVALUE_NOERROR, "into an inventory slot")
local groundBag = item(1987); groundBag.parent = {} -- a tile
eq(move(orbsPouch, {x = CONTAINER_POSITION, y = 0x41}, groundBag), RETURNVALUE_NOTPOSSIBLE, "into a bag on the ground")
local chest = item(2594); chest.parent = {}
local box = item(1987); box.parent = chest
eq(move(orbsPouch, {x = CONTAINER_POSITION, y = 0x42}, box), RETURNVALUE_NOERROR, "into the depot")
eq(move(orbsPouch, {x = CONTAINER_POSITION, y = 0x43}, bp2), RETURNVALUE_NOTPOSSIBLE, "into another player's backpack")
eq(move(keysPouch, {x = CONTAINER_POSITION, y = 0x44}, lootPouch), RETURNVALUE_NOTPOSSIBLE, "pouch into pouch")
ok(hero.msgs[#hero.msgs]:find("another pouch"), "reason told")
-- the Loot Bag stays in the purse (owner 2026-10-17)
eq(P.moveRefusal({holdsPouch = true, lootBag = true, inPurse = true, chain = {"item", "self"}}), P.LOOT_BAG_STAYS, "pure: out of the purse into the backpack")
eq(P.moveRefusal({holdsPouch = true, lootBag = true, inPurse = true, toGround = true}), P.LOOT_BAG_STAYS, "pure: out of the purse to the ground")
eq(P.moveRefusal({holdsPouch = true, lootBag = true, inPurse = true, chain = {"depot", "tile"}}), P.LOOT_BAG_STAYS, "pure: out of the purse into the depot")
eq(P.moveRefusal({holdsPouch = true, lootBag = true, inPurse = true, chain = {"purse", "self"}}), nil, "pure: within the purse")
eq(P.moveRefusal({holdsPouch = true, lootBag = true, inPurse = false, chain = {"item", "self"}}), nil, "pure: a Loot Bag outside the purse (older character) keeps the old rule")
eq(P.moveRefusal({holdsPouch = true, inPurse = true, chain = {"item", "self"}}), nil, "pure: the other pouches may leave the purse")
local purseBox = item(26052); purseBox.parent = hero
local purseLoot = item(32081, {custom = {chaos_pouch_owner = 7, chaos_storebound = 1}}); purseLoot.parent = purseBox
purseBox.items[1] = purseLoot
eq(PO.isLootBag(purseLoot), true, "isLootBag") eq(PO.isLootBag(orbsPouch), false, "the Orbs Pouch is no Loot Bag")
eq(PO.inPurse(hero, purseLoot), true, "inPurse") eq(PO.inPurse(hero, orbsPouch), false, "a pouch in the backpack is not in the purse")
eq(move(purseLoot, {x = CONTAINER_POSITION, y = 0x40}, bag), RETURNVALUE_NOTPOSSIBLE, "Loot Bag: out of the purse into a bag refused")
ok(hero.msgs[#hero.msgs]:find("stays in your purse"), "Loot Bag: reason told")
eq(move(purseLoot, {x = CONTAINER_POSITION, y = 1}, hero), RETURNVALUE_NOTPOSSIBLE, "Loot Bag: out of the purse into an inventory slot refused")
eq(move(purseLoot, {x = 100, y = 100, z = 7}), RETURNVALUE_NOTPOSSIBLE, "Loot Bag: dropped from the purse refused")
eq(move(purseLoot, {x = CONTAINER_POSITION, y = 0x42}, box), RETURNVALUE_NOTPOSSIBLE, "Loot Bag: out of the purse into the depot refused")
eq(move(purseLoot, {x = CONTAINER_POSITION, y = 0x45}, purseBox), RETURNVALUE_NOERROR, "Loot Bag: within the purse allowed")
local tradeReq = callback("onTradeRequest", 1)
eq(tradeReq(hero, other2, orbsPouch), false, "trade window refuses a pouch")
eq(tradeReq(hero, other2, purseLoot), false, "trade window refuses the Loot Bag in the purse")
ok(hero.msgs[#hero.msgs] ~= nil, "trade refusal told")
eq(tradeReq(hero, other2, bp), false, "trade window refuses a backpack holding a pouch")
eq(tradeReq(hero, other2, item(2400)), true, "other trades go on")
eq(callback("onTradeAccept", 1)(hero, other2, item(2400), bp2), false, "accept refused when the other side holds one")
-- a store-bound item nested deeper than the old 8-level walk: still found (it could be traded or dropped before)
local deepOuter = item(1987)
local deepCur = deepOuter
for _ = 1, 12 do
	local inner = item(1987); inner.parent = deepCur; deepCur.items[#deepCur.items + 1] = inner; deepCur = inner
end
local deepBound = item(2400, {custom = {chaos_storebound = 1}}); deepBound.parent = deepCur; deepCur.items[1] = deepBound
eq(PO.holdsPouch(deepOuter), true, "a pouch 13 bags deep is still found")
eq(tradeReq(hero, other2, deepOuter), false, "trade window refuses a pouch nested 13 bags deep")
eq(move(deepOuter, {x = 100, y = 100, z = 7}), RETURNVALUE_NOTPOSSIBLE, "a pouch nested 13 bags deep cannot be dropped")

-- ------------------------------------------------------------------ death
-- the engine dropped the backpack into the corpse: the pouch leaves the corpse, contents stay, back at next login
local deadCorpse = item(3058); deadCorpse.cap = 30
tiles["100:100:7"] = {getItems = function() return {deadCorpse} end}
hero.slots[CONST_SLOT_BACKPACK] = nil
bp.parent = nil
bp:moveTo(deadCorpse, 1)
local orbsInPouch = #orbsPouch.items
registry.ChaosPouchDeath.onDeath(hero, deadCorpse)
players[7] = nil -- logged out by the death
events[#events].fn()
eq(orbsPouch.removed, true, "the pouch left the corpse")
eq(lootPouch.removed and keysPouch.removed, true, "every owned pouch")
local inCorpse = 0
for _, x in ipairs(deadCorpse.items) do if x.id == 29856 or x.id == 10155 then inCorpse = inCorpse + 1 end end
ok(inCorpse >= 2, "their contents stay in the corpse")
ok(#deadCorpse.items >= orbsInPouch, "contents moved to the corpse")
ok(queries[#queries]:find("7100109") and queries[#queries]:find("player_storage"), "give-back bit written for the offline character")
-- next login: the pouches come back empty
players[7] = hero
hero.storage[ST.regrant] = 7
local bpNew = item(1988); bpNew.parent = hero; hero.slots[CONST_SLOT_BACKPACK] = bpNew
registry.ChaosPouchesLogin.onLogin(hero)
eq(#bpNew.items, 3, "three pouches back")
eq(#bpNew.items[1].items, 0, "empty")
eq(hero.storage[ST.regrant], 0, "bits cleared")
eq(hero.msgs[#hero.msgs], "Back after your death, empty: your Orbs Pouch, Rift Key Pouch, Loot Bag (backpack).", "one short line")
registry.ChaosPouchesLogin.onLogin(hero)
eq(#bpNew.items, 3, "given once")

-- ------------------------------------------------------------------ a pouch in the purse collects (one level deep)
local pp = newPlayer(30)
local ppBag = item(1988); ppBag.parent = pp; pp.slots[CONST_SLOT_BACKPACK] = ppBag
pp.storage[ST.lootRules] = -1
eq(PO.storeGive(pp, "loot"), true, "a Loot Bag bought")
local purseBag = pp.purse.items[1]
eq(purseBag.id, 32081, "in the purse")
local loot1 = item(2401)
drop(nil, corpse(pp.id, {loot1}))
eq(loot1.parent, purseBag, "the Loot Bag in the purse collects")
ok(pp.msgs[#pp.msgs]:find("^Looted:"), "the loot line")
ok(PO.storeCheck(pp, "loot"):find("already have"), "one per character: the purse's pouch counts")
-- one level deep only: a pouch inside a bag in the purse does not collect
local inner = item(1987)
table.remove(pp.purse.items, 1)
purseBag.parent = nil
pp.purse.items[1] = inner; inner.parent = pp.purse
inner.items[1] = purseBag; purseBag.parent = inner
eq(PO.carried(pp).loot, nil, "a pouch in a bag in the purse is not carried")
ok(PO.storeCheck(pp, "loot"):find("already have"), "but still owned")
local loot2 = item(2401)
local c2 = corpse(pp.id, {loot2})
drop(nil, c2)
eq(loot2.parent, c2, "nothing collected from two levels down")
-- the inventory first: a pouch in the backpack wins over one in the purse
local hold = newPlayer(31)
local hb = item(1988); hb.parent = hold; hold.slots[CONST_SLOT_BACKPACK] = hb
local inBag, inPurse = PO.create(hold, "orbs"), PO.create(hold, "orbs")
inBag:moveTo(hb, 0)
hold.purse:addItemEx(inPurse)
eq(PO.carried(hold).orbs, inBag, "the backpack's pouch first")
hold.noPurse = true
eq(PO.carried(hold).orbs, inBag, "no purse: the backpack only")

-- ------------------------------------------------------------------ the loot goes to the Loot Bag, the backpack only when it is full
-- (owner 2026-10-16: "the loot bag and the backpack are conflicting")
local lb = newPlayer(32)
local lbBp = item(1988); lbBp.parent = lb; lb.slots[CONST_SLOT_BACKPACK] = lbBp
local innerBp = item(1988); innerBp.parent = nil; innerBp:moveTo(lbBp, 0)
lb.storage[ST.lootRules] = -1
local bag = PO.create(lb, "loot"); bag:moveTo(lbBp, 0)
local before = #lbBp.items
local g1, g2, g3 = item(2148, {count = 27, cat = "currency"}), item(2401), item(2402, {cat = "equipment", rarity = 2})
drop(nil, corpse(lb.id, {g1, g2, g3}))
eq(#lbBp.items, before, "nothing into the backpack while the Loot Bag has room") eq(#innerBp.items, 0, "nor a bag in it")
eq(g2.parent, bag, "loot into the Loot Bag") eq(g3.parent, bag, "gear into the Loot Bag")
ok(not lb.msgs[#lb.msgs]:find("backpack"), "no spill note")
bag.cap = #bag.items -- full
local s1 = item(2403)
drop(nil, corpse(lb.id, {s1}))
ok(s1.parent == lbBp or s1.parent == innerBp, "the Loot Bag full: the backpack")
ok(lb.msgs[#lb.msgs]:find("Loot Bag is full") and lb.msgs[#lb.msgs]:find("1 to your backpack"), "told: " .. lb.msgs[#lb.msgs])

-- ------------------------------------------------------------------ former Bottomless Loot Pouch owners
local old = newPlayer(20)
local bpo = item(1988); bpo.parent = old; old.slots[CONST_SLOT_BACKPACK] = bpo
old.storage[Chaos.storage.shopLootPouch] = 1
registry.ChaosPouchesLogin.onLogin(old)
eq(old.purse.items[1] and old.purse.items[1].id, 32081, "a free Loot Bag, in the purse like a store item")
ok(old.msgs[#old.msgs]:find("retired"), "with a short message")
eq(old.storage[ST.legacyGrant], 1, "marked")
registry.ChaosPouchesLogin.onLogin(old)
eq(#old.purse.items, 1, "only once")
local fresh = newPlayer(21)
registry.ChaosPouchesLogin.onLogin(fresh)
eq(fresh.storage[ST.legacyGrant], nil, "nothing for characters without the old unlock")

-- a pouch given before bindLock (chaos_locked 1, drawn grey by the client) is rebound at login, wherever it is
local grey = newPlayer(23)
local greyBp = item(1988); greyBp.parent = grey; grey.slots[CONST_SLOT_BACKPACK] = greyBp
local oldLoot = item(32081); oldLoot.custom.chaos_locked = 1; oldLoot.custom.chaos_pouch_owner = 23
oldLoot.parent = greyBp; greyBp.items[1] = oldLoot
local oldKeys = item(32083); oldKeys.custom.chaos_locked = 1
oldKeys.parent = grey.inbox; grey.inbox.items[1] = oldKeys
local plain = item(2160); plain.custom.chaos_locked = 1
plain.parent = greyBp; greyBp.items[2] = plain
local updates = 0
function oldLoot:sendUpdate() updates = updates + 1 end
registry.ChaosPouchesLogin.onLogin(grey)
eq(oldLoot.custom.chaos_locked, 2, "the Loot Bag in the backpack rebound") eq(updates, 1, "and sent again to the client")
eq(oldKeys.custom.chaos_locked, 2, "the Rift Key Pouch in the inbox rebound")
eq(plain.custom.chaos_locked, 1, "a player's own lock on another item is left alone")
eq(PO.rebind(grey), 0, "a second pass changes nothing")

-- the store while a pouch is owed
local owed = newPlayer(22)
owed.storage[ST.regrant] = 2
ok(PO.storeCheck(owed, "orbs"):find("next login"), "a pouch owed back is not sold again")
eq(PO.storeCheck(owed, "keys"), nil, "the other kinds can be bought")
TYPES[32083] = nil
ok(PO.storeCheck(owed, "keys"):find("not installed"), "not installed: refused")

print("pouches_test: " .. checks .. " checks OK")
