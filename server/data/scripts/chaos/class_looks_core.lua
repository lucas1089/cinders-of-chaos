-- class_looks_core.lua: the default look of every class (ChaosClassLooks), no engine calls (tests/class_kit_test.lua).
--
-- Every class has its own look, male and female, from the donor sprite libraries; none is the stock art of the
-- client pair (client pair things_custom10b: look types 2039-2081 imported by client/tools/sprites/import_outfits.py and
-- client/tools/outfit_art/add_template.py; 2043, 2057 and 2058 of that pair are left unused: they turned out to be
-- stock art).
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
--
-- Addons: a class look is worn with both addons (L.ADDONS) and the character owns both for every class look it is
-- given (Player:addOutfitAddon; outfits.xml cannot grant addons, its entries stay locked). Only the class looks' own
-- addons are given. At a login, a look whose addons were just given is put on with them when it is the worn look
-- (existing characters at their next login); any other worn look (a store outfit) stays.
--
-- Pair 19 switch (L.PAIR19_LOOKS, off): client pair things_custom19 adds 2161-2172, six new class looks
-- (L.pair19Looks). An older pair draws nothing for those ids, so they are sent only when the switch is on. Flip it in
-- the commit that follows the pair's push to windows-assets (server/README.md "Class looks"). With it on, the six
-- classes use the new looks, the looks they replace stay owned and wearable ("<name> (old)" in outfits.xml, listed
-- in L.retired so the store never sells them), and a character wearing a replaced look of its class gets the new one
-- at its next login.

ChaosClassLooks = ChaosClassLooks or {}
local L = ChaosClassLooks

-- vocation id -> {name, male, female}: the outfit's name in outfits.xml and its look types (type 1 male, 0 female)
L.looks = {
	-- Warrior line
	[4] = {name = "Warrior Class", male = 2073, female = 2074}, -- horned helm, spear
	[8] = {name = "Juggernaut Class", male = 2039, female = 2040}, -- Juggernaut: massive spiked plate
	[14] = {name = "Berserker Class", male = 2075, female = 2076}, -- Berserker: skull mask, furs, trident
	-- Ranger line
	[3] = {name = "Ranger Class", male = 2078, female = 2079}, -- leather archers
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
	[17] = {name = "Monk Class", male = 2080, female = 2081}, -- bare-chested / pelt
	[18] = {name = "Shadowfist Class", male = 2053, female = 2054}, -- Shadowfist: dark spaulders
	[19] = {name = "Iron Sage Class", male = 2055, female = 2056}, -- Iron Sage: heavy gilded iron, great blade
	-- Necromancer line
	[20] = {name = "Necromancer Class", male = 2044, female = 2064}, -- hooded, burning eyes / skull staff
	[21] = {name = "Lich Class", male = 2059, female = 2059}, -- Lich: the skull in black, chains (one look)
	[22] = {name = "Bone Lord Class", male = 2065, female = 2066}, -- Bone Lord: armed skeletons
	-- Templar line
	[23] = {name = "Templar Class", male = 2067, female = 2068}, -- crystal plate
	[24] = {name = "Inquisitor Class", male = 2077, female = 2077}, -- Inquisitor: witch-hunter hat, gilded staff (one look)
	[25] = {name = "Sentinel Class", male = 2042, female = 2041} -- Sentinel: white plate
}

-- the things_custom19 looks (client/tools/sprites/monster_looks/classlook_picks.csv) for six classes: used only with
-- L.PAIR19_LOOKS on. vocation id -> {male, female}
L.PAIR19_LOOKS = false
L.pair19Looks = {
	[8] = {male = 2161, female = 2162}, -- Juggernaut: gilded plate, tower shield (donor D 997/998)
	[3] = {male = 2163, female = 2164}, -- Ranger: hooded archer (donor H 246/247)
	[15] = {male = 2165, female = 2166}, -- Beastmaster: fur cloak (donor D 166/167)
	[22] = {male = 2167, female = 2168}, -- Bone Lord: bone wings, skull rack (donor D 508/509)
	[18] = {male = 2169, female = 2170}, -- Shadowfist: claws, violet glow (donor D 1057/1058)
	[25] = {male = 2171, female = 2172} -- Sentinel: holy orbs, tower shield (donor D 992/993)
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

-- worn class looks carry both addons (bit 1 and bit 2)
L.ADDONS = 3

local function withLook(current, look)
	local out = {}
	for k, v in pairs(current) do
		out[k] = v
	end
	out.lookType = look
	out.lookAddons = L.ADDONS
	return out
end

-- the outfit to put on: `current` (the getOutfit table) with the class's look type and both addons, everything else
-- (colours, mount) kept; nil when there is nothing to change
function L.wearOutfit(current, vocId, sex)
	local look = L.lookFor(vocId, sex)
	if not look or not current then
		return nil
	end
	if current.lookType == look and (current.lookAddons or 0) == L.ADDONS then
		return nil
	end
	return withLook(current, look)
end

-- the outfit to put on after L.apply gave the looks: with `wear` (first login, class change) the class's look; else
-- only a class look of this character that it already wears: a replaced look (pair 19 switch) becomes its new look,
-- a look whose addons were just given (`granted`: look type -> true) gets them. A store outfit stays. nil: no change
function L.loginOutfit(current, vocId, sex, wear, granted)
	if not current then
		return nil
	end
	if wear then
		return L.wearOutfit(current, vocId, sex)
	end
	local mine = {}
	for _, look in ipairs(L.unlocksFor(vocId, sex)) do
		mine[look] = true
	end
	local new = L.replaced[current.lookType]
	if new and mine[new] then
		return withLook(current, new)
	end
	if mine[current.lookType] and granted and granted[current.lookType] and (current.lookAddons or 0) ~= L.ADDONS then
		return withLook(current, current.lookType)
	end
	return nil
end

-- the pair 19 switch: L.looks as of things_custom18 (L.pair18Looks, kept) with L.pair19Looks put in when `on`.
-- L.former: vocation id -> the replaced entry ({name = "<name> (old)", male, female}); L.replaced: old look type -> new
-- one; the replaced looks are appended to L.retired. Idempotent; run once at load with L.PAIR19_LOOKS.
function L.usePair19(on)
	L.looks, L.former, L.replaced = {}, {}, {}
	local retired = {}
	for _, e in ipairs(L.retired18) do
		retired[#retired + 1] = e
	end
	for vocId, e in pairs(L.pair18Looks) do
		local n = on and L.pair19Looks[vocId]
		if n then
			L.looks[vocId] = {name = e.name, male = n.male, female = n.female}
			L.former[vocId] = {name = e.name .. " (old)", male = e.male, female = e.female}
			L.replaced[e.male], L.replaced[e.female] = n.male, n.female
			retired[#retired + 1] = {male = e.male, female = e.female}
		else
			L.looks[vocId] = e
		end
	end
	L.retired = retired
	L.pair19 = on and true or false
end
L.pair18Looks, L.retired18 = L.looks, L.retired
L.usePair19(L.PAIR19_LOOKS)

-- the first login of a character (the engine's lastLoginSaved is 0 until the first logout is saved)
function L.isFirstLogin(lastLoginSaved)
	return (lastLoginSaved or 0) <= 0
end

return L
