-- cards_core.lua: the rules of the cards and decks (server/README.md "Cards and decks"). Pure Lua, no engine calls; the
-- glue is cards.lua, the numbers cards_config.lua, the tests tests/cards_test.lua. Lua 5.1 / LuaJIT and 5.3.
--
-- A card is on when its storage is 1 and one copy of it sits in a deck the player carries with the action id 37866 (the
-- base refuses to move or trade that copy). The scan of the carried bags (cards.lua) gives this module:
--   decks = {{id = deck item id, used = cards inside, size = capacity, cards = {{id, aid = bool, ref}}}}
--   loose = {{id, aid = bool, ref}}   cards carried outside a deck
--   storage = function(cardId) -> value of the card's storage
-- reconcile() says what to repair, decide() what a "use" does, statusText() what Character Info shows.

local C = ChaosCardsConfig or dofile("data/scripts/chaos/cards_config.lua")
ChaosCardsConfig = C
ChaosCardsCore = ChaosCardsCore or {}
local K = ChaosCardsCore
K.config = C

K.deckInfo = {}
for _, d in ipairs(C.decks) do
	K.deckInfo[d.id] = d
end

function K.isCard(id)
	return C.cards[tonumber(id) or -1] ~= nil
end

function K.isDeck(id)
	return K.deckInfo[tonumber(id) or -1] ~= nil
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
K.T = T

-- ---------------------------------------------------------------- texts (keys are English; pt-BR in i18n_strings.lua)
K.TEXT = {
	on = "You turned on %s: %s",
	off = "You turned off %s.",
	moved = "%s went into your %s.",
	dupe = "%s is already on with another copy of it. Only one copy counts.",
	max = "You already have %d cards on, the most there can be. Turn one off first.",
	full = "Your decks are full. Take a card out of a deck that is off, or buy a bigger deck from %s.",
	nodeck = "You need a deck to use cards. Buy one from %s in the hub: Bronze Deck for %d gold (5 cards), Silver Deck for %d (10 cards, level %d), Golden Deck for %d (20 cards, level %d). Carry it, then use the card again.",
	lostoff = "The card %s is no longer in a deck you carry: turned off.",
	notcarried = "Carry the card in your backpack to use it: not in the depot or the Purse.",
	failed = "The card could not be moved into your deck.",
	-- Character Info
	hdr_decks = "Decks carried: %s",
	hdr_none = "You carry no deck.",
	hdr_on = "Cards on (%d of %d):",
	hdr_off = "Cards in your decks, off:",
	hdr_loose = "Cards carried outside a deck (use one to put it in a deck):",
	none_on = "No card is on.",
	more = "... and %d more.",
	cut = "(The list is cut here.)",
	deckline = "%s %d of %d",
	howto = "Use a card you carry: it goes into a deck and turns on. Use it again to turn it off. At most %d cards are on at once.",
	-- bonus texts: one per kind of card (the item description is this plus HINT)
	convert = "While on, %s deals %s damage instead. With several cards of this spell on, the highest one counts.",
	convert2 = "While on, %s deal %s damage instead. With several cards of these spells on, the highest one counts.",
	heal = "While on, %s heals %d%% more. With several cards of this spell on, the highest one counts.",
	melee = "While on, %s lasts %d seconds longer and gives %d more percentage points of melee skill.",
	widen = "While on, %s reaches a wider area (step %d of 4).",
	bow = "While on, %s lasts %d seconds longer and gives %d more percentage points of distance skill.",
	legendary = "Needs %s. While on, a hit of %d damage or more has a %d%% chance to summon a monster that fights with you and gives you %d more %s for %d seconds. Only one summon at a time.",
}

-- the hint every card description ends with (tools/patch_badges.py CARD_HINT is the same text; tests compare them)
K.HINT = "Use it to put it in a deck you carry and turn it on, use it again to turn it off. Veyra the Apothecary sells decks."

-- the vocabulary the bonus texts put in (each is a key in i18n_strings.lua)
local function word(lang, w)
	return T(lang, w)
end

-- what a card gives, one sentence (the status text of Character Info, the item description, the tooltip)
function K.bonusText(lang, id)
	local c = C.cards[tonumber(id) or -1]
	if not c then
		return ""
	end
	if c.kind == "convert" then
		if c.spellNames and #c.spellNames > 1 then
			-- a line that acts on spells of several classes: "A and B deal Fire damage instead"
			local names = {}
			for i, n in ipairs(c.spellNames) do
				names[i] = n
			end
			local last = table.remove(names)
			local list = table.concat(names, ", ") .. T(lang, " and ") .. last
			return T(lang, K.TEXT.convert2, list, word(lang, c.element))
		end
		return T(lang, K.TEXT.convert, c.spell, word(lang, c.element))
	elseif c.kind == "heal" then
		return T(lang, K.TEXT.heal, c.spell, c.pct)
	elseif c.kind == "melee" then
		return T(lang, K.TEXT.melee, c.spell, c.secs, c.pct)
	elseif c.kind == "widen" then
		return T(lang, K.TEXT.widen, c.spell, c.tier)
	elseif c.kind == "bow" then
		return T(lang, K.TEXT.bow, c.spell, c.secs, c.pct)
	elseif c.kind == "legendary" then
		return T(lang, K.TEXT.legendary, word(lang, C.legendaryWeapon[c.class]), C.legendaryMinDamage, c.pct, c.amount,
			word(lang, c.stat), c.secs)
	end
	return ""
end

-- the item description of a card: what it gives and how to use it
function K.description(lang, id)
	if not K.isCard(id) then
		return ""
	end
	return K.bonusText(lang, id) .. " " .. T(lang, K.HINT)
end

-- the seller's prices for the no-deck text: {id, price, level} per deck from apothecary_config.lua
function K.sellerDecks()
	local ok, cfg = pcall(dofile, "data/scripts/chaos/apothecary_config.lua")
	local out = {}
	if ok and type(cfg) == "table" and cfg.decks then
		for _, d in ipairs(cfg.decks) do
			out[#out + 1] = {id = d.id, price = d.price, level = d.level}
		end
	end
	return out
end

local function priceOf(list, id)
	for _, d in ipairs(list) do
		if d.id == id then
			return d.price, d.level
		end
	end
	return 0, 0
end

function K.noDeckText(lang, sellers)
	sellers = sellers or K.sellerDecks()
	local bp = priceOf(sellers, 27632)
	local sp, sl = priceOf(sellers, 27633)
	local gp, gl = priceOf(sellers, 27634)
	return T(lang, K.TEXT.nodeck, C.seller, bp, sp, sl, gp, gl)
end

-- ---------------------------------------------------------------- legendary cards: the weapon
-- The legendary card of a class fires when the hit comes with the right weapon in the left hand (the base script: four
-- lists of stock item ids; tools/patch_badges.py now hands the check to ChaosCards.holds, which classifies by weapon
-- type). kind: "sword", "club", "axe", "distance", "wand" (engine weapon types), "fist" (a fist weapon: weapon type
-- shield with an attack, in the shield hand), nil for an empty hand.
function K.kindOf(typeName, isFistItem)
	if typeName == "sword" or typeName == "club" or typeName == "axe" or typeName == "distance" or typeName == "wand" then
		return typeName
	end
	if isFistItem then
		return "fist"
	end
	return nil
end

-- class: "Knight" | "Paladin" | "Sorcerer" | "Druid"; hands = {left = kind, right = kind (the other hand), fistLine = the
-- player is in the Monk line}. A fist weapon counts from either hand (it sits in the shield hand), and the Monk line
-- fights with an empty left hand.
function K.holds(class, hands)
	local kinds = C.legendaryKinds[class]
	if not kinds or not hands then
		return false
	end
	if hands.left and kinds[hands.left] then
		return true
	end
	if hands.right == "fist" and kinds.fist then
		return true
	end
	return hands.left == nil and hands.fistLine == true and kinds.fist == true
end

-- the legendary card ids that fire for a class row of C.classes with one of its weapons ("none" = empty hands)
function K.legendaryFor(classRow, weapon)
	local out = {}
	for id, c in pairs(C.cards) do
		if c.legendary then
			local hands = {fistLine = classRow.line == C.fistLine}
			if weapon == "fist" then
				hands.right = "fist"
			elseif weapon ~= "none" then
				hands.left = weapon
			end
			if K.holds(c.class, hands) then
				out[#out + 1] = id
			end
		end
	end
	table.sort(out)
	return out
end

-- ---------------------------------------------------------------- reconcile
-- What to repair so storage, action ids and the carried decks agree:
--   off     card ids whose storage is 1 but no copy of the card is on in a deck carried (it was dropped, lost, put away):
--           their storage goes to 0
--   clear   refs of copies that carry the action id without being the on copy (a second copy, a copy outside a deck, a
--           copy whose storage is off): the action id goes, so the card can be moved again
--   active  card id -> the ref of the copy that is on
-- The first copy with the action id in a deck wins when the storage is 1.
function K.reconcile(decks, loose, storage)
	local active, clear, off = {}, {}, {}
	for _, deck in ipairs(decks or {}) do
		for _, card in ipairs(deck.cards or {}) do
			if card.aid then
				if storage(card.id) == 1 and not active[card.id] then
					active[card.id] = card
				else
					clear[#clear + 1] = card
				end
			end
		end
	end
	for _, card in ipairs(loose or {}) do
		if card.aid then
			clear[#clear + 1] = card
		end
	end
	local ids = {}
	for id in pairs(C.cards) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		if storage(id) == 1 and not active[id] then
			off[#off + 1] = id
		end
	end
	return {off = off, clear = clear, active = active}
end

-- number of cards on after a reconcile
function K.activeCount(plan)
	local n = 0
	for _ in pairs(plan.active) do
		n = n + 1
	end
	return n
end

-- ---------------------------------------------------------------- use
-- s = {id, inDeck (the used copy sits in a deck carried), isOn (this copy is the one that is on), storageOn (the card is on,
-- after reconcile), count (cards on), decks = {{used, size}}}. Returns the action and, for "move", the index in s.decks
-- of the deck to put it in (the first with room; the scan lists the biggest deck first).
function K.decide(s)
	if not K.isCard(s.id) then
		return "notcard"
	end
	if s.storageOn then
		return s.isOn and "off" or "dupe"
	end
	if (s.count or 0) >= C.maxActive then
		return "max"
	end
	if s.inDeck then
		return "on"
	end
	if #(s.decks or {}) == 0 then
		return "nodeck"
	end
	for i, d in ipairs(s.decks) do
		if (d.used or 0) < (d.size or 0) then
			return "move", i
		end
	end
	return "full"
end

-- ---------------------------------------------------------------- Character Info
local function deckName(id)
	local d = K.deckInfo[id]
	return d and d.name or tostring(id)
end

-- The text of the `deck` command. st = {decks, loose, storage, nameOf = function(id) -> item name}.
-- Names go through nameOf (the item type's name); the text stays under C.maxTextBytes.
function K.statusText(lang, st)
	local nameOf = st.nameOf or function(id) return tostring(id) end
	local lines = {}
	local function add(s)
		lines[#lines + 1] = s
	end
	local plan = K.reconcile(st.decks, st.loose, st.storage)
	local used, total, parts = 0, 0, {}
	for _, d in ipairs(st.decks) do
		used, total = used + (d.used or 0), total + (d.size or 0)
		parts[#parts + 1] = T(lang, K.TEXT.deckline, T(lang, deckName(d.id)), d.used or 0, d.size or 0)
	end
	if #st.decks == 0 then
		add(T(lang, K.TEXT.hdr_none))
		add(K.noDeckText(lang, st.sellers))
	else
		add(T(lang, K.TEXT.hdr_decks, table.concat(parts, ", ")))
		add(T(lang, K.TEXT.deckline, T(lang, "Cards"), used, total))
	end
	add(T(lang, K.TEXT.howto, C.maxActive))
	add("")
	local count = K.activeCount(plan)
	add(T(lang, K.TEXT.hdr_on, count, C.maxActive))
	local onIds = {}
	for id in pairs(plan.active) do
		onIds[#onIds + 1] = id
	end
	table.sort(onIds)
	if #onIds == 0 then
		add("  " .. T(lang, K.TEXT.none_on))
	end
	for _, id in ipairs(onIds) do
		add("  " .. nameOf(id) .. ": " .. K.bonusText(lang, id))
	end
	-- cards in decks that are off, one line each copy; then the loose ones
	local offList, looseList = {}, {}
	for _, d in ipairs(st.decks) do
		for _, card in ipairs(d.cards or {}) do
			if plan.active[card.id] ~= card then
				offList[#offList + 1] = card.id
			end
		end
	end
	for _, card in ipairs(st.loose or {}) do
		looseList[#looseList + 1] = card.id
	end
	table.sort(offList)
	table.sort(looseList)
	local bytes = 0
	for _, l in ipairs(lines) do
		bytes = bytes + #l + 1
	end
	local cut = false
	local function section(title, ids)
		if #ids == 0 or cut then
			return
		end
		add("")
		add(title)
		bytes = bytes + #title + 2
		for i, id in ipairs(ids) do
			local line = "  " .. nameOf(id) .. ": " .. K.bonusText(lang, id)
			if bytes + #line + 1 > C.maxTextBytes - 200 then
				add("  " .. T(lang, K.TEXT.more, #ids - i + 1))
				cut = true
				return
			end
			add(line)
			bytes = bytes + #line + 1
		end
	end
	section(T(lang, K.TEXT.hdr_off), offList)
	section(T(lang, K.TEXT.hdr_loose), looseList)
	return table.concat(lines, "\n")
end

return K
