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
--   "chaos_corrupted" = 1                      the item is corrupted (Void Orb): no orb changes it any more
--   "chaos_cimp" = attribute key               the corrupted implicit modifier a Void Orb added (a modifier of this
--                                              file, stored like any other; it takes no prefix or suffix slot)
-- Attack speed is local to the weapon: the weapon's own attack interval (item attribute ITEM_ATTRIBUTE_ATTACK_SPEED,
-- which the engine uses for whoever wields it and the look text shows as "Atk Spd") is set from its base interval.

if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua") -- the seven rarities: names, order, the mapping of the 15 old ids
end

ChaosItemMods = ChaosItemMods or {}
local M = ChaosItemMods

M.PREFIX = "chaos_mod_"
M.TIER_PREFIX = "ct_"
M.ILVL = "chaos_ilvl"
M.QUALITY = "chaos_quality"
M.RUINED = "chaos_ruined"
M.EXTRA = "chaos_ext"
M.CORRUPTED = "chaos_corrupted"
M.IMPLICIT = "chaos_cimp"
M.RAW_PREFIX = "cv_"
M.BIND_PREFIX = "cb_"
M.QUIVER_SPEED = "chaos_qspd" -- on a launcher: the Attack Speed with Bows of the quiver worn with it (archery.lua)

-- ---------------------------------------------------------------------------------------------------------------
-- configuration
-- ---------------------------------------------------------------------------------------------------------------
-- kinds of items (M.kindOf): weapon, shield, helmet, armor, legs, boots, jewel (amulet or ring), other (gloves, belts..)
-- side: "prefix" (damage and defence) or "suffix" (utility, resistances, speed); a rarity allows so many of each.
-- tiers: value range per tier, T1 (lowest) .. T8 (highest). Raised on 2026-10-18 (owner item 78, about x1.5 to x3 for the
-- small numbers, less at the top where a cap sits near: no single item beats its cap, and a stat with a hard engine cap
-- keeps its top tier under it); the ranges before are in M.legacy / M.legacyEngine, which still read the tier of an old
-- item without a stored tier. cap: the most a character gets from all equipped items together.
-- fmt: "pct" = "+N%", "flat" = "+N", "less" = "-N%"; text: a format of its own ("%d" = the value).
-- weight: chance to be picked among every modifier an item may get (the engine's types weigh in, chaos_crafting.lua).
M.config = {
	-- Global absorb ceiling, percent per combat type: equipment and the absorb storages (gear rolls, passive tree, Paragon)
	-- together never remove more than this. Owner decision 2026-10-20. The engine copy is CHAOS_ABSORB_CEILING_PERCENT in
	-- src-patches/0049-absorb-ceiling.patch (tests/absorb_ceiling_test.lua keeps the two equal).
	absorbCeiling = 75,
	maxTier = 8,
	-- the item level a tier needs (T1 .. T8)
	tierLevels = {1, 15, 30, 50, 70, 95, 120, 140},
	-- roll weight of each tier: higher tiers are rarer
	tierWeights = {100, 90, 80, 65, 50, 35, 22, 12},
	-- only the best `tierWindow` tiers the item level allows can roll (a level 150 item rolls T4 .. T8)
	tierWindow = 5,
	-- today's five tiers on the new scale (old tier t = new tier oldTiers[t])
	oldTiers = {2, 3, 4, 5, 6},

	-- per rarity (ChaosRarity order: Common, Uncommon, Magic, Rare, Legendary, Divine): how many modifiers a new item
	-- gets, and how many prefixes and how many suffixes it may carry at most (the orbs fill up to 2 x sides). Before the
	-- seven rarities (2026-10-18) the 15 rarities had 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6 modifiers
	rarity = {
		count = {1, 2, 3, 4, 5, 6},
		sides = {1, 1, 2, 2, 3, 3}
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
			tiers = {{2, 2}, {2, 4}, {3, 5}, {4, 6}, {5, 8}, {6, 10}, {8, 12}, {10, 14}}},
		skill = {side = "prefix", weight = 3, -- fist, club, sword, axe, distance, shielding, magic level
			tiers = {{1, 2}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 8}, {6, 9}, {7, 10}}},
		profession = {side = "suffix", weight = 1, -- fishing, crafting, woodcutting, mining, herbalism, smithing
			tiers = {{1, 2}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 8}, {6, 9}, {7, 10}}},
		critical = {side = "prefix", weight = 8, -- the amount; the chance is about two thirds of it (C.specialChance)
			tiers = {{2, 2}, {2, 3}, {2, 5}, {3, 5}, {4, 6}, {5, 8}, {6, 9}, {8, 10}}},
		leech = {side = "suffix", weight = 6, -- life and mana leech, each
			tiers = {{2, 2}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}, {6, 9}, {7, 10}}},
		element = {side = "prefix", weight = 2, -- weapons without an element of their own, one element at most
			tiers = {{2, 4}, {4, 9}, {7, 13}, {10, 18}, {15, 24}, {20, 30}, {26, 39}, {33, 52}}}
	},

	-- item quality (orbs v2, the Whetstone): every modifier value is multiplied by (100 + quality) / 100 and rounded; one
	-- Whetstone adds `perStone` percent, up to `cap` (`capHigh` from rarity `highFrom`, Divine and better)
	quality = {perStone = 1, cap = 20, capHigh = 30, highFrom = 10},

	-- bound modifiers (Orb of Binding): how many an item of a rarity may have, index = ChaosRarity rank (Common .. Divine)
	bind = {max = {1, 1, 1, 1, 2, 2}},

	-- legendary powers (chaos_powers.lua): only on items of rarity `minRarity` (Legendary) or better, one per item
	powers = {minRarity = 5, maxPerItem = 1},

	mods = {
		-- prefixes: damage and defence
		{key = "bossdamage", label = "Damage to Elites and Bosses", fmt = "pct", side = "prefix", weight = 6, cap = 30,
			kinds = {weapon = true, jewel = true},
			tiers = {{2, 5}, {4, 7}, {6, 10}, {9, 13}, {11, 16}, {14, 18}, {16, 20}, {18, 22}}},
		{key = "dodge", label = "Dodge", fmt = "pct", side = "prefix", weight = 5, cap = 10,
			kinds = {armor = true, legs = true, boots = true, shield = true, other = true},
			tiers = {{1, 2}, {2, 2}, {2, 3}, {2, 4}, {3, 5}, {3, 5}, {4, 6}, {5, 7}}},
		{key = "reflect", label = "Reflect Damage", fmt = "pct", side = "prefix", weight = 5, cap = 15,
			kinds = {armor = true, shield = true},
			tiers = {{2, 3}, {3, 4}, {4, 5}, {5, 6}, {6, 8}, {7, 9}, {8, 10}, {9, 11}}},
		{key = "thorns", label = "Thorns", fmt = "flat", side = "prefix", weight = 6, cap = 250,
			kinds = {armor = true, shield = true, legs = true},
			tiers = {{2, 6}, {5, 12}, {12, 24}, {24, 45}, {40, 75}, {60, 110}, {90, 150}, {120, 190}}},
		{key = "monsterreduction", label = "Damage Taken from Monsters", fmt = "less", side = "prefix", weight = 6,
			cap = 12, kinds = {armor = true, helmet = true, legs = true, shield = true},
			tiers = {{1, 2}, {2, 2}, {2, 3}, {3, 4}, {3, 5}, {4, 6}, {5, 7}, {6, 8}}},
		{key = "block", label = "Block Chance", fmt = "pct", side = "prefix", weight = 8, cap = 15,
			kinds = {shield = true},
			tiers = {{2, 3}, {3, 5}, {4, 6}, {5, 8}, {7, 10}, {8, 11}, {9, 12}, {11, 14}}},
		{key = "bleedchance", label = "Chance to Bleed", fmt = "pct", side = "prefix", weight = 4, cap = 30,
			kinds = {weapon = true, other = true},
			tiers = {{3, 5}, {5, 7}, {7, 10}, {9, 13}, {11, 16}, {14, 18}, {17, 21}, {20, 25}}},
		{key = "ignitechance", label = "Chance to Ignite", fmt = "pct", side = "prefix", weight = 4, cap = 30,
			kinds = {weapon = true, other = true},
			tiers = {{3, 5}, {5, 7}, {7, 10}, {9, 13}, {11, 16}, {14, 18}, {17, 21}, {20, 25}}},
		{key = "poisonchance", label = "Chance to Poison", fmt = "pct", side = "prefix", weight = 4, cap = 30,
			kinds = {weapon = true, other = true},
			tiers = {{3, 5}, {5, 7}, {7, 10}, {9, 13}, {11, 16}, {14, 18}, {17, 21}, {20, 25}}},
		{key = "chillchance", label = "Chance to Chill", fmt = "pct", side = "prefix", weight = 4, cap = 30,
			kinds = {weapon = true, other = true},
			tiers = {{3, 5}, {5, 7}, {7, 10}, {9, 13}, {11, 16}, {14, 18}, {17, 21}, {20, 25}}},
		{key = "shockchance", label = "Chance to Shock", fmt = "pct", side = "prefix", weight = 4, cap = 30,
			kinds = {weapon = true, other = true},
			tiers = {{3, 5}, {5, 7}, {7, 10}, {9, 13}, {11, 16}, {14, 18}, {17, 21}, {20, 25}}},
		{key = "physpen", label = "Physical Penetration", fmt = "pct", side = "prefix", weight = 4, cap = 25,
			kinds = {weapon = true, jewel = true},
			tiers = {{2, 4}, {3, 5}, {5, 7}, {7, 10}, {9, 13}, {11, 15}, {14, 18}, {17, 22}}},
		{key = "elepen", label = "Elemental Penetration", fmt = "pct", side = "prefix", weight = 4, cap = 25,
			kinds = {weapon = true, jewel = true},
			tiers = {{2, 4}, {3, 5}, {5, 7}, {7, 10}, {9, 13}, {11, 15}, {14, 18}, {17, 22}}},
		{key = "execute", label = "Execute", text = "Executes Monsters below %d%% Health", side = "prefix", weight = 3,
			cap = 10, kinds = {weapon = true},
			tiers = {{1, 2}, {2, 3}, {3, 3}, {3, 4}, {4, 5}, {5, 6}, {6, 7}, {7, 9}}},
		{key = "dot", label = "Damage over Time", fmt = "pct", side = "prefix", weight = 4, cap = 60,
			kinds = {weapon = true, jewel = true, other = true},
			tiers = {{4, 7}, {7, 11}, {10, 15}, {14, 20}, {18, 26}, {23, 32}, {29, 39}, {36, 48}}},

		-- suffixes: utility, resistances and speed
		{key = "attackspeed", label = "Attack Speed", fmt = "pct", side = "suffix", weight = 8, cap = 15,
			kinds = {weapon = true},
			tiers = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {7, 9}, {9, 11}, {11, 13}, {13, 15}}},
		{key = "movespeed", label = "Movement Speed", fmt = "pct", side = "suffix", weight = 10, cap = 12,
			kinds = {boots = true},
			tiers = {{2, 3}, {3, 4}, {4, 5}, {5, 7}, {6, 8}, {8, 10}, {9, 11}, {10, 12}}},
		{key = "lifeonkill", label = "Life on Kill", fmt = "flat", side = "suffix", weight = 6, cap = 300,
			kinds = {weapon = true, jewel = true, helmet = true},
			tiers = {{4, 9}, {9, 18}, {18, 36}, {36, 70}, {60, 100}, {85, 150}, {120, 200}, {160, 260}}},
		{key = "manaonkill", label = "Mana on Kill", fmt = "flat", side = "suffix", weight = 6, cap = 200,
			kinds = {weapon = true, jewel = true, helmet = true},
			tiers = {{2, 5}, {5, 10}, {10, 20}, {20, 40}, {35, 65}, {50, 95}, {80, 130}, {110, 170}}},
		{key = "lifeonhit", label = "Health on Hit", fmt = "flat", side = "suffix", weight = 5, cap = 120,
			kinds = {weapon = true, jewel = true, other = true},
			tiers = {{2, 4}, {4, 7}, {5, 11}, {9, 16}, {13, 23}, {18, 32}, {25, 45}, {36, 63}}},
		{key = "manaonhit", label = "Mana on Hit", fmt = "flat", side = "suffix", weight = 5, cap = 80,
			kinds = {weapon = true, jewel = true, other = true},
			tiers = {{2, 2}, {2, 4}, {4, 7}, {5, 11}, {9, 14}, {13, 21}, {18, 29}, {25, 40}}},
		{key = "regen", label = "Health Regeneration", text = "Health Regeneration +%d per Second", side = "suffix",
			weight = 6, cap = 120, kinds = {armor = true, legs = true, helmet = true, jewel = true, shield = true},
			tiers = {{2, 4}, {4, 7}, {7, 12}, {11, 18}, {16, 26}, {23, 36}, {32, 48}, {44, 70}}},
		{key = "experience", label = "Experience", fmt = "pct", side = "suffix", weight = 4, cap = 15,
			kinds = {helmet = true, jewel = true},
			tiers = {{1, 2}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 8}, {6, 9}, {8, 11}}},
		{key = "goldfind", label = "Gold Find", fmt = "pct", side = "suffix", weight = 5, cap = 40,
			kinds = {helmet = true, jewel = true, legs = true, other = true},
			tiers = {{2, 5}, {4, 7}, {5, 10}, {7, 14}, {11, 18}, {14, 23}, {19, 28}, {24, 34}}},
		{key = "itemfind", label = "Item Find", fmt = "pct", side = "suffix", weight = 4, cap = 25,
			kinds = {helmet = true, jewel = true},
			tiers = {{2, 2}, {2, 3}, {3, 5}, {4, 7}, {5, 10}, {7, 13}, {10, 16}, {13, 19}}},
		{key = "rarityfind", label = "Rarity Find", fmt = "pct", side = "suffix", weight = 4, cap = 40,
			kinds = {helmet = true, jewel = true},
			tiers = {{2, 5}, {4, 7}, {5, 10}, {9, 14}, {11, 18}, {14, 23}, {19, 28}, {24, 34}}},
		{key = "healing", label = "Healing Done", fmt = "pct", side = "suffix", weight = 5, cap = 20,
			kinds = {weapon = true, shield = true, jewel = true},
			tiers = {{2, 2}, {2, 3}, {3, 5}, {5, 8}, {7, 10}, {9, 13}, {11, 15}, {13, 18}}},
		-- the treasure goblin roll of a respawn near the player (treasure_goblin.lua: the highest total of the players
		-- around the spawn point counts; +100% = twice the odds)
		{key = "goblinchance", label = "Treasure Goblin Chance", fmt = "pct", side = "suffix", weight = 3, cap = 100,
			kinds = {helmet = true, jewel = true},
			tiers = {{9, 15}, {15, 23}, {21, 30}, {27, 41}, {33, 50}, {42, 60}, {53, 75}, {68, 90}}},
		{key = "cdr", label = "Cooldown Reduction", fmt = "pct", side = "suffix", weight = 4, cap = 20,
			kinds = {helmet = true, jewel = true, other = true},
			tiers = {{2, 3}, {3, 4}, {4, 6}, {6, 8}, {8, 10}, {9, 12}, {11, 14}, {13, 16}}},
		{key = "manacost", label = "Mana Cost Reduction", fmt = "pct", side = "suffix", weight = 4, cap = 25,
			kinds = {helmet = true, armor = true, jewel = true},
			tiers = {{2, 3}, {3, 5}, {5, 7}, {7, 10}, {9, 12}, {11, 15}, {14, 18}, {17, 21}}}
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

-- pcall on named functions, not on a closure made per call: these run for every modifier of every worn item of
-- every player in the equipment check, and the closures were most of its garbage (server/README.md "Game loop stalls")
local function itemTypeOf(item)
	return ItemType(item:getId())
end

local function callMethod(obj, method)
	return obj[method](obj)
end

local function getCustom(item, key)
	return item:getCustomAttribute(key)
end

local function typeOf(item)
	local ok, it = pcall(itemTypeOf, item)
	return ok and it or nil
end

local function typeNumber(it, method)
	local ok, v = pcall(callMethod, it, method)
	return ok and tonumber(v) or 0
end

local function custom(item, key)
	local ok, v = pcall(getCustom, item, key)
	return ok and num(v) or nil
end

function M.attr(key)
	return M.PREFIX .. key
end

-- the attribute that holds the tier of the modifier stored under attribute `attrKey`
function M.tierAttr(attrKey)
	return M.TIER_PREFIX .. tostring(attrKey):lower()
end


-- The value ranges the modifiers had until 2026-10-18 (owner item 78: "the prefixes and suffixes must raise the values more,
-- most of them are tiny"). Items rolled before that keep their numbers; the tier of one without a stored tier ("ct_" attribute)
-- is still read from these ranges, so an old +4% reads as the tier it was rolled in. Chaos modifiers by key, the engine's
-- types by group.
M.legacy = {
	bossdamage = {{1, 3}, {2, 4}, {3, 6}, {5, 8}, {6, 10}, {8, 12}, {10, 14}, {12, 16}},
	dodge = {{1, 1}, {1, 1}, {1, 2}, {1, 2}, {2, 3}, {2, 4}, {3, 4}, {3, 5}},
	reflect = {{1, 1}, {1, 2}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}, {6, 8}},
	thorns = {{1, 4}, {3, 8}, {8, 15}, {15, 30}, {25, 50}, {40, 80}, {60, 110}, {90, 150}},
	monsterreduction = {{1, 1}, {1, 1}, {1, 2}, {1, 2}, {2, 3}, {2, 4}, {3, 5}, {4, 6}},
	block = {{1, 2}, {2, 3}, {3, 4}, {4, 5}, {5, 7}, {6, 8}, {7, 10}, {9, 12}},
	bleedchance = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}, {12, 16}},
	ignitechance = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}, {12, 16}},
	poisonchance = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}, {12, 16}},
	chillchance = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}, {12, 16}},
	shockchance = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}, {12, 16}},
	physpen = {{1, 2}, {2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}},
	elepen = {{1, 2}, {2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}},
	execute = {{1, 1}, {1, 2}, {2, 2}, {2, 3}, {3, 4}, {4, 5}, {5, 6}, {6, 8}},
	dot = {{2, 4}, {4, 6}, {6, 9}, {8, 12}, {10, 15}, {13, 19}, {16, 23}, {20, 28}},
	attackspeed = {{1, 2}, {2, 3}, {3, 5}, {4, 6}, {5, 8}, {7, 10}, {9, 12}, {11, 14}},
	movespeed = {{1, 2}, {2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 10}, {9, 11}},
	lifeonkill = {{2, 5}, {5, 10}, {10, 20}, {20, 40}, {35, 60}, {50, 90}, {75, 120}, {100, 150}},
	manaonkill = {{1, 3}, {3, 6}, {6, 12}, {12, 25}, {20, 40}, {30, 60}, {50, 80}, {70, 100}},
	lifeonhit = {{1, 2}, {2, 4}, {3, 6}, {5, 9}, {7, 13}, {10, 18}, {14, 25}, {20, 35}},
	manaonhit = {{1, 1}, {1, 2}, {2, 4}, {3, 6}, {5, 8}, {7, 12}, {10, 16}, {14, 22}},
	regen = {{1, 2}, {2, 4}, {4, 7}, {6, 10}, {9, 15}, {13, 21}, {18, 28}, {25, 40}},
	experience = {{1, 1}, {1, 2}, {1, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}, {6, 8}},
	goldfind = {{1, 3}, {2, 4}, {3, 6}, {4, 8}, {6, 10}, {8, 14}, {11, 17}, {14, 20}},
	itemfind = {{1, 1}, {1, 2}, {2, 3}, {2, 4}, {3, 6}, {4, 8}, {6, 10}, {8, 12}},
	rarityfind = {{1, 3}, {2, 4}, {3, 6}, {5, 8}, {6, 10}, {8, 14}, {11, 17}, {14, 20}},
	healing = {{1, 1}, {1, 2}, {2, 3}, {3, 5}, {4, 6}, {5, 8}, {7, 10}, {9, 12}},
	goblinchance = {{6, 10}, {10, 15}, {14, 20}, {18, 27}, {22, 33}, {28, 40}, {35, 50}, {45, 60}},
	cdr = {{1, 2}, {2, 3}, {3, 4}, {4, 5}, {5, 6}, {6, 8}, {7, 9}, {8, 10}},
	manacost = {{1, 2}, {2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}}
}
M.legacyEngine = {
	absorb = {{1, 1}, {1, 2}, {1, 3}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}},
	skill = {{1, 1}, {1, 2}, {1, 3}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}},
	profession = {{1, 1}, {1, 2}, {1, 3}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}},
	critical = {{1, 1}, {1, 2}, {1, 3}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}},
	leech = {{1, 1}, {1, 2}, {1, 3}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}},
	element = {{1, 3}, {3, 6}, {5, 9}, {7, 12}, {10, 16}, {13, 20}, {17, 26}, {22, 35}}
}

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
	-- a quiver (data/lib/chaos_archery_core.lua): off-hand equipment with modifiers of its own (weapon type "quiver",
	-- engine patch 0023: no weapon)
	if ChaosArchery and ChaosArchery.isQuiverType(it) then
		return "quiver"
	end
	if weapon ~= 0 and weapon ~= (WEAPON_AMMO or 7) and weapon ~= (WEAPON_QUIVER or 8) then
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

-- a quiver rolls only the modifiers that name it (chaos_archery_config.lua mods and sharedMods), never the ones open
-- to every kind (the engine's absorbs, skills, critical and leech pairs: the base rarity script would apply those
-- whatever the wearer holds)
function M.allowed(def, kind)
	if kind == "quiver" then
		return def.kinds ~= nil and def.kinds.quiver == true
	end
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

-- corrupted by a Void Orb (chaos_orbs.lua): every orb refuses the item
function M.isCorrupted(item)
	return (custom(item, M.CORRUPTED) or 0) ~= 0
end

-- the attribute key (lower case) of the corrupted implicit modifier, or nil
function M.implicitKey(item)
	local ok, v = pcall(getCustom, item, M.IMPLICIT)
	return ok and type(v) == "string" and v ~= "" and v:lower() or nil
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
	return M.rankOf(rarity) > 0 and ChaosRarity.at(M.config.bind.max, rarity, 1) or 0
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
-- the place of a rarity in the tables above (0 = none; any number is read through ChaosRarity, so an item that still
-- carries one of the 15 old ids counts as the rarity it became)
function M.rankOf(rarity)
	return ChaosRarity.rank(rarity)
end

local function rarityIndex(rarity)
	local rank = M.rankOf(rarity)
	return rank <= #M.config.rarity.count and rank or 0 -- Unique (place 7) is no rolled rarity
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
	-- an item without a stored tier was rolled before the ranges were raised (2026-10-18): read it from the old ranges
	return M.tierOfValue(M.legacy[key] or def.tiers, value or M.value(item, key), old[1], old[#old])
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
	-- the Attack Speed with Bows of the wielder's quiver (archery.lua writes it on the launcher in the hands)
	pct = pct + (custom(item, M.QUIVER_SPEED) or 0)
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
	-- the second ring slot (the old ammunition slot, engine patch 0023): a ring counts there as in the ring slot
	add(CONST_SLOT_AMMO, SLOTP_RING)
	return bits
end

-- the launcher kind of the weapon in the player's hands ("bow" | "crossbow"), nil without one
function M.handLauncher(player)
	if not (player and ChaosArchery) then
		return nil
	end
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local ok, item = pcall(function() return player:getSlotItem(slot) end)
		local kind = ok and item and ChaosArchery.kindOfType(typeOf(item))
		if kind then
			return kind, item
		end
	end
	return nil
end

-- true when the item counts in this slot (worn where it belongs; weapons and shields in a hand). A quiver counts only
-- in the off-hand (the shield hand) while `player` holds a bow or crossbow (without a player: never)
function M.fits(item, slot, bits, player)
	bits = bits or M.slotBits()
	local bitValue = bits[slot]
	if not bitValue then
		return false
	end
	if M.kindOf(item) == "quiver" then
		return slot == CONST_SLOT_RIGHT and M.handLauncher(player) ~= nil
	end
	local it = item:getType()
	if hasBit(it:getSlotPosition(), bitValue) then
		return true
	end
	if slot == CONST_SLOT_LEFT or slot == CONST_SLOT_RIGHT then
		local wt = it:getWeaponType()
		return wt ~= (WEAPON_NONE or 0) and wt ~= (WEAPON_AMMO or 7) and wt ~= (WEAPON_QUIVER or 8)
	end
	return false
end

-- the equipped items that count: {item, ...}
function M.equippedItems(player)
	local bits, out = M.slotBits(), {}
	for slot in pairs(bits) do
		local item = player:getSlotItem(slot)
		if item and M.fits(item, slot, bits, player) then
			out[#out + 1] = item
		end
	end
	return out
end

-- the absorb percent a character really gets on one combat type, as engine patch 0049 computes it: equipment (a list of
-- percents, each applied to what the previous one left, the stock rule) and the absorb storages (percent, taken off after
-- by the Lua absorb event). Held at config.absorbCeiling; a storage sum past the ceiling is not held (the Lua event takes it).
function M.effectiveAbsorb(items, storage)
	local cap = M.config.absorbCeiling
	storage = math.max(0, math.min(100, tonumber(storage) or 0))
	local items_ = 1
	for _, p in ipairs(items or {}) do
		items_ = items_ * (1 - (tonumber(p) or 0) / 100)
	end
	local least = (1 - cap / 100) / (1 - math.min(storage, cap) / 100) -- equipment may leave this share at the least
	if items_ < 1 and items_ < least then
		items_ = math.min(least, 1)
	end
	local total = (1 - items_ * (1 - storage / 100)) * 100
	return math.floor(total * 1e6 + 0.5) / 1e6
end

-- ---------------------------------------------------------------------------------------------------------------
-- totals of a character
-- ---------------------------------------------------------------------------------------------------------------
-- sum of the Chaos modifiers of the given items, each capped: {key -> value} (every key present, 0 when none).
-- extra (optional): more numbers {key -> value} under the same caps (the item set bonuses, itemsets.lua)
function M.totals(items, extra)
	local t = {}
	for _, def in ipairs(M.config.mods) do
		t[def.key] = 0
	end
	for key, value in pairs(extra or {}) do
		if t[key] then
			t[key] = t[key] + (tonumber(value) or 0)
		end
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
-- and the quiver modifiers (chaos_archery_core.lua; every load, the catalogue above is new each time)
if not (ChaosArchery and ChaosArchery.registerMods) then
	dofile("data/lib/chaos_archery_core.lua")
end
ChaosArchery.registerMods(M)
-- and the energy shield modifiers (chaos_energy_shield.lua)
if not (ChaosEnergyShield and ChaosEnergyShield.keys) then
	dofile("data/lib/chaos_energy_shield.lua")
end

return M
