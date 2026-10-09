-- Chaos crafting: the whole modifier roll of an item (ChaosCrafting.forge) and the currency orbs that change it.
-- Used by data/scripts/chaos/crafting.lua (crafting bench window, !craft, use-with on the orbs), by the loot layer
-- (loot.lua: every gear drop with a rarity) and by every script that hands out gear with a rarity (ChaosCrafting
-- .createItem); tested by server/tests/crafting_test.lua against a mocked item. Lua 5.1 / LuaJIT compatible.
--
-- How an item carries a rarity and its modifiers:
--   custom attribute "rarity"            1..15 (Common .. Transcendent, names in Chaos loot_config.lua gear.names)
--   custom attribute "chaos_ilvl"        the item level (1..150, from the drop's source: chaos_item_mods.lua
--                                        M.sourceLevel), mirrored into "combatPowerLevel" (the client and the engine
--                                        show that one); an item from before item levels has only "combatPowerLevel"
--   attack/defense/armor/hit chance      raised once by a small bonus of the rarity and the item level
--   one custom attribute per modifier    the engine's types: rarity_<x>Absorb (percent), rarity_<skill>Skill,
--                                        rarity_maglevelSkill, rarity_criticalHitChance + rarity_criticalHitAmount
--                                        (always a pair, same for mana and life leech), rarity_element<x> (weapons
--                                        only, % extra damage); and the Chaos types "chaos_mod_<key>"
--   "ct_<attribute key>" per modifier    its tier, T1 (lowest) .. T8 (chaos_item_mods.lua); missing on old items: the
--                                        tier then follows from the value
--   the description attribute           "Item Level: 57. Prefixes: Sword +2 (T3); Critical Chance +1%, Critical Hit
--                                        +2% (T2). Suffixes: Fire +3% (T4)" - the look text shows this text
-- The engine's own roll (src/item.cpp Item::applyRarityEffects, Monster::dropLoot) is not used for new items any more:
-- C.forge rolls every modifier here, tiers by the item level, how many by the rarity, prefixes and suffixes apart.
-- customs/rarity/base_rarity.lua reads the engine types' attributes when the item is equipped (conditions for skills,
-- critical and leech; storages for absorbs and element damage), so the attribute keys stay the engine's.
-- Custom attribute keys are case-insensitive.
--
-- A "modifier" here is one line of the description: one absorb, one skill, one leech/critical pair, one element or
-- one Chaos modifier. Uniques (custom attribute "chaos_unique", data/lib/chaos_unique_items.lua) are never touched.
--
-- Rift Keys (rift.lua: item 10155 with action id 47401, custom attributes "rift_tier" and "rift_mods") are craftable
-- too, the map way: the orbs change the key's modifiers inside the rift's own pool and ranges (rift_core.lua), see
-- C.keyCheck / C.keyApply below.
--
-- New orbs: C.addOrb{key, id, name, text, keyText, check = fn(item, opts) -> ok, reason, apply = fn(item, opts) -> ok,
-- result, preview = fn(item) -> text, pick = fn(item) -> {attribute keys the orb may be aimed at}}. The building blocks:
-- C.readMods, C.candidates, C.rollAffix, C.removeMod, C.forge, C.rerollValues, C.rerollTiers, C.recreate,
-- C.rewriteDescription, C.qualityOf / C.addQuality (item quality), C.setBound (bound modifiers), C.ruin (ruined items).
-- The orbs of orbs v2 (Tempering, Binding, Excision, Reforging, Ruin, the Whetstone) are in data/lib/chaos_orbs.lua.

ChaosCrafting = ChaosCrafting or {}
local C = ChaosCrafting
if not ChaosItemMods then
	dofile("data/lib/chaos_item_mods.lua")
end
local M = ChaosItemMods
if not ChaosGems then
	dofile("data/lib/chaos_gems.lua") -- sockets and gems (server/README.md "Gems and sockets")
end
local G = ChaosGems

-- ---------------------------------------------------------------------------------------------------------------
-- configuration
-- ---------------------------------------------------------------------------------------------------------------
C.config = {
	-- orbs in the order the bench shows them. id = server item id. The three new ids (24688, 24691, 24697) are unused
	-- stackable rune stones without an items.xml entry; server/tools/install_crafting.py gives them their names.
	orbs = {
		{key = "transmutation", id = 29851, name = "Orb of Awakening",
			text = "Turns a normal item into a Common or Uncommon one with random modifiers (tiers by its item level).",
			keyText = "Gives a Rift Key without modifiers one modifier."},
		{key = "alchemy", id = 24691, name = "Orb of Gilding",
			text = "Turns a normal item into a Rare, Epic or Legendary one with random modifiers (tiers by its item level).",
			keyText = "Gives a Rift Key without modifiers two or three modifiers."},
		{key = "exalted", id = 29855, name = "Orb of Grafting",
			text = "Adds one random modifier on an open prefix or suffix of an item with a rarity.",
			keyText = "Adds one modifier to a Rift Key (three at most)."},
		{key = "annulment", id = 24697, name = "Orb of Unmaking",
			text = "Removes one random modifier that is not bound.",
			keyText = "Removes one random modifier of a Rift Key."},
		{key = "scouring", id = 24688, name = "Orb of Erasure",
			text = "Removes the rarity, every modifier and every bind: a normal item again (item level and quality stay).",
			keyText = "Removes every modifier of a Rift Key."},
		{key = "chaos", id = 29856, name = "Orb of Upheaval",
			text = "Rerolls every modifier that is not bound (rarity, item level and quality stay).",
			keyText = "Rerolls the modifiers of a Rift Key (one to three new ones)."},
		{key = "divine", id = 29857, name = "Orb of Fate",
			text = "Rolls a new random rarity, often none; item level and quality stay. Not on an item with a bound modifier.",
			keyText = "Rerolls the values of a Rift Key's modifiers inside their ranges."},
		-- gems and sockets (chaos_gems_config.lua socketOrb; install_gems.py names the rune stone)
		{key = "sockets", id = ChaosGems.config.socketOrb.id, name = ChaosGems.config.socketOrb.name,
			text = ChaosGems.config.socketOrb.text,
			keyText = "Rift Keys have no sockets."}
	},

	-- rarity names (same as the stock look text, default_onLook.lua)
	rarityNames = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Exotic", "Mythic", "Chaos", "Eternal",
		"Divine", "Phantasmal", "Celestial", "Cosmic", "Abyssal", "Transcendent"},

	-- the attack / defense / armor / hit chance bonus of a rarity (item.cpp's table): {min, max}; the bonus is
	-- min + floor(item level x (max - min + 1) / 100)
	baseBonus = {{1, 1}, {1, 2}, {1, 2}, {1, 3}, {1, 3}, {2, 4}, {2, 5}, {3, 6}, {3, 7}, {4, 8}, {4, 9}, {5, 10},
		{6, 10}, {7, 12}, {9, 15}},

	maxElements = 1, -- element modifiers per weapon (the stock roll never gives more than one)

	-- Orbs of Awakening and Alchemy: {rarity, weight}
	transmutation = {{1, 65}, {2, 35}},
	alchemy = {{3, 55}, {4, 30}, {5, 15}},

	-- the stock Orb of Fate roll (customs/rarity/reroll_rarity_stats.lua rollRarityForReroll): rollChance % to get a
	-- rarity at all, then each rarity in order with its own chance
	divineRollChance = 15,
	divineChances = {25.0, 18.0, 15.0, 12.0, 10.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.5, 3.0, 2.5, 2.0, 1.0},

	-- items no orb may touch (boats, same list as customs/rarity/reroll_rarity_stats.lua)
	excludedItems = {[27797] = true, [27798] = true, [27799] = true, [27800] = true, [27801] = true, [27802] = true},

	historySize = 8, -- crafts shown on the bench
	historyTable = "chaos_crafting_log", -- server/sql/chaos.sql
	historyKeepDays = 60
}

-- ---------------------------------------------------------------------------------------------------------------
-- modifier catalogue (keys and labels exactly as item.cpp writes them)
-- ---------------------------------------------------------------------------------------------------------------
C.absorbs = {
	{key = "rarity_physicalAbsorb", label = "Physical"},
	{key = "rarity_energyAbsorb", label = "Energy"},
	{key = "rarity_earthAbsorb", label = "Earth"},
	{key = "rarity_fireAbsorb", label = "Fire"},
	{key = "rarity_drownAbsorb", label = "Drown"},
	{key = "rarity_iceAbsorb", label = "Ice"},
	{key = "rarity_holyAbsorb", label = "Holy"},
	{key = "rarity_deathAbsorb", label = "Death"},
	{key = "rarity_waterAbsorb", label = "Water"},
	{key = "rarity_arcaneAbsorb", label = "Arcane"}
}
C.skills = {
	{key = "rarity_fistSkill", label = "Fist", kind = "combat"},
	{key = "rarity_clubSkill", label = "Club", kind = "combat"},
	{key = "rarity_swordSkill", label = "Sword", kind = "combat"},
	{key = "rarity_axeSkill", label = "Axe", kind = "combat"},
	{key = "rarity_distanceSkill", label = "Distance", kind = "combat"},
	{key = "rarity_shieldSkill", label = "Shielding", kind = "combat"},
	{key = "rarity_fishingSkill", label = "Fishing", kind = "profession"},
	{key = "rarity_craftingSkill", label = "Crafting", kind = "profession"},
	{key = "rarity_woodcuttingSkill", label = "Woodcutting", kind = "profession"},
	{key = "rarity_miningSkill", label = "Mining", kind = "profession"},
	{key = "rarity_herbalistSkill", label = "Herbalism", kind = "profession"},
	{key = "rarity_armorsmithSkill", label = "Armorsmithing", kind = "profession"},
	{key = "rarity_weaponsmithSkill", label = "Weaponsmithing", kind = "profession"},
	{key = "rarity_jewelsmithSkill", label = "Jewelsmithing", kind = "profession"},
	{key = "rarity_maglevelSkill", label = "Magic", kind = "combat"}
}
C.specials = {
	{key = "rarity_criticalHitChance", key2 = "rarity_criticalHitAmount", label = "Critical Chance", label2 = "Critical Hit",
		kind = "critical"},
	{key = "rarity_manaLeechChance", key2 = "rarity_manaLeechAmount", label = "Mana Chance", label2 = "Mana Amount",
		kind = "leech"},
	{key = "rarity_lifeLeechChance", key2 = "rarity_lifeLeechAmount", label = "Life Chance", label2 = "Life Amount",
		kind = "leech"}
}
C.elements = {
	{key = "rarity_elementfire", label = "Fire"},
	{key = "rarity_elementice", label = "Ice"},
	{key = "rarity_elementenergy", label = "Energy"},
	{key = "rarity_elementdeath", label = "Death"},
	{key = "rarity_elementearth", label = "Earth"},
	{key = "rarity_elementwater", label = "Water"},
	{key = "rarity_elementarcane", label = "Arcane"},
	{key = "rarity_elementholy", label = "Holy"}
}

C.orbByKey, C.orbById = {}, {}
local function indexOrb(orb)
	C.orbByKey[orb.key] = orb
	C.orbById[orb.id] = orb
end
for _, orb in ipairs(C.config.orbs) do
	indexOrb(orb)
end

-- add an orb (orbs v2): {key, id, name, text, keyText, check, apply, preview}. On gear the orb's own check / apply /
-- preview run instead of the built-in rules (the common ones - gear, unique, stack - are checked first); Rift Keys
-- refuse it unless it has keyCheck / keyApply. crafting.lua registers a use-with action for every orb in
-- C.config.orbs when it loads, so add orbs before it (a data/lib file).
function C.addOrb(orb)
	assert(type(orb) == "table" and orb.key and orb.id and orb.name, "orb needs key, id and name")
	if C.orbByKey[orb.key] then
		return C.orbByKey[orb.key]
	end
	table.insert(C.config.orbs, orb)
	indexOrb(orb)
	return orb
end

-- random source; tests replace it
C.random = function(a, b)
	return math.random(a, b)
end

-- ---------------------------------------------------------------------------------------------------------------
-- the affix list: every modifier type an item may roll, the engine's and the Chaos ones, with side, weight, tiers
-- {key (attribute), key2, group, label, label2, side, weight, tiers, kinds (nil = any gear), chaosKey, def}
-- ---------------------------------------------------------------------------------------------------------------
local affixCache
function C.affixes()
	if affixCache then
		return affixCache
	end
	local E, list = M.config.engine, {}
	local function add(row, e)
		row.side, row.weight, row.tiers = e.side, e.weight, e.tiers
		list[#list + 1] = row
	end
	for _, a in ipairs(C.absorbs) do
		add({key = a.key, group = "absorb", label = a.label}, E.absorb)
	end
	for _, s in ipairs(C.skills) do
		add({key = s.key, group = "skill", label = s.label}, s.kind == "profession" and E.profession or E.skill)
	end
	for _, s in ipairs(C.specials) do
		add({key = s.key, key2 = s.key2, group = "special", label = s.label, label2 = s.label2}, E[s.kind])
	end
	for _, def in ipairs(M.config.mods) do
		list[#list + 1] = {key = M.attr(def.key), chaosKey = def.key, group = "chaos", label = def.label, side = def.side,
			weight = def.weight, tiers = def.tiers, kinds = def.kinds, def = def}
	end
	for _, e in ipairs(C.elements) do
		add({key = e.key, group = "element", label = e.label}, E.element)
	end
	affixCache = list
	C.affixByKey = {}
	for _, a in ipairs(list) do
		C.affixByKey[a.key:lower()] = a
	end
	return list
end

-- every custom attribute key a rolled item may carry (rarity, item level, each modifier and its tier mark): what a
-- script that copies an item by hand (the guild depot) must copy
function C.attributeKeys()
	local out = {"rarity", M.ILVL, "combatPowerLevel", M.QUALITY, M.RUINED, M.EXTRA}
	for _, a in ipairs(C.affixes()) do
		out[#out + 1] = a.key
		if a.key2 then
			out[#out + 1] = a.key2
		end
		out[#out + 1] = M.tierAttr(a.key)
		out[#out + 1] = M.rawAttr(a.key)
		out[#out + 1] = M.bindAttr(a.key)
	end
	return out
end

function C.affixOf(key)
	C.affixes()
	return C.affixByKey[tostring(key):lower()]
end

-- ---------------------------------------------------------------------------------------------------------------
-- reading an item
-- ---------------------------------------------------------------------------------------------------------------
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

local function custom(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	if not ok then
		return nil
	end
	return v
end

function C.customNumber(item, key)
	return num(custom(item, key)) or 0
end

-- the rarity (a drop's rarity is a text while the engine's own roll passes the corpse: C.shield)
function C.rarityOf(item)
	local r = math.floor(C.customNumber(item, "rarity"))
	if r < 0 or r > #C.config.rarityNames then
		return 0
	end
	return r
end

function C.rarityName(r)
	return C.config.rarityNames[r] or ("Rarity " .. tostring(r))
end

function C.levelOf(item)
	return M.itemLevelOf(item)
end

function C.isUnique(item)
	if custom(item, "chaos_unique") ~= nil then
		return true
	end
	-- a unique made before the marker existed: its base id has a spec and it carries the spec's name
	local spec = ChaosUniqueSpecs and ChaosUniqueSpecs[item:getId()]
	if spec and ITEM_ATTRIBUTE_NAME then
		local ok, name = pcall(function() return item:getAttribute(ITEM_ATTRIBUTE_NAME) end)
		if ok and name == spec.name then
			return true
		end
	end
	return false
end

-- the tier of a modifier: stored, else from its value (a critical / leech pair: from its amount)
local function tierOf(item, affix, value)
	local t = M.storedTier(item, affix.key)
	if t then
		return t
	end
	return M.tierOfValue(affix.tiers, value)
end

-- list of modifiers in description order:
-- {group, key, key2, label, label2, value, value2, tier, side, lo, hi, chaosKey, affix}
function C.readMods(item)
	local mods = {}
	local function push(m, affix, tierValue)
		m.affix = affix
		m.side = affix and affix.side or "suffix"
		m.tier = affix and tierOf(item, affix, tierValue) or 1
		m.bound = M.isBound(item, m.key)
		m.power = affix and affix.def and M.isPower(affix.def) or false
		if affix then
			local r = M.tierRange(affix.tiers, m.tier)
			m.lo, m.hi = r[1], r[2]
			if m.group == "special" then
				m.lo, m.hi = C.specialChance(r[1]), C.specialChance(r[2]) -- the chance part (value); value2 = amount
				m.lo2, m.hi2 = r[1], r[2]
			end
		end
		mods[#mods + 1] = m
	end
	C.affixes()
	for _, a in ipairs(C.absorbs) do
		local v = C.customNumber(item, a.key)
		if v ~= 0 then
			push({group = "absorb", key = a.key, label = a.label, value = v}, C.affixOf(a.key), v)
		end
	end
	for _, s in ipairs(C.skills) do
		local v = C.customNumber(item, s.key)
		if v ~= 0 then
			push({group = "skill", key = s.key, label = s.label, value = v}, C.affixOf(s.key), v)
		end
	end
	for _, s in ipairs(C.specials) do
		local v, v2 = C.customNumber(item, s.key), C.customNumber(item, s.key2)
		if v ~= 0 or v2 ~= 0 then
			push({group = "special", key = s.key, key2 = s.key2, label = s.label, label2 = s.label2, value = v, value2 = v2},
				C.affixOf(s.key), v2 ~= 0 and v2 or v)
		end
	end
	for _, m in ipairs(M.read(item)) do
		push({group = "chaos", key = M.attr(m.key), chaosKey = m.key, label = m.label, value = m.value},
			C.affixOf(M.attr(m.key)), m.value)
	end
	for _, e in ipairs(C.elements) do
		local v = C.customNumber(item, e.key)
		if v ~= 0 then
			push({group = "element", key = e.key, label = e.label, value = v}, C.affixOf(e.key), v)
		end
	end
	return mods
end

-- prefixes and suffixes on the item: p, s
function C.sideCounts(mods)
	local p, s = 0, 0
	for _, m in ipairs(mods) do
		if m.side == "prefix" then
			p = p + 1
		else
			s = s + 1
		end
	end
	return p, s
end

-- text of one modifier, as item.cpp writes it into the description
function C.modText(m)
	if m.group == "absorb" then
		return string.format("%s +%d%%", m.label, m.value)
	elseif m.group == "skill" then
		return string.format("%s +%d", m.label, m.value)
	elseif m.group == "special" then
		return string.format("%s +%d%%, %s +%d%%", m.label, m.value, m.label2, m.value2 or m.value)
	elseif m.group == "chaos" then
		return M.text(m.chaosKey, m.value)
	end
	return string.format("%s +%d%% dmg", m.label, m.value)
end

-- with the tier: "Sword +2 (T3)"
function C.modTierText(m)
	return string.format("%s (T%d%s)", C.modText(m), m.tier or 1, m.bound and ", bound" or "")
end

-- the modifier part of the description: "Prefixes: Sword +2 (T3); Fire +5% dmg (T2). Suffixes: Earth +2% (T4)"
function C.modsText(mods)
	local pre, suf = {}, {}
	for _, m in ipairs(mods) do
		local list = m.side == "prefix" and pre or suf
		list[#list + 1] = C.modTierText(m)
	end
	local parts = {}
	if #pre > 0 then
		parts[#parts + 1] = "Prefixes: " .. table.concat(pre, "; ")
	end
	if #suf > 0 then
		parts[#parts + 1] = "Suffixes: " .. table.concat(suf, "; ")
	end
	return table.concat(parts, ". ")
end

-- ---------------------------------------------------------------------------------------------------------------
-- eligibility
-- ---------------------------------------------------------------------------------------------------------------
local function itemType(item)
	local ok, it = pcall(function() return ItemType(item:getId()) end)
	return ok and it or nil
end

local function typeNumber(it, method)
	local ok, v = pcall(function() return it[method](it) end)
	return ok and tonumber(v) or 0
end

-- gear that can carry a rarity: same test as the stock reroll script (isRerollable) plus an equipment slot
function C.isGear(item)
	local it = itemType(item)
	if not it then
		return false
	end
	if C.config.excludedItems[item:getId()] then
		return false
	end
	local ok, flag = pcall(function() return it:isContainer() or it:isStackable() end)
	if not ok or flag then
		return false
	end
	if typeNumber(it, "getSlotPosition") == 0 and typeNumber(it, "getWeaponType") == 0 then
		return false
	end
	if typeNumber(it, "getWeaponType") ~= 0 then
		return true
	end
	for _, m in ipairs({"getArmor", "getAttack", "getDefense", "getHitChance"}) do
		if typeNumber(it, m) > 0 then
			return true
		end
	end
	local okAb, ab = pcall(function() return it:getAbilities() end)
	if okAb and type(ab) == "table" and (ab.skills or ab.absorbPercent or ab.specialSkills) then
		return true
	end
	return false
end

-- weapons with an attack and no element of their own may carry an element modifier (as item.cpp)
function C.canHaveElement(item)
	local it = itemType(item)
	if not it then
		return false
	end
	return typeNumber(it, "getWeaponType") ~= 0 and typeNumber(it, "getAttack") > 0
		and typeNumber(it, "getElementDamage") <= 0
end

-- true when the item has no rarity, no modifiers and no rolled level (the +N upgrade scripts write one too; the item
-- level of a plain drop, "chaos_ilvl", does not count)
function C.isNormal(item)
	return C.rarityOf(item) == 0 and #C.readMods(item) == 0 and C.customNumber(item, "combatPowerLevel") == 0
end

function C.maxMods(rarity)
	return M.maxMods(rarity)
end

-- every modifier this item may carry: its rarity's, plus the one extra slot an Orb of Ruin gave
function C.maxModsOf(item, rarity)
	return M.maxMods(rarity or C.rarityOf(item)) + (M.extraSide(item) and 1 or 0)
end

-- how many modifiers are bound / how many may be
function C.bindCount(mods)
	local n = 0
	for _, m in ipairs(mods) do
		if m.bound then
			n = n + 1
		end
	end
	return n
end

-- the modifiers that could still be added: list of {entry = affix, weight}. Not on the item yet, allowed on its kind,
-- an open side (rarity's prefix / suffix limit, plus the extra slot; rarity = the item's unless given), one element at
-- most on a weapon that may have one, a legendary power only from Legendary on and only one per item. opts.extra = true:
-- one more than the limit on each side (the Orb of Ruin's extra slot).
function C.candidates(item, rarity, mods, opts)
	mods = mods or C.readMods(item)
	rarity = rarity or C.rarityOf(item)
	local have, elements, powers = {}, 0, 0
	for _, m in ipairs(mods) do
		have[m.key:lower()] = true
		if m.group == "element" then
			elements = elements + 1
		end
		if m.power then
			powers = powers + 1
		end
	end
	local p, s = C.sideCounts(mods)
	local extra = opts and opts.extra and 1 or 0
	local open = {prefix = p < M.sideLimitOf(item, "prefix", rarity) + extra,
		suffix = s < M.sideLimitOf(item, "suffix", rarity) + extra}
	local kind = M.kindOf(item)
	local elementOk = elements < C.config.maxElements and C.canHaveElement(item)
	local powerOk = rarity >= M.config.powers.minRarity and powers < M.config.powers.maxPerItem
	local out = {}
	for _, a in ipairs(C.affixes()) do
		local isPower = a.def and M.isPower(a.def)
		if not have[a.key:lower()] and open[a.side] and M.allowed(a, kind) and (a.group ~= "element" or elementOk)
				and (not isPower or powerOk) then
			out[#out + 1] = {entry = a, weight = a.weight}
		end
	end
	return out
end

C.reasons = {
	notGear = "This item cannot carry modifiers.",
	unique = "Unique items cannot be changed by orbs.",
	stack = "Orbs work on a single item.",
	needNormal = "This orb works only on a normal item (no rarity, no modifiers).",
	needRarity = "This orb works only on an item with a rarity.",
	full = "This item has no free modifier slot.",
	sidesFull = "Every open prefix and suffix of this item is taken.",
	noMods = "This item has no modifier to remove.",
	nothingToAdd = "There is no modifier left that this item could get.",
	unknownOrb = "Unknown orb.",
	ruined = "This item is ruined: no orb can change it any more.",
	allBound = "Every modifier of this item is bound.",
	noneBound = "This item has no bound modifier.",
	tooManyBinds = "This item has all the bound modifiers its rarity allows.",
	needMod = "Choose a modifier of the item first.",
	badMod = "That modifier cannot be chosen for this orb.",
	hasBound = "Bound modifiers stop this orb: use an Orb of Erasure first.",
	qualityFull = "This item has all the quality it can get.",
	needMods = "This item has no modifier for the quality to act on.",
	ruinNothing = "Nothing left to risk: the item has no modifier an Orb of Ruin could improve.",
	keyNeedNone = "This orb works only on a Rift Key without modifiers.",
	keyNoMods = "This Rift Key has no modifiers.",
	keyFull = "This Rift Key has the most modifiers a key can have.",
	keyNothing = "There is no modifier left that this Rift Key could get.",
	keySockets = "Rift Keys have no sockets.",
	keyOrb = "This orb does not work on Rift Keys."
}

-- the modifiers an orb may be aimed at (attribute keys), for the orbs that take one (orb.pick); empty = none
function C.pickList(orbKey, item)
	local orb = C.orbByKey[orbKey]
	if not orb or not item then
		return {}
	end
	if C.isRiftKey(item) then
		return orb.keyPick and orb.keyPick(item) or {}
	end
	return orb.pick and orb.pick(item) or {}
end

-- can this orb be used on this item? returns true or false, reasonCode. opts.mod = the attribute key of the modifier it is
-- aimed at (orbs with `pick`; none = the orb chooses at random where it may)
function C.check(orbKey, item, opts)
	local orb = C.orbByKey[orbKey]
	if not orb then
		return false, "unknownOrb"
	end
	if item and C.isRiftKey(item) then
		if orb.check and not orb.keyCheck then
			return false, "keyOrb"
		end
		if orb.keyCheck then
			return orb.keyCheck(item)
		end
		return C.keyCheck(orbKey, item)
	end
	if not item or not C.isGear(item) then
		return false, "notGear"
	end
	if M.isRuined(item) then
		return false, "ruined"
	end
	if orbKey == "sockets" then
		local okS, why = G.orbCheck(item)
		if not okS then
			return false, C.reasons[why] and why or (G.reasons[why] or why) -- unique, notGear, stack: the orbs' own codes
		end
		return true
	end
	if C.isUnique(item) then
		return false, "unique"
	end
	local okCount, count = pcall(function() return item:getCount() end)
	if okCount and tonumber(count) and count > 1 then
		return false, "stack"
	end
	if orb.check then
		return orb.check(item, opts)
	end
	local rarity = C.rarityOf(item)
	if orbKey == "transmutation" or orbKey == "alchemy" then
		if not C.isNormal(item) then
			return false, "needNormal"
		end
	elseif orbKey == "divine" then
		if C.bindCount(C.readMods(item)) > 0 then
			return false, "hasBound"
		end
		return true
	else
		if rarity == 0 then
			return false, "needRarity"
		end
		local mods = C.readMods(item)
		if orbKey == "exalted" then
			if #mods >= C.maxModsOf(item, rarity) then
				return false, "full"
			end
			if #C.candidates(item, rarity, mods) == 0 then
				local p, s = C.sideCounts(mods)
				return false, (p >= M.sideLimitOf(item, "prefix", rarity) or s >= M.sideLimitOf(item, "suffix", rarity))
					and "sidesFull" or "nothingToAdd"
			end
		elseif orbKey == "annulment" then
			if #mods == 0 then
				return false, "noMods"
			end
			if #mods == C.bindCount(mods) then
				return false, "allBound"
			end
		elseif orbKey == "chaos" then
			if #mods > 0 and #mods == C.bindCount(mods) then
				return false, "allBound"
			end
		end
	end
	return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- rolls
-- ---------------------------------------------------------------------------------------------------------------
function C.weighted(rows) -- rows = {{value, weight}, ...}
	local total = 0
	for _, r in ipairs(rows) do
		total = total + r[2]
	end
	if total <= 0 then
		return nil
	end
	local roll, acc = C.random(1, total), 0
	for _, r in ipairs(rows) do
		acc = acc + r[2]
		if roll <= acc then
			return r[1]
		end
	end
	return rows[#rows][1]
end

-- the chance of a critical / leech pair rolled as `v` (the amount keeps v): about two thirds, as engine patch 0004
-- does since the chance rolls are uniform (1..6 -> 1, 1, 2, 3, 3, 4)
function C.specialChance(v)
	return math.max(1, math.floor((2 * v + 1) / 3))
end

-- the stock Orb of Fate roll: 0 (no rarity) most of the time
function C.rollDivineRarity()
	if C.random(1, 100) > C.config.divineRollChance then
		return 0
	end
	for id, chance in ipairs(C.config.divineChances) do
		if C.random(1, 100) <= chance then
			return id
		end
	end
	return 0
end

-- item quality in percent (0 when none)
function C.qualityOf(item)
	return M.qualityOf(item)
end

local function removeCustom(item, key)
	pcall(function() item:removeCustomAttribute(key) end)
end

-- write one modifier of `affix` at `tier` (the value rolled inside the tier unless given; `value` is always the value
-- before quality). With item quality q the item carries value x (100 + q) / 100, rounded, and keeps the rolled value
-- under "cv_<key>" so the next quality step starts from it. Returns the modifier.
function C.writeAffix(item, affix, tier, value, rand)
	rand = rand or C.random
	local r = M.tierRange(affix.tiers, tier)
	value = value or rand(r[1], r[2])
	local q = M.qualityOf(item)
	local function eff(v)
		return q > 0 and M.scaleQuality(v, q) or v
	end
	local m = {group = affix.group, key = affix.key, key2 = affix.key2, label = affix.label, label2 = affix.label2,
		chaosKey = affix.chaosKey, side = affix.side, tier = tier, lo = r[1], hi = r[2], affix = affix,
		bound = M.isBound(item, affix.key), power = affix.def and M.isPower(affix.def) or false}
	if affix.group == "chaos" then
		M.set(item, affix.chaosKey, eff(value), tier)
		m.value = eff(value)
	elseif affix.group == "special" then
		m.value, m.value2 = eff(C.specialChance(value)), eff(value)
		item:setCustomAttribute(affix.key, m.value)
		item:setCustomAttribute(affix.key2, m.value2)
		M.setTier(item, affix.key, tier)
		m.lo, m.hi, m.lo2, m.hi2 = C.specialChance(r[1]), C.specialChance(r[2]), r[1], r[2]
	else
		item:setCustomAttribute(affix.key, eff(value))
		M.setTier(item, affix.key, tier)
		m.value = eff(value)
	end
	if q > 0 then
		item:setCustomAttribute(M.rawAttr(affix.key), value)
	else
		removeCustom(item, M.rawAttr(affix.key))
	end
	return m
end

-- roll one modifier of `affix` on an item of item level `level`: the tier among those the level allows, the value
-- inside the tier
function C.rollAffix(item, affix, level, rand)
	rand = rand or C.random
	return C.writeAffix(item, affix, M.rollTier(level, rand), nil, rand)
end

-- add `n` random modifiers (the rarity's side limits, the item's kind). Returns the added ones.
function C.rollAffixes(item, rarity, level, n, rand)
	rand = rand or C.random
	local added = {}
	for _ = 1, n or 0 do
		local affix = M.pick(C.candidates(item, rarity), rand)
		if not affix then
			break
		end
		added[#added + 1] = C.rollAffix(item, affix, level, rand)
	end
	return added
end

-- the value a modifier was rolled at, before the item's quality
function C.rawValue(item, m)
	local v = custom(item, M.rawAttr(m.key))
	v = num(v)
	if v and v > 0 then
		return math.floor(v)
	end
	return m.group == "special" and m.value2 or m.value
end

-- remove one modifier (as C.readMods returns it); its tier, bind and rolled value go too. A bound modifier stays unless
-- force is set (the plain copies of the orbs). Returns true when it went.
function C.removeMod(item, m, force)
	if m.bound and not force then
		return false
	end
	if m.group == "chaos" then
		M.remove(item, m.chaosKey)
	else
		item:removeCustomAttribute(m.key)
		if m.key2 then
			item:removeCustomAttribute(m.key2)
		end
		M.removeTier(item, m.key)
	end
	removeCustom(item, M.rawAttr(m.key))
	removeCustom(item, M.bindAttr(m.key))
	return true
end

-- every modifier, tier mark, bind and the extra slot go (rarity, level and quality stay)
function C.clearMods(item)
	for _, m in ipairs(C.readMods(item)) do
		C.removeMod(item, m, true)
	end
	for _, a in ipairs(C.affixes()) do
		M.removeTier(item, a.key)
		removeCustom(item, M.rawAttr(a.key))
		removeCustom(item, M.bindAttr(a.key))
	end
	removeCustom(item, M.EXTRA)
end

-- the modifier of an item under this attribute key (as C.readMods returns it) or nil
function C.modByKey(item, key, mods)
	key = tostring(key or ""):lower()
	for _, m in ipairs(mods or C.readMods(item)) do
		if m.key:lower() == key then
			return m
		end
	end
	return nil
end

-- bind (or free) one modifier. Returns true when it changed.
function C.setBound(item, m, on)
	if (m.bound and true or false) == (on and true or false) then
		return false
	end
	M.setBound(item, m.key, on)
	m.bound = on and true or false
	return true
end

-- new values inside the current tiers of every modifier that is not bound (the Orb of Tempering)
function C.rerollValues(item, rand)
	for _, m in ipairs(C.readMods(item)) do
		if m.affix and not m.bound then
			C.writeAffix(item, m.affix, m.tier, nil, rand)
		end
	end
	C.rewriteDescription(item)
end

-- new tiers (by the item level) and values for the same modifiers that are not bound (orbs v2); `only` = one modifier
function C.rerollTiers(item, rand, only)
	local level = C.orbLevel(item)
	for _, m in ipairs(C.readMods(item)) do
		if m.affix and not m.bound and (not only or m.key:lower() == tostring(only):lower()) then
			C.rollAffix(item, m.affix, level, rand)
		end
	end
	C.rewriteDescription(item)
end

-- the Orb of Whetstone: `stones` x the configured percent more quality, up to the cap of the item's rarity. Every value
-- is worked out again from the value it was rolled at. Returns the new quality, the old one.
function C.addQuality(item, stones)
	local old = M.qualityOf(item)
	local rarity = C.rarityOf(item)
	local q = math.min(M.qualityCap(rarity), old + (tonumber(stones) or 1) * M.config.quality.perStone)
	if q == old then
		return q, old
	end
	local mods = C.readMods(item)
	local raws = {}
	for i, m in ipairs(mods) do
		raws[i] = C.rawValue(item, m) -- before the quality changes (a stored raw value, else the value as it is)
	end
	item:setCustomAttribute(M.QUALITY, q)
	for i, m in ipairs(mods) do
		if m.affix then
			C.writeAffix(item, m.affix, m.tier, raws[i], nil) -- the tier is stored by this call too (old items had none)
		end
	end
	C.rewriteDescription(item)
	return q, old
end

-- the base stat bonus of a rarity at an item level (item.cpp's formula)
function C.baseBonusOf(rarity, level)
	local b = C.config.baseBonus[rarity]
	if not b then
		return 0
	end
	return b[1] + math.floor((tonumber(level) or 0) * (b[2] - b[1] + 1) / 100)
end

-- attack / defense / armor / hit chance = the item type's + the bonus (only on a fresh item: the forge of a drop or
-- of an orb's new copy)
function C.applyBaseBonus(item, rarity, level)
	local it = itemType(item)
	local bonus = C.baseBonusOf(rarity, level)
	if not it or bonus <= 0 then
		return
	end
	local function raise(attr, method)
		local base = typeNumber(it, method)
		if attr and base > 0 then
			item:setAttribute(attr, base + bonus)
		end
	end
	raise(ITEM_ATTRIBUTE_ATTACK, "getAttack")
	raise(ITEM_ATTRIBUTE_DEFENSE, "getDefense")
	raise(ITEM_ATTRIBUTE_ARMOR, "getArmor")
	raise(ITEM_ATTRIBUTE_HITCHANCE, "getHitChance")
end

-- the whole roll of an item with a rarity: rarity, item level, base bonus (opts.base ~= false), as many modifiers as
-- the rarity gets (M.modCount), each tier by the item level, prefixes and suffixes apart; the description. Every
-- earlier modifier goes. Returns the added modifiers.
function C.forge(item, rarity, level, rand, opts)
	rand = rand or C.random
	level = math.max(1, math.min(M.config.itemLevel.max, math.floor(tonumber(level) or 1)))
	C.clearMods(item)
	item:setCustomAttribute("rarity", rarity)
	item:setCustomAttribute(M.ILVL, level)
	item:setCustomAttribute("combatPowerLevel", level)
	if not opts or opts.base ~= false then
		C.applyBaseBonus(item, rarity, level)
	end
	local added = C.rollAffixes(item, rarity, level, M.modCount(rarity), rand)
	C.rewriteDescription(item)
	return added
end

-- the item level an orb uses: the item's own, else one from the item type's required level (old plain items)
function C.orbLevel(item)
	local level = C.levelOf(item)
	if level > 0 then
		return level
	end
	local it = itemType(item)
	return M.sourceLevel({monsterLevel = math.max(1, it and typeNumber(it, "getMinReqLevel") or 1)})
end

-- a new item of id with this rarity (0 = plain, keeps only the level) and item level, rolled by C.forge. For every
-- script that hands out gear (rift chests, world boss, treasure goblin, store, tutorial): use it instead of
-- Game.createItemWithRarity, whose engine roll ignores item levels and tiers.
function C.createItem(id, rarity, level, rand)
	local item = Game.createItem(id, 1)
	if not item then
		return nil
	end
	rarity = tonumber(rarity) or 0
	if C.isGear(item) and not C.isUnique(item) then
		if rarity > 0 then
			C.forge(item, rarity, level, rand)
		elseif level then
			item:setCustomAttribute(M.ILVL, math.max(1, math.floor(level)))
		end
	end
	return item
end

-- While the engine's rarity pass (Monster::dropLoot, after every onDropLoot callback) runs over a corpse, a forged drop
-- keeps its rarity as text: the pass rolls only items whose "rarity" is a number, so it leaves ours alone. Every
-- reader goes through tonumber; C.unshield (item_mods.lua, a tick later, and on the way out of a corpse) makes it a
-- number again.
function C.shield(item)
	local r = C.rarityOf(item)
	if r > 0 then
		item:setCustomAttribute("rarity", tostring(r))
	end
end

function C.unshield(item)
	local raw = custom(item, "rarity")
	if type(raw) == "string" then
		local r = C.rarityOf(item)
		if r > 0 then
			item:setCustomAttribute("rarity", r)
		else
			item:removeCustomAttribute("rarity")
		end
		return true
	end
	return false
end

-- ---------------------------------------------------------------------------------------------------------------
-- description
-- ---------------------------------------------------------------------------------------------------------------
local function descriptionOf(item)
	local ok, d = pcall(function() return item:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION) end)
	if ok and type(d) == "string" then
		return d
	end
	return ""
end

-- rewrite the rarity part of the description from the item's attributes. Text in front of "Item Level: N" (or an
-- old item's "Level: N") and bracketed upgrade slots behind it ("[Attack+2]", customs/upgrade) are kept.
function C.rewriteDescription(item)
	local old = G.strip(descriptionOf(item)) -- the sockets section is written again at the end
	local prefix, rest = old, ""
	local s = old:find("Item Level:%s*%-?%d+") or old:find("Level:%s*%-?%d+")
	if s then
		prefix, rest = old:sub(1, s - 1), old:sub(s)
	end
	local slots = {}
	for b in rest:gmatch("%[[^%]]*%]") do
		slots[#slots + 1] = b
	end
	prefix = prefix:gsub("[,%.%s]+$", "")
	local body = "Item Level: " .. C.levelOf(item)
	local quality = M.qualityOf(item)
	if quality > 0 then
		body = body .. string.format(". Quality: +%d%%", quality)
	end
	if M.isRuined(item) then
		body = body .. ". Ruined"
	end
	local modsText = C.modsText(C.readMods(item))
	if modsText ~= "" then
		body = body .. ". " .. modsText
	end
	local text = prefix ~= "" and (prefix .. ". " .. body) or body
	if #slots > 0 then
		text = text .. " " .. table.concat(slots, ", ")
	end
	text = G.append(text, item)
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, text)
	M.sendUpdate(item) -- every change of the modifiers ends here: the client gets the new attributes
	return text
end

-- ---------------------------------------------------------------------------------------------------------------
-- the orbs that change an item in place
-- ---------------------------------------------------------------------------------------------------------------
-- Orb of Grafting: one new modifier on an open side, its tier by the item level. Returns the added modifier.
function C.exalt(item)
	local rarity = C.rarityOf(item)
	local affix = M.pick(C.candidates(item, rarity), C.random)
	if not affix then
		return nil
	end
	local m = C.rollAffix(item, affix, C.orbLevel(item), C.random)
	C.rewriteDescription(item)
	return m
end

-- Orb of Unmaking: one random modifier goes. Returns the removed modifier.
function C.annul(item)
	local free = {}
	for _, m in ipairs(C.readMods(item)) do
		if not m.bound then
			free[#free + 1] = m
		end
	end
	if #free == 0 then
		return nil
	end
	local m = free[C.random(1, #free)]
	C.removeMod(item, m)
	C.rewriteDescription(item)
	return m
end

-- Orb of Upheaval on an item with bound modifiers: they stay, every other modifier is rolled again in place (the rarity's
-- count minus the bound ones; an extra slot stays). Returns the new modifiers.
function C.upheave(item, rand)
	rand = rand or C.random
	local rarity, level = C.rarityOf(item), C.orbLevel(item)
	local kept = 0
	for _, m in ipairs(C.readMods(item)) do
		if m.bound then
			kept = kept + 1
		else
			C.removeMod(item, m)
		end
	end
	local added = C.rollAffixes(item, rarity, level, math.max(0, M.modCount(rarity) - kept), rand)
	C.rewriteDescription(item)
	return added
end

-- ---------------------------------------------------------------------------------------------------------------
-- the orbs that make a new copy of the base item
-- ---------------------------------------------------------------------------------------------------------------
-- rarity the new copy gets for this orb (0 = a normal copy)
function C.targetRarity(orbKey, item)
	if orbKey == "transmutation" then
		return C.weighted(C.config.transmutation)
	elseif orbKey == "alchemy" then
		return C.weighted(C.config.alchemy)
	elseif orbKey == "scouring" then
		return 0
	elseif orbKey == "chaos" then
		return C.rarityOf(item)
	elseif orbKey == "divine" then
		return C.rollDivineRarity()
	end
	return nil
end

-- make the new copy (rarity and level rolled by C.forge; level = the old item's, which every orb keeps) and put it
-- where the old one was (same container). Returns the new item or nil, reason.
function C.recreate(item, rarity, level)
	local id = item:getId()
	level = level or C.orbLevel(item)
	local newItem = Game.createItem(id, 1)
	if not newItem then
		return nil, "The orb fizzles: the new item could not be made."
	end
	G.copy(item, newItem) -- sockets and gems survive every orb (chaos_gems.lua)
	local quality = M.qualityOf(item)
	if quality > 0 then
		newItem:setCustomAttribute(M.QUALITY, quality) -- item quality survives every orb; forge rolls with it
	end
	if ChaosSalvage and ChaosSalvage.copyLock then
		ChaosSalvage.copyLock(item, newItem) -- the item lock too (salvage.lua)
	end
	if rarity > 0 then
		C.forge(newItem, rarity, level, C.random)
	else
		newItem:setCustomAttribute(M.ILVL, level)
		if quality > 0 then
			C.rewriteDescription(newItem) -- "Quality: +N%"
		elseif G.count(newItem) > 0 then
			G.writeDescription(newItem)
		end
	end
	local parent = item:getParent()
	if not parent or not parent.addItemEx then
		newItem:remove()
		return nil, "Put the item in your backpack first."
	end
	-- FLAG_NOLIMIT: the old copy still takes its slot and weight until it is removed below
	local ret = parent:addItemEx(newItem, INDEX_WHEREEVER or -1, FLAG_NOLIMIT or 1)
	if ret ~= (RETURNVALUE_NOERROR or 0) then
		newItem:remove()
		return nil, "There is no room for the item."
	end
	item:remove()
	return newItem
end

-- ---------------------------------------------------------------------------------------------------------------
-- apply an orb (the caller has checked ownership and position, and removes the orb on success)
-- returns ok, result where result = {item = <the item now>, text = <what happened>, mods = {...}} or a message
-- ---------------------------------------------------------------------------------------------------------------
function C.apply(orbKey, item, opts)
	local ok, reason = C.check(orbKey, item, opts)
	if not ok then
		return false, C.reasons[reason] or reason
	end
	local orb = C.orbByKey[orbKey]
	if C.isRiftKey(item) then
		if orb.keyApply then
			return orb.keyApply(item, opts)
		end
		return C.keyApply(orbKey, item)
	end
	if orb.apply then
		return orb.apply(item, opts)
	end
	local name = C.itemName(item)
	if orbKey == "sockets" then
		local n, old = G.orbApply(item, C.random)
		G.writeDescription(item)
		return true, {item = item, text = string.format("%s now has %d socket%s (had %d).", name, n, n == 1 and "" or "s",
			old), sockets = n}
	end
	if orbKey == "exalted" then
		local m = C.exalt(item)
		if not m then
			return false, C.reasons.nothingToAdd
		end
		return true, {item = item, text = string.format("%s gained %s (%s).", name, C.modTierText(m), m.side), added = m}
	elseif orbKey == "annulment" then
		local m = C.annul(item)
		if not m then
			return false, C.reasons.noMods
		end
		return true, {item = item, text = string.format("%s lost %s.", name, C.modTierText(m)), removed = m}
	end
	if orbKey == "chaos" and C.bindCount(C.readMods(item)) > 0 then
		local added = C.upheave(item, C.random)
		return true, {item = item, text = string.format("%s: %d new modifier%s, the bound ones stayed (%s).", name, #added,
			#added == 1 and "" or "s", C.modsText(C.readMods(item))), added = added}
	end
	local rarity = C.targetRarity(orbKey, item)
	if not rarity then
		return false, C.reasons.unknownOrb
	end
	local level = C.orbLevel(item)
	local newItem, err = C.recreate(item, rarity, level)
	if not newItem then
		return false, err
	end
	local text
	if rarity > 0 then
		local mods = C.readMods(newItem)
		text = string.format("%s is now %s (item level %d): %s.", name, C.rarityName(rarity), C.levelOf(newItem),
			#mods > 0 and C.modsText(mods) or "no modifiers")
	else
		text = string.format("%s is now a normal item (item level %d).", name, level)
	end
	return true, {item = newItem, text = text, rarity = rarity}
end

-- ---------------------------------------------------------------------------------------------------------------
-- drops: the loot layer (loot.lua) forges every gear item with a rarity in the corpse at the source's item level and
-- shields it from the engine's own pass (C.shield); a plain gear drop gets the item level only.
-- ---------------------------------------------------------------------------------------------------------------
function C.forgeDrop(item, level, rand)
	if not item or not C.isGear(item) or C.isUnique(item) then
		return {}
	end
	local rarity = C.rarityOf(item)
	if rarity < 1 then
		if level and C.levelOf(item) == 0 then
			item:setCustomAttribute(M.ILVL, math.max(1, math.floor(level)))
		end
		return {}
	end
	local added = C.forge(item, rarity, level or C.orbLevel(item), rand or M.random)
	C.shield(item)
	return added
end

-- ---------------------------------------------------------------------------------------------------------------
-- Rift Keys (rift.lua / rift_core.lua / rift_config.lua). The orbs work on the key's modifiers the map way, inside the
-- rift's own modifier pool and value ranges; the tier never changes. The reward bonuses follow from the modifiers
-- (rift_core.lua R.bonuses), so the rewritten description shows the new ones.
-- ---------------------------------------------------------------------------------------------------------------
local function rift()
	if not ChaosRiftCore then
		pcall(dofile, "data/scripts/chaos/rift_core.lua")
	end
	if not ChaosRiftConfig then
		local ok, cfg = pcall(dofile, "data/scripts/chaos/rift_config.lua")
		if ok then
			ChaosRiftConfig = cfg
		end
	end
	return ChaosRiftCore, ChaosRiftConfig
end
C.rift = rift

function C.keyMaxMods()
	local _, cfg = rift()
	return cfg and cfg.key and cfg.key.maxMods or 3
end

function C.isRiftKey(item)
	local _, cfg = rift()
	if not cfg or not item then
		return false
	end
	local ok, res = pcall(function()
		return item:getId() == cfg.key.itemId and item:getActionId() == cfg.key.actionId
			and item:getCustomAttribute("rift_tier") ~= nil
	end)
	return ok and res or false
end

-- {tier, mods = {{key, value}, ...}}
function C.readKey(item)
	local R, cfg = rift()
	return {tier = R.clampTier(cfg, num(custom(item, "rift_tier")) or 1), mods = R.decodeMods(cfg, custom(item, "rift_mods") or "")}
end

function C.writeKey(item, key)
	local R, cfg = rift()
	if ChaosRift and ChaosRift.applyKey then
		return ChaosRift.applyKey(item, key)
	end
	item:setCustomAttribute("rift_tier", key.tier)
	item:setCustomAttribute("rift_mods", R.encodeMods(key.mods))
	item:setAttribute(ITEM_ATTRIBUTE_NAME, R.keyName(cfg, key.tier))
	if ITEM_ATTRIBUTE_ARTICLE then
		item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, "a")
	end
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, R.describe(cfg, key))
	return item
end

function C.keyCheck(orbKey, item)
	if orbKey == "sockets" then
		return false, "keySockets"
	end
	local _, cfg = rift()
	local key = C.readKey(item)
	local n = #key.mods
	if orbKey == "transmutation" or orbKey == "alchemy" then
		if n > 0 then
			return false, "keyNeedNone"
		end
	elseif orbKey == "exalted" then
		if n >= C.keyMaxMods() then
			return false, "keyFull"
		end
		if n >= #cfg.mods then
			return false, "keyNothing"
		end
	elseif n == 0 then -- annulment, scouring, chaos, divine
		return false, "keyNoMods"
	end
	return true
end

-- `count` new modifiers the key does not have yet: weighted and gated by the key's tier, as on drops (rift_core.lua)
local function addKeyMods(key, count)
	local R, cfg = rift()
	return R.addMods(cfg, key, count, C.random)
end

local function keyModsText(key)
	local R, cfg = rift()
	local parts = {}
	for _, m in ipairs(key.mods) do
		parts[#parts + 1] = R.modText(cfg, m)
	end
	return #parts > 0 and table.concat(parts, "; ") or "no modifiers"
end

function C.keyApply(orbKey, item)
	local R, cfg = rift()
	local key = C.readKey(item)
	local name = R.keyName(cfg, key.tier)
	local text
	if orbKey == "transmutation" then
		addKeyMods(key, 1)
	elseif orbKey == "alchemy" then
		addKeyMods(key, C.weighted(cfg.key.alchemyCount or {{2, 60}, {3, 40}}))
	elseif orbKey == "exalted" then
		addKeyMods(key, 1)
	elseif orbKey == "annulment" then
		local m = table.remove(key.mods, C.random(1, #key.mods))
		text = string.format("%s lost \"%s\".", name, R.modText(cfg, m))
	elseif orbKey == "scouring" then
		key.mods = {}
		text = string.format("%s has no modifiers now.", name)
	elseif orbKey == "chaos" then
		key.mods = {}
		addKeyMods(key, math.min(C.keyMaxMods(), R.rollModCount(cfg, C.random)))
	elseif orbKey == "divine" then
		for _, m in ipairs(key.mods) do
			m.value = R.rollValue(R.modDef(cfg, m.key), C.random, key.tier, cfg) -- inside the tier window of the key
		end
	else
		return false, C.reasons.unknownOrb
	end
	C.writeKey(item, key)
	local b = R.bonuses(cfg, key.mods, key.tier)
	text = text or string.format("%s: %s.", name, keyModsText(key))
	text = string.format("%s Rewards: +%d%% quantity, +%d%% rarity, +%d%% experience.", text, b.quantity, b.rarity,
		b.experience)
	return true, {item = item, text = text, key = key}
end

-- ---------------------------------------------------------------------------------------------------------------
-- preview: what an orb would do to this item (the bench shows it next to the orb)
-- ---------------------------------------------------------------------------------------------------------------
local function chances(rows)
	local total = 0
	for _, r in ipairs(rows) do
		total = total + r[2]
	end
	local parts = {}
	for _, r in ipairs(rows) do
		parts[#parts + 1] = string.format("%s %d%%", C.rarityName(r[1]), math.floor(r[2] * 100 / total + 0.5))
	end
	return table.concat(parts, ", ")
end

-- "T1-T3" for an item level
local function tierSpan(level)
	local rows = M.tierRows(level)
	local hi, lo = rows[1][1], rows[#rows][1]
	return lo == hi and string.format("T%d", hi) or string.format("T%d-T%d", lo, hi)
end
C.tierSpan = tierSpan

function C.preview(orbKey, item)
	if C.isRiftKey(item) then
		local key = C.readKey(item)
		local n, max = #key.mods, C.keyMaxMods()
		if orbKey == "transmutation" then
			return "0 -> 1 modifier"
		elseif orbKey == "alchemy" then
			return "0 -> 2 or 3 modifiers"
		elseif orbKey == "exalted" then
			return string.format("%d -> %d of %d modifiers", n, n + 1, max)
		elseif orbKey == "annulment" then
			return string.format("one of %d modifiers goes", n)
		elseif orbKey == "scouring" then
			return string.format("all %d modifiers go", n)
		elseif orbKey == "chaos" then
			return "new modifiers (1 to 3)"
		elseif orbKey == "divine" then
			return "same modifiers, new values"
		end
		return ""
	end
	local orb = C.orbByKey[orbKey]
	if orb and orb.preview then
		return orb.preview(item)
	end
	if orbKey == "sockets" then
		return G.orbPreview(item)
	end
	local rarity = C.rarityOf(item)
	local mods = C.readMods(item)
	local n = #mods
	local level = C.orbLevel(item)
	if orbKey == "transmutation" then
		return string.format("%s; item level %d: %s", chances(C.config.transmutation), level, tierSpan(level))
	elseif orbKey == "alchemy" then
		return string.format("%s; item level %d: %s", chances(C.config.alchemy), level, tierSpan(level))
	elseif orbKey == "exalted" then
		local p, s = C.sideCounts(mods)
		return string.format("%d -> %d of %d (prefixes %d/%d, suffixes %d/%d), %s", n, n + 1, C.maxModsOf(item, rarity), p,
			M.sideLimitOf(item, "prefix", rarity), s, M.sideLimitOf(item, "suffix", rarity), tierSpan(level))
	elseif orbKey == "annulment" then
		return string.format("one of %d modifiers goes", n - C.bindCount(mods))
	elseif orbKey == "scouring" then
		return string.format("%s with %d modifiers -> normal, item level %d", rarity > 0 and C.rarityName(rarity) or "Normal",
			n, level)
	elseif orbKey == "chaos" then
		local bound = C.bindCount(mods)
		if bound > 0 then
			return string.format("%d bound stay, %d new modifiers, %s", bound, math.max(0, M.modCount(rarity) - bound),
				tierSpan(level))
		end
		return string.format("stays %s, item level %d: %d new modifiers, %s", rarity > 0 and C.rarityName(rarity) or "Normal",
			level, M.modCount(rarity), tierSpan(level))
	elseif orbKey == "divine" then
		return string.format("new random rarity (%d%% none), item level %d stays", 100 - C.config.divineRollChance, level)
	end
	return ""
end

-- ---------------------------------------------------------------------------------------------------------------
-- display helpers
-- ---------------------------------------------------------------------------------------------------------------
function C.itemName(item)
	local ok, name = pcall(function() return item:getName() end)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	local it = itemType(item)
	local okT, tname = pcall(function() return it:getName() end)
	return (okT and tname and tname ~= "") and tname or ("item " .. tostring(item:getId()))
end

-- a short signature of the item's rarity state (the bench refuses an orb when the item changed in between)
function C.signature(item)
	if C.isRiftKey(item) then
		return string.format("%d;key;%s;%s", item:getId(), tostring(custom(item, "rift_tier")), tostring(custom(item, "rift_mods")))
	end
	local parts = {tostring(item:getId()), tostring(C.rarityOf(item)), tostring(C.levelOf(item)),
		"q" .. M.qualityOf(item) .. (M.isRuined(item) and "r" or "") .. tostring(M.extraSide(item) or "")}
	for _, m in ipairs(C.readMods(item)) do
		parts[#parts + 1] = m.key .. "=" .. tostring(m.value) .. "t" .. tostring(m.tier) .. (m.bound and "b" or "")
	end
	local s = G.read(item)
	parts[#parts + 1] = "s" .. s.count
	for i = 1, s.count do
		parts[#parts + 1] = tostring(s.gems[i])
	end
	return table.concat(parts, ";")
end

-- everything the bench shows about an item. mods = [{group, text, tier, side, lo, hi}] (prefixes first),
-- prefixes / suffixes = {n, max}
function C.describe(item, opts)
	if C.isRiftKey(item) then
		return C.describeKey(item, opts)
	end
	local rarity = C.rarityOf(item)
	local mods = C.readMods(item)
	local list = {}
	for _, side in ipairs({"prefix", "suffix"}) do
		for _, m in ipairs(mods) do
			if m.side == side then
				list[#list + 1] = {group = m.group, key = m.key, text = C.modText(m), tier = m.tier, side = m.side, lo = m.lo,
					hi = m.hi, bound = m.bound or nil, power = m.power or nil,
					short = m.power and string.format("%s %d%s", m.label, m.value, (m.affix and m.affix.def and m.affix.def.fmt == "flat") and "/s" or "%") or nil}
			end
		end
	end
	local orbs, preview = {}, {}
	for _, orb in ipairs(C.config.orbs) do
		local ok, reason = C.check(orb.key, item)
		orbs[orb.key] = ok and "" or ((opts and opts.codes and C.reasons[reason]) and reason or (C.reasons[reason] or reason))
		preview[orb.key] = ok and C.preview(orb.key, item) or ""
	end
	local p, s = C.sideCounts(mods)
	local limit = M.sideLimit(rarity)
	local level = C.levelOf(item)
	local picks = {}
	for _, orb in ipairs(C.config.orbs) do
		if orb.pick and orbs[orb.key] == "" then
			picks[orb.key] = C.pickList(orb.key, item)
		end
	end
	return {
		id = item:getId(),
		name = C.itemName(item),
		rarity = rarity,
		rarityName = rarity > 0 and C.rarityName(rarity) or "Normal",
		level = level,
		maxTier = level > 0 and M.maxTierFor(level) or nil,
		mods = list,
		maxMods = rarity > 0 and C.maxModsOf(item, rarity) or 0,
		prefixes = rarity > 0 and {p, M.sideLimitOf(item, "prefix", rarity)} or nil,
		suffixes = rarity > 0 and {s, M.sideLimitOf(item, "suffix", rarity)} or nil,
		quality = M.qualityOf(item),
		qualityCap = rarity > 0 and M.qualityCap(rarity) or 0,
		ruined = M.isRuined(item) or nil,
		binds = rarity > 0 and {C.bindCount(mods), M.maxBinds(rarity)} or nil,
		pick = picks, -- orb key -> the attribute keys of the modifiers it may be aimed at (the bench's picker)
		unique = C.isUnique(item),
		orbs = orbs, -- orb key -> "" when usable, else why not
		preview = preview, -- orb key -> what it would do ("" when not usable)
		sockets = C.describeSockets(item),
		sig = C.signature(item)
	}
end

-- the sockets of an item for the bench: {count, max, list = {{index, id, clientId, name, text, color, cost}}}
-- (id 0 = empty socket; cost = gold to take the gem out unharmed)
function C.describeSockets(item)
	local s = G.read(item)
	local group = G.groupOf(item)
	local list = {}
	for i = 1, s.count do
		local id = s.gems[i]
		local row = {index = i, id = id}
		if id > 0 then
			local g = G.gemOf(id)
			row.clientId = G.clientIdOf(g.type.index, g.tier)
			row.name = G.gemName(id)
			local e = G.effectOf(id, group)
			row.text = e and G.effectText(e.key, e.value, e.value2) or ""
			row.color = g.type.color
			row.cost = G.removeCost(id)
		end
		list[i] = row
	end
	return {count = s.count, max = G.maxSockets(item), list = list}
end

-- the bench view of a Rift Key (kind = "riftkey"; mods in the rift group, the reward bonuses as one line)
function C.describeKey(item, opts)
	local R, cfg = rift()
	local key = C.readKey(item)
	local list = {}
	for _, m in ipairs(key.mods) do
		list[#list + 1] = {group = "rift", key = tostring(m.key), text = R.modText(cfg, m)}
	end
	local b = R.bonuses(cfg, key.mods, key.tier)
	local orbs, preview, picks = {}, {}, {}
	for _, orb in ipairs(C.config.orbs) do
		local ok, reason = C.check(orb.key, item)
		orbs[orb.key] = ok and "" or ((opts and opts.codes and C.reasons[reason]) and reason or (C.reasons[reason] or reason))
		preview[orb.key] = ok and C.preview(orb.key, item) or ""
		if ok and orb.keyPick then
			picks[orb.key] = orb.keyPick(item)
		end
	end
	return {
		id = item:getId(),
		kind = "riftkey",
		pick = picks,
		name = R.keyName(cfg, key.tier),
		tier = key.tier,
		rarity = 0,
		rarityName = "Rift Key",
		level = R.tierInfo(cfg, key.tier).minLevel,
		mods = list,
		maxMods = C.keyMaxMods(),
		rewards = string.format("+%d%% quantity, +%d%% rarity, +%d%% experience", b.quantity, b.rarity, b.experience),
		unique = false,
		orbs = orbs,
		preview = preview,
		sig = C.signature(item)
	}
end

-- the orbs of orbs v2 (Tempering, Binding, Excision, Reforging, Ruin, the Whetstone): chaos_orbs.lua adds them
if not ChaosOrbs then
	dofile("data/lib/chaos_orbs.lua")
end

return C
