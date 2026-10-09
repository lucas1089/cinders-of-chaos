-- Chaos item modifiers (ChaosItemMods): modifier types the engine's rarity roll does not have (attack speed, movement
-- speed, damage to elites and bosses, life / mana on kill, dodge, reflect, thorns, experience, gold / item / rarity
-- find, healing done, damage taken from monsters).
--
-- This file is the pure part (no engine calls apart from reading and writing item attributes): the catalogue, the
-- value tiers per rarity, the rolls, the caps, the description text and the per-player totals. It is loaded by
-- data/lib/chaos_crafting.lua (which writes the description and rolls the modifiers of new drops and recreated items)
-- and by data/scripts/chaos/item_mods.lua (which applies the totals of the equipped items to the player).
-- Tested by server/tests/item_mods_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Storage on the item: one custom attribute per modifier, "chaos_mod_<key>" = whole number (e.g. chaos_mod_movespeed = 4).
-- The description shows it after the engine's modifiers ("Level: 57, Physical +2%, Movement Speed +4%").
-- Attack speed is local to the weapon: the weapon's own attack interval (item attribute ITEM_ATTRIBUTE_ATTACK_SPEED,
-- which the engine uses for whoever wields it and the look text shows as "Atk Spd") is set from its base interval.

ChaosItemMods = ChaosItemMods or {}
local M = ChaosItemMods

M.PREFIX = "chaos_mod_"

-- ---------------------------------------------------------------------------------------------------------------
-- configuration
-- ---------------------------------------------------------------------------------------------------------------
-- kinds of items (M.kindOf): weapon, shield, helmet, armor, legs, boots, jewel (amulet or ring), other (gloves, belts..)
-- tiers: value range per modifier tier. Tier = ceil(rarity / 3): Common-Rare 1, Epic-Exotic 2, Mythic-Eternal 3,
-- Divine-Celestial 4, Cosmic-Transcendent 5. cap: the most a character gets from all equipped items together.
-- fmt: "pct" = "+N%", "flat" = "+N", "less" = "-N%". weight: chance to be picked among the modifiers an item may get.
-- The numbers sit next to the passive tree's: a tree node gives +1% to +3% of a stat, the tree's speed tops out at
-- +80 flat, its experience at about +15%.
M.config = {
	mods = {
		{key = "attackspeed", label = "Attack Speed", fmt = "pct", weight = 10, cap = 15, kinds = {weapon = true},
			tiers = {{2, 3}, {3, 5}, {4, 6}, {5, 8}, {7, 10}}},
		{key = "movespeed", label = "Movement Speed", fmt = "pct", weight = 10, cap = 12, kinds = {boots = true},
			tiers = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}}},
		{key = "bossdamage", label = "Damage to Elites and Bosses", fmt = "pct", weight = 8, cap = 30,
			kinds = {weapon = true, jewel = true}, tiers = {{2, 4}, {3, 6}, {5, 8}, {6, 10}, {8, 12}}},
		{key = "lifeonkill", label = "Life on Kill", fmt = "flat", weight = 10, cap = 300,
			kinds = {weapon = true, jewel = true, helmet = true}, tiers = {{5, 10}, {10, 20}, {20, 40}, {35, 60}, {50, 90}}},
		{key = "manaonkill", label = "Mana on Kill", fmt = "flat", weight = 10, cap = 200,
			kinds = {weapon = true, jewel = true, helmet = true}, tiers = {{3, 6}, {6, 12}, {12, 25}, {20, 40}, {30, 60}}},
		{key = "dodge", label = "Dodge", fmt = "pct", weight = 6, cap = 10,
			kinds = {armor = true, legs = true, boots = true, shield = true, other = true},
			tiers = {{1, 1}, {1, 2}, {1, 2}, {2, 3}, {2, 4}}},
		{key = "reflect", label = "Reflect Damage", fmt = "pct", weight = 6, cap = 15, kinds = {armor = true, shield = true},
			tiers = {{1, 2}, {2, 3}, {2, 4}, {3, 5}, {4, 6}}},
		{key = "thorns", label = "Thorns", fmt = "flat", weight = 8, cap = 250,
			kinds = {armor = true, shield = true, legs = true}, tiers = {{3, 8}, {8, 15}, {15, 30}, {25, 50}, {40, 80}}},
		{key = "experience", label = "Experience", fmt = "pct", weight = 6, cap = 15, kinds = {helmet = true, jewel = true},
			tiers = {{1, 2}, {1, 3}, {2, 4}, {3, 5}, {4, 6}}},
		{key = "goldfind", label = "Gold Find", fmt = "pct", weight = 8, cap = 40,
			kinds = {helmet = true, jewel = true, legs = true, other = true}, tiers = {{2, 4}, {3, 6}, {4, 8}, {6, 10}, {8, 14}}},
		{key = "itemfind", label = "Item Find", fmt = "pct", weight = 6, cap = 25, kinds = {helmet = true, jewel = true},
			tiers = {{1, 2}, {2, 3}, {2, 4}, {3, 6}, {4, 8}}},
		{key = "rarityfind", label = "Rarity Find", fmt = "pct", weight = 6, cap = 40, kinds = {helmet = true, jewel = true},
			tiers = {{2, 4}, {3, 6}, {5, 8}, {6, 10}, {8, 14}}},
		{key = "healing", label = "Healing Done", fmt = "pct", weight = 8, cap = 20,
			kinds = {weapon = true, shield = true, jewel = true}, tiers = {{1, 2}, {2, 3}, {3, 5}, {4, 6}, {5, 8}}},
		{key = "monsterreduction", label = "Damage Taken from Monsters", fmt = "less", weight = 8, cap = 12,
			kinds = {armor = true, helmet = true, legs = true, shield = true}, tiers = {{1, 1}, {1, 2}, {1, 2}, {2, 3}, {2, 4}}}
	},
	raritiesPerTier = 3, -- tier = ceil(rarity / 3)
	levelsPerTier = 30, -- item levels of a tier window (the engine gives rarity r levels 10r-9 .. 10r)
	-- item level inside the tier's window raises the low end of the roll by up to this share of the range
	levelPull = 0.5,
	-- new drops (Chaos loot layer) and items the Transmutation, Alchemy, Chaos and Divine Orbs make: percent chance per
	-- rarity of one Chaos modifier, then of a second one; never above the rarity's modifier maximum
	dropChance = {8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 33, 36, 40},
	secondChance = {0, 0, 0, 0, 0, 5, 6, 7, 8, 10, 12, 14, 16, 18, 20},
	-- weapons without an attack interval of their own swing at the vocation's speed; the engine falls back to this
	defaultAttackSpeed = 2000,
	minAttackSpeed = 100 -- the engine's floor for the attribute
}

M.byKey = {}
for i, def in ipairs(M.config.mods) do
	def.index = i
	M.byKey[def.key] = def
end

-- random source of drops (the crafting orbs pass their own); tests replace it
M.random = function(a, b)
	return math.random(a, b)
end

-- ---------------------------------------------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------------------------------------------
local floor = math.floor

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function num(v)
	if type(v) == "number" then
		return v
	end
	if type(v) == "userdata" or type(v) == "table" then
		local ok, n = pcall(function() return tonumber(v.value) end)
		return ok and n or nil
	end
	return tonumber(v)
end

local function hasBit(value, b)
	return floor((value or 0) / b) % 2 == 1
end

local function typeOf(item)
	local ok, it = pcall(function() return ItemType(item:getId()) end)
	return ok and it or nil
end

local function typeNumber(it, method)
	local ok, v = pcall(function() return it[method](it) end)
	return ok and tonumber(v) or 0
end

function M.attr(key)
	return M.PREFIX .. key
end

-- ---------------------------------------------------------------------------------------------------------------
-- kinds
-- ---------------------------------------------------------------------------------------------------------------
local SLOTP = {head = 1, necklace = 2, armor = 8, legs = 64, feet = 128, ring = 256}

-- kind of an ItemType (or nil when it is no equipment)
function M.kindOfType(it)
	if not it then
		return nil
	end
	local weapon = typeNumber(it, "getWeaponType")
	if weapon == (WEAPON_SHIELD or 4) then
		return "shield"
	end
	if weapon ~= 0 and weapon ~= (WEAPON_AMMO or 7) then
		return "weapon"
	end
	local slots = typeNumber(it, "getSlotPosition")
	if hasBit(slots, SLOTP.head) then
		return "helmet"
	elseif hasBit(slots, SLOTP.armor) then
		return "armor"
	elseif hasBit(slots, SLOTP.legs) then
		return "legs"
	elseif hasBit(slots, SLOTP.feet) then
		return "boots"
	elseif hasBit(slots, SLOTP.necklace) or hasBit(slots, SLOTP.ring) then
		return "jewel"
	elseif slots ~= 0 then
		return "other"
	end
	return nil
end

function M.kindOf(item)
	return M.kindOfType(typeOf(item))
end

function M.allowed(def, kind)
	return kind ~= nil and def.kinds[kind] == true
end

-- ---------------------------------------------------------------------------------------------------------------
-- tiers and rolls
-- ---------------------------------------------------------------------------------------------------------------
function M.tierOf(rarity)
	rarity = clamp(floor(tonumber(rarity) or 1), 1, 15)
	return math.ceil(rarity / M.config.raritiesPerTier)
end

-- the range a modifier rolls in for an item of this rarity and item level: {lo, hi}
function M.range(def, rarity, level)
	local t = M.tierOf(rarity)
	local r = def.tiers[t] or def.tiers[#def.tiers]
	local lo, hi = r[1], r[2]
	local per = M.config.levelsPerTier
	local first = (t - 1) * per + 1
	local frac = clamp(((tonumber(level) or 0) - first) / (per - 1), 0, 1)
	lo = lo + floor((hi - lo) * frac * M.config.levelPull + 1e-9)
	return {lo, hi}
end

function M.rollValue(def, rarity, level, rand)
	local r = M.range(def, rarity, level)
	return (rand or M.random)(r[1], r[2])
end

-- ---------------------------------------------------------------------------------------------------------------
-- reading and writing an item
-- ---------------------------------------------------------------------------------------------------------------
function M.value(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(M.attr(key)) end)
	return ok and floor(num(v) or 0) or 0
end

-- the Chaos modifiers of an item in catalogue order: {key, value, def, label}
function M.read(item)
	local out = {}
	for _, def in ipairs(M.config.mods) do
		local v = M.value(item, def.key)
		if v ~= 0 then
			out[#out + 1] = {key = def.key, value = v, def = def, label = def.label}
		end
	end
	return out
end

function M.text(key, value)
	local def = M.byKey[key]
	if not def then
		return tostring(key)
	end
	value = floor(tonumber(value) or 0)
	if def.fmt == "flat" then
		return string.format("%s +%d", def.label, value)
	elseif def.fmt == "less" then
		return string.format("%s -%d%%", def.label, value)
	end
	return string.format("%s +%d%%", def.label, value)
end

-- one line, "Attack Speed +5%; Life on Kill +12" (loot filter tooltips)
function M.summary(item)
	local parts = {}
	for _, m in ipairs(M.read(item)) do
		parts[#parts + 1] = M.text(m.key, m.value)
	end
	return table.concat(parts, "; ")
end

-- the weapon's attack interval for an attack speed bonus (pct) from its base interval
function M.attackInterval(base, pct)
	base = tonumber(base) or 0
	if base <= 0 then
		base = M.config.defaultAttackSpeed
	end
	return math.max(M.config.minAttackSpeed, floor(base * (100 - (tonumber(pct) or 0)) / 100 + 1e-9))
end

-- keep the weapon's attack interval in line with its attack speed modifier and its topaz gems (chaos_gems.lua: both
-- together at most the gems' attackspeed cap)
function M.syncAttackSpeed(item)
	if not ITEM_ATTRIBUTE_ATTACK_SPEED then
		return
	end
	local pct = M.value(item, "attackspeed")
	if ChaosGems and ChaosGems.attackSpeedOf then
		local gems = ChaosGems.attackSpeedOf(item)
		if gems > 0 then
			local cap = ChaosGems.config.effects.attackspeed.cap or 20
			pct = math.min(math.max(pct, cap), pct + gems) -- the modifier alone may sit at its own cap
		end
	end
	if pct > 0 then
		local it = typeOf(item)
		item:setAttribute(ITEM_ATTRIBUTE_ATTACK_SPEED, M.attackInterval(it and typeNumber(it, "getAttackSpeed") or 0, pct))
	else
		pcall(function() item:removeAttribute(ITEM_ATTRIBUTE_ATTACK_SPEED) end)
	end
end

-- send the item again to the clients that see it (engine patch 0003, item:sendUpdate): a client that reads item custom
-- attributes (rarity frame, tooltip version) keeps the old ones otherwise, because the engine sends an item only when
-- it moves or its id or count changes. Does nothing without the patch or outside a container / inventory / tile.
function M.sendUpdate(item)
	if item and type(item.sendUpdate) == "function" then
		pcall(item.sendUpdate, item)
	end
end

function M.set(item, key, value)
	item:setCustomAttribute(M.attr(key), floor(value))
	if key == "attackspeed" then
		M.syncAttackSpeed(item)
	end
end

function M.remove(item, key)
	item:removeCustomAttribute(M.attr(key))
	if key == "attackspeed" then
		M.syncAttackSpeed(item)
	end
end

function M.clear(item)
	for _, m in ipairs(M.read(item)) do
		M.remove(item, m.key)
	end
end

-- modifiers this item could still get: list of {entry = def, weight}
function M.addable(item)
	local kind = M.kindOf(item)
	local out = {}
	for _, def in ipairs(M.config.mods) do
		if M.allowed(def, kind) and M.value(item, def.key) == 0 then
			out[#out + 1] = {entry = def, weight = def.weight}
		end
	end
	return out
end

local function pick(rows, rand)
	local total = 0
	for _, r in ipairs(rows) do
		total = total + r.weight
	end
	if total <= 0 then
		return nil
	end
	local roll, acc = rand(1, total), 0
	for _, r in ipairs(rows) do
		acc = acc + r.weight
		if roll <= acc then
			return r.entry
		end
	end
	return rows[#rows].entry
end
M.pick = pick

-- add one random modifier the item may get; returns {key, value} or nil
function M.addRandom(item, rarity, level, rand)
	rand = rand or M.random
	local def = pick(M.addable(item), rand)
	if not def then
		return nil
	end
	local value = M.rollValue(def, rarity, level, rand)
	M.set(item, def.key, value)
	return {key = def.key, value = value, def = def, label = def.label}
end

-- how many Chaos modifiers a new item of this rarity gets (before the free slots limit it)
function M.rollCount(rarity, rand)
	rand = rand or M.random
	local r = clamp(floor(tonumber(rarity) or 0), 0, 15)
	if r < 1 then
		return 0
	end
	local n = 0
	if rand(1, 100) <= (M.config.dropChance[r] or 0) then
		n = 1
		if rand(1, 100) <= (M.config.secondChance[r] or 0) then
			n = 2
		end
	end
	return n
end

-- roll the Chaos modifiers of a new item (drop or orb). free = slots left under the rarity's maximum.
-- returns the list of added modifiers
function M.rollNew(item, rarity, level, free, rand)
	rand = rand or M.random
	local added = {}
	local n = math.min(M.rollCount(rarity, rand), math.max(0, free or 0))
	for _ = 1, n do
		local m = M.addRandom(item, rarity, level, rand)
		if not m then
			break
		end
		added[#added + 1] = m
	end
	return added
end

-- ---------------------------------------------------------------------------------------------------------------
-- totals of a character
-- ---------------------------------------------------------------------------------------------------------------
-- sum of the Chaos modifiers of the given items, each capped: {key -> value} (every key present, 0 when none)
function M.totals(items)
	local t = {}
	for _, def in ipairs(M.config.mods) do
		t[def.key] = 0
	end
	for _, item in ipairs(items or {}) do
		for _, m in ipairs(M.read(item)) do
			t[m.key] = t[m.key] + m.value
		end
	end
	for _, def in ipairs(M.config.mods) do
		t[def.key] = clamp(t[def.key], 0, def.cap)
	end
	return t
end

-- ---------------------------------------------------------------------------------------------------------------
-- effect maths (used by item_mods.lua, tested)
-- ---------------------------------------------------------------------------------------------------------------
-- movement speed: percent of the base speed, whole points
function M.speedBonus(baseSpeed, pct)
	return floor((tonumber(baseSpeed) or 0) * (tonumber(pct) or 0) / 100 + 1e-9)
end

-- a damage value scaled by percent (rounding toward zero; the value may be negative)
function M.scale(value, pct)
	local a = floor(math.abs(value) * (100 + pct) / 100 + 1e-6)
	return value < 0 and -a or a
end

-- the share of a hit that is reflected (whole points, of the damage that lands)
function M.reflected(landed, pct)
	return floor(math.max(0, tonumber(landed) or 0) * (tonumber(pct) or 0) / 100 + 1e-9)
end

-- experience with the bonus
function M.experience(exp, pct)
	return floor((tonumber(exp) or 0) * (100 + (tonumber(pct) or 0)) / 100 + 1e-9)
end

return M
