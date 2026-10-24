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
C.summonReleaseMs = 5000 -- a legendary summon that died early frees the "one summon at a time" lock at most this late
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
-- `also` (hit lines only): more current spells the same line acts on, {name, spell id}. The Thief, Monk, Templar and
-- Necromancer lines had no card line at all (beta 2026-10-23: "a card I put in my deck does not work", a Ninja): each now
-- has one spell on a line whose stock spell was retired, so nobody who had the line lost it. Every class of the 21 has
-- at least one line (tests/cards_test.lua walks every card x every class).
-- O149 (parity): the median class had 3 usable common lines (the rune everyone casts counts), the Illusionist, Thief, Monk
-- and Templar lines only 2 and the Necromancer line 3 of the 4 the martial lines have. More `also` spells bring every class
-- to at least 3 and the Necromancer line to 4: Marrow Bolt and Soulrend Beam on Rime Bloom, Shattered Psyche (Mystic and
-- Illusionist) on Frozen Crypt, Shuriken Toss on Primordial Squall, Radiant Smite on Dawnpiercer and Palm Shockwave on
-- Earthbreaker. tests/cards_test.lua keeps the floor (MIN_LINES).
local families = {
	{kind = "convert", spell = "Reaping Gyre", id = 220, how = "hit", elements = {"Earth", "Ice", "Death", "Energy"}},
	{kind = "convert", spell = "Rime Bloom", id = 200, how = "hit", elements = {"Fire", "Holy", "Death", "Energy"},
		also = {{"Marrow Bolt", 106}, {"Soulrend Beam", 118}}},
	{kind = "convert", spell = "Tempest Fan", id = 13, how = "live", elements = {"Holy", "Ice", "Drown", "Death"}},
	{kind = "convert", spell = "Sanctum Burst", id = 124, how = "live", elements = {"Fire", "Ice", "Earth", "Death"}},
	{kind = "convert", spell = "Frostfall Rune", id = 115, how = "live", elements = {"Fire", "Earth", "Energy", "Death"}},
	{kind = "convert", spell = "Doomtide", id = 206, how = "hit", elements = {"Fire", "Holy", "Death", "Energy"},
		also = {{"Blade Flurry", 73}}},
	{kind = "convert", spell = "Primordial Squall", id = 213, how = "hit", elements = {"Holy", "Earth", "Death", "Ice"},
		also = {{"Shuriken Toss", 236}}},
	{kind = "convert", spell = "Earthbreaker", id = 221, how = "hit", elements = {"Fire", "Earth", "Ice", "Death"},
		also = {{"Consecration", 190}, {"Palm Shockwave", 194}}},
	{kind = "melee", spell = "Bloodlust", id = 133, how = "live", secs = {2, 4, 6, 10}, pct = {2, 4, 6, 7}},
	{kind = "convert", spell = "Pyre Torrent", id = 163, how = "live", elements = {"Ice", "Holy", "Death", "Energy"}},
	{kind = "convert", spell = "Frozen Crypt", id = 205, how = "hit", elements = {"Fire", "Holy", "Death", "Energy"},
		also = {{"Sundering Palm", 64}, {"Shattered Psyche", 228}}},
	{kind = "heal", spell = "Grand Mending", id = 3, how = "hit", pct = {10, 20, 30, 40}},
	{kind = "convert", spell = "Dawnpiercer", id = 214, how = "hit", elements = {"Fire", "Earth", "Death", "Energy"},
		also = {{"Bone Spear", 181}, {"Radiant Smite", 189}}},
	{kind = "widen", spell = "Taunt of Iron", id = 93, how = "live"},
	{kind = "bow", spell = "Tautstring", id = 135, how = "bow", secs = {2, 4, 6, 8}, pct = {2, 4, 6, 8}},
}
C.families = families

-- id -> {storage, kind, ...}; byTarget[spell id] = the family a "hit" card line acts on
C.cards = {}
C.byTarget = {}
for f, fam in ipairs(families) do
	fam.ids = {}
	fam.spells = {{fam.spell, fam.id}}
	for _, extra in ipairs(fam.also or {}) do
		fam.spells[#fam.spells + 1] = extra
	end
	if fam.how == "hit" then
		for _, sp in ipairs(fam.spells) do
			C.byTarget[sp[2]] = fam
		end
	end
	for t = 1, 4 do
		local id = 27482 + (f - 1) * 4 + (t - 1)
		fam.ids[t] = id
		local names = {}
		for _, sp in ipairs(fam.spells) do
			names[#names + 1] = sp[1]
		end
		C.cards[id] = {storage = 37000 + (id - 27482), tier = t, kind = fam.kind, spell = fam.spell, spellId = fam.id,
			spells = fam.spells, spellNames = names, how = fam.how, family = f, element = fam.elements and fam.elements[t] or nil,
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
C.legendaryWeapon = {Sorcerer = "a wand or a rod in your left hand", Druid = "a wand or a rod in your left hand",
	Paladin = "a bow or a crossbow in your left hand",
	Knight = "a melee weapon in your left hand (the Monk line: a fist weapon or bare fists)"}
-- Which weapon in the left hand lets the legendary card of a class fire (cards_core.lua K.holds; the base script knew only
-- four lists of stock item ids, so most weapons, all the Chaos ones, never fired; tools/patch_badges.py hands the check to
-- ChaosCards.holds). The kinds are the engine's weapon types: sword, club and axe (daggers are swords), distance (bows,
-- crossbows, thrown weapons), wand (wands and rods are one weapon type: a wand or a rod fires either mage card) and fist
-- (a fist weapon sits in the shield hand; the Monk line also fights with empty hands).
C.legendaryKinds = {
	Knight = {sword = true, club = true, axe = true, fist = true},
	Paladin = {distance = true},
	Sorcerer = {wand = true},
	Druid = {wand = true},
}
-- The 21 classes (docs/CLASSES.md; Chaos.classes.ids): vocation id, the vocation name the spell files use, the line
-- (base class) and the weapons the class fights with (the kinds above; "none" = empty hands).
C.fistLine = "Monk" -- the line that fights with empty hands
C.classes = {
	{name = "Warrior", id = 4, line = "Warrior", weapons = {"sword", "club", "axe"}},
	{name = "Juggernaut", id = 8, line = "Warrior", weapons = {"sword", "club", "axe"}},
	{name = "Berserker", id = 14, line = "Warrior", weapons = {"sword", "club", "axe"}},
	{name = "Ranger", id = 3, line = "Ranger", weapons = {"distance"}},
	{name = "Deadeye", id = 7, line = "Ranger", weapons = {"distance"}},
	{name = "Beastmaster", id = 15, line = "Ranger", weapons = {"distance"}},
	{name = "Mystic", id = 1, line = "Mystic", weapons = {"wand"}},
	{name = "Elementalist", id = 5, line = "Mystic", weapons = {"wand"}},
	{name = "Illusionist", id = 10, line = "Mystic", weapons = {"wand"}},
	{name = "Thief", id = 11, line = "Thief", weapons = {"sword"}},
	{name = "Ninja", id = 12, line = "Thief", weapons = {"sword"}},
	{name = "Samurai", id = 13, line = "Thief", weapons = {"sword"}},
	{name = "Necromancer", id = 20, line = "Necromancer", weapons = {"wand"}},
	{name = "Lich", id = 21, line = "Necromancer", weapons = {"wand"}},
	{name = "Bone Lord", id = 22, line = "Necromancer", weapons = {"wand"}},
	{name = "Monk", id = 17, line = "Monk", weapons = {"fist", "none", "club"}},
	{name = "Shadowfist", id = 18, line = "Monk", weapons = {"fist", "none", "sword"}},
	{name = "Iron Sage", id = 19, line = "Monk", weapons = {"fist", "none", "club"}},
	{name = "Templar", id = 23, line = "Templar", weapons = {"sword", "club"}},
	{name = "Inquisitor", id = 24, line = "Templar", weapons = {"sword", "club"}},
	{name = "Sentinel", id = 25, line = "Templar", weapons = {"sword", "club"}},
}
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
