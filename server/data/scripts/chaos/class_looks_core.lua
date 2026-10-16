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
-- Pair 19 switch (L.PAIR19_LOOKS, on since 2026-10-12, when things_custom19 went to windows-assets): client pair
-- things_custom19 adds 2161-2172, six new class looks (L.pair19Looks). An older pair draws nothing for those ids, so
-- they are sent only when the switch is on (rollback: server/README.md "Class looks"). With it on, the six
-- classes use the new looks, the looks they replace stay owned and wearable ("<name> (old)" in outfits.xml, listed
-- in L.retired so the store never sells them), and a character wearing a replaced look of its class gets the new one
-- at its next login.
--
-- Pair 20 switch (L.PAIR20_LOOKS, on since 2026-10-12, when things_custom20 went to windows-assets at 77b9cc9b):
-- client pair things_custom20 = things_custom19 plus 2173-2184 (client/MANIFEST.md "Class looks pair 20"), six more
-- class looks (L.pair20Looks): matched pairs for the Lich and the Inquisitor (one look for both sexes before) and the
-- Necromancer (two unrelated outfits before), and new looks for the Thief, the Ninja and the Templar. Same rules as
-- pair 19: an older pair draws nothing for those ids, so they are sent only with the switch on (rollback:
-- server/README.md "Class looks"); the replaced looks stay owned as "<name> (old)" and retired; a character wearing
-- a replaced look of its class gets the new one at its next login (for a replaced one-look class, the new look of
-- the character's sex). The two switches are independent (L.applyPairs); the pair 20 classes are not pair 19 classes.

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
L.PAIR19_LOOKS = true
L.pair19Looks = {
	[8] = {male = 2161, female = 2162}, -- Juggernaut: gilded plate, tower shield (donor D 997/998)
	[3] = {male = 2163, female = 2164}, -- Ranger: hooded archer (donor H 246/247)
	[15] = {male = 2165, female = 2166}, -- Beastmaster: fur cloak (donor D 166/167)
	[22] = {male = 2167, female = 2168}, -- Bone Lord: bone wings, skull rack (donor D 508/509)
	[18] = {male = 2169, female = 2170}, -- Shadowfist: claws, violet glow (donor D 1057/1058)
	[25] = {male = 2171, female = 2172} -- Sentinel: holy orbs, tower shield (donor D 992/993)
}

-- the things_custom20 looks (client/tools/sprites/monster_looks/classlook_picks20.csv and the compose specs
-- client/tools/sprites/compose/classlook_*.json): used only with L.PAIR20_LOOKS on. vocation id -> {male, female}
L.PAIR20_LOOKS = true
L.pair20Looks = {
	[21] = {male = 2173, female = 2174}, -- Lich: skeletal lord, skull cape, bone sceptre (donor D 219/220)
	[11] = {male = 2175, female = 2176}, -- Thief: hooded rogue, twin daggers (donor D 521/522)
	[12] = {male = 2177, female = 2178}, -- Ninja: black shinobi, red-eyed mask, katana (donor D 789/790)
	[23] = {male = 2179, female = 2180}, -- Templar: gilded holy knight, kite shield (donor D 609/610)
	[24] = {male = 2181, female = 2182}, -- Inquisitor: witch-hunter hat, rapier, holy sceptre (D 419/420 + D 827/828)
	[20] = {male = 2183, female = 2184} -- Necromancer: blood hood / witch hat, blood orb, skull (D 856/857 + D 829)
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

-- The colours a new character of a base class starts with (head, body, legs, feet; the 133-colour outfit palette),
-- put on with its class look at the first login (L.startOutfit) and at creation by the website (lib.php
-- chaos_apply_class_look) and add-account.sh. Every class look is a colour template, so the colours make the art: with
-- the website's old starter colours (head 78, body 68, legs 58, feet 76: yellow and blue) the Ranger's hooded archer
-- (2163 / 2164) read as a blue-robed mage with a headband (owner report 2026-10-16, character "Jokr"). An ascended
-- class starts like its base class. KEEP ONE ROW PER LINE: the website and add-account.sh read them with a pattern.
L.startColors = {
	[4] = {head = 57, body = 113, legs = 114, feet = 116}, -- Warrior: grey, crimson, black, brown
	[3] = {head = 116, body = 120, legs = 116, feet = 115}, -- Ranger: brown, forest green, brown, dark brown
	[1] = {head = 57, body = 107, legs = 126, feet = 114}, -- Mystic: grey, deep blue, navy, black
	[11] = {head = 95, body = 114, legs = 95, feet = 114}, -- Thief: dark grey and black
	[17] = {head = 97, body = 97, legs = 116, feet = 116}, -- Monk: ochre and brown
	[20] = {head = 114, body = 128, legs = 114, feet = 114}, -- Necromancer: black and dark purple
	[23] = {head = 79, body = 0, legs = 79, feet = 57} -- Templar: gold and white
}
-- the starter colours the website wrote before (ZnoteX's) and the players table's own defaults
L.OLD_COLORS = {head = 78, body = 68, legs = 58, feet = 76}

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

-- the start colours of a vocation (its base class's row), or nil
function L.startColorsFor(vocId)
	return L.startColors[vocId] or L.startColors[baseOf(vocId)]
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

-- the outfit of a new character's first login: the class look with both addons and the class's start colours
-- (mount and the rest kept); nil when the vocation has no look
function L.startOutfit(current, vocId, sex)
	local look = L.lookFor(vocId, sex)
	if not look or not current then
		return nil
	end
	local out = withLook(current, look)
	local c = L.startColorsFor(vocId)
	if c then
		out.lookHead, out.lookBody, out.lookLegs, out.lookFeet = c.head, c.body, c.legs, c.feet
	end
	return out
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
	local new = L.replacedFor(current.lookType, sex)
	if new and mine[new] then
		return withLook(current, new)
	end
	if mine[current.lookType] and granted and granted[current.lookType] and (current.lookAddons or 0) ~= L.ADDONS then
		return withLook(current, current.lookType)
	end
	return nil
end

-- the new look of the character's sex for a replaced look (one of L.former), else nil
function L.replacedFor(look, sex)
	for vocId, e in pairs(L.former) do
		if e.male == look or e.female == look then
			local n = L.looks[vocId]
			return sex == L.FEMALE and n.female or n.male
		end
	end
	return nil
end

-- the pair switches: L.looks as of things_custom18 (L.pair18Looks, kept) with L.pair19Looks put in when `on19` and
-- L.pair20Looks when `on20`. L.former: vocation id -> the replaced entry ({name = "<name> (old)", male, female});
-- L.replaced: old look type -> new one (a one-look class's old look -> the new male look; logins use L.replacedFor);
-- the replaced looks are appended to L.retired. Idempotent; run once at load with L.PAIR19_LOOKS and L.PAIR20_LOOKS.
function L.applyPairs(on19, on20)
	L.looks, L.former, L.replaced = {}, {}, {}
	local retired = {}
	for _, e in ipairs(L.retired18) do
		retired[#retired + 1] = e
	end
	for vocId, e in pairs(L.pair18Looks) do
		local n = (on19 and L.pair19Looks[vocId]) or (on20 and L.pair20Looks[vocId])
		if n then
			L.looks[vocId] = {name = e.name, male = n.male, female = n.female}
			L.former[vocId] = {name = e.name .. " (old)", male = e.male, female = e.female}
			L.replaced[e.female] = n.female
			L.replaced[e.male] = n.male -- after the female line: a one-look class maps to the male look
			retired[#retired + 1] = {male = e.male, female = e.female}
		else
			L.looks[vocId] = e
		end
	end
	L.retired = retired
	L.pair19 = on19 and true or false
	L.pair20 = on20 and true or false
end

-- one switch at a time, the other kept as applied
function L.usePair19(on)
	L.applyPairs(on, L.pair20)
end
function L.usePair20(on)
	L.applyPairs(L.pair19, on)
end
L.pair18Looks, L.retired18 = L.looks, L.retired
L.applyPairs(L.PAIR19_LOOKS, L.PAIR20_LOOKS)

-- the first login of a character (the engine's lastLoginSaved is 0 until the first logout is saved)
function L.isFirstLogin(lastLoginSaved)
	return (lastLoginSaved or 0) <= 0
end

return L
