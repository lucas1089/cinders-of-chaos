-- The cards and decks (cards_core.lua, cards.lua; server/README.md "Cards and decks"). Plain data, no engine calls
-- (tests/cards_test.lua and tools/patch_badges.py read it). Lua 5.1 / LuaJIT and 5.3.
--
-- The base deck system keeps a card on or off in one player storage per card (DeckSystem.Cards / .Legendary of the base
-- lib, 37000-37059 and 37065-37080) and tags a card that is on with action id 37866 (the base Player:onMoveItem refuses
-- to move or trade such a card). Chaos keeps that exactly: the bonus scripts of the base read the same storages.
-- Item names are not repeated here: the server reads them from the item types (the rename step makes them ours).
local C = {}

C.maxActive = 5 -- the base's maxActivatedCards: at most this many cards on, whatever the decks
C.activeActionId = 37866 -- the action id of a card that is on (the base's BLOCK_CARDS_AID)
C.legendaryFlagBase = 110017 -- base: storage 110017 + (id - 27547) is set once when a legendary card is first turned on
C.legendaryFlagFrom = 27547
C.scanLimit = 600 -- items looked at per scan of the backpack tree (a guard, a bag has far fewer)
C.reconcileMs = 60000 -- a card that left the deck (death, a bag put away) is turned off at most this late
C.maxTextBytes = 6000 -- the status text stays under the extended opcode's 8192 bytes with its JSON around it

-- deck item id -> cards it holds (the base items.xml containerSize)
C.decks = {
	{id = 27632, size = 5, name = "Bronze Deck"},
	{id = 27633, size = 10, name = "Silver Deck"},
	{id = 27634, size = 20, name = "Golden Deck"},
}

-- Where a deck comes from: Veyra the Apothecary (apothecary_config.lua `decks`; her prices are read from there)
C.seller = "Veyra the Apothecary"

C.tiers = {"Minor", "Major", "Intense", "Powerful"}

-- The 60 common to mythic cards: 15 lines of four tiers (Minor, Major, Intense, Powerful), ids 27482-27541 in this order;
-- storage 37000 + (id - 27482). Each line belongs to one CURRENT spell (name and spell id; stock_spells.csv or
-- spells_chaos.xml, tests/cards_test.lua checks both). The base spell scripts read the card storages themselves for the
-- spells that still have their stock script (how = "live": no code here). The stock spells that were retired have their
-- lines moved to the Chaos spell of the same role (how = "hit": cards.lua acts when the spell hits; how = "bow":
-- tautstring.lua reads buffBonus()).
--   kind convert  the spell's damage becomes the element of the highest tier on
--   kind heal     the spell heals pct[tier] percent more (highest tier on)
--   kind melee    Bloodlust: secs[tier] longer, pct[tier] more percentage points of melee skill
--   kind widen    Taunt of Iron: a wider area, step = tier
--   kind bow      Tautstring: secs[tier] longer, pct[tier] more percentage points of distance skill
local families = {
	{kind = "convert", spell = "Reaping Gyre", id = 220, how = "hit", elements = {"Earth", "Ice", "Death", "Energy"}},
	{kind = "convert", spell = "Rime Bloom", id = 200, how = "hit", elements = {"Fire", "Holy", "Death", "Energy"}},
	{kind = "convert", spell = "Tempest Fan", id = 13, how = "live", elements = {"Holy", "Ice", "Drown", "Death"}},
	{kind = "convert", spell = "Sanctum Burst", id = 124, how = "live", elements = {"Fire", "Ice", "Earth", "Death"}},
	{kind = "convert", spell = "Frostfall Rune", id = 115, how = "live", elements = {"Fire", "Earth", "Energy", "Death"}},
	{kind = "convert", spell = "Doomtide", id = 206, how = "hit", elements = {"Fire", "Holy", "Death", "Energy"}},
	{kind = "convert", spell = "Primordial Squall", id = 213, how = "hit", elements = {"Holy", "Earth", "Death", "Ice"}},
	{kind = "convert", spell = "Earthbreaker", id = 221, how = "hit", elements = {"Fire", "Earth", "Ice", "Death"}},
	{kind = "melee", spell = "Bloodlust", id = 133, how = "live", secs = {2, 4, 6, 10}, pct = {2, 4, 6, 7}},
	{kind = "convert", spell = "Pyre Torrent", id = 163, how = "live", elements = {"Ice", "Holy", "Death", "Energy"}},
	{kind = "convert", spell = "Frozen Crypt", id = 205, how = "hit", elements = {"Fire", "Holy", "Death", "Energy"}},
	{kind = "heal", spell = "Grand Mending", id = 3, how = "hit", pct = {10, 20, 30, 40}},
	{kind = "convert", spell = "Dawnpiercer", id = 214, how = "hit", elements = {"Fire", "Earth", "Death", "Energy"}},
	{kind = "widen", spell = "Taunt of Iron", id = 93, how = "live"},
	{kind = "bow", spell = "Tautstring", id = 135, how = "bow", secs = {2, 4, 6, 8}, pct = {2, 4, 6, 8}},
}
C.families = families

-- id -> {storage, kind, ...}; byTarget[spell id] = the family a "hit" card line acts on
C.cards = {}
C.byTarget = {}
for f, fam in ipairs(families) do
	fam.ids = {}
	if fam.how == "hit" then
		C.byTarget[fam.id] = fam
	end
	for t = 1, 4 do
		local id = 27482 + (f - 1) * 4 + (t - 1)
		fam.ids[t] = id
		C.cards[id] = {storage = 37000 + (id - 27482), tier = t, kind = fam.kind, spell = fam.spell, spellId = fam.id,
			how = fam.how, family = f, element = fam.elements and fam.elements[t] or nil,
			secs = fam.secs and fam.secs[t] or nil, pct = fam.pct and fam.pct[t] or nil}
	end
end

-- the highest tier of a family that is on (0 = none); storageOf(storage key) -> value
function C.topTier(fam, storageOf)
	for t = 4, 1, -1 do
		if storageOf(C.cards[fam.ids[t]].storage) == 1 then
			return t
		end
	end
	return 0
end

-- Tautstring (spells state): the extra seconds and percentage points of the line that is on
function C.buffBonus(spellId, storageOf)
	for _, fam in ipairs(families) do
		if fam.id == spellId and fam.how == "bow" then
			local t = C.topTier(fam, storageOf)
			if t > 0 then
				return fam.secs[t], fam.pct[t]
			end
		end
	end
	return 0, 0
end

-- The 16 level 6 legendary cards (the lower levels only upgrade and are not turned on): id order of the base table, storage
-- 37065 + position. class (the weapon in the left hand decides, not the vocation), the stat it raises, by how much, for
-- how many seconds. The chance of the summon (the base's chance, chance2, chance3, chance4) goes by position in the class.
C.legendaryMinDamage = 50
C.legendaryChance = {7, 9, 14, 20}
C.legendaryWeapon = {Sorcerer = "a wand", Druid = "a rod", Paladin = "a bow or a crossbow", Knight = "a melee weapon"}
local legendary = {
	{27547, "Sorcerer", "magic level", 3, 25}, {27553, "Sorcerer", "magic level", 6, 45},
	{27559, "Sorcerer", "magic level", 9, 65}, {27565, "Sorcerer", "magic level", 15, 90},
	{27571, "Druid", "magic level", 3, 25}, {27577, "Druid", "magic level", 6, 45},
	{27583, "Druid", "magic level", 9, 65}, {27589, "Druid", "magic level", 15, 90},
	{27595, "Paladin", "distance skill", 3, 25}, {27601, "Paladin", "distance skill", 6, 45},
	{27607, "Paladin", "distance skill", 9, 65}, {27640, "Paladin", "distance skill", 15, 90},
	{27613, "Knight", "melee skill", 3, 25}, {27619, "Knight", "melee skill", 6, 45},
	{27625, "Knight", "melee skill", 9, 65}, {27631, "Knight", "melee skill", 15, 90},
}
for i, l in ipairs(legendary) do
	C.cards[l[1]] = {storage = 37064 + i, kind = "legendary", class = l[2], pct = C.legendaryChance[(i - 1) % 4 + 1],
		stat = l[3], amount = l[4], secs = l[5], legendary = true}
end

return C
