-- Chaos item rarities: exactly seven, Common, Uncommon, Magic, Rare, Legendary, Divine and Unique (owner item 87,
-- 2026-10-18; before: 15 rarities from Common to Transcendent). The one place that names them; every script that needs a
-- name, a colour, an order or the mapping of an old item reads it from here (server/README.md "Item rarities").
-- Pure (no engine calls). Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- The custom attribute "rarity" (and every database column that mirrors it) keeps the engine's old number space 1..15,
-- so an item saved before the change loads without any conversion and the engine's own tables (indexed 1..15, rarity
-- shaders of the client) stay valid. Six numbers are the rarities of today (the "stored ids"), the others only exist on
-- old items and mean the stored id they map to:
--
--   stored id   rarity      old rarities that became it
--   1           Common      Common
--   2           Uncommon    Uncommon
--   3           Magic       Rare
--   4           Rare        Epic
--   5           Legendary   Legendary, Exotic, Mythic, Chaos, Eternal       (ids 5 .. 9)
--   10          Divine      Divine, Phantasmal, Celestial, Cosmic, Abyssal, Transcendent   (ids 10 .. 15)
--   16          Unique      (never stored: the item carries the unique marker, "chaos_unique", and no rarity)
--
-- R.canon(n) is the stored id of any number, R.rank(n) its place 1..6 (Unique 7), the index of every per-rarity table
-- (R.at). An old item is rewritten to its stored id when it passes through the login migration (rarity_migrate.lua),
-- the crafting orbs or the forge; until then every reader maps it on the fly, so nothing waits for the migration.

ChaosRarity = ChaosRarity or {}
local R = ChaosRarity

R.UNIQUE = 16 -- the id Unique has in lists (never a stored value)
R.MAX_LEGACY = 15 -- the highest id an old item can carry

-- id, key, English name, pt-BR name, colour (the client and the loot filter draw the same ones)
R.list = {
	{id = 1, rank = 1, key = "common", name = "Common", pt = "Comum", color = "#c8c8c8"},
	{id = 2, rank = 2, key = "uncommon", name = "Uncommon", pt = "Incomum", color = "#5ccf5c"},
	{id = 3, rank = 3, key = "magic", name = "Magic", pt = "Mágica", color = "#4a90ff"},
	{id = 4, rank = 4, key = "rare", name = "Rare", pt = "Rara", color = "#a35cf0"},
	{id = 5, rank = 5, key = "legendary", name = "Legendary", pt = "Lendária", color = "#ffd040"},
	{id = 10, rank = 6, key = "divine", name = "Divine", pt = "Divina", color = "#c8e8ff"},
	{id = 16, rank = 7, key = "unique", name = "Unique", pt = "Única", color = "#e07b24", unique = true}
}
R.COUNT = #R.list -- 7
R.STORED = 6 -- the rarities an item can carry as its "rarity" attribute (Unique is the 7th, derived)

-- the names the 15 rarities had (old items, old chat links, old text): "[EXOTIC]" still reads as Legendary
R.legacyNames = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Exotic", "Mythic", "Chaos", "Eternal", "Divine",
	"Phantasmal", "Celestial", "Cosmic", "Abyssal", "Transcendent"}

-- old id (1..15) -> stored id
R.legacyToStored = {1, 2, 3, 4, 5, 5, 5, 5, 5, 10, 10, 10, 10, 10, 10}

local byId, byKey = {}, {}
for _, row in ipairs(R.list) do
	byId[row.id] = row
	byKey[row.key] = row
end
R.byId, R.byKey = byId, byKey

-- the stored id of a number: 0 for none or anything out of range, 1..5 as they are, 6..9 -> 5, 10..15 -> 10; Unique (16)
-- stays 16 (a list id, never read from an attribute)
function R.canon(n)
	n = math.floor(tonumber(n) or 0)
	if n == R.UNIQUE then
		return R.UNIQUE
	end
	if n < 1 or n > R.MAX_LEGACY then
		return 0
	end
	return R.legacyToStored[n]
end

-- place of a number in the order 1..6 (Unique 7, none 0): the index of every per-rarity table
function R.rank(n)
	local c = R.canon(n)
	return c > 0 and byId[c].rank or 0
end

-- the stored id of rank 1..6 (7 -> Unique's list id), 0 when out of range
function R.idOfRank(rank)
	rank = math.floor(tonumber(rank) or 0)
	return R.list[rank] and R.list[rank].id or 0
end

-- the stored id of a key ("legendary") or a name in any case ("Legendary"); an old name too ("Mythic" -> Legendary)
function R.idOf(name)
	local key = tostring(name or ""):lower()
	if byKey[key] then
		return byKey[key].id
	end
	for i, n in ipairs(R.legacyNames) do
		if n:lower() == key then
			return R.legacyToStored[i]
		end
	end
	return 0
end

-- true when the number is an id of today (1..5, 10), false for none and for ids only an old item carries
function R.isStored(n)
	n = math.floor(tonumber(n) or 0)
	return byId[n] ~= nil and n ~= R.UNIQUE
end

-- true when the number is an old id that maps to another one (6..9, 11..15)
function R.isLegacy(n)
	n = math.floor(tonumber(n) or 0)
	return n >= 1 and n <= R.MAX_LEGACY and R.legacyToStored[n] ~= n
end

function R.name(n)
	local row = byId[R.canon(n)]
	return row and row.name or nil
end

function R.namePt(n)
	local row = byId[R.canon(n)]
	return row and row.pt or nil
end

function R.color(n)
	local row = byId[R.canon(n)]
	return row and row.color or nil
end

-- the entry of a per-rarity table (an array in rank order, Common .. Divine and, where the table has one, Unique) for any
-- number; `default` when none. A table shorter than the rank uses its last entry.
function R.at(tbl, n, default)
	local rank = R.rank(n)
	if rank < 1 or type(tbl) ~= "table" or #tbl == 0 then
		return default
	end
	local v = tbl[math.min(rank, #tbl)]
	if v == nil then
		return default
	end
	return v
end

-- the names of the stored rarities in order: {"Common", "Uncommon", "Magic", "Rare", "Legendary", "Divine"} (the list
-- the crafting bench, the salvage window and the gamble window show; Unique is not one a craft can give)
function R.storedNames()
	local out = {}
	for i = 1, R.STORED do
		out[i] = R.list[i].name
	end
	return out
end

-- the stored ids in order: {1, 2, 3, 4, 5, 10}
function R.storedIds()
	local out = {}
	for i = 1, R.STORED do
		out[i] = R.list[i].id
	end
	return out
end

-- rarity thresholds ("Legendary and up", "from Divine"): true when `n` is at least `min`, both read through the mapping
function R.atLeast(n, min)
	return R.rank(n) >= R.rank(min) and R.rank(n) > 0
end

-- ---------------------------------------------------------------------------------------------------------------
-- stock roll
-- ---------------------------------------------------------------------------------------------------------------
-- The base server rolls the rarity of a gear drop in data/scripts/eventcallbacks/monster/default_onDropLoot.lua
-- (rollRarity): `rollChance` percent get a rarity at all, then every entry in order is tried with its own chance and the
-- first hit wins. tools/patch_base_events.py step 17 makes that function read this list instead of the base's 15 rows.
-- The share of the entries after the first is smaller than the chance shows (`math.random(100) <= chance`, whole
-- percent): Common 10.5 %, Uncommon 8.3 %, Magic 6.1 %, Rare 4.5 %, Legendary 2.8 %, Divine 0.38 % of all gear drops
-- (43 % got a rarity before, 33 % do now; README "Item rarities").
R.stockRollChance = 70
R.stockRolls = {
	{id = 1, chance = 15.0},
	{id = 2, chance = 14.0},
	{id = 3, chance = 12.0},
	{id = 4, chance = 10.0},
	{id = 5, chance = 7},
	{id = 10, chance = 1}
}

return R
