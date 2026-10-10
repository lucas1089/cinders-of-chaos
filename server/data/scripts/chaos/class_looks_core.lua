-- class_looks_core.lua: the default look of every class (ChaosClassLooks), no engine calls (tests/class_kit_test.lua).
--
-- Every class has its own look, male and female, from the donor sprite libraries or free looks of the client pair
-- (client pair things_custom10: look types 2039-2072 imported by client/tools/sprites/import_outfits.py and
-- client/tools/outfit_art/add_template.py; 1455-1458, 1464, 1465 were in the pair already and used by nothing).
-- Every one has a colour template, so the player's colours show. Sources per look (licence tracing):
-- client/tools/outfit_art/class_looks_sources.csv. outfits.xml entries (both sexes, locked) come from
-- server/tools/install_outfits.py, which reads L.looks below.
-- A character wears its class's look at its first login (character creation: the website and the engine only set the
-- generic default look) and after every class change (ascension, the free switch, the store's Vocation Change), with
-- its own colours kept. The look is given to the character for good: a later class change adds the new class's look
-- and takes nothing away. At every login a character gets the looks of its class and of its base class that it does
-- not own yet (the look it wears is left alone). Glue: class_looks.lua, ascension.lua
-- (ChaosClasses.afterVocationChange). The donor art class outfits (Chaos.classes.outfits) are still given as before.
--
-- None of these looks is sold in the store or given as a reward (gen_shop_cosmetics.py and shop.lua read L.looks and
-- L.retired; the season pass test checks its own list against them).

ChaosClassLooks = ChaosClassLooks or {}
local L = ChaosClassLooks

-- vocation id -> {name, male, female}: the outfit's name in outfits.xml and its look types (type 1 male, 0 female)
L.looks = {
	-- Warrior line
	[4] = {name = "Warrior Class", male = 1455, female = 1456}, -- plain steel plate
	[8] = {name = "Juggernaut Class", male = 2039, female = 2040}, -- Juggernaut: massive spiked plate
	[14] = {name = "Berserker Class", male = 2057, female = 2058}, -- Berserker: bare-armed, great axe / skull flail
	-- Ranger line
	[3] = {name = "Ranger Class", male = 1457, female = 1458}, -- hooded leather
	[7] = {name = "Deadeye Class", male = 2045, female = 2046}, -- Deadeye: armoured archer, long bow
	[15] = {name = "Beastmaster Class", male = 2047, female = 2048}, -- Beastmaster: wolf pelts
	-- Mystic line
	[1] = {name = "Mystic Class", male = 2060, female = 2061}, -- dark hooded robe and staff
	[5] = {name = "Elementalist Class", male = 2062, female = 2063}, -- Elementalist: burning torch
	[10] = {name = "Illusionist Class", male = 2049, female = 2050}, -- Illusionist: coiled staff
	-- Thief line
	[11] = {name = "Thief Class", male = 2051, female = 2052}, -- Thief: hooded, blade
	[12] = {name = "Ninja Class", male = 2069, female = 2070}, -- Ninja: shadow ninja, crimson ninja
	[13] = {name = "Samurai Class", male = 2071, female = 2072}, -- Samurai: oni samurai, dark samurai
	-- Monk line
	[17] = {name = "Monk Class", male = 1464, female = 1465}, -- bare-chested, wraps
	[18] = {name = "Shadowfist Class", male = 2053, female = 2054}, -- Shadowfist: dark spaulders
	[19] = {name = "Iron Sage Class", male = 2055, female = 2056}, -- Iron Sage: heavy gilded iron, great blade
	-- Necromancer line
	[20] = {name = "Necromancer Class", male = 2044, female = 2064}, -- hooded, burning eyes / skull staff
	[21] = {name = "Lich Class", male = 2059, female = 2059}, -- Lich: the skull in black, chains (one look)
	[22] = {name = "Bone Lord Class", male = 2065, female = 2066}, -- Bone Lord: armed skeletons
	-- Templar line
	[23] = {name = "Templar Class", male = 2067, female = 2068}, -- crystal plate
	[24] = {name = "Inquisitor Class", male = 2043, female = 2043}, -- Inquisitor: skull-masked (one look)
	[25] = {name = "Sentinel Class", male = 2042, female = 2041} -- Sentinel: white plate
}

-- the stock looks classes wore before (until 2026-10): characters own them already, so the store does not sell them
L.retired = {
	{male = 131, female = 139}, {male = 633, female = 632}, {male = 919, female = 920}, {male = 684, female = 683},
	{male = 915, female = 916}, {male = 637, female = 636}, {male = 130, female = 138}, {male = 925, female = 926},
	{male = 634, female = 635}, {male = 913, female = 914}, {male = 1206, female = 1205}, {male = 921, female = 922},
	{male = 911, female = 912}, {male = 1373, female = 1372}, {male = 853, female = 852}, {male = 699, female = 698},
	{male = 923, female = 924}, {male = 697, female = 696}, {male = 984, female = 985}, {male = 1014, female = 1015},
	{male = 1188, female = 1189}
}

-- the engine's sex ids (PLAYERSEX_FEMALE 0, PLAYERSEX_MALE 1)
L.FEMALE, L.MALE = 0, 1

local function baseOf(vocId)
	local classes = Chaos and Chaos.classes
	return classes and classes.baseOf and classes.baseOf[vocId] or vocId
end

-- the class's look type for this sex, and the outfit's name; nil for a vocation without a look (0, retired ids)
function L.lookFor(vocId, sex)
	local e = L.looks[vocId]
	if not e then
		return nil
	end
	return sex == L.FEMALE and e.female or e.male, e.name
end

-- look types a character of this vocation and sex is given: its class's, then its base class's (an ascended class
-- keeps the base look); each once
function L.unlocksFor(vocId, sex)
	local out, seen = {}, {}
	for _, v in ipairs({vocId, baseOf(vocId)}) do
		local look = L.lookFor(v, sex)
		if look and not seen[look] then
			seen[look] = true
			out[#out + 1] = look
		end
	end
	return out
end

-- the outfit to put on: `current` (the getOutfit table) with the class's look type and no addons, everything else
-- (colours, mount) kept; nil when there is nothing to change
function L.wearOutfit(current, vocId, sex)
	local look = L.lookFor(vocId, sex)
	if not look or not current then
		return nil
	end
	if current.lookType == look and (current.lookAddons or 0) == 0 then
		return nil
	end
	local out = {}
	for k, v in pairs(current) do
		out[k] = v
	end
	out.lookType = look
	out.lookAddons = 0
	return out
end

-- the first login of a character (the engine's lastLoginSaved is 0 until the first logout is saved)
function L.isFirstLogin(lastLoginSaved)
	return (lastLoginSaved or 0) <= 0
end

return L
