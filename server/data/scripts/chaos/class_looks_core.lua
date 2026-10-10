-- class_looks_core.lua: the default look of every class (ChaosClassLooks), no engine calls (tests/class_kit_test.lua).
--
-- Every class has a stock outfit of the base server (in its outfits.xml for both sexes, in the 10.98 client's dat;
-- no new art). A character wears its class's look at its first login (character creation: the website and the
-- engine only set the generic default look) and after every class change (ascension, the free switch, the store's
-- Vocation Change), with its own colours kept. The look is given to the character for good: a later class change
-- adds the new class's look and takes nothing away. At every login a character gets the looks of its class and of
-- its base class that it does not own yet (the look it wears is left alone). Glue: class_looks.lua, ascension.lua
-- (ChaosClasses.afterVocationChange). The donor art class outfits (Chaos.classes.outfits) are still given as before.
--
-- Only outfits with premium="no" in the base outfits.xml are used (freePremium is off: the engine does not let a free
-- account wear a premium outfit), and none that the store, the achievements or the seasons hand out as a reward.

ChaosClassLooks = ChaosClassLooks or {}
local L = ChaosClassLooks

-- vocation id -> {name, male, female}: the outfit's name in outfits.xml and its look types (type 1 male, 0 female)
L.looks = {
	-- Warrior line
	[4] = {name = "Knight", male = 131, female = 139},
	[8] = {name = "Champion", male = 633, female = 632}, -- Juggernaut: heavy plate
	[14] = {name = "Lion of War", male = 919, female = 920}, -- Berserker: mane and a two-handed blade
	-- Ranger line
	[3] = {name = "Ranger", male = 684, female = 683},
	[7] = {name = "Armoured Archer", male = 915, female = 916}, -- Deadeye
	[15] = {name = "Beastmaster", male = 637, female = 636},
	-- Mystic line
	[1] = {name = "Mage", male = 130, female = 138},
	[5] = {name = "Flamefury Mage", male = 925, female = 926}, -- Elementalist
	[10] = {name = "Conjurer", male = 634, female = 635}, -- Illusionist
	-- Thief line
	[11] = {name = "Frost Tracer", male = 913, female = 914}, -- Thief: hooded tracker in leather
	[12] = {name = "Skullhunter", male = 1206, female = 1205}, -- Ninja: dark hooded cloak
	[13] = {name = "Decaying Defender", male = 921, female = 922}, -- Samurai: lamellar armour
	-- Monk line
	[17] = {name = "Ancient Aucar", male = 911, female = 912}, -- Monk: wraps, bare arms
	[18] = {name = "Fiend Slayer", male = 1373, female = 1372}, -- Shadowfist
	[19] = {name = "Winter Warden", male = 853, female = 852}, -- Iron Sage: staff and furs
	-- Necromancer line
	[20] = {name = "Spirit Caller", male = 699, female = 698},
	[21] = {name = "Darklight Evoker", male = 923, female = 924}, -- Lich
	[22] = {name = "Puppeteer", male = 697, female = 696}, -- Bone Lord: the master of the army
	-- Templar line
	[23] = {name = "Herald", male = 984, female = 985},
	[24] = {name = "Hand of Inquisition", male = 1014, female = 1015}, -- Inquisitor
	[25] = {name = "Celestial Avenger", male = 1188, female = 1189} -- Sentinel
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
