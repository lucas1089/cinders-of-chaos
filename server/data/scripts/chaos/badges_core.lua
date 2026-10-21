-- badges_core.lua: the base server's badges are retired (server/README.md "Retired badges"). Pure Lua, no engine
-- calls; the glue is badges.lua, the base data changes are tools/patch_badges.py; tests/badges_test.lua.
--
-- The base has 40 badges (server ids 27803-27842: nine lines of four or five tiers, Raging, Furious, Tempest, Blazing,
-- Eternal) for the base engine's deck / badge inventory slots (12, 13), and 31 amplifier catalysts (27843-27873) that
-- upgrade a badge one tier. Our client draws inventory slots 1-10 only, so no badge can be put on: the base bosses
-- dropped items nobody can use. patch_badges.py takes them out of every drop, task reward and roulette prize; copies
-- the players hold sell to the Loot Buyer. A catalyst used on anything explains that and is kept; a move of a badge
-- into slot 12 or 13 (a packet the client cannot send) is refused. Lua 5.1 / LuaJIT and 5.3.

ChaosBadgesCore = ChaosBadgesCore or {}
local K = ChaosBadgesCore

K.TIERS = {"Raging", "Furious", "Tempest", "Blazing", "Eternal"}
-- the nine badge lines in id order: the first badge's id and its number of tiers (the base's upgrade table)
K.LINES = {
	{key = "exiled", first = 27803, tiers = 4},
	{key = "fury", first = 27807, tiers = 4},
	{key = "moon", first = 27811, tiers = 5},
	{key = "nightseeker", first = 27816, tiers = 5},
	{key = "earthshade", first = 27821, tiers = 4},
	{key = "reborn", first = 27825, tiers = 5},
	{key = "chaosfiend", first = 27830, tiers = 4},
	{key = "veins", first = 27834, tiers = 4},
	{key = "daybreak", first = 27838, tiers = 5},
}
K.FIRST_BADGE, K.LAST_BADGE = 27803, 27842
K.FIRST_CATALYST, K.LAST_CATALYST = 27843, 27873
-- the base engine's deck and badge inventory slots (CONST_SLOT_DECK, CONST_SLOT_BADGE); a deckbadge item fits both
K.SLOTS = {[12] = true, [13] = true}
K.INVENTORY_X = 0xFFFF

-- badge id -> {line, tier}; catalyst id -> {line, tier = the tier it makes, from, to} (the base's upgrade table)
K.badges, K.catalysts = {}, {}
do
	local cat = K.FIRST_CATALYST
	for _, line in ipairs(K.LINES) do
		for t = 1, line.tiers do
			K.badges[line.first + t - 1] = {line = line.key, tier = t}
		end
		for t = 2, line.tiers do
			K.catalysts[cat] = {line = line.key, tier = t, from = line.first + t - 2, to = line.first + t - 1}
			cat = cat + 1
		end
	end
end

function K.isBadge(id)
	return K.badges[tonumber(id) or -1] ~= nil
end

function K.isCatalyst(id)
	return K.catalysts[tonumber(id) or -1] ~= nil
end

-- every retired id (badges, then catalysts), sorted
function K.ids()
	local out = {}
	for id = K.FIRST_BADGE, K.LAST_CATALYST do
		out[#out + 1] = id
	end
	return out
end

-- the text of a key in lang (through ChaosI18n when it is loaded, English otherwise)
local function T(lang, key, ...)
	local I = rawget(_G, "ChaosI18n")
	if lang and I and I.text then
		return I.text(lang, key, ...)
	end
	if select("#", ...) > 0 then
		return string.format(key, ...)
	end
	return key
end

K.TEXT_CATALYST = "Badges are retired: no character can wear one, so this catalyst upgrades nothing and was not used up."
K.TEXT_PRICE = "The Loot Buyer pays %d gold for it."
K.TEXT_EQUIP = "Badges are retired: no character can wear one. The Loot Buyer buys it."

-- what a player reads after using a catalyst; price = what the Loot Buyer pays for this copy (0 or nil: not named)
function K.catalystText(price, lang)
	local text = T(lang, K.TEXT_CATALYST)
	price = math.floor(tonumber(price) or 0)
	if price > 0 then
		text = text .. " " .. T(lang, K.TEXT_PRICE, price)
	end
	return text
end

function K.equipText(lang)
	return T(lang, K.TEXT_EQUIP)
end

-- true when a move of item id to pos puts a badge on (an inventory slot of the deck or the badge)
function K.refusesMove(id, pos)
	if not K.isBadge(id) or type(pos) ~= "table" then
		return false
	end
	return tonumber(pos.x) == K.INVENTORY_X and K.SLOTS[tonumber(pos.y) or -1] == true
end

return K
