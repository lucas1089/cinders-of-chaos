-- badges_core.lua: the base server's extra inventory slots (server/README.md "Badge slot"). Pure Lua, no engine
-- calls; the glue is badges.lua, the base data changes are tools/patch_badges.py; tests/badges_test.lua.
--
-- The base engine has five extra slots: deck (12), badge (13), ship (14), belt (15) and gloves (16). Owner decision
-- 2026-10-21: the badge slot is drawn where the second ring slot was (client base patch 0113) and the second ring slot
-- goes (engine patch 0058: the ammunition slot, 10, takes nothing). The other four stay retired: no client draws them
-- and the engine refuses every item there (0058). What they held keeps its other uses:
--   * the 40 badges (27803-27842: nine lines of four or five tiers, Raging, Furious, Tempest, Blazing, Eternal) are
--     worn in slot 13; the 31 amplifier catalysts (27843-27873) upgrade a badge one tier as the base made them. The
--     Eternal Moon Badge (27815) is a container, as in the base.
--   * the decks (27632-27634) hold the cards: a card used inside a deck the player carries turns on or off (the base
--     wanted the deck worn in slot 12).
--   * the ships (27796-27802): a player who carries one sails from the docks (the base wanted it worn in slot 14);
--     carrying one also opens its trainer portal, as wearing it did.
--   * the belts and gloves (slot type "beltgloves") have no other use: they can't be worn; the Loot Buyer buys them.
-- Lua 5.1 / LuaJIT and 5.3.

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
K.CONTAINER_BADGE = 27815 -- Eternal Moon Badge: a container of 10 (base items.xml containerSize)

K.INVENTORY_X = 0xFFFF
K.AMMO_SLOT = 10 -- the second ring slot of engine patch 0023 until 0058: takes nothing now (archery.lua moves it out)
K.BADGE_SLOT = 13
K.RETIRED_SLOTS = {[12] = true, [14] = true, [15] = true, [16] = true} -- deck, ship, belt, gloves

-- the decks, largest first (the one a card is looked for in when a player carries several)
K.DECKS = {27634, 27633, 27632}
-- ship id -> the base storages its equip script set: the ship's own (base lib Ships table, read by the sea tiles'
-- step-in) and the trainer portal it opens (set once, never cleared)
K.SHIPS = {
	[27796] = {storage = 37120, unlock = 110010},
	[27797] = {storage = 37121, unlock = 110011},
	[27798] = {storage = 37122, unlock = 110012},
	[27799] = {storage = 37123, unlock = 110013},
	[27800] = {storage = 37124, unlock = 110014},
	[27801] = {storage = 37125, unlock = 110015},
	[27802] = {storage = 37126, unlock = 110016},
}
K.SAILING_STORAGE = 109017 -- the base's "navigating" flag (its Player:onMoveItem keeps the ship slot while it is 1)
-- the belts and gloves (base slot type "beltgloves")
K.BELTGLOVES = {29577, 29578, 29582, 29583, 29584, 29586, 29587, 29588, 29589, 29590, 29591, 29592, 29593, 29594,
	29595, 29596, 29597, 29598, 29914, 29915, 29916, 29917, 29918, 29919}

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

-- id -> "deck" | "ship" | "beltgloves": the items of the retired slots
K.retired = {}
for _, id in ipairs(K.DECKS) do
	K.retired[id] = "deck"
end
for id in pairs(K.SHIPS) do
	K.retired[id] = "ship"
end
for _, id in ipairs(K.BELTGLOVES) do
	K.retired[id] = "beltgloves"
end

function K.isBadge(id)
	return K.badges[tonumber(id) or -1] ~= nil
end

function K.isCatalyst(id)
	return K.catalysts[tonumber(id) or -1] ~= nil
end

-- "deck" | "ship" | "beltgloves" for an item of a retired slot, nil otherwise
function K.retiredKind(id)
	return K.retired[tonumber(id) or -1]
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

K.TEXT_EQUIP = "This slot is retired: nothing can be worn there."
K.TEXT_RETIRED = "This item can't be worn. The Loot Buyer buys it."
K.TEXT_MOVED = "These slots are retired: decks, ships, belts and gloves can't be worn. Moved: %s."

function K.equipText(lang, id)
	return T(lang, K.retiredKind(id) and K.TEXT_RETIRED or K.TEXT_EQUIP)
end

function K.movedText(lang, list)
	return T(lang, K.TEXT_MOVED, list)
end

local function slotOf(pos)
	if type(pos) ~= "table" or tonumber(pos.x) ~= K.INVENTORY_X then
		return nil
	end
	return tonumber(pos.y)
end

-- true when a move of item id to pos goes into a retired slot (12, 14, 15, 16: anything), or puts a deck, ship, belt
-- or gloves into the badge slot. The engine refuses the same (patch 0058); this is the message and the guard for an
-- engine without it.
function K.refusesMove(id, pos)
	local slot = slotOf(pos)
	if not slot then
		return false
	end
	if K.RETIRED_SLOTS[slot] then
		return true
	end
	return slot == K.BADGE_SLOT and K.retiredKind(id) ~= nil
end

-- the base's "one badge at a time" storage (data/movements/scripts/equipments/badges.lua and the special skill scripts:
-- set to the badge's id on equip, cleared on de-equip; a value above 0 refuses every other badge). A value left over
-- with no such badge worn (a badge that left slot 13 without its de-equip event) would lock the slot for good.
K.BASE_BADGE_STORAGE = 249578

-- true when the stored value must be cleared: set, and the badge in slot 13 (wornId, nil when empty) is not that one
function K.staleBadgeStorage(stored, wornId)
	stored = tonumber(stored) or -1
	return stored > 0 and stored ~= tonumber(wornId)
end

-- the login check: which worn items must move out. worn = {[slot] = id}. Every item in a retired slot, and anything in
-- the badge slot that is no badge (a deck worn there before). Slot 10 is archery.lua's (ChaosArchery.loginPlan).
-- Returns the slots, sorted.
function K.loginMoves(worn)
	local out = {}
	for slot, id in pairs(worn or {}) do
		if K.RETIRED_SLOTS[slot] or (slot == K.BADGE_SLOT and not K.isBadge(id)) then
			out[#out + 1] = slot
		end
	end
	table.sort(out)
	return out
end

-- the ship storages for what a player carries: carried = {[ship id] = true}; current = {[storage] = value} (the unlock
-- storages' values). Returns {[storage] = value} to write: every ship storage 1 when carried and 0 when not, the
-- sailing flag 1 when any is carried, and each carried ship's trainer portal 1 when it is not set yet.
function K.shipStorages(carried, current)
	local out, any = {}, false
	current = current or {}
	for id, s in pairs(K.SHIPS) do
		if carried and carried[id] then
			any = true
			out[s.storage] = 1
			if (tonumber(current[s.unlock]) or -1) <= 0 then
				out[s.unlock] = 1
			end
		else
			out[s.storage] = 0
		end
	end
	out[K.SAILING_STORAGE] = any and 1 or 0
	return out
end

return K
