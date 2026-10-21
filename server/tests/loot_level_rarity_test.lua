-- Run from the server/ folder: luajit tests/loot_level_rarity_test.lua (and lua5.3; CI runs both)
-- The hunting level's rarity roll of the Chaos loot layer (loot.lua L.levelRarityChance / L.upgradeRarity, loot_config.lua
-- gear.levelRarity; server/README.md "Level 500+ rarity"). Beta 2026-10-20: two days at level 500+ gave no Rare or
-- Legendary item; for normal and magic monsters this layer gave at most Magic, so every Rare came from the stock roll.

local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function near(a, b, eps, what)
	ok(math.abs(a - b) <= eps, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

Chaos = {}
MAX_LOOTCHANCE = 100000
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
function ItemType(id)
	return {isStackable = function() return false end, getName = function() return "item " .. id end}
end
dofile("data/scripts/chaos/loot.lua")
local L, C = ChaosLoot, ChaosLootConfig
local R = ChaosRarity
local lr = C.gear.levelRarity
ok(type(lr) == "table" and #lr.points >= 2, "levelRarity configured")

-- the curve: nothing below the first point, linear between, flat beyond
near(L.levelRarityChance(0), 0, 1e-9, "level 0")
near(L.levelRarityChance(lr.points[1][1] - 1), 0, 1e-9, "below the first point")
near(L.levelRarityChance(500), 4, 1e-9, "level 500")
near(L.levelRarityChance(750), 5, 1e-9, "level 750: halfway between 500 and 1000")
near(L.levelRarityChance(1000), 6, 1e-9, "level 1000")
near(L.levelRarityChance(5000), 8, 1e-9, "flat beyond the last point")
near(L.levelRarityChance(nil), 0, 1e-9, "no level")
for i = 2, #lr.points do
	ok(lr.points[i][1] > lr.points[i - 1][1] and lr.points[i][2] >= lr.points[i - 1][2], "the curve rises " .. i)
end

-- rates over many rolls (a fixed generator): a normal monster's plain gear drop
math.randomseed(12345)
local seed = 1
L.setRandom(function(a, b)
	seed = seed + 1
	return math.random(a, b)
end)
local function rates(tier, level, n)
	local rare, leg, any = 0, 0, 0
	for _ = 1, n do
		local r = R.rank(L.upgradeRarity(tier, 0, 1, level))
		if r >= 4 then any = any + 1 end
		if r == 4 then rare = rare + 1 end
		if r == 5 then leg = leg + 1 end
	end
	return any / n * 100, rare / n * 100, leg / n * 100
end
local any = rates("normal", 400, 40000)
near(any, 0, 1e-9, "level 400 normal monster: the layer adds no Rare (unchanged below the curve)")
local a5, r5, l5 = rates("normal", 600, 80000)
local want = L.levelRarityChance(600)
near(a5, want, 0.3, "level 600: rare+ at the curve's chance")
near(l5 / a5 * 100, lr.legendaryShare, 3, "legendaryShare of them Legendary")
ok(r5 > 0, "Rare drops at 600")
-- item find scales it
local a6 = rates("normal", 600, 80000)
local seed2 = seed
local found = 0
for _ = 1, 80000 do
	if R.rank(L.upgradeRarity("normal", 0, 2, 600)) >= 4 then found = found + 1 end
end
near(found / 80000 * 100, 2 * want, 0.5, "item find x2 doubles the chance")
ok(seed2 ~= nil and a6 > 0, "rolls ran")
-- never lowers what the item has; never above the max rarity
for _ = 1, 2000 do
	ok(R.rank(L.upgradeRarity("normal", 10, 1, 2000)) == R.rank(10), "a Divine item stays Divine")
end
local top = R.rank(C.gear.maxRarity)
local over = 0
for _ = 1, 20000 do
	local r = R.rank(L.upgradeRarity("normal", 0, 50, 2000))
	if r > top and r ~= R.rank(10) then over = over + 1 end
end
ok(over == 0, "the level roll never passes maxRarity")
-- a rare monster keeps its own floor (Magic) and the level roll comes on top
local seen = {}
for _ = 1, 20000 do
	seen[R.rank(L.upgradeRarity("rare", 0, 1, 800))] = true
end
ok(seen[3] and seen[4] and seen[5], "rare monster at 800: Magic floor, Rare and Legendary from the level roll")
L.setRandom(nil)

print(string.format("loot_level_rarity_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
