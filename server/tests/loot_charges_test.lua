-- Run from the server/ folder: luajit tests/loot_charges_test.lua (and lua5.3; CI runs both)
-- loot.lua L.restoreCharges: an amulet with charges dropped with 1 charge (the loot entry's count is the charges of a
-- non-stackable item with charges); a fresh corpse's charged items get the item type's full charges.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

Chaos = {}
ITEM_ATTRIBUTE_CHARGES = 99
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
function ItemType(id) return {isStackable = function() return false end, getName = function() return "x" end} end
dofile("data/scripts/chaos/loot.lua")
local L = ChaosLoot

local TYPES = {
	[1] = {charges = 200, stack = false}, -- amulet with 200 charges
	[2] = {charges = 0, stack = false},   -- plain sword
	[3] = {charges = 5, stack = true},    -- a stackable with "charges" is left alone
	[4] = {charges = 1, stack = false},   -- single use
	[5] = {charges = 0, stack = false},   -- a bag
}
local function typeOf(id)
	local t = TYPES[id]
	return {getCharges = function() return t.charges end, isStackable = function() return t.stack end}
end
local function item(id, charges, contents)
	local it = {id = id, charges = charges, contents = contents}
	function it:getId() return self.id end
	function it:getCharges() return self.charges or 0 end
	function it:setAttribute(k, v) if k == ITEM_ATTRIBUTE_CHARGES then self.charges = v end end
	function it:isContainer() return self.contents ~= nil end
	function it:getSize() return self.contents and #self.contents or 0 end
	function it:getItem(i) return self.contents and self.contents[i + 1] end
	return it
end
local function corpse(list) return item(0, nil, list) end

local amulet, sword, stack, once = item(1, 1), item(2, 0), item(3, 1), item(4, 1)
local c = corpse({amulet, sword, stack, once})
ok(L.restoreCharges(c, typeOf) == 1, "one item fixed")
ok(amulet.charges == 200, "amulet has its full 200 charges")
ok(sword.charges == 0, "plain sword untouched")
ok(stack.charges == 1, "stackable untouched")
ok(once.charges == 1, "single-charge type untouched")

-- already full or with more: untouched; zero (never set): untouched
local full, over, none = item(1, 200), item(1, 300), item(1, 0)
ok(L.restoreCharges(corpse({full, over, none}), typeOf) == 0, "full, over and unset left alone")
ok(over.charges == 300 and none.charges == 0, "values kept")

-- inside a bag in the corpse
local inner = item(1, 1)
L.restoreCharges(corpse({item(5, 0, {inner})}), typeOf)
ok(inner.charges == 200, "amulet inside a bag fixed")

-- robustness
ok(L.restoreCharges(nil, typeOf) == 0, "no corpse")
ok(L.restoreCharges(corpse({}), typeOf) == 0, "empty corpse")
-- default ItemType without getCharges (mock engine): nothing happens
ok(L.restoreCharges(corpse({item(1, 1)})) == 0, "ItemType without getCharges")

print(string.format("loot_charges_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
