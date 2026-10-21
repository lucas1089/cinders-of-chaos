-- chaos_jewelry.lua: rings and necklaces are ordinary equipment (server/README.md "Rings and necklaces as gear").
-- Loaded with
--     ChaosJewelry = ChaosJewelry or dofile("data/lib/chaos_jewelry.lua")
-- by data/lib/chaos_crafting.lua (C.isGear), data/scripts/chaos/loot.lua (L.isGearId, the rarity strip) and
-- data/scripts/chaos/jewelry.lua (the loot rows, old copies). server/tools/patch_base_jewelry.py reads `consumable`
-- below (install step `jewelry`). Plain Lua, no engine calls at load; tested by server/tests/jewelry_test.lua.
-- Lua 5.1 / LuaJIT and 5.3.
--
-- Owner request 2026-10-22: "faça rings e necklaces iguais a equips normais. pra equipar, com affixo e suffixo" and
-- "distribua esses rings e necklaces na loot pool também".
--
-- What the base had: most rings changed id when worn (transformEquipTo: "sword ring" -> "sword ring (sword fighting
-- +4)") and the worn id decayed to nothing (duration, decayTo 0); most amulets had charges and vanished at 0. A rolled
-- copy (rarity, prefixes, suffixes, sockets) vanished with them, and the unworn id had no stats, so the loot layer never
-- saw it as gear. patch_base_jewelry.py makes every ring and necklace of items.xml permanent equipment (the worn id's
-- stats on the unworn id, no transformation, no duration, no charges), except the consumables below.
--
-- The consumables stay as the base has them and never carry a rarity or modifiers: their effect is a short burst that
-- would break the game worn for ever (invisibility, magic shield, haste, 80% absorbs, 20% physical and magic, death
-- protection). The loot layer takes a rarity the stock roll gave one off again (loot.lua L.stripStackableRarity).

local J = {}

-- id -> what it is (the unworn and the worn id of a pair are both listed)
J.consumable = {
	[2164] = "might ring", -- 20 charges, 20% physical and magic; one at a time (the might ring rule)
	[2165] = "stealth ring", [2202] = "stealth ring (worn)", -- invisibility
	[2167] = "energy ring", [2204] = "energy ring (worn)", -- magic shield
	[2169] = "time ring", [2206] = "time ring (worn)", -- haste
	[2213] = "dwarven ring", [2215] = "dwarven ring (worn)", -- drunkenness immunity
	[2173] = "amulet of loss", -- death protection
	[2197] = "stone skin amulet", -- 5 charges, 80% physical and death
	[10218] = "bonfire amulet", [10219] = "sacred tree amulet", [10220] = "leviathan's amulet",
	[10221] = "shockwave amulet" -- 5 charges, 60% physical and 40% of an element
}

function J.isConsumable(id)
	return J.consumable[tonumber(id) or 0] ~= nil
end

-- the loot bases (monster loot, jewelry.lua): permanent after the install step, no class lock in movements.xml.
-- level: the hunting level from which a monster drops it (the equip level where the base has one).
-- look: the client id of its own look in pair 35 (client/tools/sprites/gen_jewelry_art.py, client/MANIFEST.md
-- "Jewelry looks (pair 35)"); server/tools/patch_base_jewelry.py points the items.otb node at it (--stock-looks keeps
-- the stock look, for a client on pair 34 or older). stock: the base item's own client id (items.otb of the base)
J.bases = {
	ring = {
		{id = 2168, level = 8, name = "life ring", look = 38612, stock = 3052},
		{id = 2166, level = 20, name = "power ring", look = 38613, stock = 3050},
		{id = 2207, level = 20, name = "sword ring", look = 38614, stock = 3091},
		{id = 2208, level = 20, name = "axe ring", look = 38615, stock = 3092},
		{id = 2209, level = 20, name = "club ring", look = 38616, stock = 3093},
		{id = 2214, level = 40, name = "ring of healing", look = 38617, stock = 3098},
		{id = 6300, level = 70, name = "death ring", look = 38618, stock = 6299},
		{id = 18408, level = 120, name = "prismatic ring", look = 38619, stock = 16114},
		{id = 28691, level = 150, name = "ring of temptation", look = 38620, stock = 26035},
		{id = 26808, level = 220, name = "butterfly ring", look = 38621, stock = 24152}
	},
	necklace = {
		{id = 2172, level = 8, name = "bronze amulet", look = 38622, stock = 3056},
		{id = 2200, level = 8, name = "protection amulet", look = 38623, stock = 3084},
		{id = 2161, level = 25, name = "strange talisman", look = 38624, stock = 3045},
		{id = 2170, level = 25, name = "silver amulet", look = 38625, stock = 3054},
		{id = 2201, level = 25, name = "dragon necklace", look = 38626, stock = 3085},
		{id = 2198, level = 30, name = "elven amulet", look = 38627, stock = 3082},
		{id = 2199, level = 30, name = "garlic necklace", look = 38628, stock = 3083},
		{id = 7887, level = 60, name = "terra amulet", look = 38629, stock = 814},
		{id = 7888, level = 60, name = "glacier amulet", look = 38630, stock = 815},
		{id = 7889, level = 60, name = "lightning pendant", look = 38631, stock = 816},
		{id = 7890, level = 60, name = "magma amulet", look = 38632, stock = 817},
		{id = 24851, level = 70, name = "onyx pendant", look = 38633, stock = 22195},
		{id = 15403, level = 120, name = "necklace of the deep", look = 38634, stock = 13990},
		{id = 18402, level = 150, name = "gill necklace", look = 38635, stock = 16108},
		{id = 18407, level = 150, name = "prismatic necklace", look = 38636, stock = 16113},
		{id = 27652, level = 180, name = "exotic amulet", look = 38637, stock = 24996},
		{id = 26807, level = 200, name = "foxtail amulet", look = 38638, stock = 24151},
		{id = 27251, level = 220, name = "rainbow necklace", look = 38639, stock = 24595},
		{id = 27215, level = 250, name = "cobra amulet", look = 38640, stock = 24559}
	}
}

-- uniques that sat on consumable bases (the worn time ring decayed and turned back into a time ring when taken off;
-- the 5-charge amulets vanished and gave 60% physical absorb) have bases of their own: new server ids 41640-41642
-- (reserved 41640-41659), copies of the stock node `copy` in items.otb (same client id and flags), with the unique's
-- stats that no item attribute can hold (chaos_unique_specs.lua `skipped`) as item type stats in items.xml and
-- Equip / DeEquip entries (patch_base_jewelry.py). `from`: the ids old copies have; `unique`: the unique's name.
-- chaos_items.xml and chaos_unique_items.lua name the new ids.
J.uniqueBases = {
	{id = 41640, copy = 2206, from = {2206, 2169}, slot = "ring", name = "ember ring", unique = "Ring of the Last Ember"},
	{id = 41641, copy = 10218, from = {10218}, slot = "necklace", name = "cinder heart amulet",
		unique = "Heart of Cinders"},
	{id = 41642, copy = 10221, from = {10221}, slot = "necklace", name = "heartbleed pendant",
		unique = "Heartbleed Pendant"}
}

-- the new id of an old unique copy on a consumable base, or nil. isUnique: the copy carries the chaos_unique marker;
-- name: its name attribute (a copy made before the marker existed)
function J.uniqueTarget(id, isUnique, name)
	id = tonumber(id) or 0
	for _, b in ipairs(J.uniqueBases) do
		for _, from in ipairs(b.from) do
			if from == id and (isUnique or name == b.unique) then
				return b.id
			end
		end
	end
	return nil
end

J.config = {
	-- chance per kill (per 100000, the loot unit) that one piece of the kind drops, shared by the eligible bases. 75 is
	-- the share of one slot in the equipment sets of pair 28 (600 per kill over about eight slots, chaos_gear_sets.lua):
	-- rings and necklaces each get one slot's worth, on top of the base loot tables (which already list rings and
	-- amulets). Bosses of the bounty pool: one slot's share of the sets' boss chance (15000 / 8)
	monsterChance = {ring = 75, necklace = 75},
	bossChance = {ring = 1900, necklace = 1900},
	-- no single row below this (a monster with many eligible bases)
	minChance = 5,
	-- a base is eligible when its level is at most the monster's level + above and at least its level - below; a
	-- monster above every window drops the `fallback` highest bases (the bases stop at 250, the item level and the
	-- rarity carry the power beyond: chaos_item_mods.lua)
	window = {below = 200, above = 50},
	fallback = 3
}

local KINDS = {"ring", "necklace"}
J.KINDS = KINDS

-- the bases of one kind a monster of hunting level `level` may drop (by level, then id)
function J.eligible(kind, level, cfg)
	cfg = cfg or J.config
	level = tonumber(level) or 0
	local w = cfg.window
	local inWindow, below = {}, {}
	for _, b in ipairs(J.bases[kind] or {}) do
		if b.level <= level + w.above then
			below[#below + 1] = b
			if b.level >= level - w.below then
				inWindow[#inWindow + 1] = b
			end
		end
	end
	if #inWindow > 0 then
		return inWindow
	end
	local out = {}
	for i = math.max(1, #below - cfg.fallback + 1), #below do
		out[#out + 1] = below[i]
	end
	return out
end

-- the loot rows {monster name, item id, chance per 100000} of a bounty pool ({hunt = {...}, bosses = {...}}, the
-- entries {name, level, exp, health, ...} of data/scripts/chaos/bounty_pool.lua). levelOf(entry) -> hunting level
-- (pace_core.lua P.entryLevel); without it the pool level.
function J.lootRows(pool, levelOf, cfg)
	cfg = cfg or J.config
	levelOf = levelOf or function(e) return tonumber(e.level) or 1 end
	local rows = {}
	for _, group in ipairs({{pool and pool.hunt or {}, cfg.monsterChance}, {pool and pool.bosses or {}, cfg.bossChance}}) do
		for _, e in ipairs(group[1]) do
			local level = levelOf(e)
			for _, kind in ipairs(KINDS) do
				local list = J.eligible(kind, level, cfg)
				local total = tonumber(group[2][kind]) or 0
				if #list > 0 and total > 0 then
					local each = math.max(cfg.minChance, math.floor(total / #list))
					for _, b in ipairs(list) do
						rows[#rows + 1] = {e.name, b.id, each}
					end
				end
			end
		end
	end
	return rows
end

-- per kind: the summed chance per kill (per 100000) of one monster of `level` (the report and the tests)
function J.chancePerKill(level, boss, cfg)
	cfg = cfg or J.config
	local out = {}
	for _, kind in ipairs(KINDS) do
		local rows = J.lootRows({hunt = boss and {} or {{name = "x", level = level}},
			bosses = boss and {{name = "x", level = level}} or {}}, nil, cfg)
		local sum = 0
		for _, r in ipairs(rows) do
			for _, b in ipairs(J.bases[kind]) do
				if b.id == r[2] then
					sum = sum + r[3]
				end
			end
		end
		out[kind] = sum
	end
	return out
end

-- ---------------------------------------------------------------- old copies
-- A copy made before the install step keeps the charges or the time left it had (item attributes): the engine would
-- still count its charges down when it absorbs a hit and remove it at 0. normalize takes them off a ring or necklace
-- whose item type has none any more (so never off a consumable, whose type keeps them). `it` is the ItemType;
-- attr = {charges = ITEM_ATTRIBUTE_CHARGES, duration = ITEM_ATTRIBUTE_DURATION}. Returns how many attributes went.
local function call(obj, method, ...)
	if obj == nil or type(obj[method]) ~= "function" then
		return nil
	end
	local ok, v = pcall(obj[method], obj, ...)
	return ok and v or nil
end

function J.isJewelType(it)
	local slots = tonumber(call(it, "getSlotPosition")) or 0
	-- SLOTP_NECKLACE 2, SLOTP_RING 256
	return math.floor(slots / 2) % 2 == 1 or math.floor(slots / 256) % 2 == 1
end

function J.normalize(item, it, attr)
	if not item or not it or not attr then
		return 0
	end
	local id = tonumber(call(item, "getId")) or 0
	if J.isConsumable(id) or not J.isJewelType(it) or call(it, "isStackable") then
		return 0
	end
	local n = 0
	if attr.charges and (tonumber(call(it, "getCharges")) or 0) == 0
			and (tonumber(call(item, "getAttribute", attr.charges)) or 0) > 0 then
		call(item, "removeAttribute", attr.charges)
		n = n + 1
	end
	if attr.duration and (tonumber(call(it, "getDuration")) or 0) == 0
			and (tonumber(call(item, "getAttribute", attr.duration)) or 0) > 0 then
		call(item, "removeAttribute", attr.duration)
		n = n + 1
	end
	return n
end

return J
