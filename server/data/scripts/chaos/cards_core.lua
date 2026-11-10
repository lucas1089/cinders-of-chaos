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
	-- card sets (O453): the line of Character Info, the message after a card is turned on or off, the card text
	set_on = "Card set %s is on with %s cards: %s",
	set_progress = "Card set %s: %s of %s cards. The bonus: %s",
	set_none = "No card set yet. %s cards of one element, one for each spell you cast, give a set bonus.",
	set_off = "Card set %s is off.",
	setcard = "It counts for the %s card set. With %s cards of one element, one for each spell you cast, you get a bonus.",
	set_damage = "Your %s damage: +%s%% increased damage (a card set adds at most 4 to the one damage pool).",
	set_slow = "Your %s hits slow the target by %s%% for %s seconds.",
	set_poison = "Your %s hits poison the target for %s%% of the hit over %s seconds.",
	set_leech = "Your %s hits heal you for %s%% of the damage, at most %s%% of your maximum health a hit.",
	set_heal = "Your %s hits heal you for %s%% of your maximum health, at most once every %s seconds.",
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

-- ---------------------------------------------------------------- card sets (O453)
-- Pure rules: which cards count for a set, the state of a player's cards, the bonus numbers and texts. The engine glue
-- (cards.lua) applies the bonus at the hit; tests/cards_test.lua tests every rule here.
local S = C.sets
K.sets = S

-- the number as a short text: 5 -> "5", 1.5 -> "1.5"
local function num(n)
	return string.format("%g", n)
end

-- The element a card counts for in a set: the element of a convert card whose element has a set bonus. Nil for a card with
-- no element (heal, melee, widen, bow, legendary), for an element with no set (Drown: one line only) and for no card.
function K.setElement(id)
	local c = C.cards[tonumber(id) or -1]
	if c and c.kind == "convert" and c.element and S.by[c.element] then
		return c.element
	end
	return nil
end

-- does the class (a name of C.classes) cast the spells of a convert line
local lineSets = {}
for spell, names in pairs(C.lineClasses) do
	local set = {}
	for _, n in ipairs(names) do
		set[n] = true
	end
	lineSets[spell] = set
end
function K.castsLine(className, fam)
	local set = lineSets[fam.spell]
	return set ~= nil and set[className] == true
end

-- the name of a class by vocation id (C.classes); nil for an id that is no class
function K.classNameOf(vocId)
	vocId = tonumber(vocId)
	for _, row in ipairs(C.classes) do
		if row.id == vocId then
			return row.name
		end
	end
	return nil
end

-- The cards that count for a class: one per convert line the class casts, the highest card of the line that is on (a lower card
-- of the same line is overridden by it, so it counts for nothing). isOn(card id) -> true when the card is on. Each entry:
-- {line, spell, tier, id, element}; element is nil when that card has no set element (Drown).
function K.effectiveCards(isOn, className)
	local out = {}
	for f, fam in ipairs(C.families) do
		if fam.kind == "convert" and K.castsLine(className, fam) then
			for t = 4, 1, -1 do
				if isOn(fam.ids[t]) then
					out[#out + 1] = {line = f, spell = fam.spell, tier = t, id = fam.ids[t], element = K.setElement(fam.ids[t])}
					break
				end
			end
		end
	end
	return out
end

-- The state of the sets of a class for the cards that are on: {counts = {element = cards}, active = {{element, count}}
-- (at most S.maxSets, the most cards first, then S.order), element/count = the first active one, best = {element, count} the
-- element with the most cards while no set is on (ties by S.order), nil with no card of an element}. With 4 or 5 cards of the
-- element the bonus is the same: one tier only.
function K.setState(isOn, className)
	local counts = {}
	for _, e in ipairs(K.effectiveCards(isOn, className)) do
		if e.element then
			counts[e.element] = (counts[e.element] or 0) + 1
		end
	end
	local list, best = {}, nil
	for rank, el in ipairs(S.order) do
		local n = counts[el] or 0
		if n >= S.need then
			list[#list + 1] = {element = el, count = n, rank = rank}
		end
		if n > 0 and (not best or n > best.count) then
			best = {element = el, count = n}
		end
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.rank < b.rank
	end)
	local state = {counts = counts, active = {}, best = best}
	for i = 1, math.min(#list, S.maxSets) do
		state.active[i] = {element = list[i].element, count = list[i].count}
	end
	if state.active[1] then
		state.element, state.count = state.active[1].element, state.active[1].count
	end
	return state
end

-- the text two equal states share, to tell the player only when the set changes
function K.setKey(state)
	if not state then
		return ""
	end
	if state.element then
		local parts = {}
		for i, a in ipairs(state.active) do
			parts[i] = a.element
		end
		return "on:" .. table.concat(parts, ",")
	end
	-- the player is told about progress from 2 cards on (one card of an element is not news)
	return state.best and state.best.count >= 2 and ("progress:" .. state.best.element .. state.best.count) or ""
end

-- the bonus of an element (a row of S.by), nil when the element has none
function K.setBonus(element)
	return S.by[element]
end

-- the factor of a bonus number against a target: 1 against monsters, S.pvpScale against a player
function K.setScale(vsPlayer)
	return vsPlayer and S.pvpScale or 1
end

-- A damage part (damage or poison) of a set on a hit: the extra amount (same sign as the hit, rounded toward zero). pct of
-- the part of the hit that is of the element, x the PvP scale. Zero for a hit of another element, for no set, for a kind that
-- has no damage part.
function K.setExtra(element, kind, amount, vsPlayer)
	local b = S.by[element]
	if not b or b.kind ~= kind or (kind ~= "damage" and kind ~= "poison") or not amount or amount == 0 then
		return 0
	end
	local a = math.floor(math.abs(amount) * b.pct * K.setScale(vsPlayer) / 100 + 1e-6)
	return amount < 0 and -a or a
end

-- the health a Death set leeches from a hit of `dealt` damage (a positive number), at most maxShare percent of the maximum
function K.setLeech(element, dealt, maxHealth)
	local b = S.by[element]
	if not b or b.kind ~= "leech" or not dealt or dealt <= 0 then
		return 0
	end
	local n = math.floor(dealt * b.pct / 100 + 1e-6)
	return math.max(0, math.min(n, math.floor((maxHealth or 0) * b.maxShare / 100)))
end

-- the health a Holy set heals on a hit (a share of the maximum health)
function K.setHeal(element, maxHealth)
	local b = S.by[element]
	if not b or b.kind ~= "heal" then
		return 0
	end
	return math.max(0, math.floor((maxHealth or 0) * b.pct / 100 + 1e-6))
end

-- the slow of an Ice set against a target: percent (0..1 for the engine) and milliseconds; nil against a player
function K.setSlow(element, vsPlayer)
	local b = S.by[element]
	if not b or b.kind ~= "slow" or vsPlayer then
		return nil
	end
	return b.percent / 100, b.ms
end

-- the bonus of an element in a sentence
function K.setBonusText(lang, element)
	local b = S.by[element]
	if not b then
		return ""
	end
	local el = word(lang, element)
	if b.kind == "damage" then
		return T(lang, K.TEXT.set_damage, el, num(b.pct))
	elseif b.kind == "slow" then
		return T(lang, K.TEXT.set_slow, el, num(b.percent), num(b.ms / 1000))
	elseif b.kind == "poison" then
		return T(lang, K.TEXT.set_poison, el, num(b.pct), num(b.ticks))
	elseif b.kind == "leech" then
		return T(lang, K.TEXT.set_leech, el, num(b.pct), num(b.maxShare))
	elseif b.kind == "heal" then
		return T(lang, K.TEXT.set_heal, el, num(b.pct), num(b.cooldownMs / 1000))
	end
	return ""
end

-- the line for a state: the set that is on, else the progress, else how to get one
function K.setLine(lang, state)
	if state and state.element then
		return T(lang, K.TEXT.set_on, word(lang, state.element), num(state.count), K.setBonusText(lang, state.element))
	end
	if state and state.best then
		return T(lang, K.TEXT.set_progress, word(lang, state.best.element), num(state.best.count), num(S.need),
			K.setBonusText(lang, state.best.element))
	end
	return T(lang, K.TEXT.set_none, num(S.need))
end

-- what to tell a player after a card went on or off: nil when the set did not change. before and after are states.
function K.setMessage(lang, before, after)
	if K.setKey(before) == K.setKey(after) then
		return nil
	end
	if before and before.element and not (after and after.element) then
		return T(lang, K.TEXT.set_off, word(lang, before.element))
	end
	return K.setLine(lang, after)
end

-- the state of the sets for a reconcile plan (the cards that are on) and a class name
function K.planSetState(plan, className)
	local active = (plan and plan.active) or {}
	return K.setState(function(id) return active[id] ~= nil end, className)
end

-- the item description of a card: what it gives, the set it counts for, and how to use it
function K.description(lang, id)
	if not K.isCard(id) then
		return ""
	end
	local text = K.bonusText(lang, id)
	local el = K.setElement(id)
	if el then
		text = text .. " " .. T(lang, K.TEXT.setcard, word(lang, el), num(S.need))
	end
	return text .. " " .. T(lang, K.HINT)
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

-- ---------------------------------------------------------------- card borders
-- The client draws a border on the cards inside a deck window (client game_cardborder): gold-green when the card is on, dim
-- when it is off. It cannot see action ids, so the server sends the card ids that are on (extended opcode 172, action
-- "state", data {on = {ids}}). A card is told by its id, not by its copy: the client only decorates cards that sit in a
-- deck container, and a second copy in a deck beside the one that is on shows as on too (the server counts one copy).
-- ids of the cards that are on after a reconcile, ascending
function K.activeIds(plan)
	local ids = {}
	for id in pairs((plan and plan.active) or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

-- the text two equal sets share, to send only when the set changes
function K.stateKey(ids)
	local parts = {}
	for i, id in ipairs(ids or {}) do
		parts[i] = tostring(id)
	end
	return table.concat(parts, ",")
end

-- the payload of the "state" message, in the ids the client draws (clientId(serverId); the same number when nil):
--   on     the cards that are on, ascending by server id
--   cards  every card, decks  every deck: the client decorates only cards inside a deck container
function K.statePayload(plan, clientId)
	local conv = clientId or function(id) return id end
	local out = {on = {}, cards = {}, decks = {}}
	for _, id in ipairs(K.activeIds(plan)) do
		out.on[#out.on + 1] = conv(id)
	end
	local ids = {}
	for id in pairs(C.cards) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		out.cards[#out.cards + 1] = conv(id)
	end
	for _, d in ipairs(C.decks) do
		out.decks[#out.decks + 1] = conv(d.id)
	end
	return out
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
	-- the card set (O453): needs the class; a caller without one (st.vocId nil) gets no set line
	local className = K.classNameOf(st.vocId)
	if className then
		add("")
		add(K.setLine(lang, K.planSetState(plan, className)))
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
