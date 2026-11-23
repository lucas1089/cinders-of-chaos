-- Run from the server/ folder: luajit tests/loot_set_floor_test.lua (and lua5.3; CI runs both)
-- O717: a piece of an equipment set never drops below Rare (loot_config.lua gear.setMinRarity, loot.lua L.setPieceTarget);
-- a higher roll stays, a plain item and a unique are not touched.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

Chaos = {}
MAX_LOOTCHANCE = 100000
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
function ItemType(id)
	return {isStackable = function() return false end, getName = function() return "item " .. id end}
end
dofile("data/scripts/chaos/loot.lua")
local L, C, R = ChaosLoot, ChaosLootConfig, ChaosRarity
ok(C.gear.setMinRarity == 4, "the floor is Rare (stored id 4)")

local function item(attrs)
	return {getCustomAttribute = function(_, k) return attrs[k] end}
end
local setPiece, plain, uniq = item({}), item({}), item({chaos_unique = 1})
ChaosItemSets = {pieceOf = function(it) if it == setPiece or it == uniq then return {key = "cinderwrought"} end end}

for _, below in ipairs({0, 1, 2, 3}) do
	ok(R.rank(L.setPieceTarget(setPiece, below)) == R.rank(4), "a set piece rolled " .. below .. " becomes Rare")
end
ok(L.setPieceTarget(setPiece, 4) == 4, "Rare stays")
ok(L.setPieceTarget(setPiece, 5) == 5, "Legendary stays")
ok(L.setPieceTarget(setPiece, 10) == 10, "Divine stays")
ok(L.setPieceTarget(plain, 1) == 1, "a plain item is not lifted")
ok(L.setPieceTarget(uniq, 0) == 0, "a unique is not lifted")
ok(L.setPieceTarget(nil, 1) == 1, "no item")
-- many rolls of the real roll: a set piece never ends below Rare
local seed = 7
L.setRandom(function(a, b)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return a + seed % (b - a + 1)
end)
for _, tier in ipairs({"normal", "magic", "rare", "legendary", "boss"}) do
	for _ = 1, 300 do
		local t = L.setPieceTarget(setPiece, L.upgradeRarity(tier, L.stockRarity(), 1, 100))
		if R.rank(t) < R.rank(4) then
			ok(false, "set piece below Rare in " .. tier)
			break
		end
	end
end
print(string.format("%d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
