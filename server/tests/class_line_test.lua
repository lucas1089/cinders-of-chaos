-- Run from the server/ folder: luajit tests/class_line_test.lua (and lua5.3; CI runs both)
-- The class line of the item tooltip ("For ..."): every equippable item of the configs gets one, the classes that may
-- wear it or "all classes" (data/scripts/chaos/item_tooltip_core.lua T.classLine). An empty engine vocation string
-- (a stock Warrior Helmet is worn by everybody) used to print nothing. Walks the equipment sets, the uniques and the
-- stock equipment table; fails when one item would render no line.

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/lib/chaos_crafting.lua")
-- the specs index attributes by engine constants: any name does
setmetatable(_G, {__index = function(_, k)
	if type(k) == "string" and k:match("^ITEM_ATTRIBUTE_") then return k end
end})
dofile("data/lib/chaos_unique_items.lua")
dofile("data/lib/chaos_unique_specs.lua")
dofile("data/scripts/chaos/item_tooltip_core.lua")
local T = ChaosItemTooltip

-- slot bits of the engine slot position (item_tooltip_core.lua SLOTP)
local BITS = {head = 1, necklace = 2, body = 8, legs = 64, feet = 128, ring = 256}
-- csv slot / set kind / unique slot -> {slot position, tooltip kind}
local function place(slot)
	if BITS[slot] then
		return BITS[slot], nil
	end
	if slot == "shield" or slot == "spellbook" or slot == "book" then
		return 32, "shield"
	end
	return 16, "weapon" -- every weapon family: sword axe club bow crossbow distance wand rod fist weapon two-handed
end
local KIND_SLOT = {amulet = "necklace", armor = "body", boots = "feet"}

local function line(vocString, slot, equip)
	local sp, kind = place(slot)
	local _, slotName = T.slotsOf(sp, kind)
	return T.classLine(vocString, {slot = sp}, slotName, equip), slotName
end

-- the rule itself
eq(T.classLine("", {slot = 1}, "Helmet"), "all classes", "no engine list: everybody")
eq(T.classLine("warriors", {slot = 1}, "Helmet"), "Warrior, Juggernaut, Berserker", "a list is named")
eq(T.classLine("", {slot = 1}, "Helmet", {lines = {"Ranger", "Thief"}}), "Ranger, Thief", "a unique's own rule wins")
eq(T.classLine("", {slot = 1}, "Helmet", {level = 50, lines = {}}), "all classes", "own rule without lines")
eq(T.classLine("", {slot = 4}, "Container"), nil, "a backpack shows none")
eq(T.classLine("", {slot = 8192}, "Badge"), nil, "a badge shows none")
eq(T.classLine("", {slot = 0}, nil), nil, "a plain item shows none")

-- the equipment sets
local sets = dofile("data/lib/chaos_gear_sets_items.lua")
local pieces = 0
for _, p in ipairs(sets.pieces) do
	pieces = pieces + 1
	local l = line(#p.classes > 0 and table.concat(p.classes, ", ") or "", KIND_SLOT[p.kind] or p.kind)
	eq(type(l), "string", "set piece " .. p.id .. " " .. p.name)
	if #p.classes == 0 then
		eq(l, "all classes", "set piece " .. p.id)
	end
end
eq(pieces >= 448, true, "the sets were walked")

-- the uniques: an own equip rule or the base item's list (empty here: the engine's list is not in the repo)
local uniques = 0
for _, e in ipairs(ChaosUniqueItems) do
	uniques = uniques + 1
	local spec = ChaosUniqueSpecs and ChaosUniqueSpecs[e.id]
	local l = line("", KIND_SLOT[e.slot] or e.slot, spec and spec.equip)
	eq(type(l), "string", "unique " .. e.id .. " " .. e.name)
end
eq(uniques > 100, true, "the uniques were walked")

-- the stock equipment: slots the tooltip dresses (head body legs feet necklace ring shield weapon two-handed)
local f = assert(io.open("data/items/base_item_values.csv", "r"))
local stock = 0
for row in f:lines() do
	local id, cat, slot = row:match("^(%d+),([^,]*),([^,]*),")
	if cat == "equip" and (BITS[slot] or slot == "shield" or slot == "weapon" or slot == "two-handed") then
		stock = stock + 1
		eq(line("", slot), "all classes", "stock item " .. id .. " with no engine list")
	end
end
f:close()
eq(stock > 400, true, "the stock equipment was walked")

print(string.format("class_line_test: %d checks, %d set pieces, %d uniques, %d stock items ok", n, pieces, uniques, stock))
