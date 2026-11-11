-- Run from the server/ folder: luajit tests/item_fusion_test.lua (and lua5.3; CI runs both)
-- Item fusion takes only plain copies (O509, data/scripts/chaos/item_fusion_core.lua) against a mocked player, with the
-- real crafting rules (data/lib/chaos_crafting.lua): what a plain copy is, the engine's order, that a unique or set
-- copy is never taken, and that nothing is removed when the plain copies are not enough.

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- engine mock
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME = 1, 2
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_ARMOR = 11, 12
CONST_SLOT_HEAD, CONST_SLOT_BACKPACK, CONST_SLOT_RIGHT, CONST_SLOT_LEFT = 1, 3, 5, 6

local BLADE, HELMET, COIN, BAG = 7384, 2498, 2160, 1988
local TYPES = {
	[BLADE] = {name = "mystic blade", weaponType = 1, attack = 44, slot = 48},
	[HELMET] = {name = "royal helmet", armor = 9, slot = 1},
	[COIN] = {name = "crystal coin", stackable = true},
	[BAG] = {name = "backpack", container = true, slot = 4}
}

function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getName = function() return t.name or "" end,
		isContainer = function() return t.container == true end,
		isStackable = function() return t.stackable == true end,
		getWeaponType = function() return t.weaponType or 0 end,
		getSlotPosition = function() return t.slot or 0 end,
		getArmor = function() return t.armor or 0 end,
		getAttack = function() return t.attack or 0 end,
		getDefense = function() return 0 end,
		getHitChance = function() return 0 end,
		getElementDamage = function() return 0 end,
		getAbilities = function() return {} end
	}
end

local removals = {}
local Item = {}
Item.__index = Item
local function newItem(id, count)
	return setmetatable({id = id, count = count or 1, attrs = {}, custom = {}, items = {}}, Item)
end
function Item:getId() return self.id end
function Item:getCount() return self.count end
function Item:getType() return ItemType(self.id) end
function Item:getName() return self.attrs[ITEM_ATTRIBUTE_NAME] or ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:getAttribute(k) return self.attrs[k] or (k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil) end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:isStoreItem() return self.store == true end
function Item:isContainer() return (TYPES[self.id] or {}).container == true end
function Item:getSize() return #self.items end
function Item:add(item)
	self.items[#self.items + 1] = item
	item.parent = self
	return item
end
-- as the engine's Container::getItems(true): breadth first, the whole tree
function Item:getItems(recursive)
	local out, queue = {}, {self}
	while #queue > 0 do
		local c = table.remove(queue, 1)
		for _, it in ipairs(c.items) do
			out[#out + 1] = it
			if recursive and it:isContainer() then
				queue[#queue + 1] = it
			end
		end
	end
	return out
end
function Item:remove(n)
	if self.gone or self.stuck then
		return false
	end
	removals[#removals + 1] = self
	if n and n > 0 and n < self.count then
		self.count = self.count - n
		return true
	end
	self.gone = true
	local holder = self.parent
	if holder then
		for i, it in ipairs(holder.items) do
			if it == self then
				table.remove(holder.items, i)
				break
			end
		end
	end
	if self.player then
		self.player.slots[self.slot] = nil
	end
	return true
end

local function newPlayer()
	local p = {slots = {}}
	function p:getSlotItem(slot) return self.slots[slot] end
	function p:wear(slot, item)
		self.slots[slot] = item
		item.player, item.slot = self, slot
		return item
	end
	return p
end

local F = dofile("data/scripts/chaos/item_fusion_core.lua")
eq(F, ChaosItemFusion, "the file returns the global table")
eq(type(ChaosCrafting), "nil", "the crafting rules load on first use, not at file load")

-- ---------------------------------------------------------------- what a plain copy is
local function made(id, fn)
	local it = newItem(id)
	if fn then
		fn(it)
	end
	return it
end
local function mark(key, value)
	return function(it) it:setCustomAttribute(key, value) end
end

eq(F.keptWhy(newItem(BLADE)), nil, "a stock copy is plain")
eq(type(ChaosCrafting), "table", "the first question loaded the crafting rules")
eq(F.keptWhy(made(BLADE, mark("chaos_ilvl", 57))), nil, "the item level of a plain drop does not count")
eq(F.keptWhy(made(BLADE, mark("chaos_locked", 0))), nil, "an unlocked copy (lock mark 0) is plain")
eq(F.keptWhy(made(BLADE, mark("chaos_locked", 1))), "locked", "a locked copy")
eq(F.keptWhy(made(BLADE, mark("chaos_unique", 1))), "fixed", "a unique")
eq(F.keptWhy(made(BLADE, mark("chaos_set", "duskstalker"))), "fixed", "a set piece")
eq(F.keptWhy(made(BLADE, mark("chaos_raid", 1))), "fixed", "raid vendor gear")
eq(F.keptWhy(made(BLADE, mark("chaos_faction", 1))), "fixed", "faction vendor gear")
eq(F.keptWhy(made(BLADE, mark("chaos_storebound", 1))), "fixed", "a store-bound copy")
eq(F.keptWhy(made(BLADE, function(it) it.store = true end)), "fixed", "an engine store item")
for _, rarity in ipairs({1, 2, 3, 4, 5, 10}) do
	eq(F.keptWhy(made(BLADE, mark("rarity", rarity))), "rolled", "rarity " .. rarity)
end
eq(F.keptWhy(made(BLADE, mark("rarity_swordSkill", 2))), "rolled", "a modifier without a rarity")
eq(F.keptWhy(made(BLADE, mark("combatPowerLevel", 3))), "rolled", "a +N upgrade level")
eq(F.keptWhy(made(BLADE, mark("chaos_sockets", 1))), "sockets", "an empty socket")
eq(F.keptWhy(made(BLADE, mark("chaos_gem2", 44001))), "sockets", "a gem mark without a socket count")
eq(F.keptWhy(made(BLADE, mark("chaos_quality", 5))), "worked", "quality")
eq(F.keptWhy(made(BLADE, mark("chaos_tmog", 2400))), "worked", "a transmog look")

-- a unique made before the marker existed: its base id has a spec and it carries the spec's name
ChaosUniqueSpecs = {[BLADE] = {name = "Emberfall Blade"}}
local old = made(BLADE, function(it) it:setAttribute(ITEM_ATTRIBUTE_NAME, "Emberfall Blade") end)
eq(F.keptWhy(old), "fixed", "an old unique without the marker")
eq(F.keptWhy(newItem(BLADE)), nil, "the plain base of a unique stays plain")
ChaosUniqueSpecs = nil

local full = newItem(BAG)
full:add(newItem(COIN, 5))
eq(F.keptWhy(full), "container", "a container with something inside")
eq(F.keptWhy(newItem(BAG)), nil, "an empty container is plain")

-- the rules of this file agree with the crafting rules: nothing they call fixed or not normal is plain
local C = ChaosCrafting
for _, it in ipairs({made(BLADE, mark("chaos_unique", 1)), made(BLADE, mark("chaos_set", "x")),
	made(BLADE, mark("rarity", 4)), made(BLADE, mark("rarity_fireAbsorb", 3)), made(HELMET, mark("chaos_raid", 1))}) do
	eq(C.hasFixedValues(it) or not C.isNormal(it), true, "the crafting rules see the mark")
	eq(F.keptWhy(it) ~= nil, true, "and the fusion keeps the copy")
end

-- ---------------------------------------------------------------- the reported case: the unique lies before the plain copies
local function bagPlayer(...)
	local p = newPlayer()
	local bag = p:wear(CONST_SLOT_BACKPACK, newItem(BAG))
	for _, it in ipairs({...}) do
		bag:add(it)
	end
	return p, bag
end

removals = {}
local unique = made(BLADE, mark("chaos_unique", 1))
local a, b, c = newItem(BLADE), newItem(BLADE), newItem(BLADE)
local p, bag = bagPlayer(unique, a, b, c)
local list, kept = F.copies(p, BLADE)
eq(#list, 3, "three plain copies")
eq(kept, 1, "one copy kept")
eq(F.take(p, BLADE, 3), true, "three plain copies fuse")
eq(unique.gone, nil, "the unique is still there")
eq(a.gone and b.gone and c.gone, true, "the three plain copies are gone")
eq(#bag.items, 1, "one item left in the bag")
eq(bag.items[1], unique, "it is the unique")

-- two plain copies and a unique: stock took all three; now nothing goes
removals = {}
unique = made(BLADE, mark("chaos_unique", 1))
a, b = newItem(BLADE), newItem(BLADE)
p, bag = bagPlayer(a, unique, b)
eq(F.take(p, BLADE, 3), false, "two plain copies are not enough")
eq(#removals, 0, "nothing was removed")
eq(#bag.items, 3, "the bag is untouched")

-- a worn unique and plain copies in the bag
removals = {}
unique = made(BLADE, mark("chaos_unique", 1))
a, b, c = newItem(BLADE), newItem(BLADE), newItem(BLADE)
p, bag = bagPlayer(a, b)
p:wear(CONST_SLOT_RIGHT, unique)
eq(F.take(p, BLADE, 3), false, "the worn unique does not count")
eq(#removals, 0, "nothing was removed")
bag:add(c)
eq(F.take(p, BLADE, 3), true, "with a third plain copy it fuses")
eq(p.slots[CONST_SLOT_RIGHT], unique, "the worn unique stays in the hand")
eq(#bag.items, 0, "the bag copies are gone")

-- a set piece, a Rare copy, a socketed copy and a locked copy among the plain ones
removals = {}
local set, rare = made(BLADE, mark("chaos_set", "duskstalker")), made(BLADE, mark("rarity", 4))
local socketed, locked = made(BLADE, mark("chaos_sockets", 2)), made(BLADE, mark("chaos_locked", 1))
a, b, c = newItem(BLADE), newItem(BLADE), newItem(BLADE)
p, bag = bagPlayer(set, a, rare, b, socketed, locked, c)
list, kept = F.copies(p, BLADE)
eq(#list, 3, "three plain copies among seven")
eq(kept, 4, "four kept")
eq(F.take(p, BLADE, 3), true, "the plain ones fuse")
eq(#bag.items, 4, "four items left")
for _, it in ipairs({set, rare, socketed, locked}) do
	eq(it.gone, nil, "a special copy is never taken")
end

-- ---------------------------------------------------------------- the engine's order
-- head slot first, then the backpack to the bottom (breadth first), then the hands
removals = {}
local worn, inHand = newItem(HELMET), newItem(HELMET)
local top, deep, deeper = newItem(HELMET), newItem(HELMET), newItem(HELMET)
p = newPlayer()
p:wear(CONST_SLOT_HEAD, worn)
bag = p:wear(CONST_SLOT_BACKPACK, newItem(BAG))
local inner = bag:add(newItem(BAG))
bag:add(top)
inner:add(deep)
local innermost = inner:add(newItem(BAG))
innermost:add(deeper)
p:wear(CONST_SLOT_LEFT, inHand)
list = F.copies(p, HELMET)
eq(#list, 5, "five copies")
eq(list[1].item, worn, "the head slot first")
eq(list[2].item, top, "then the top of the backpack")
eq(list[3].item, deep, "then one level down")
eq(list[4].item, deeper, "then two levels down")
eq(list[5].item, inHand, "the hand last")
eq(F.take(p, HELMET, 3), true, "three of five")
eq(removals[1] == worn and removals[2] == top and removals[3] == deep, true, "the first three in that order")
eq(deeper.gone, nil, "the fourth stays")
eq(inHand.gone, nil, "the fifth stays")

-- a backpack of the fused id worn in the backpack slot counts as one copy and is not searched (as the engine)
p = newPlayer()
bag = p:wear(CONST_SLOT_BACKPACK, newItem(BAG))
bag:add(newItem(BAG))
list, kept = F.copies(p, BAG)
eq(#list, 0, "the worn backpack holds something: not plain")
eq(kept, 1, "it is one kept copy, its contents are not looked at")

-- ---------------------------------------------------------------- stacks, bad input, failures
removals = {}
local stack, stack2 = newItem(COIN, 2), newItem(COIN, 5)
p, bag = bagPlayer(stack, stack2)
eq(F.take(p, COIN, 8), false, "seven in two stacks are not eight")
eq(#removals, 0, "nothing was removed")
eq(F.take(p, COIN, 3), true, "three from two stacks")
eq(stack.gone, true, "the first stack is gone")
eq(stack2.count, 4, "one came from the second")

p = bagPlayer(newItem(BLADE), newItem(BLADE), newItem(BLADE))
eq(F.take(nil, BLADE, 3), false, "no player")
eq(F.take(p, nil, 3), false, "no id")
eq(F.take(p, BLADE, 0), false, "amount 0")
eq(F.take(p, BLADE, 2.5), false, "a fraction")
eq(F.take(p, "x", 3), false, "an id that is no number")
eq(F.take(p, 9999, 3), false, "an id the player does not carry")

-- a removal the engine refuses: no success
local stuck = newItem(BLADE)
stuck.stuck = true
p = bagPlayer(newItem(BLADE), stuck, newItem(BLADE))
eq(F.take(p, BLADE, 3), false, "a refused removal is no success")

-- fail closed: without the crafting rules no copy is plain
local keep = ChaosCrafting
ChaosCrafting = {}
p, bag = bagPlayer(newItem(BLADE), newItem(BLADE), newItem(BLADE))
eq(F.keptWhy(newItem(BLADE)), "norules", "no rules, no plain copy")
eq(F.take(p, BLADE, 3), false, "no rules, no fusion")
eq(#bag.items, 3, "nothing was removed")
ChaosCrafting = keep
-- a rule that throws: the copy is kept
local isNormal = keep.isNormal
keep.isNormal = function() error("boom") end
eq(F.keptWhy(newItem(BLADE)), "norules", "a failing rule keeps the copy")
keep.isNormal = isNormal
eq(F.take(p, BLADE, 3), true, "with the rules back it fuses")

print("item_fusion_test: ok")
