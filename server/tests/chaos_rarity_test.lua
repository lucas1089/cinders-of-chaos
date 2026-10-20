-- Run from the server/ folder: luajit tests/chaos_rarity_test.lua (and lua5.3; CI runs both)
-- The seven item rarities (data/lib/chaos_rarity.lua, owner item 87): names, order, colours, the mapping of the 15 old ids,
-- the per-rarity tables of the other systems, and the login migration (rarity_migrate_core.lua).
local fails, checks = 0, 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		fails = fails + 1
		print("FAIL " .. (m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
	end
end

dofile("data/lib/chaos_rarity.lua")
local R = ChaosRarity

-- ---------------------------------------------------------------- exactly seven
eq(R.COUNT, 7, "seven rarities")
eq(#R.list, 7, "seven rows")
local want = {"Common", "Uncommon", "Magic", "Rare", "Legendary", "Divine", "Unique"}
local wantPt = {"Comum", "Incomum", "Mágica", "Rara", "Lendária", "Divina", "Única"}
for i, row in ipairs(R.list) do
	eq(row.name, want[i], "name " .. i)
	eq(row.pt, wantPt[i], "pt-BR name " .. i)
	eq(row.rank, i, "rank " .. i)
	eq(row.color:match("^#%x%x%x%x%x%x$") ~= nil, true, "colour of " .. row.name)
end
eq(R.list[7].unique, true, "the seventh is Unique") eq(R.STORED, 6, "six can be stored on an item")
eq(table.concat(R.storedNames(), ","), "Common,Uncommon,Magic,Rare,Legendary,Divine", "stored names in order")
eq(table.concat(R.storedIds(), ","), "1,2,3,4,5,10", "stored ids in order")

-- ---------------------------------------------------------------- the mapping of the 15 old rarities
local map = {[1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 5, [6] = 5, [7] = 5, [8] = 5, [9] = 5, [10] = 10, [11] = 10, [12] = 10,
	[13] = 10, [14] = 10, [15] = 10}
local oldNames = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Exotic", "Mythic", "Chaos", "Eternal", "Divine",
	"Phantasmal", "Celestial", "Cosmic", "Abyssal", "Transcendent"}
for old = 1, 15 do
	eq(R.canon(old), map[old], "old id " .. old .. " -> " .. map[old])
	eq(R.canon(R.canon(old)), R.canon(old), "idempotent at " .. old)
	eq(R.legacyNames[old], oldNames[old], "the old name of " .. old)
	if not R.byKey[oldNames[old]:lower()] then -- a name of today ("Rare") means today's rarity; the others are old names
		eq(R.idOf(oldNames[old]), map[old], "the old name " .. oldNames[old] .. " reads as a stored id")
	end
end
eq(R.canon(0), 0, "none") eq(R.canon(-3), 0) eq(R.canon(16), 16, "Unique keeps its list id") eq(R.canon(99), 0, "out of range") eq(R.canon("7"), 5)
eq(R.canon(nil), 0) eq(R.canon("junk"), 0) eq(R.canon(7.9), 5, "a fraction floors")
eq(R.rank(1), 1) eq(R.rank(3), 3) eq(R.rank(5), 5) eq(R.rank(10), 6) eq(R.rank(15), 6) eq(R.rank(9), 5) eq(R.rank(16), 7) eq(R.rank(0), 0)
eq(R.idOfRank(6), 10) eq(R.idOfRank(7), 16) eq(R.idOfRank(0), 0) eq(R.idOfRank(8), 0)
for rank = 1, 6 do
	eq(R.rank(R.idOfRank(rank)), rank, "rank round trip " .. rank)
end
eq(R.isStored(10), true) eq(R.isStored(7), false) eq(R.isStored(0), false) eq(R.isStored(16), false)
eq(R.isLegacy(7), true) eq(R.isLegacy(5), false) eq(R.isLegacy(10), false) eq(R.isLegacy(15), true) eq(R.isLegacy(0), false)
eq(R.name(12), "Divine") eq(R.name(8), "Legendary") eq(R.name(3), "Magic") eq(R.name(0), nil) eq(R.namePt(10), "Divina")
eq(R.color(10), "#c8e8ff") eq(R.color(7), R.color(5), "an old Mythic is drawn like a Legendary")
-- thresholds: monotone, so "Legendary and up" is `id >= 5` for the stored ids and for the old ones alike
eq(R.atLeast(5, 5), true) eq(R.atLeast(4, 5), false) eq(R.atLeast(7, 5), true, "old Mythic is Legendary") eq(R.atLeast(9, 10), false)
eq(R.atLeast(10, 10), true) eq(R.atLeast(12, 10), true) eq(R.atLeast(0, 1), false)
local last = 0
for id = 1, 15 do
	assert(R.rank(id) >= last, "rank never falls with the old id")
	last = R.rank(id)
end
-- a per-rarity table by place
eq(R.at({10, 20, 30, 40, 50, 60}, 10), 60) eq(R.at({10, 20, 30, 40, 50, 60}, 7), 50) eq(R.at({10, 20}, 5), 20, "short table: its last")
eq(R.at({1, 2, 3}, 0, "d"), "d", "none: the default")

-- ---------------------------------------------------------------- the stock roll
local total = 0
for i, row in ipairs(R.stockRolls) do
	eq(row.id, R.idOfRank(i), "stock row " .. i)
	total = total + row.chance
end
eq(#R.stockRolls, 6, "six stock rows") eq(R.stockRollChance, 70)
local left, odds = R.stockRollChance / 100, {}
for i, row in ipairs(R.stockRolls) do
	odds[i] = left * row.chance / 100
	left = left * (1 - row.chance / 100)
end
local rolled = 0
for i = 1, 6 do rolled = rolled + odds[i] end
assert(rolled > 0.30 and rolled < 0.36, "about a third of the gear drops carry a rarity: " .. rolled)
assert(odds[6] > 0.003 and odds[6] < 0.005, "Divine 0.38% of the drops: " .. odds[6])
assert(odds[5] > 0.025 and odds[5] < 0.031, "Legendary 2.8% of the drops: " .. odds[5])
for i = 2, 6 do
	assert(odds[i] < odds[i - 1], "each rarity rarer than the one below")
end
local lootCfg = dofile("data/scripts/chaos/loot_config.lua")
for i, c in ipairs(lootCfg.gear.stockChances) do
	eq(c, R.stockRolls[i].chance, "loot_config.lua stockChances " .. i .. " matches the patched base roll")
end

-- ---------------------------------------------------------------- every per-rarity table has the right length
dofile("data/lib/chaos_gems_config.lua")
dofile("data/lib/chaos_item_mods.lua")
local M = ChaosItemMods
eq(#M.config.rarity.count, 6, "mod counts") eq(#M.config.rarity.sides, 6, "sides") eq(#M.config.bind.max, 6, "binds")
eq(table.concat(M.config.rarity.count, ","), "1,2,3,4,5,6", "1 to 6 modifiers")
eq(table.concat(M.config.rarity.sides, ","), "1,1,2,2,3,3")
local salvage = dofile("data/scripts/chaos/salvage_config.lua")
eq(#salvage.baseShards, 6, "shards") eq(#salvage.orbChance, 6, "orb chances")
local prices = dofile("data/lib/chaos_item_prices_data.lua")
eq(#prices.rarityMult, 6, "price multipliers")
local gemsCfg = dofile("data/lib/chaos_gems_config.lua")
eq(#gemsCfg.rarityMax, 7, "sockets (no rarity + six)") eq(#gemsCfg.dropWeights, 6, "socket drop weights")

-- ---------------------------------------------------------------- the migration (rarity_migrate_core.lua)
dofile("data/scripts/chaos/rarity_migrate_core.lua")
local K = ChaosRarityMigrateCore
local function item(attrs)
	local it = {a = attrs}
	return it, function(k) return it.a[k] end, function(k, v) it.a[k] = v end
end
for old = 1, 15 do
	local it, get, set = item({rarity = old, rarity_swordSkill = 3, ct_rarity_swordskill = 4, chaos_ilvl = 77, chaos_mod_dodge = 2, chaos_quality = 9})
	local changed = K.fixItem(get, set)
	eq(it.a.rarity, map[old], "migrated " .. old)
	eq(changed, old ~= map[old] and old or nil, "reports the old id only when it changed (" .. old .. ")")
	eq(it.a.rarity_swordSkill, 3, "modifier value kept") eq(it.a.ct_rarity_swordskill, 4, "tier kept") eq(it.a.chaos_ilvl, 77, "item level kept")
	eq(it.a.chaos_mod_dodge, 2, "Chaos modifier kept") eq(it.a.chaos_quality, 9, "quality kept")
	eq(K.fixItem(get, set), nil, "a second run changes nothing (" .. old .. ")")
end
local none, get0, set0 = item({})
eq(K.fixItem(get0, set0), nil, "no rarity: untouched") eq(none.a.rarity, nil)
local shielded, getS, setS = item({rarity = "9"})
eq(K.fixItem(getS, setS), nil, "a drop's rarity as text is left to the shield") eq(shielded.a.rarity, "9")
local err, getE, setE = item({})
eq(K.fixItem(function() error("boom") end, setE), nil, "a failing read is skipped")
eq(K.summary({[7] = 2, [13] = 1}), "Mythic x2, Cosmic x1") eq(K.summary({}), nil)

if fails > 0 then
	error(fails .. " failure(s) of " .. checks)
end
print("chaos_rarity_test: " .. checks .. " checks OK")
