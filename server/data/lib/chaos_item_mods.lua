-- Chaos item modifiers (ChaosItemMods): item levels, modifier tiers, the prefix / suffix split and the modifier types
-- the engine's rarity roll does not have (attack speed, movement speed, damage to elites and bosses, life / mana on
-- kill and on hit, dodge, block, reflect, thorns, experience, gold / item / rarity find, healing done, damage taken from
-- monsters, treasure goblin chance, ailment chances, penetration, execute, damage over time, cooldown and mana cost
-- reduction, health regeneration).
--
-- This file is the pure part (no engine calls apart from reading and writing item attributes): the catalogue, the
-- tiers (T1 lowest .. T8 highest) with their item level requirements and roll weights, the item level of a drop from
-- its source, how many modifiers a rarity gets, the caps, the description text and the per-player totals. It is loaded
-- by data/lib/chaos_crafting.lua (which owns the whole roll of an item: the engine's modifier types and these, see
-- ChaosCrafting.forge), by data/scripts/chaos/item_mods.lua (which applies the totals of the equipped items to the
-- player) and by data/spells/chaos/_supports.lua (cooldown and mana cost reduction on casts).
-- Tested by server/tests/item_mods_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible. Overview: server/README.md
-- "Item modifiers".
--
-- Storage on the item:
--   "chaos_mod_<key>" = whole number           one custom attribute per modifier of this file (chaos_mod_movespeed = 4)
--   "ct_<attribute key, lower case>" = 1..8    the tier of a modifier (ct_chaos_mod_movespeed, ct_rarity_swordskill);
--                                              an item from before tiers has none: the tier then follows from the value
--   "chaos_ilvl" = 1..150                      the item level (also on plain gear drops, which have no rarity yet);
--                                              rolled items mirror it into "combatPowerLevel", which the client shows
--   "cb_<attribute key, lower case>" = 1      the modifier is bound (Orb of Binding): Tempering, Unmaking, Excision, Reforging
--                                              and Upheaval skip it; at most config.bind.max of them (chaos_crafting.lua)
--   "cv_<attribute key, lower case>" = number the value rolled inside the tier before the item quality (only on an
--                                              item with quality; the stored value is the one the item acts with)
--   "chaos_quality" = 0..30                    item quality in percent: every modifier value is multiplied by it
--   "chaos_ruined" = 1                         the item is ruined (Orb of Ruin): no orb changes it any more
--   "chaos_ext" = 1 | 2                        the one extra prefix (1) or suffix (2) slot an Orb of Ruin gave
-- Attack speed is local to the weapon: the weapon's own attack interval (item attribute ITEM_ATTRIBUTE_ATTACK_SPEED,
-- which the engine uses for whoever wields it and the look text shows as "Atk Spd") is set from its base interval.

ChaosItemMods = ChaosItemMods or {}
local M = ChaosItemMods

M.PREFIX = "chaos_mod_"
M.TIER_PREFIX = "ct_"
M.ILVL = "chaos_ilvl"
M.QUALITY = "chaos_quality"
M.RUINED = "chaos_ruined"
M.EXTRA = "chaos_ext"
M.RAW_PREFIX = "cv_"
M.BIND_PREFIX = "cb_"

-- ---------------------------------------------------------------------------------------------------------------
-- configuration
-- ---------------------------------------------------------------------------------------------------------------
-- kinds of items (M.kindOf): weapon, shield, helmet, armor, legs, boots, jewel (amulet or ring), other (gloves, belts..)
-- side: "prefix" (damage and defence) or "suffix" (utility, resistances, speed); a rarity allows so many of each.
-- tiers: value range per tier, T1 (lowest) .. T8 (highest). The five ranges the modifiers had before item levels
-- (tier = ceil(rarity / 3)) are T2 .. T6 here, so an old item keeps what its numbers meant; T1 is new below them,
-- T7 and T8 are new above them. cap: the most a character gets from all equipped items together.
-- fmt: "pct" = "+N%", "flat" = "+N", "less" = "-N%"; text: a format of its own ("%d" = the value).
-- weight: chance to be picked among every modifier an item may get (the engine's types weigh in, chaos_crafting.lua).
M.config = {
	maxTier = 8,
	-- the item level a tier needs (T1 .. T8)
	tierLevels = {1, 15, 30, 50, 70, 95, 120, 140},
	-- roll weight of each tier: higher tiers are rarer
	tierWeights = {100, 90, 80, 65, 50, 35, 22, 12},
	-- only the best `tierWindow` tiers the item level allows can roll (a level 150 item rolls T4 .. T8)
	tierWindow = 5,
	-- today's five tiers on the new scale (old tier t = new tier oldTiers[t])
	oldTiers = {2, 3, 4, 5, 6},

	-- rarity 1..15 (Common .. Transcendent): how many modifiers a new item gets, and how many prefixes and how many
	-- suffixes it may carry at most (the orbs fill up to 2 x sides)
	rarity = {
		count = {2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6},
		sides = {1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3}
	},

	-- item level of a drop: the dropping monster's level (Monster:getMonsterLevel, else its hunting level from
	-- bounty_pool.lua, else 1.6 x sqrt(experience) raised by health / 60, as tools/gen_bounty_pool.py estimates it)
	-- along `curve` ({monster level, item level}, straight lines in between), plus the bonuses, at most `max`
	itemLevel = {
		max = 150,
		curve = {{1, 1}, {10, 5}, {25, 12}, {50, 22}, {100, 36}, {200, 54}, {350, 74}, {500, 90}, {700, 106},
			{900, 118}, {1100, 128}, {1500, 136}, {3000, 142}, {6000, 145}},
		tierBonus = {normal = 0, magic = 2, rare = 4, legendary = 7, boss = 10},
		riftPerTier = 1, -- + rift tier x this (a kill inside a rift, the rift's chest), at most riftMax
		riftMax = 15,
		omen = 15, -- an Omen guardian arena, on top of the rift bonus
		worldBoss = 145, -- fixed: world boss drops and rewards
		store = 60, -- fixed: gear the Chaos store or an NPC hands out with a rarity
		tutorial = 5 -- fixed: the tutorial island's gear
	},

	-- the engine's modifier types (absorbs, skills, critical / leech pairs, weapon elements; chaos_crafting.lua) get
	-- tiers too. The values replace item.cpp's ranges per rarity; old items keep theirs.
	engine = {
		absorb = {side = "suffix", weight = 3,
			tiers = {{1, 1}, {1, 2}, {1, 3}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}}},
		skill = {side = "prefix", weight = 3, -- fist, club, sword, axe, distance, shielding, magic level
			tiers = {{1, 1}, {1, 2}, {1, 3}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}}},
		profession = {side = "suffix", weight = 1, -- fishing, crafting, woodcutting, mining, herbalism, smithing
			tiers = {{1, 1}, {1, 2}, {1, 3}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}}},
		critical = {side = "prefix", weight = 8, -- the amount; the chance is about two thirds of it (C.specialChance)
			tiers = {{1, 1}, {1, 2}, {1, 3}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}}},
		leech = {side = "suffix", weight = 6, -- life and mana leech, each
			tiers = {{1, 1}, {1, 2}, {1, 3}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}}},
		element = {side = "prefix", weight = 2, -- weapons without an element of their own, one element at most
			tiers = {{1, 3}, {3, 6}, {5, 9}, {7, 12}, {10, 16}, {13, 20}, {17, 26}, {22, 35}}}
	},

	-- item quality (orbs v2, the Whetstone): every modifier value is multiplied by (100 + quality) / 100 and rounded; one
	-- Whetstone adds `perStone` percent, up to `cap` (`capHigh` from rarity `highFrom`, Divine and better)
	quality = {perStone = 1, cap = 20, capHigh = 30, highFrom = 10},

	-- bound modifiers (Orb of Binding): how many an item of a rarity may have, index = rarity 1..15
	bind = {max = {1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2}},

	-- legendary powers (chaos_powers.lua): only on items of rarity `minRarity` (Legendary) or better, one per item
	powers = {minRarity = 5, maxPerItem = 1},

	mods = {
		-- prefixes: damage and defence
		{key = "bossdamage", label = "Damage to Elites and Bosses", fmt = "pct", side = "prefix", weight = 6, cap = 30,
			kinds = {weapon = true, jewel = true},
			tiers = {{1, 3}, {2, 4}, {3, 6}, {5, 8}, {6, 10}, {8, 12}, {10, 14}, {12, 16}}},
		{key = "dodge", label = "Dodge", fmt = "pct", side = "prefix", weight = 5, cap = 10,
			kinds = {armor = true, legs = true, boots = true, shield = true, other = true},
			tiers = {{1, 1}, {1, 1}, {1, 2}, {1, 2}, {2, 3}, {2, 4}, {3, 4}, {3, 5}}},
		{key = "reflect", label = "Reflect Damage", fmt = "pct", side = "prefix", weight = 5, cap = 15,
			kinds = {armor = true, shield = true},
			tiers = {{1, 1}, {1, 2}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}, {6, 8}}},
		{key = "thorns", label = "Thorns", fmt = "flat", side = "prefix", weight = 6, cap = 250,
			kinds = {armor = true, shield = true, legs = true},
			tiers = {{1, 4}, {3, 8}, {8, 15}, {15, 30}, {25, 50}, {40, 80}, {60, 110}, {90, 150}}},
		{key = "monsterreduction", label = "Damage Taken from Monsters", fmt = "less", side = "prefix", weight = 6,
			cap = 12, kinds = {armor = true, helmet = true, legs = true, shield = true},
			tiers = {{1, 1}, {1, 1}, {1, 2}, {1, 2}, {2, 3}, {2, 4}, {3, 5}, {4, 6}}},
		{key = "block", label = "Block Chance", fmt = "pct", side = "prefix", weight = 8, cap = 15,
			kinds = {shield = true},
			tiers = {{1, 2}, {2, 3}, {3, 4}, {4, 5}, {5, 7}, {6, 8}, {7, 10}, {9, 12}}},
		{key = "bleedchance", label = "Chance to Bleed", fmt = "pct", side = "prefix", weight = 4, cap = 30,
			kinds = {weapon = true, other = true},
			tiers = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}, {12, 16}}},
		{key = "ignitechance", label = "Chance to Ignite", fmt = "pct", side = "prefix", weight = 4, cap = 30,
			kinds = {weapon = true, other = true},
			tiers = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}, {12, 16}}},
		{key = "poisonchance", label = "Chance to Poison", fmt = "pct", side = "prefix", weight = 4, cap = 30,
			kinds = {weapon = true, other = true},
			tiers = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}, {12, 16}}},
		{key = "chillchance", label = "Chance to Chill", fmt = "pct", side = "prefix", weight = 4, cap = 30,
			kinds = {weapon = true, other = true},
			tiers = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}, {12, 16}}},
		{key = "shockchance", label = "Chance to Shock", fmt = "pct", side = "prefix", weight = 4, cap = 30,
			kinds = {weapon = true, other = true},
			tiers = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}, {12, 16}}},
		{key = "physpen", label = "Physical Penetration", fmt = "pct", side = "prefix", weight = 4, cap = 25,
			kinds = {weapon = true, jewel = true},
			tiers = {{1, 2}, {2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}}},
		{key = "elepen", label = "Elemental Penetration", fmt = "pct", side = "prefix", weight = 4, cap = 25,
			kinds = {weapon = true, jewel = true},
			tiers = {{1, 2}, {2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}}},
		{key = "execute", label = "Execute", text = "Executes Monsters below %d%% Health", side = "prefix", weight = 3,
			cap = 10, kinds = {weapon = true},
			tiers = {{1, 1}, {1, 2}, {2, 2}, {2, 3}, {3, 4}, {4, 5}, {5, 6}, {6, 8}}},
		{key = "dot", label = "Damage over Time", fmt = "pct", side = "prefix", weight = 4, cap = 60,
			kinds = {weapon = true, jewel = true, other = true},
			tiers = {{2, 4}, {4, 6}, {6, 9}, {8, 12}, {10, 15}, {13, 19}, {16, 23}, {20, 28}}},

		-- suffixes: utility, resistances and speed
		{key = "attackspeed", label = "Attack Speed", fmt = "pct", side = "suffix", weight = 8, cap = 15,
			kinds = {weapon = true},
			tiers = {{1, 2}, {2, 3}, {3, 5}, {4, 6}, {5, 8}, {7, 10}, {9, 12}, {11, 14}}},
		{key = "movespeed", label = "Movement Speed", fmt = "pct", side = "suffix", weight = 10, cap = 12,
			kinds = {boots = true},
			tiers = {{1, 2}, {2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 10}, {9, 11}}},
		{key = "lifeonkill", label = "Life on Kill", fmt = "flat", side = "suffix", weight = 6, cap = 300,
			kinds = {weapon = true, jewel = true, helmet = true},
			tiers = {{2, 5}, {5, 10}, {10, 20}, {20, 40}, {35, 60}, {50, 90}, {75, 120}, {100, 150}}},
		{key = "manaonkill", label = "Mana on Kill", fmt = "flat", side = "suffix", weight = 6, cap = 200,
			kinds = {weapon = true, jewel = true, helmet = true},
			tiers = {{1, 3}, {3, 6}, {6, 12}, {12, 25}, {20, 40}, {30, 60}, {50, 80}, {70, 100}}},
		{key = "lifeonhit", label = "Health on Hit", fmt = "flat", side = "suffix", weight = 5, cap = 120,
			kinds = {weapon = true, jewel = true, other = true},
			tiers = {{1, 2}, {2, 4}, {3, 6}, {5, 9}, {7, 13}, {10, 18}, {14, 25}, {20, 35}}},
		{key = "manaonhit", label = "Mana on Hit", fmt = "flat", side = "suffix", weight = 5, cap = 80,
			kinds = {weapon = true, jewel = true, other = true},
			tiers = {{1, 1}, {1, 2}, {2, 4}, {3, 6}, {5, 8}, {7, 12}, {10, 16}, {14, 22}}},
		{key = "regen", label = "Health Regeneration", text = "Health Regeneration +%d per Second", side = "suffix",
			weight = 6, cap = 120, kinds = {armor = true, legs = true, helmet = true, jewel = true, shield = true},
			tiers = {{1, 2}, {2, 4}, {4, 7}, {6, 10}, {9, 15}, {13, 21}, {18, 28}, {25, 40}}},
		{key = "experience", label = "Experience", fmt = "pct", side = "suffix", weight = 4, cap = 15,
			kinds = {helmet = true, jewel = true},
			tiers = {{1, 1}, {1, 2}, {1, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}, {6, 8}}},
		{key = "goldfind", label = "Gold Find", fmt = "pct", side = "suffix", weight = 5, cap = 40,
			kinds = {helmet = true, jewel = true, legs = true, other = true},
			tiers = {{1, 3}, {2, 4}, {3, 6}, {4, 8}, {6, 10}, {8, 14}, {11, 17}, {14, 20}}},
		{key = "itemfind", label = "Item Find", fmt = "pct", side = "suffix", weight = 4, cap = 25,
			kinds = {helmet = true, jewel = true},
			tiers = {{1, 1}, {1, 2}, {2, 3}, {2, 4}, {3, 6}, {4, 8}, {6, 10}, {8, 12}}},
		{key = "rarityfind", label = "Rarity Find", fmt = "pct", side = "suffix", weight = 4, cap = 40,
			kinds = {helmet = true, jewel = true},
			tiers = {{1, 3}, {2, 4}, {3, 6}, {5, 8}, {6, 10}, {8, 14}, {11, 17}, {14, 20}}},
		{key = "healing", label = "Healing Done", fmt = "pct", side = "suffix", weight = 5, cap = 20,
			kinds = {weapon = true, shield = true, jewel = true},
			tiers = {{1, 1}, {1, 2}, {2, 3}, {3, 5}, {4, 6}, {5, 8}, {7, 10}, {9, 12}}},
		-- the treasure goblin roll of a respawn near the player (treasure_goblin.lua: the highest total of the players
		-- around the spawn point counts; +100% = twice the odds)
		{key = "goblinchance", label = "Treasure Goblin Chance", fmt = "pct", side = "suffix", weight = 3, cap = 100,
			kinds = {helmet = true, jewel = true},
			tiers = {{6, 10}, {10, 15}, {14, 20}, {18, 27}, {22, 33}, {28, 40}, {35, 50}, {45, 60}}},
		{key = "cdr", label = "Cooldown Reduction", fmt = "pct", side = "suffix", weight = 4, cap = 20,
			kinds = {helmet = true, jewel = true, other = true},
			tiers = {{1, 2}, {2, 3}, {3, 4}, {4, 5}, {5, 6}, {6, 8}, {7, 9}, {8, 10}}},
		{key = "manacost", label = "Mana Cost Reduction", fmt = "pct", side = "suffix", weight = 4, cap = 25,
			kinds = {helmet = true, armor = true, jewel = true},
			tiers = {{1, 2}, {2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}}}
	},

	-- what the new modifiers do (item_mods.lua): an ailment deals `share` % of the hit that caused it over `rounds`
	-- ticks of `interval` ms (bleeding: physical, ignite: fire, poison: earth); a chill slows by chillSlow % for
	-- chillMs; a shocked monster takes shockPct % more damage from everyone for shockMs
	ailment = {share = 40, rounds = 4, interval = 1000, chillSlow = 30, chillMs = 3000, shockPct = 15, shockMs = 4000},
	regenEvery = 3000, -- ms between two regeneration ticks (the equipment check of item_mods.lua)

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
M.num = num

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

local function custom(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	return ok and num(v) or nil
end

function M.attr(key)
	return M.PREFIX .. key
end

-- the attribute that holds the tier of the modifier stored under attribute `attrKey`
function M.tierAttr(attrKey)
	return M.TIER_PREFIX .. tostring(attrKey):lower()
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
		-- a shield with an attack is a Monk's fist weapon (server/tools/install_fist_weapons.py; no stock shield has
		-- one): it rolls weapon modifiers
		if typeNumber(it, "getAttack") > 0 then
			return "weapon"
		end
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
	return kind ~= nil and (def.kinds == nil or def.kinds[kind] == true)
end

-- ---------------------------------------------------------------------------------------------------------------
-- tiers
-- ---------------------------------------------------------------------------------------------------------------
-- the best tier an item level allows (1 at least)
function M.maxTierFor(level)
	level = tonumber(level) or 0
	local best = 1
	for t, need in ipairs(M.config.tierLevels) do
		if level >= need then
			best = t
		end
	end
	return best
end

-- the tiers that can roll at this item level, best first: {{tier, weight}, ...}
function M.tierRows(level)
	local top = M.maxTierFor(level)
	local rows = {}
	for t = top, math.max(1, top - M.config.tierWindow + 1), -1 do
		rows[#rows + 1] = {t, M.config.tierWeights[t] or 1}
	end
	return rows
end

local function weighted(rows, rand)
	local total = 0
	for _, r in ipairs(rows) do
		total = total + r[2]
	end
	if total <= 0 then
		return nil
	end
	local roll, acc = rand(1, total), 0
	for _, r in ipairs(rows) do
		acc = acc + r[2]
		if roll <= acc then
			return r[1]
		end
	end
	return rows[#rows][1]
end
M.weighted = weighted

-- a tier for a modifier of an item of this level
function M.rollTier(level, rand)
	return weighted(M.tierRows(level), rand or M.random) or 1
end

-- chance (percent, one decimal) of each tier at this item level: {[tier] = pct}
function M.tierChances(level)
	local rows, total, out = M.tierRows(level), 0, {}
	for _, r in ipairs(rows) do
		total = total + r[2]
	end
	for _, r in ipairs(rows) do
		out[r[1]] = floor(r[2] * 1000 / total + 0.5) / 10
	end
	return out
end

-- the value range of a tier table at tier t (clamped to the table): {lo, hi}
function M.tierRange(tiers, t)
	t = clamp(floor(tonumber(t) or 1), 1, #tiers)
	return tiers[t]
end

-- the tier an old value (no stored tier) belongs to: the lowest tier whose range holds it, searched in minT .. maxT
-- (default all); a value above every range gets maxT, one between ranges the best tier that starts below it
function M.tierOfValue(tiers, value, minT, maxT)
	value = tonumber(value) or 0
	minT, maxT = minT or 1, math.min(maxT or #tiers, #tiers)
	local below = minT
	for t = minT, maxT do
		local r = tiers[t]
		if value >= r[1] and value <= r[2] then
			return t
		end
		if value >= r[1] then
			below = t
		end
	end
	return below
end

-- the range of a modifier of this file at tier t: {lo, hi}
function M.range(def, tier)
	return M.tierRange(def.tiers, tier)
end

function M.rollValue(def, tier, rand)
	local r = M.range(def, tier)
	return (rand or M.random)(r[1], r[2])
end

-- the stored tier of the modifier under attrKey (nil when none or out of range)
function M.storedTier(item, attrKey)
	local t = custom(item, M.tierAttr(attrKey))
	t = t and floor(t) or nil
	if t and t >= 1 and t <= M.config.maxTier then
		return t
	end
	return nil
end

function M.setTier(item, attrKey, tier)
	item:setCustomAttribute(M.tierAttr(attrKey), clamp(floor(tonumber(tier) or 1), 1, M.config.maxTier))
end

function M.removeTier(item, attrKey)
	pcall(function() item:removeCustomAttribute(M.tierAttr(attrKey)) end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- quality, bound modifiers, ruin, the extra slot, legendary powers (orbs v2)
-- ---------------------------------------------------------------------------------------------------------------
function M.rawAttr(attrKey)
	return M.RAW_PREFIX .. tostring(attrKey):lower()
end

function M.bindAttr(attrKey)
	return M.BIND_PREFIX .. tostring(attrKey):lower()
end

-- the most quality an item of this rarity may have
function M.qualityCap(rarity)
	local q = M.config.quality
	return (tonumber(rarity) or 0) >= q.highFrom and q.capHigh or q.cap
end

-- the item's quality in percent (0 when none)
function M.qualityOf(item)
	local v = custom(item, M.QUALITY)
	return v and clamp(floor(v), 0, M.config.quality.capHigh) or 0
end

-- a modifier value with quality q percent: rounded to the nearest whole number, never below the value itself
function M.scaleQuality(value, q)
	value, q = floor(tonumber(value) or 0), tonumber(q) or 0
	if value <= 0 or q <= 0 then
		return value
	end
	return math.max(value, floor(value * (100 + q) / 100 + 0.5))
end

function M.isRuined(item)
	return (custom(item, M.RUINED) or 0) ~= 0
end

function M.isBound(item, attrKey)
	return (custom(item, M.bindAttr(attrKey)) or 0) ~= 0
end

function M.setBound(item, attrKey, on)
	if on then
		item:setCustomAttribute(M.bindAttr(attrKey), 1)
	else
		pcall(function() item:removeCustomAttribute(M.bindAttr(attrKey)) end)
	end
end

-- how many modifiers an item of this rarity may have bound
function M.maxBinds(rarity)
	local r = floor(tonumber(rarity) or 0)
	return r > 0 and (M.config.bind.max[math.min(r, #M.config.bind.max)] or 1) or 0
end

-- the side the Orb of Ruin gave an extra slot ("prefix", "suffix") or nil
function M.extraSide(item)
	local v = custom(item, M.EXTRA)
	return v == 1 and "prefix" or v == 2 and "suffix" or nil
end

-- prefixes (and suffixes) an item may carry: its rarity's limit, plus the extra slot on that side
function M.sideLimitOf(item, side, rarity)
	return M.sideLimit(rarity) + (M.extraSide(item) == side and 1 or 0)
end

-- a legendary power is a modifier of this file with `power = true` (chaos_powers.lua adds them)
function M.isPower(def)
	return def ~= nil and def.power == true
end

-- add a modifier definition after the file was loaded (chaos_powers.lua)
function M.addMod(def)
	assert(def.key and def.tiers and #def.tiers == M.config.maxTier, "bad modifier " .. tostring(def.key))
	if M.byKey[def.key] then
		return M.byKey[def.key]
	end
	table.insert(M.config.mods, def)
	def.index = #M.config.mods
	M.byKey[def.key] = def
	return def
end

-- ---------------------------------------------------------------------------------------------------------------
-- rarity: how many modifiers
-- ---------------------------------------------------------------------------------------------------------------
local function rarityIndex(rarity)
	return clamp(floor(tonumber(rarity) or 0), 0, #M.config.rarity.count)
end

-- modifiers a new item of this rarity gets
function M.modCount(rarity)
	local r = rarityIndex(rarity)
	return r > 0 and M.config.rarity.count[r] or 0
end

-- prefixes (and, the same number, suffixes) an item of this rarity may carry
function M.sideLimit(rarity)
	local r = rarityIndex(rarity)
	return r > 0 and M.config.rarity.sides[r] or 0
end

-- every modifier an item of this rarity may carry (what the Orb of Grafting fills up to)
function M.maxMods(rarity)
	return 2 * M.sideLimit(rarity)
end

-- ---------------------------------------------------------------------------------------------------------------
-- item level
-- ---------------------------------------------------------------------------------------------------------------
function M.itemLevelOf(item)
	local v = custom(item, M.ILVL)
	if v and v > 0 then
		return floor(v)
	end
	v = custom(item, "combatPowerLevel")
	return v and v > 0 and floor(v) or 0
end

-- the item level the curve gives a monster level (before bonuses)
function M.levelFromMonster(monsterLevel)
	local lv = math.max(1, tonumber(monsterLevel) or 1)
	local curve = M.config.itemLevel.curve
	if lv <= curve[1][1] then
		return curve[1][2]
	end
	for i = 2, #curve do
		local a, b = curve[i - 1], curve[i]
		if lv <= b[1] then
			return floor(a[2] + (b[2] - a[2]) * (lv - a[1]) / (b[1] - a[1]) + 1e-9)
		end
	end
	return curve[#curve][2]
end

-- the hunting level of a monster without a level of its own (tools/gen_bounty_pool.py estimate_level)
function M.estimateMonsterLevel(experience, health)
	local byExp = 1.6 * math.sqrt(math.max(tonumber(experience) or 0, 1))
	local byHp = (tonumber(health) or 0) / 60
	return math.max(1, floor(math.max(byExp, math.min(byHp, byExp * 1.5)) + 0.5))
end

-- the item level of a drop. src = {monsterLevel, tier = "normal" | "magic" | "rare" | "legendary" | "boss",
-- riftTier, omen = bool, worldBoss = bool, fixed = item level (store, tutorial ...)}
function M.sourceLevel(src)
	local c = M.config.itemLevel
	src = src or {}
	if src.fixed then
		return clamp(floor(tonumber(src.fixed) or 1), 1, c.max)
	end
	if src.worldBoss then
		return c.worldBoss
	end
	local lv = M.levelFromMonster(src.monsterLevel)
	lv = lv + (c.tierBonus[src.tier or "normal"] or 0)
	local rt = tonumber(src.riftTier) or 0
	if rt > 0 then
		lv = lv + math.min(c.riftMax, floor(rt * c.riftPerTier))
	end
	if src.omen then
		lv = lv + c.omen
	end
	return clamp(lv, 1, c.max)
end

-- ---------------------------------------------------------------------------------------------------------------
-- reading and writing an item
-- ---------------------------------------------------------------------------------------------------------------
function M.value(item, key)
	local v = custom(item, M.attr(key))
	return v and floor(v) or 0
end

-- the tier of a modifier of this file on an item: the stored one, else the one its value belongs to (an item from
-- before tiers was rolled in today's T2 .. T6)
function M.tierOf(item, key, value)
	local def = M.byKey[key]
	local t = M.storedTier(item, M.attr(key))
	if t or not def then
		return t or 1
	end
	local old = M.config.oldTiers
	return M.tierOfValue(def.tiers, value or M.value(item, key), old[1], old[#old])
end

-- the Chaos modifiers of an item in catalogue order: {key, value, def, label, tier, side}
function M.read(item)
	local out = {}
	for _, def in ipairs(M.config.mods) do
		local v = M.value(item, def.key)
		if v ~= 0 then
			out[#out + 1] = {key = def.key, value = v, def = def, label = def.label, side = def.side,
				tier = M.tierOf(item, def.key, v)}
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
	if def.text then
		return string.format(def.text, value)
	elseif def.fmt == "flat" then
		return string.format("%s +%d", def.label, value)
	elseif def.fmt == "less" then
		return string.format("%s -%d%%", def.label, value)
	end
	return string.format("%s +%d%%", def.label, value)
end

-- one line, "Attack Speed +5% (T4); Life on Kill +12 (T3)" (loot filter tooltips)
function M.summary(item)
	local parts = {}
	for _, m in ipairs(M.read(item)) do
		parts[#parts + 1] = string.format("%s (T%d)", M.text(m.key, m.value), m.tier)
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

-- Attack speed cap (engine patch 0011; server/README.md "Attack speed cap"). The engine owns the numbers (config.lua
-- minPlayerAttackInterval, maxPlayerAttackSpeedBonus); these are its defaults, used where configManager is missing.
M.attackCap = {minInterval = 1000, maxBonus = 25}

function M.attackCapConfig()
	local cap = {minInterval = M.attackCap.minInterval, maxBonus = M.attackCap.maxBonus}
	if configManager and configKeys and configKeys.MIN_PLAYER_ATTACK_INTERVAL then
		local ok, a = pcall(configManager.getNumber, configKeys.MIN_PLAYER_ATTACK_INTERVAL)
		local ok2, b = pcall(configManager.getNumber, configKeys.MAX_PLAYER_ATTACK_SPEED_BONUS)
		cap.minInterval = ok and tonumber(a) or cap.minInterval
		cap.maxBonus = ok2 and tonumber(b) or cap.maxBonus
	end
	return cap
end

-- the interval (ms) a character swings at, as the engine's Player::getAttackSpeed computes it: typeSpeed = the weapon
-- type's own interval (0 = none), itemSpeed = the weapon's interval (its attribute, else typeSpeed; 0 / nil = no
-- weapon or none), vocSpeed = the vocation's attackspeed, dexterity = the stat window's points. Returns the interval,
-- whether the cap raised it, and the interval without the cap.
function M.effectiveInterval(typeSpeed, itemSpeed, vocSpeed, dexterity, cap)
	cap = cap or M.attackCapConfig()
	vocSpeed = tonumber(vocSpeed) or 2000
	itemSpeed, typeSpeed = tonumber(itemSpeed) or 0, tonumber(typeSpeed) or 0
	local ret, base = vocSpeed, vocSpeed
	if itemSpeed > 0 then
		ret = floor(itemSpeed * vocSpeed / 2000)
		base = floor((typeSpeed > 0 and typeSpeed or M.config.defaultAttackSpeed) * vocSpeed / 2000)
	end
	local dex = math.min(100, math.max(0, tonumber(dexterity) or 0))
	local uncapped = floor(ret - ret * dex / 100 + 1e-9)
	local interval = ret - ret * dex / 100
	local maxBonus = tonumber(cap.maxBonus) or 0
	if maxBonus > 0 and maxBonus < 100 then
		interval = math.max(interval, base * (100 - maxBonus) / 100)
	end
	interval = floor(math.max(interval, math.max(0, tonumber(cap.minInterval) or 0)) + 1e-9)
	return interval, interval > uncapped, uncapped
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

-- write a modifier (and its tier when given; without one an old tier is dropped, the value then decides)
function M.set(item, key, value, tier)
	item:setCustomAttribute(M.attr(key), floor(value))
	if tier then
		M.setTier(item, M.attr(key), tier)
	else
		M.removeTier(item, M.attr(key))
	end
	if key == "attackspeed" then
		M.syncAttackSpeed(item)
	end
end

function M.remove(item, key)
	item:removeCustomAttribute(M.attr(key))
	M.removeTier(item, M.attr(key))
	if key == "attackspeed" then
		M.syncAttackSpeed(item)
	end
end

function M.clear(item)
	for _, m in ipairs(M.read(item)) do
		M.remove(item, m.key)
	end
end

-- modifiers of this file the item could still get (its kind, not on it yet): list of {entry = def, weight}
function M.addable(item, rarity)
	local kind = M.kindOf(item)
	local out = {}
	for _, def in ipairs(M.config.mods) do
		if M.allowed(def, kind) and M.value(item, def.key) == 0
				and (not M.isPower(def) or (tonumber(rarity) or 0) >= M.config.powers.minRarity) then
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

-- ---------------------------------------------------------------------------------------------------------------
-- equipped items (item_mods.lua and the spell side)
-- ---------------------------------------------------------------------------------------------------------------
function M.slotBits()
	local bits = {}
	local function add(slot, bit)
		if slot and bit then
			bits[slot] = bit
		end
	end
	add(CONST_SLOT_HEAD, SLOTP_HEAD); add(CONST_SLOT_NECKLACE, SLOTP_NECKLACE); add(CONST_SLOT_ARMOR, SLOTP_ARMOR)
	add(CONST_SLOT_LEGS, SLOTP_LEGS); add(CONST_SLOT_FEET, SLOTP_FEET); add(CONST_SLOT_RING, SLOTP_RING)
	add(CONST_SLOT_RIGHT, SLOTP_RIGHT); add(CONST_SLOT_LEFT, SLOTP_LEFT)
	add(CONST_SLOT_BADGE, SLOTP_BADGE); add(CONST_SLOT_GLOVES, SLOTP_GLOVES); add(CONST_SLOT_BELT, SLOTP_BELT)
	return bits
end

-- true when the item counts in this slot (worn where it belongs; weapons and shields in a hand)
function M.fits(item, slot, bits)
	bits = bits or M.slotBits()
	local bitValue = bits[slot]
	if not bitValue then
		return false
	end
	local it = item:getType()
	if hasBit(it:getSlotPosition(), bitValue) then
		return true
	end
	if slot == CONST_SLOT_LEFT or slot == CONST_SLOT_RIGHT then
		return it:getWeaponType() ~= (WEAPON_NONE or 0) and it:getWeaponType() ~= (WEAPON_AMMO or 7)
	end
	return false
end

-- the equipped items that count: {item, ...}
function M.equippedItems(player)
	local bits, out = M.slotBits(), {}
	for slot in pairs(bits) do
		local item = player:getSlotItem(slot)
		if item and M.fits(item, slot, bits) then
			out[#out + 1] = item
		end
	end
	return out
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

-- penetration: a hit that the monster's resistance r (percent) reduced, as if r were pen points lower (never below 0;
-- an immune monster stays immune). Same maths as the Sunder support (chaos_supports.lua S.penetrate).
function M.penetrate(value, r, pen)
	r, pen = tonumber(r) or 0, tonumber(pen) or 0
	if r <= 0 or r >= 100 or pen <= 0 then
		return value
	end
	local rNew = math.max(0, r - pen)
	local raw = math.abs(value) * 100 / (100 - r)
	local a = floor(raw * (100 - rNew) / 100 + 1e-6)
	return value < 0 and -a or a
end

-- damage per tick of an ailment caused by a hit of `hit` (whole points, at least 1)
function M.ailmentTick(hit)
	local a = M.config.ailment
	return math.max(1, floor(math.abs(tonumber(hit) or 0) * a.share / 100 / a.rounds + 1e-9))
end

-- true when a monster at `health` of `maxHealth` drops to or below `pct` % by a hit of `damage` (and survives it):
-- the execute modifier kills it instead
function M.executes(health, maxHealth, damage, pct)
	health, maxHealth, damage, pct = tonumber(health) or 0, tonumber(maxHealth) or 0, tonumber(damage) or 0, tonumber(pct) or 0
	if pct <= 0 or maxHealth <= 0 then
		return false
	end
	local left = health - damage
	return left > 0 and left * 100 <= maxHealth * pct
end

-- health a regeneration total gives per tick of `ms`
function M.regenAmount(perSecond, ms)
	return floor((tonumber(perSecond) or 0) * (tonumber(ms) or M.config.regenEvery) / 1000 + 1e-9)
end

-- the legendary powers are modifiers of this file too (chaos_powers.lua adds them to M.config.mods)
if not (ChaosPowers and ChaosPowers.keys) then
	dofile("data/lib/chaos_powers.lua")
end
-- and the energy shield modifiers (chaos_energy_shield.lua)
if not (ChaosEnergyShield and ChaosEnergyShield.keys) then
	dofile("data/lib/chaos_energy_shield.lua")
end

return M
