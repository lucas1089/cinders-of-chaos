-- Run from the server/ folder: luajit tests/throwables_test.lua (and lua5.3; CI runs both)
-- Stackable throwing weapons are out of the game (owner 2026-10-20; README "Throwing weapons"): the list in
-- data/lib/chaos_throwables.lua, no class kit and no supply table names one, the shuriken spells need no star, and a
-- stackable item never carries a rarity (the loot layer and the rarity walk both clear it).
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/lib/chaos_throwables.lua")
local T = ChaosThrowables
for _, id in ipairs({1294, 2389, 2399, 2410, 3965, 7366, 7367, 7368, 7378}) do
	ok(T.isThrowable(id), "throwable " .. id)
end
ok(not T.isThrowable(2379), "a dagger is no throwable")
ok(not T.isThrowable(2544), "an arrow is no throwable (the archery patch owns ammunition)")
eq(#T.list(), 9, "nine ids")
ok(T.list()[1] < T.list()[2], "the list is sorted")

-- no kit names one
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/newplayer_core.lua")
local kits = ChaosNewPlayer.cfg().kits
local n = 0
for name, kit in pairs(kits) do
	for _, list in ipairs({kit.equip or {}, kit.backpack or {}}) do
		for _, e in ipairs(list) do
			n = n + 1
			ok(not T.isThrowable(e.id), "kit " .. name .. " names throwable " .. tostring(e.id))
		end
	end
end
ok(n > 20, "the kits were read (" .. n .. " entries)")
-- the shuriken spells need no star: a default attack, no item list
ok(Chaos.classes.shuriken ~= nil and Chaos.classes.shuriken.defaultAttack == 50, "shuriken default attack kept")
eq(Chaos.classes.shuriken.items, nil, "no shuriken item list")
-- hunt supply prices
local supplies = dofile("data/scripts/chaos/hunt_supplies.lua")
for id in pairs(supplies) do
	ok(not T.isThrowable(id), "hunt supply " .. id)
end

-- the rarity rule for stackables: pure part
eq(T.mayCarryRarity({isStackable = function() return true end}), false, "a stackable carries no rarity")
eq(T.mayCarryRarity({isStackable = function() return false end}), true, "a single item may")
eq(T.mayCarryRarity(nil), true, "no type: leave it (the gear gate decides)")

-- the loot layer clears a rarity a stackable drop got from the stock roll
Chaos = Chaos or {}
local function item(id, stack, rarity)
	local it = {id = id, a = {rarity = rarity}}
	function it:getId() return self.id end
	function it:getCustomAttribute(k) return self.a[k] end
	function it:removeCustomAttribute(k) self.a[k] = nil return true end
	return it
end
MAX_LOOTCHANCE = 100000
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
local stackableIds = {[7378] = true, [2400] = false}
function ItemType(id)
	return {isStackable = function() return stackableIds[id] == true end, getName = function() return "item " .. id end}
end
dofile("data/scripts/chaos/loot.lua")
local spear, sword = item(7378, true, 3), item(2400, false, 3)
eq(ChaosLoot.stripStackableRarity({spear, sword}), 1, "one stackable cleared")
eq(spear:getCustomAttribute("rarity"), nil, "royal spear: no rarity")
eq(sword:getCustomAttribute("rarity"), 3, "the sword keeps its rarity")
eq(ChaosLoot.stripStackableRarity({spear, sword}), 0, "second pass changes nothing")
local late = item(7378, true, 5)
ChaosLoot.finalizeRarity(late)
eq(late:getCustomAttribute("rarity"), nil, "finalizeRarity (autoloot) clears it too")
-- the throwables themselves leave a corpse
ok(ChaosLoot.isRemovedId(7378) and ChaosLoot.isRemovedId(2399), "throwables are removed ids")
ok(not ChaosLoot.isRemovedId(2400), "other items are not")

if fails > 0 then
	error(fails .. " failure(s) of " .. checks)
end
print("throwables_test: " .. checks .. " checks OK")
