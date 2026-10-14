-- Run from the server/ folder: luajit tests/death_keep_test.lua (and lua5.3; CI runs both)
-- Store-bound items never drop on death (death_keep_core.lua, death_keep.lua; server/README.md "Store pouches and the
-- Everfull Ration"). Live test 2026-10-14: a death on shallow water (no corpse) lost the Loot Bag and the Everfull
-- Ration. This runs the stock death loop of droploot.lua (the base script, with the hook of tools/patch_base_events.py
-- step 15) on a mocked engine: with and without a corpse, every kept kind (a Loot Bag, the ration, a nemesis trophy
-- in the Loot Bag, any chaos_storebound item) ends in the inbox, the loot still drops, a kept item worn in a slot stays,
-- and the next login puts them back into the backpack.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

-- ---------------------------------------------------------------- mocked items
local POUCH, RATION, TROPHY, BAG, BACKPACK, LOOT, GOLD, RING = 32081, 32084, 7393, 1987, 1988, 2400, 2148, 2207
local CONTAINERS = {[POUCH] = true, [BAG] = true, [BACKPACK] = true, [1990] = true}
local Item = {}
Item.__index = Item
local function newItem(id, name, attrs, kids)
	local it = setmetatable({id = id, name = name or ("item " .. id), attrs = attrs or {}, kids = {}, removed = false}, Item)
	for _, k in ipairs(kids or {}) do
		k.parent = it
		it.kids[#it.kids + 1] = k
	end
	return it
end
function Item:getId() return self.id end
function Item:getName() return self.name end
function Item:isContainer() return CONTAINERS[self.id] or false end
function Item:getItems() local o = {} for i, k in ipairs(self.kids) do o[i] = k end return o end
function Item:getCustomAttribute(k) return self.attrs[k] end
function Item:setCustomAttribute(k, v) self.attrs[k] = v end
function Item:removeCustomAttribute(k) self.attrs[k] = nil end
local function detach(it)
	local p = it.parent
	if p and p.kids then
		for i, k in ipairs(p.kids) do
			if k == it then table.remove(p.kids, i) break end
		end
	elseif p and p.slots then
		for s, k in pairs(p.slots) do
			if k == it then p.slots[s] = nil end
		end
	end
	it.parent = nil
end
function Item:remove() detach(self); self.removed = true; return true end
function Item:moveTo(dest, flags)
	if dest == nil or self.removed then
		return nil -- the engine: no cylinder (no corpse) -> nil
	end
	if flags == 0 and dest.capacity and #dest.kids >= dest.capacity then
		return false
	end
	detach(self)
	self.parent = dest
	dest.kids[#dest.kids + 1] = self
	return true
end
-- removed itself or inside a removed container
local function gone(it)
	while it do
		if it.removed then return true end
		it = it.parent
	end
	return false
end
local function holds(container, it)
	local queue, i = {container}, 1
	while queue[i] do
		local c = queue[i]
		i = i + 1
		for _, k in ipairs(c.kids or {}) do
			if k == it then return true end
			queue[#queue + 1] = k
		end
	end
	return false
end

-- ---------------------------------------------------------------- mocked engine (only what death_keep.lua uses)
CONST_SLOT_HEAD, CONST_SLOT_BACKPACK, CONST_SLOT_AMMO = 1, 3, 10
MESSAGE_EVENT_ADVANCE = 19
local events = {}
function CreatureEvent(name)
	local e = {name = name}
	function e:type() end
	function e:register() events[name] = self end
	return e
end
Chaos = Chaos or {}
local messages = {}

local function newPlayer()
	local p = {slots = {}, inbox = newItem(1990, "inbox")}
	p.inbox.parent = p
	function p:getSlotItem(s) return self.slots[s] end
	function p:getInbox() return self.inbox end
	function p:getName() return "Tester" end
	function p:sendTextMessage(_, text) messages[#messages + 1] = text end
	function p:equip(slot, it) it.parent = self; self.slots[slot] = it end
	return p
end

-- a store pouch / the ration / a nemesis trophy as their scripts make them
local function lootBag(kids) return newItem(POUCH, "loot bag", {chaos_storebound = 1, chaos_pouch_owner = 7}, kids) end
local function ration() return newItem(RATION, "everfull ration", {chaos_storebound = 1, chaos_food_owner = 7}) end
local function trophy() return newItem(TROPHY, "nemesis trophy", {chaos_storebound = 1, chaos_nemesis_owner = 7}) end

dofile("data/scripts/chaos/death_keep.lua")
local DK, K = ChaosDeathKeep, ChaosDeathKeepCore
check(events.ChaosDeathKeepLogin ~= nil, "login event registered")

-- the stock loop of data/creaturescripts/scripts/droploot.lua (every slot drops: a red skull), with or without the
-- hook of patch_base_events.py step 15
local function stockDrop(player, corpse, hooked)
	for slot = CONST_SLOT_HEAD, CONST_SLOT_AMMO do
		local item = player:getSlotItem(slot)
		if item then
			if not (hooked and ChaosDeathKeep and ChaosDeathKeep.beforeDrop
					and ChaosDeathKeep.beforeDrop(player, item, corpse)) and not item:moveTo(corpse) then
				item:remove()
			end
		end
	end
end

local function scene()
	local p = newPlayer()
	local sword, gold, potion = newItem(LOOT, "sword"), newItem(GOLD, "gold coin"), newItem(7590, "potion")
	local tr = trophy()
	local bag = lootBag({gold, tr})
	local food = ration()
	local inner = newItem(BAG, "bag", {}, {food, potion})
	local backpack = newItem(BACKPACK, "backpack", {}, {sword, bag, inner})
	p:equip(CONST_SLOT_BACKPACK, backpack)
	return p, {sword = sword, gold = gold, potion = potion, trophy = tr, bag = bag, food = food, backpack = backpack}
end

-- ---------------------------------------------------------------- the bug: water, no corpse, no hook
do
	local p, s = scene()
	stockDrop(p, nil, false)
	check(gone(s.bag) and gone(s.food), "old rule: on water the Loot Bag and the ration are lost (the bug)")
end

-- ---------------------------------------------------------------- water: no corpse
do
	local p, s = scene()
	stockDrop(p, nil, true)
	check(not s.bag.removed and holds(p.inbox, s.bag), "water: the Loot Bag is in the inbox")
	check(not s.food.removed and holds(p.inbox, s.food), "water: the Everfull Ration is in the inbox")
	check(holds(s.bag, s.trophy) and not s.trophy.removed, "water: the nemesis trophy stays in the Loot Bag")
	eq(#s.bag.kids, 1, "water: only the trophy is left in the Loot Bag (its loot dropped)")
	check(gone(s.gold) and gone(s.sword) and gone(s.potion), "water: the loot is gone, as with any drop")
	check(s.backpack.removed and p:getSlotItem(CONST_SLOT_BACKPACK) == nil, "water: the backpack dropped")
	eq(s.bag.attrs[DK.MARK], 1, "parked items are marked")
	eq(s.bag.attrs.chaos_pouch_owner, 7, "the Loot Bag keeps its owner (the same item, not a copy)")
end

-- ---------------------------------------------------------------- land: a corpse
do
	local p, s = scene()
	local corpse = newItem(BAG, "dead human")
	stockDrop(p, corpse, true)
	check(holds(p.inbox, s.bag) and holds(p.inbox, s.food), "land: the kept items are in the inbox, not the corpse")
	check(not holds(corpse, s.bag) and not holds(corpse, s.food), "land: nothing kept is in the corpse")
	check(holds(corpse, s.gold) and holds(corpse, s.sword) and holds(corpse, s.potion), "land: the loot is in the corpse")
	check(holds(corpse, s.backpack), "land: the backpack is in the corpse")
end

-- ---------------------------------------------------------------- a kept item worn in a slot stays there
do
	local p = newPlayer()
	local loot = newItem(LOOT, "sword")
	local bag = lootBag({loot})
	p:equip(CONST_SLOT_BACKPACK, bag)
	local food = ration()
	p:equip(CONST_SLOT_AMMO, food)
	local ring = newItem(RING, "ring", {chaos_storebound = 1})
	p:equip(5, ring)
	stockDrop(p, nil, true)
	check(p:getSlotItem(CONST_SLOT_BACKPACK) == bag and not bag.removed, "a Loot Bag worn as backpack stays")
	check(loot.removed, "its loot still drops (no death-proof backpack)")
	check(p:getSlotItem(CONST_SLOT_AMMO) == food, "the ration in the ammo slot stays")
	check(p:getSlotItem(5) == ring, "any chaos_storebound item stays")
	local corpse = newItem(BAG, "dead human")
	local loot2 = newItem(LOOT, "sword")
	bag.kids[1], loot2.parent = loot2, bag
	stockDrop(p, corpse, true)
	check(holds(corpse, loot2) and p:getSlotItem(CONST_SLOT_BACKPACK) == bag, "with a corpse its loot goes there")
end

-- ---------------------------------------------------------------- the pure rules on their own
do
	local api = DK.api(newPlayer())
	local a, b = lootBag(), ration()
	local root = newItem(BACKPACK, "backpack", {}, {newItem(BAG, "bag", {}, {a}), b})
	local found = K.find(root, api)
	eq(#found, 2, "find: both kept items")
	check(not DK.kept(newItem(LOOT)), "plain loot is not kept")
	check(DK.kept(newItem(LOOT, "x", {chaos_storebound = 1})), "any chaos_storebound item is kept")
	eq(K.loginText({"Loot Bag", "Everfull Ration"}, "backpack"),
		"Kept through your death: your Loot Bag, Everfull Ration (backpack).", "login text")
	check(K.loginText({}, "inbox") == nil, "no login text without items")
end

-- ---------------------------------------------------------------- the next login: back to the backpack
do
	local p, s = scene()
	stockDrop(p, nil, true)
	local fresh = newItem(BACKPACK, "bag")
	fresh.capacity = 1
	p:equip(CONST_SLOT_BACKPACK, fresh)
	messages = {}
	events.ChaosDeathKeepLogin.onLogin(p)
	eq(#fresh.kids, 1, "login: what fits goes to the backpack")
	eq(#p.inbox.kids, 1, "login: the rest stays in the inbox")
	check(s.bag.attrs[DK.MARK] == nil and s.food.attrs[DK.MARK] == nil, "login: the marks are gone")
	eq(messages[1], "Kept through your death: your Loot bag, Everfull ration (backpack and inbox).", "login message")
	messages = {}
	events.ChaosDeathKeepLogin.onLogin(p)
	eq(#messages, 0, "a second login says nothing")
end

if failures > 0 then
	error(string.format("%d of %d checks failed", failures, checks))
end
print(string.format("death_keep_test: %d checks passed", checks))
