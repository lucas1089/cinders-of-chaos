-- Chaos crafting: currency orbs that change the rarity modifiers of an item (ChaosCrafting).
-- Used by data/scripts/chaos/crafting.lua (crafting bench window, !craft, use-with on the orbs) and tested by
-- server/tests/crafting_test.lua against a mocked item. Lua 5.1 / LuaJIT compatible.
--
-- How the base server stores a rarity (src/item.cpp Item::applyRarityEffects, Game.createItemWithRarity):
--   custom attribute "rarity"            1..15 (Common .. Transcendent, names in Chaos loot_config.lua gear.names)
--   custom attribute "combatPowerLevel"  item level rolled inside the tier's level window (shown as "Level: N")
--   attack/defense/armor/hit chance      raised once by a small tier bonus (item attributes)
--   one custom attribute per modifier    rarity_<x>Absorb (percent), rarity_<skill>Skill, rarity_maglevelSkill,
--                                        rarity_criticalHitChance + rarity_criticalHitAmount (always a pair, same for
--                                        mana and life leech), rarity_element<x> (weapons only, % extra damage)
--   the description attribute           "Level: 57, Physical +2%, Sword +1, Critical Chance +1%, Critical Hit +1%,
--                                        Element: Fire +5% dmg" - the look text and the client tooltip show this text
-- customs/rarity/base_rarity.lua reads the modifier attributes when the item is equipped (conditions for skills,
-- critical and leech; storages for absorbs and element damage), so an item that is changed while it sits in the
-- backpack is picked up correctly the next time it is equipped. Custom attribute keys are case-insensitive.
--
-- A "modifier" here is one line of the description: one absorb, one skill, one leech/critical pair, one element or
-- one Chaos modifier (data/lib/chaos_item_mods.lua: attack speed, life on kill, ... stored as "chaos_mod_<key>").
-- Uniques (custom attribute "chaos_unique", data/lib/chaos_unique_items.lua) are never touched.
--
-- Rift Keys (rift.lua: item 10155 with action id 47401, custom attributes "rift_tier" and "rift_mods") are craftable
-- too, the map way: the orbs change the key's modifiers inside the rift's own pool and ranges (rift_core.lua), see
-- C.keyCheck / C.keyApply below.

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
		{key = "transmutation", id = 29851, name = "Orb of Transmutation",
			text = "Turns a normal item into a Common or Uncommon one with random modifiers.",
			keyText = "Gives a Rift Key without modifiers one modifier."},
		{key = "alchemy", id = 24691, name = "Orb of Alchemy",
			text = "Turns a normal item into a Rare, Epic or Legendary one with random modifiers.",
			keyText = "Gives a Rift Key without modifiers two or three modifiers."},
		{key = "exalted", id = 29855, name = "Exalted Orb",
			text = "Adds one random modifier to an item with a rarity that has a free modifier slot.",
			keyText = "Adds one modifier to a Rift Key (three at most)."},
		{key = "annulment", id = 24697, name = "Orb of Annulment",
			text = "Removes one random modifier.",
			keyText = "Removes one random modifier of a Rift Key."},
		{key = "scouring", id = 24688, name = "Orb of Scouring",
			text = "Removes the rarity and every modifier: the item becomes a normal one.",
			keyText = "Removes every modifier of a Rift Key."},
		{key = "chaos", id = 29856, name = "Chaos Orb",
			text = "Rerolls the item level and the modifiers of an item with a rarity (same rarity).",
			keyText = "Rerolls the modifiers of a Rift Key (one to three new ones)."},
		{key = "divine", id = 29857, name = "Divine Orb",
			text = "Rolls a new random rarity for the item, often none (the stock Divine Orb).",
			keyText = "Rerolls the values of a Rift Key's modifiers inside their ranges."},
		-- gems and sockets (chaos_gems_config.lua socketOrb; install_gems.py names the rune stone)
		{key = "sockets", id = ChaosGems.config.socketOrb.id, name = ChaosGems.config.socketOrb.name,
			text = ChaosGems.config.socketOrb.text,
			keyText = "Rift Keys have no sockets."}
	},

	-- rarity names (same as the stock look text, default_onLook.lua)
	rarityNames = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Exotic", "Mythic", "Chaos", "Eternal",
		"Divine", "Phantasmal", "Celestial", "Cosmic", "Abyssal", "Transcendent"},

	-- maximum number of modifiers per rarity. The stock roll gives a weapon 2/3/3/4/4/5/5/5/6/6/6/6/6/8/8 modifiers
	-- (one fewer on other gear: no element); every rarity allows one more than a weapon rolls.
	maxMods = {3, 4, 4, 5, 5, 6, 6, 6, 7, 7, 7, 7, 7, 9, 9},

	-- value ranges per rarity, copied from item.cpp: absorbs, skills, critical and leech use absorbRange (a critical /
	-- leech chance is C.specialChance of the roll, its amount the roll), element damage uses elementRange
	absorbRange = {{1, 1}, {1, 1}, {1, 1}, {1, 2}, {1, 2}, {1, 3}, {1, 3}, {1, 4}, {1, 4}, {2, 5},
		{2, 5}, {2, 5}, {3, 6}, {4, 6}, {5, 6}},
	elementRange = {{1, 3}, {3, 6}, {4, 8}, {5, 10}, {6, 12}, {7, 14}, {8, 16}, {9, 18}, {10, 20}, {12, 22},
		{14, 24}, {16, 26}, {18, 28}, {20, 30}, {25, 40}},

	-- Exalted Orb: weight of each modifier group (a group with nothing left to add is skipped). chaos = the Chaos
	-- modifiers of chaos_item_mods.lua (only those the item's kind may get)
	groupWeights = {absorb = 30, skill = 30, special = 25, element = 15, chaos = 25},
	-- weight of a skill inside the skill group: profession skills are rarer than combat skills
	skillWeights = {combat = 4, profession = 1},
	maxElements = 1, -- element modifiers per weapon (the stock roll never gives more than one)

	-- Orbs of Transmutation and Alchemy: {rarity, weight}
	transmutation = {{1, 65}, {2, 35}},
	alchemy = {{3, 55}, {4, 30}, {5, 15}},

	-- the stock Divine Orb roll (customs/rarity/reroll_rarity_stats.lua rollRarityForReroll): rollChance % to get a
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
	{key = "rarity_criticalHitChance", key2 = "rarity_criticalHitAmount", label = "Critical Chance", label2 = "Critical Hit"},
	{key = "rarity_manaLeechChance", key2 = "rarity_manaLeechAmount", label = "Mana Chance", label2 = "Mana Amount"},
	{key = "rarity_lifeLeechChance", key2 = "rarity_lifeLeechAmount", label = "Life Chance", label2 = "Life Amount"}
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
for _, orb in ipairs(C.config.orbs) do
	C.orbByKey[orb.key] = orb
	C.orbById[orb.id] = orb
end

-- random source; tests replace it
C.random = function(a, b)
	return math.random(a, b)
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

function C.rarityOf(item)
	local r = math.floor(C.customNumber(item, "rarity"))
	if r < 0 or r > #C.config.maxMods then
		return 0
	end
	return r
end

function C.rarityName(r)
	return C.config.rarityNames[r] or ("Rarity " .. tostring(r))
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

-- list of modifiers in description order: {group, key, key2, label, label2, value}
function C.readMods(item)
	local mods = {}
	for _, a in ipairs(C.absorbs) do
		local v = C.customNumber(item, a.key)
		if v ~= 0 then
			mods[#mods + 1] = {group = "absorb", key = a.key, label = a.label, value = v}
		end
	end
	for _, s in ipairs(C.skills) do
		local v = C.customNumber(item, s.key)
		if v ~= 0 then
			mods[#mods + 1] = {group = "skill", key = s.key, label = s.label, value = v}
		end
	end
	for _, s in ipairs(C.specials) do
		local v, v2 = C.customNumber(item, s.key), C.customNumber(item, s.key2)
		if v ~= 0 or v2 ~= 0 then
			mods[#mods + 1] = {group = "special", key = s.key, key2 = s.key2, label = s.label, label2 = s.label2,
				value = v, value2 = v2}
		end
	end
	for _, m in ipairs(M.read(item)) do
		mods[#mods + 1] = {group = "chaos", key = M.attr(m.key), chaosKey = m.key, label = m.label, value = m.value}
	end
	for _, e in ipairs(C.elements) do
		local v = C.customNumber(item, e.key)
		if v ~= 0 then
			mods[#mods + 1] = {group = "element", key = e.key, label = e.label, value = v}
		end
	end
	return mods
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

-- the modifier part of the description: "Physical +2%, Sword +1, Element: Fire +5% dmg"
function C.modsText(mods)
	local parts, elements = {}, {}
	for _, m in ipairs(mods) do
		if m.group == "element" then
			elements[#elements + 1] = C.modText(m)
		else
			parts[#parts + 1] = C.modText(m)
		end
	end
	if #elements > 0 then
		parts[#parts + 1] = "Element: " .. table.concat(elements, ", ")
	end
	return table.concat(parts, ", ")
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

-- true when the item has no rarity, no modifiers and no item level (upgrade scripts write one too)
function C.isNormal(item)
	return C.rarityOf(item) == 0 and #C.readMods(item) == 0 and C.customNumber(item, "combatPowerLevel") == 0
end

function C.maxMods(rarity)
	return C.config.maxMods[rarity] or 0
end

-- modifiers that could still be added: list of {group, entry, weight}
function C.addable(item)
	local mods = C.readMods(item)
	local have, elements = {}, 0
	for _, m in ipairs(mods) do
		have[m.key] = true
		if m.group == "element" then
			elements = elements + 1
		end
	end
	local out = {absorb = {}, skill = {}, special = {}, element = {}, chaos = M.addable(item)}
	for _, a in ipairs(C.absorbs) do
		if not have[a.key] then
			out.absorb[#out.absorb + 1] = {entry = a, weight = 1}
		end
	end
	for _, s in ipairs(C.skills) do
		if not have[s.key] then
			out.skill[#out.skill + 1] = {entry = s, weight = C.config.skillWeights[s.kind] or 1}
		end
	end
	for _, s in ipairs(C.specials) do
		if not have[s.key] then
			out.special[#out.special + 1] = {entry = s, weight = 1}
		end
	end
	if elements < C.config.maxElements and C.canHaveElement(item) then
		for _, e in ipairs(C.elements) do
			out.element[#out.element + 1] = {entry = e, weight = 1}
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
	noMods = "This item has no modifier to remove.",
	nothingToAdd = "There is no modifier left that this item could get.",
	unknownOrb = "Unknown orb.",
	keyNeedNone = "This orb works only on a Rift Key without modifiers.",
	keyNoMods = "This Rift Key has no modifiers.",
	keyFull = "This Rift Key has the most modifiers a key can have.",
	keyNothing = "There is no modifier left that this Rift Key could get.",
	keySockets = "Rift Keys have no sockets."
}

-- can this orb be used on this item? returns true or false, reasonCode
function C.check(orbKey, item)
	local orb = C.orbByKey[orbKey]
	if not orb then
		return false, "unknownOrb"
	end
	if item and C.isRiftKey(item) then
		return C.keyCheck(orbKey, item)
	end
	if not item or not C.isGear(item) then
		return false, "notGear"
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
	local rarity = C.rarityOf(item)
	if orbKey == "transmutation" or orbKey == "alchemy" then
		if not C.isNormal(item) then
			return false, "needNormal"
		end
	elseif orbKey == "divine" then
		return true
	else
		if rarity == 0 then
			return false, "needRarity"
		end
		local mods = C.readMods(item)
		if orbKey == "exalted" then
			if #mods >= C.maxMods(rarity) then
				return false, "full"
			end
			local add = C.addable(item)
			if #add.absorb + #add.skill + #add.special + #add.element + #add.chaos == 0 then
				return false, "nothingToAdd"
			end
		elseif orbKey == "annulment" then
			if #mods == 0 then
				return false, "noMods"
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

function C.rollValue(group, rarity)
	local ranges = group == "element" and C.config.elementRange or C.config.absorbRange
	local r = ranges[rarity] or ranges[1]
	return C.random(r[1], r[2])
end

-- the chance of a critical / leech pair rolled as `v` (the amount keeps v): about two thirds, as engine patch 0004
-- does since the chance rolls are uniform (1..6 -> 1, 1, 2, 3, 3, 4)
function C.specialChance(v)
	return math.max(1, math.floor((2 * v + 1) / 3))
end

-- the stock Divine Orb roll: 0 (no rarity) most of the time
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

-- rewrite the rarity part of the description from the item's attributes. Text in front of "Level: N" and
-- bracketed upgrade slots behind it ("[Attack+2]", customs/upgrade) are kept.
function C.rewriteDescription(item)
	local old = G.strip(descriptionOf(item)) -- the sockets section is written again at the end
	local prefix, rest = old, ""
	local s = old:find("Level:%s*%-?%d+")
	if s then
		prefix, rest = old:sub(1, s - 1), old:sub(s)
	end
	local slots = {}
	for b in rest:gmatch("%[[^%]]*%]") do
		slots[#slots + 1] = b
	end
	prefix = prefix:gsub("[,%s]+$", "")
	local body = "Level: " .. math.floor(C.customNumber(item, "combatPowerLevel"))
	local modsText = C.modsText(C.readMods(item))
	if modsText ~= "" then
		body = body .. ", " .. modsText
	end
	local text = prefix ~= "" and (prefix .. ", " .. body) or body
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
-- Exalted Orb: one new modifier. Returns the added modifier.
function C.exalt(item)
	local rarity = C.rarityOf(item)
	local add = C.addable(item)
	local groups = {}
	for group, list in pairs(add) do
		if #list > 0 and group ~= "chaos" then
			groups[#groups + 1] = {group, C.config.groupWeights[group] or 1}
		end
	end
	table.sort(groups, function(a, b) return a[1] < b[1] end) -- pairs() order is not stable
	if #add.chaos > 0 then
		groups[#groups + 1] = {"chaos", C.config.groupWeights.chaos or 1} -- last, after the engine's groups
	end
	local group = C.weighted(groups)
	if not group then
		return nil
	end
	local rows = {}
	for _, cand in ipairs(add[group]) do
		rows[#rows + 1] = {cand.entry, cand.weight}
	end
	local entry = C.weighted(rows)
	if group == "chaos" then
		local v = M.rollValue(entry, rarity, C.customNumber(item, "combatPowerLevel"), C.random)
		M.set(item, entry.key, v)
		C.rewriteDescription(item)
		return {group = "chaos", key = M.attr(entry.key), chaosKey = entry.key, label = entry.label, value = v}
	end
	local value = C.rollValue(group, rarity)
	local amount = value
	if group == "special" then
		value = C.specialChance(amount)
	end
	item:setCustomAttribute(entry.key, value)
	if entry.key2 then
		item:setCustomAttribute(entry.key2, amount)
	end
	C.rewriteDescription(item)
	return {group = group, key = entry.key, key2 = entry.key2, label = entry.label, label2 = entry.label2,
		value = value, value2 = entry.key2 and amount or nil}
end

-- Orb of Annulment: one random modifier goes. Returns the removed modifier.
function C.annul(item)
	local mods = C.readMods(item)
	if #mods == 0 then
		return nil
	end
	local m = mods[C.random(1, #mods)]
	if m.group == "chaos" then
		M.remove(item, m.chaosKey)
	else
		item:removeCustomAttribute(m.key)
	end
	if m.key2 then
		item:removeCustomAttribute(m.key2)
	end
	C.rewriteDescription(item)
	return m
end

-- ---------------------------------------------------------------------------------------------------------------
-- the orbs that make a new copy of the base item (the engine rolls the rarity: Game.createItemWithRarity)
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

-- make the new copy and put it where the old one was (same container). Returns the new item or nil, reason.
function C.recreate(item, rarity)
	local id = item:getId()
	local newItem
	if rarity > 0 then
		newItem = Game.createItemWithRarity(id, 1, rarity)
	else
		newItem = Game.createItem(id, 1)
	end
	if not newItem then
		return nil, "The orb fizzles: the new item could not be made."
	end
	if rarity > 0 and C.rarityOf(newItem) ~= rarity then
		newItem:remove()
		return nil, "This item cannot carry a rarity."
	end
	G.copy(item, newItem) -- sockets and gems survive every orb (chaos_gems.lua)
	if ChaosSalvage and ChaosSalvage.copyLock then
		ChaosSalvage.copyLock(item, newItem) -- the item lock too (salvage.lua)
	end
	if rarity > 0 then
		C.rollDropMods(newItem) -- the Chaos modifiers a drop of this rarity gets
	end
	if G.count(newItem) > 0 then
		G.writeDescription(newItem)
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
function C.apply(orbKey, item)
	local ok, reason = C.check(orbKey, item)
	if not ok then
		return false, C.reasons[reason] or reason
	end
	if C.isRiftKey(item) then
		return C.keyApply(orbKey, item)
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
		return true, {item = item, text = string.format("%s gained %s.", name, C.modText(m)), added = m}
	elseif orbKey == "annulment" then
		local m = C.annul(item)
		if not m then
			return false, C.reasons.noMods
		end
		return true, {item = item, text = string.format("%s lost %s.", name, C.modText(m)), removed = m}
	end
	local rarity = C.targetRarity(orbKey, item)
	if not rarity then
		return false, C.reasons.unknownOrb
	end
	local newItem, err = C.recreate(item, rarity)
	if not newItem then
		return false, err
	end
	local text
	if rarity > 0 then
		local mods = C.readMods(newItem)
		text = string.format("%s is now %s (level %d): %s.", name, C.rarityName(rarity),
			math.floor(C.customNumber(newItem, "combatPowerLevel")), #mods > 0 and C.modsText(mods) or "no modifiers")
	else
		text = string.format("%s is now a normal item.", name)
	end
	return true, {item = newItem, text = text, rarity = rarity}
end

-- ---------------------------------------------------------------------------------------------------------------
-- Chaos modifiers of a new item (loot layer drops and the copies the Transmutation, Alchemy, Chaos and Divine Orbs
-- make): chaos_item_mods.lua rolls them inside the free slots of the rarity, the description is rewritten.
-- A monster drop whose rarity the engine has not rolled yet (only the "rarity" attribute: the stock loot callback
-- leaves the roll to Monster::dropLoot, after every Lua callback) leaves room for the engine's modifiers (a weapon
-- rolls maxMods - 1 of them, other gear one fewer) and keeps its description: item_mods.lua rewrites it once the
-- engine is done (ChaosItemMods.afterDrop).
-- returns the list of added modifiers
-- ---------------------------------------------------------------------------------------------------------------
function C.rollDropMods(item, rand)
	if not item or not C.isGear(item) or C.isUnique(item) then
		return {}
	end
	local rarity = C.rarityOf(item)
	if rarity < 1 or #M.read(item) > 0 then
		return {}
	end
	local level = C.customNumber(item, "combatPowerLevel")
	local free
	if level > 0 then
		free = C.maxMods(rarity) - #C.readMods(item)
	else -- the engine's roll is still to come
		free = M.kindOf(item) == "weapon" and 1 or 2
	end
	local added = M.rollNew(item, rarity, level, free, rand or M.random)
	if #added > 0 and level > 0 then
		C.rewriteDescription(item)
	end
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
	if orbKey == "sockets" then
		return G.orbPreview(item)
	end
	local rarity = C.rarityOf(item)
	local n = #C.readMods(item)
	if orbKey == "transmutation" then
		return chances(C.config.transmutation)
	elseif orbKey == "alchemy" then
		return chances(C.config.alchemy)
	elseif orbKey == "exalted" then
		return string.format("%d -> %d of %d modifiers", n, n + 1, C.maxMods(rarity))
	elseif orbKey == "annulment" then
		return string.format("one of %d modifiers goes", n)
	elseif orbKey == "scouring" then
		return string.format("%s with %d modifiers -> normal", rarity > 0 and C.rarityName(rarity) or "Normal", n)
	elseif orbKey == "chaos" then
		return string.format("stays %s, new level and modifiers", rarity > 0 and C.rarityName(rarity) or "Normal")
	elseif orbKey == "divine" then
		return string.format("new random rarity (%d%% none)", 100 - C.config.divineRollChance)
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
	local parts = {tostring(item:getId()), tostring(C.rarityOf(item)),
		tostring(math.floor(C.customNumber(item, "combatPowerLevel")))}
	for _, m in ipairs(C.readMods(item)) do
		parts[#parts + 1] = m.key .. "=" .. tostring(m.value)
	end
	local s = G.read(item)
	parts[#parts + 1] = "s" .. s.count
	for i = 1, s.count do
		parts[#parts + 1] = tostring(s.gems[i])
	end
	return table.concat(parts, ";")
end

-- everything the bench shows about an item
function C.describe(item)
	if C.isRiftKey(item) then
		return C.describeKey(item)
	end
	local rarity = C.rarityOf(item)
	local mods = C.readMods(item)
	local list = {}
	for _, m in ipairs(mods) do
		list[#list + 1] = {group = m.group, text = C.modText(m)}
	end
	local orbs, preview = {}, {}
	for _, orb in ipairs(C.config.orbs) do
		local ok, reason = C.check(orb.key, item)
		orbs[orb.key] = ok and "" or (C.reasons[reason] or reason)
		preview[orb.key] = ok and C.preview(orb.key, item) or ""
	end
	return {
		id = item:getId(),
		name = C.itemName(item),
		rarity = rarity,
		rarityName = rarity > 0 and C.rarityName(rarity) or "Normal",
		level = math.floor(C.customNumber(item, "combatPowerLevel")),
		mods = list,
		maxMods = rarity > 0 and C.maxMods(rarity) or 0,
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
function C.describeKey(item)
	local R, cfg = rift()
	local key = C.readKey(item)
	local list = {}
	for _, m in ipairs(key.mods) do
		list[#list + 1] = {group = "rift", text = R.modText(cfg, m)}
	end
	local b = R.bonuses(cfg, key.mods, key.tier)
	local orbs, preview = {}, {}
	for _, orb in ipairs(C.config.orbs) do
		local ok, reason = C.check(orb.key, item)
		orbs[orb.key] = ok and "" or (C.reasons[reason] or reason)
		preview[orb.key] = ok and C.preview(orb.key, item) or ""
	end
	return {
		id = item:getId(),
		kind = "riftkey",
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

return C
