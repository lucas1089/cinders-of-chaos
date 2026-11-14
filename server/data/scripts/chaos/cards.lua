-- cards.lua: the cards and the Deck of Cards (rules: cards_core.lua, numbers: cards_config.lua; server/README.md "Cards and decks",
-- "Deck of Cards (O570)"). Since O570 there is no deck item: every card a character loots is counted in its Deck of Cards (storages
-- of cards_config.lua `deck`, helpers in data/lib/chaos_carddeck.lua). The glue:
--   ChaosCards.absorb(player, deep, only)   a card item (or an old deck item) a player carries is removed and counted in the Deck: on
--        every move of a card (EventCallback onItemMoved), on use (ChaosCards.use, which the base card action asks first), by a
--        sweep every cfg.deck.absorbMs, at login; deep (ChaosCards.migrate, once, marker storage) also walks the depot chests and
--        the store inbox and empties every deck item. A new card gets the chat line and the toast "New card: NAME".
--   ChaosCards.toggle(player, id)   the window turns a card on or off (the card's own storage 37000-37080 = 1, which the base bonus
--        scripts read): the Deck must be open (a main quest step, data/lib/chaos_mqgate.lua), a copy owned, at most five on
--   ChaosCommands "deck"           Character > Character Info: the Deck of Cards, the cards on with what each gives and the set line
--        (replaces the base !deck dialog)
--   login and every cfg.reconcileMs   a card that is on but has no copy, or while the Deck is locked, or beyond five, is turned off
--   ChaosCards.push(player, plan, force)   the window (client game_carddeck, extended opcode 173 ChaosOpcodes.cardDeck): `cards` (the
--        list, on sync) and `state` (copies, new marks, cards on, set line; sent when it changed). Client -> server: sync, toggle,
--        seen, open (the main quest step "deck" is done by opening the window).
--   ChaosCardsHit (onHealthChange)  the cards of a spell whose stock script was retired act on its Chaos replacement
--        (cards_config.lua families, how = "hit"): the hit of that spell changes its element (convert cards) or a heal of
--        the spell heals more (heal cards). The spell is told by the cast context the spells state writes into the
--        caster's storage (ChaosSupports.ctxDecode). The Tautstring line (how = "bow") is read by tautstring.lua.
--        The spells that keep their stock script need no code: the stock scripts read the same storages. A line can act on
--        the spells of several classes (cards_config.lua `also`: the Thief, Monk, Templar and Necromancer lines).
--   ChaosCards.holds(player, class, leftHand, stockIds)   the legendary cards: does the player hold the weapon the card of
--        `class` ("Knight", "Paladin", "Sorcerer", "Druid") needs? The base script asked whether the left hand's item id was
--        in four lists of stock ids, so a Chaos weapon, most stock weapons, a fist weapon, bare fists and the second
--        dagger never fired a card; tools/patch_badges.py step 9 hands that check here, which classifies by weapon type
--        (cards_core.lua K.holds). The stock ids still count.
--   summon release   the base keeps "one summon at a time" in a storage it clears only when the summon times out alive: a
--        summon killed first left the storage at 1 for good, so no card fired again. Cleared at login and every few seconds
--        while the player has no summon.
--   card sets (O453)   three cards of one element (one per convert line the class casts) give a small set bonus: the cache
--        of each player's set is refreshed with every reconcile (ChaosCards.refreshSet, called by push), the bonus is applied by
--        the same ChaosCardsHit event (ChaosCards.applySet, for the hits a player deals); the player is told when the set
--        changes (use) and in Character Info. cards_core.lua has the rules.
-- Storage: the base's card storages (37000-37059, 37065-37080) and the Deck block 7104400 - 7104619. One opcode, 173.
-- Lua 5.1 / LuaJIT. Assumed engine API (TFS 1.4): Player:getSlotItem, Container:getSize/getItem, Item:getId/getActionId/
-- setActionId/moveTo/isContainer/getName.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end
if not ChaosCardsCore or not ChaosCardsCore.decide then
	dofile("data/scripts/chaos/cards_core.lua")
end

if not ChaosCardDeck then
	dofile("data/lib/chaos_carddeck.lua")
end

ChaosCards = ChaosCards or {}
local M = ChaosCards
local Deck = ChaosCardDeck
local K = ChaosCardsCore
local C = K.config

local function log(msg)
	print("[ChaosCards] " .. msg)
end

local function langOf(player)
	return Chaos.lang and Chaos.lang(player) or nil
end

local function nameOf(id)
	local ok, name = pcall(function() return ItemType(id):getName() end)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return tostring(id)
end

-- ---------------------------------------------------------------- the Deck of Cards (O570)
-- Where cards are taken in: the slots a player carries bags in (1-10, 12 and 13: the old deck slot and the badge slot, a badge may
-- be a bag) and, for the one-time migration, the depot chests, the inbox and the store inbox.
local SLOTS = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13}
local DK = C.deck

-- Walks the roots breadth first (containers opened) and lists what the Deck takes in:
--   cards  {item, id}   decks  {item, parent, id} (a retired deck item)   seen  items looked at
-- Never more than `limit` items. parent is the container (or nil for a slot) the deck sits in.
local function collect(roots, limit)
	local cards, decks, queue, i, seen = {}, {}, {}, 1, 0
	for _, r in ipairs(roots) do
		queue[#queue + 1] = {item = r, parent = nil}
	end
	while i <= #queue and seen < limit do
		local e = queue[i]
		i = i + 1
		seen = seen + 1
		local item = e.item
		local id = item:getId()
		if K.isCard(id) then
			cards[#cards + 1] = {item = item, id = id}
		elseif K.isRetiredDeck(id) then
			decks[#decks + 1] = {item = item, parent = e.parent, id = id}
		end
		if item:isContainer() then
			for _, inner in ipairs(item:getItems() or {}) do
				queue[#queue + 1] = {item = inner, parent = item}
			end
		end
	end
	return cards, decks, seen
end
M.collect = collect

local function carriedRoots(player)
	local roots = {}
	for _, slot in ipairs(SLOTS) do
		local it = player:getSlotItem(slot)
		if it then
			roots[#roots + 1] = it
		end
	end
	local ok, inbox = pcall(function() return player:getInbox() end)
	if ok and inbox then
		roots[#roots + 1] = inbox
	end
	return roots
end

-- everything the migration reads: carried bags, the inbox, the store inbox and every depot chest
local function deepRoots(player)
	local roots = carriedRoots(player)
	local ok, store = pcall(function() return player:getStoreInbox() end)
	if ok and store then
		roots[#roots + 1] = store
	end
	for depotId = 0, 30 do
		local okD, chest = pcall(function() return player:getDepotChest(depotId, false) end)
		if okD and chest then
			roots[#roots + 1] = chest
		end
	end
	return roots
end

-- the plan of the on / off storages as they are now (K.reconcile over the Deck)
function M.plan(player)
	return Deck.plan(player)
end

-- repair what disagrees (the plan's `off` cards go to storage 0) and tell the player; returns the plan
function M.reconcile(player, quiet)
	local plan = Deck.plan(player)
	for _, id in ipairs(plan.off) do
		player:setStorageValue(C.cards[id].storage, 0)
		log(player:getName() .. ": card " .. id .. " is off (locked Deck, no copy, or more than " .. C.maxActive .. " on)")
	end
	if not quiet and #plan.off > 0 then
		if plan.lockedOff then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, K.TEXT.lockedoff, Deck.stepTitle(langOf(player))))
		else
			for _, id in ipairs(plan.off) do
				player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, K.TEXT.lostoff, nameOf(id)))
			end
		end
	end
	if #plan.off > 0 then
		plan = Deck.plan(player)
	end
	return plan
end

-- ---------------------------------------------------------------- card sets (O453)
M.sets = {} -- player id -> the state of the player's card sets (K.setState) as of the last reconcile
M.holyAt = {} -- player id -> when the Holy set last healed (ms)

local function nowMs()
	if os.mtime then
		return os.mtime()
	end
	return os.time() * 1000
end

-- the vocation id of a player (nil when the engine has none: a test player, a creature that is no player)
local function vocationId(player)
	local ok, id = pcall(function() return player:getVocation():getId() end)
	return ok and tonumber(id) or nil
end

-- the state of the sets for a reconcile plan; the cache keeps it. Returns the old state, the new one.
function M.refreshSet(player, plan)
	local pid = player:getId()
	local before = M.sets[pid]
	local className = K.classNameOf(vocationId(player))
	local after = className and K.planSetState(plan, className) or nil
	M.sets[pid] = after
	return before, after
end

-- the element of the set that is on for a player and a hit of this combat type, nil for none
local ELEMENT_BY_TYPE = {}
local function elementOfType(ctype)
	if next(ELEMENT_BY_TYPE) == nil then
		for name, const in pairs({Fire = "COMBAT_FIREDAMAGE", Earth = "COMBAT_EARTHDAMAGE", Ice = "COMBAT_ICEDAMAGE",
				Holy = "COMBAT_HOLYDAMAGE", Death = "COMBAT_DEATHDAMAGE", Energy = "COMBAT_ENERGYDAMAGE"}) do
			local v = rawget(_G, const)
			if v then
				ELEMENT_BY_TYPE[v] = name
			end
		end
	end
	return ELEMENT_BY_TYPE[ctype]
end

local function isPlayerObject(c)
	return c ~= nil and type(c.isPlayer) == "function" and c:isPlayer() == true
end

-- does a set of the player's state have this element on
local function setOn(state, element)
	if not state then
		return false
	end
	for _, a in ipairs(state.active) do
		if a.element == element then
			return true
		end
	end
	return false
end

-- run fn(...) a moment later (the engine: addEvent), at once without one (tests)
local function later(fn, ...)
	if type(addEvent) == "function" then
		addEvent(fn, 0, ...)
	else
		fn(...)
	end
end

-- the creature behind an id a moment later (the engine's Creature is a callable table; none in tests: the object itself)
local function creatureById(cid, fallback)
	if rawget(_G, "Creature") ~= nil then
		local ok, c = pcall(Creature, cid)
		return ok and c or nil
	end
	return fallback
end

-- the effects of a set that are not a change of the hit: slow, poison, leech, heal. attacker dealt `dealt` (positive) of
-- `element` to target.
local function setEffects(attackerId, targetId, element, dealt, attackerFallback, targetFallback)
	local attacker = creatureById(attackerId, attackerFallback)
	local target = creatureById(targetId, targetFallback)
	if not attacker or not target then
		return
	end
	local b = K.setBonus(element)
	local vsPlayer = isPlayerObject(target)
	if b.kind == "slow" then
		local pct, ms = K.setSlow(element, vsPlayer)
		if pct and rawget(_G, "ChaosSpell") and ChaosSpell.slow then
			ChaosSpell.slow(target, ms, pct)
		end
	elseif b.kind == "poison" then
		local tick = math.floor(dealt * b.pct * K.setScale(vsPlayer) / 100 / b.ticks + 1e-6)
		if tick >= 1 and Condition and rawget(_G, "CONDITION_POISON") then
			local c = Condition(CONDITION_POISON)
			c:setParameter(CONDITION_PARAM_OWNER, attacker:getId())
			c:setParameter(CONDITION_PARAM_DELAYED, true)
			c:addDamage(b.ticks, 1000, -tick)
			target:addCondition(c)
		end
	elseif b.kind == "leech" then
		local n = K.setLeech(element, dealt, attacker:getMaxHealth())
		if n > 0 and attacker:getHealth() > 0 then
			attacker:addHealth(n)
		end
	elseif b.kind == "heal" then
		local pid = attacker:getId()
		local now = nowMs()
		if now - (M.holyAt[pid] or -1e12) >= b.cooldownMs and attacker:getHealth() > 0 then
			local n = K.setHeal(element, attacker:getMaxHealth())
			if n > 0 then
				M.holyAt[pid] = now
				attacker:addHealth(n)
			end
		end
	end
end
M.setEffects = setEffects

-- O473: the damage part of the card set that is on, as raw percent of the additive damage pool for a hit of `combatType`
-- (damage_pool_core.lua provider "cardSets"): the set's pct for a hit of its element when its kind is damage (Fire), x the PvP
-- scale against a player; never for a damage over time tick. At most damage_pool_config.lua sources.cardSets.cap.
function M.poolRaw(attacker, creature, combatType, origin)
	local state = M.sets[attacker:getId()]
	if not state or not state.element or origin == ORIGIN_CONDITION or not combatType then
		return 0
	end
	if creature and creature.getId and creature:getId() == attacker:getId() then
		return 0
	end
	local element = elementOfType(combatType)
	if not element or not setOn(state, element) then
		return 0
	end
	local b = K.setBonus(element)
	if not b or b.kind ~= "damage" then
		return 0
	end
	return b.pct * K.setScale(creature and isPlayerObject(creature))
end
if not ChaosDamagePool then
	dofile("data/scripts/chaos/damage_pool_core.lua")
end
ChaosDamagePool.register("cardSets", function(hit, combatType)
	return M.poolRaw(hit.attacker, hit.creature, combatType, hit.origin)
end, function(player, combatType)
	return M.poolRaw(player, nil, combatType, nil)
end)

-- (pd, pt, sd, st) after the set effects of the player who deals the hit: the effects that follow the hit (Energy slow, Earth
-- poison, Death leech, Holy heal); the Fire set's damage part is in the damage pool (M.poolRaw). A hit of another element, a
-- player without a set and a damage over time tick are untouched (the event never calls this for a tick).
function M.applySet(attacker, creature, pd, pt, sd, st)
	local state = M.sets[attacker:getId()]
	if not state or not state.element or creature:getId() == attacker:getId() then
		return pd, pt, sd, st
	end
	local dealt = 0
	local effect
	for _, part in ipairs({{"pd", pd, pt}, {"sd", sd, st}}) do
		local element = part[3] and elementOfType(part[3])
		if element and part[2] and part[2] < 0 and setOn(state, element) then
			-- O473: the damage part of a set (Fire: more damage) is a raw percent of the additive damage pool now (M.poolRaw below,
			-- asked by ChaosPassiveDealt); here only the effects that follow the hit
			dealt = dealt + math.abs(part[2])
			effect = element
		end
	end
	if effect and dealt > 0 then
		local kind = K.setBonus(effect).kind
		if kind ~= "damage" then
			later(setEffects, attacker:getId(), creature:getId(), effect, dealt, attacker, creature)
		end
	end
	return pd, pt, sd, st
end

-- tell the player when the set changed (a card went on or off)
local function announceSet(player, before, after)
	local text = K.setMessage(langOf(player), before, after)
	if text then
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	end
end

-- ---------------------------------------------------------------- the window (client game_carddeck, opcode 172)
local OPCODE = ChaosOpcodes.cardDeck
local lastSent = {} -- player id -> the key of the state the client was last told

-- the id the client draws for an item (the item type's client id; the server id when it is unknown)
local function clientIdOf(id)
	local ok, cid = pcall(function() return ItemType(id):getClientId() end)
	return ok and tonumber(cid) and cid > 0 and cid or id
end

local function stateView(player, plan)
	local className = K.classNameOf(vocationId(player))
	local lang = langOf(player)
	local state = M.sets[player:getId()]
	local unlocked = Deck.unlocked(player)
	local hint = ""
	if not unlocked then
		hint = Chaos.t(player, K.TEXT.locked, Deck.stepTitle(langOf(player)))
	end
	return {unlocked = unlocked, owned = function(id) return Deck.owned(player, id) end,
		fresh = function(id) return Deck.isFresh(player, id) end, plan = plan, className = className,
		setLine = className and K.setLine(lang, state) or "", questHint = hint}
end

-- the live state: copies, new marks, cards on, the set line. Only when it changed since the last message (or force). true when sent.
function M.push(player, plan, force)
	plan = plan or Deck.plan(player)
	M.refreshSet(player, plan)
	local payload = K.statePayload(stateView(player, plan))
	local parts = {K.stateKey(payload.on), tostring(payload.copies), tostring(payload.distinct), #payload.new, tostring(payload.unlocked),
		payload.set}
	for _, id in ipairs(payload.new) do
		parts[#parts + 1] = id
	end
	local key = table.concat(parts, "|")
	local pid = player:getId()
	if not force and lastSent[pid] == key then
		return false
	end
	lastSent[pid] = key
	local ok, err = pcall(Chaos.send, player, OPCODE, "state", payload)
	if not ok then
		log("card state " .. tostring(player:getName()) .. ": " .. tostring(err))
	end
	return ok
end

-- the static list of the 76 cards (names, rarity, text in the player's language), once per sync
function M.pushCards(player)
	local ok, err = pcall(Chaos.send, player, OPCODE, "cards", K.cardsPayload(langOf(player), nameOf, clientIdOf))
	if not ok then
		log("card list " .. tostring(player:getName()) .. ": " .. tostring(err))
	end
	return ok
end

local function sound(player)
	if playSound then
		pcall(playSound, player, "deck_card.ogg")
	end
end

local function turnOn(player, id)
	local c = C.cards[id]
	player:setStorageValue(c.storage, 1)
	if c.legendary then
		local flag = C.legendaryFlagBase + (id - C.legendaryFlagFrom)
		local v = player:getStorageValue(flag)
		if v == 0 or v == -1 then
			player:setStorageValue(flag, 1)
		end
	end
end

-- the toast "New card: NAME" of game_chaosnotify (server notifications.lua, kind newcard)
local function toastNew(player, id)
	local N = rawget(_G, "ChaosNotify")
	if N and N.send then
		pcall(N.send, player, Chaos.t(player, "New card"), nameOf(id), "newcard")
	end
end

-- Takes the listed cards and decks into the Deck: one copy per card item (its stack), the item is removed. A deck item is
-- emptied (its cards go in, anything else it holds goes to the bag it sat in) and removed; a character that held one gets the
-- Deck open when cfg.grandfather. Returns the number of cards taken in and the new card ids.
local function takeIn(player, cards, decks)
	local taken, newIds, foundDecks = 0, {}, 0
	local function absorbItem(entry)
		local n = 1
		local okC, count = pcall(function() return entry.item:getCount() end)
		if okC and tonumber(count) and count > 1 then
			n = count
		end
		local okR = pcall(function() return entry.item:remove() end)
		if okR then
			if Deck.add(player, entry.id, n) then
				newIds[#newIds + 1] = entry.id
			end
			taken = taken + n
		end
	end
	for _, entry in ipairs(cards) do
		absorbItem(entry)
	end
	for _, deck in ipairs(decks) do
		local okKids, kids = pcall(function() return deck.item:getItems() or {} end)
		local clear = true
		if okKids then
			for _, kid in ipairs(kids) do
				if K.isCard(kid:getId()) then
					-- a card inside a deck that was not in `cards` (the walk reaches it, so this is a guard)
					absorbItem({item = kid, id = kid:getId()})
				else
					local dest = deck.parent or player:getSlotItem(CONST_SLOT_BACKPACK)
					local okM, moved = pcall(function() return kid:moveTo(dest) end)
					if not (okM and moved ~= false) then
						clear = false
					end
				end
			end
		end
		if clear and pcall(function() return deck.item:remove() end) then
			foundDecks = foundDecks + 1
		end
	end
	return taken, newIds, foundDecks
end

-- tell the player what went into the Deck and show a toast for each new card
local function announceTaken(player, taken, newIds, firstId)
	if taken <= 0 then
		return
	end
	local unlocked = Deck.unlocked(player)
	if taken == 1 and firstId then
		local text = unlocked and Chaos.t(player, K.TEXT.stored, nameOf(firstId))
			or Chaos.t(player, K.TEXT.storedlocked, nameOf(firstId), Deck.stepTitle(langOf(player)))
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, K.TEXT.newcards, taken))
	end
	for i, id in ipairs(newIds) do
		if i > DK.toastMax then
			break
		end
		toastNew(player, id)
	end
	if #newIds > 0 then
		sound(player)
	end
end

-- Takes the cards the player carries (bags, inbox) into the Deck. deep = the one-time migration (also the depot chests, the store
-- inbox). Returns the number of cards taken in.
function M.absorb(player, deep, only)
	local roots = deep and deepRoots(player) or carriedRoots(player)
	local cards, decks
	if only then
		cards, decks = {{item = only, id = only:getId()}}, {}
	else
		cards, decks = collect(roots, deep and DK.migrateLimit or DK.carriedLimit)
	end
	if #cards == 0 and #decks == 0 then
		return 0
	end
	local taken, newIds, foundDecks = takeIn(player, cards, decks)
	if foundDecks > 0 then
		player:setStorageValue(DK.storage.base + DK.storage.decksFound,
			math.max(0, tonumber(player:getStorageValue(DK.storage.base + DK.storage.decksFound)) or 0) + foundDecks)
		if DK.grandfather and not Deck.unlocked(player) then
			Deck.unlock(player)
		end
	end
	if deep and (taken > 0 or foundDecks > 0) then
		local key = Deck.unlocked(player) and K.TEXT.migratedopen or K.TEXT.migrated
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, key, taken))
		for i, id in ipairs(newIds) do
			if i > DK.toastMax then
				break
			end
			toastNew(player, id)
		end
	elseif taken > 0 then
		announceTaken(player, taken, newIds, cards[1] and cards[1].id)
	end
	if taken > 0 or foundDecks > 0 then
		M.push(player, M.reconcile(player, true), true)
	end
	return taken
end

-- the base card action asks this first. true: handled; nil: not a card. A card used goes into the Deck at once.
function M.use(player, item)
	if not (player and item) then
		return nil
	end
	if not K.isCard(item:getId()) then
		return nil
	end
	M.absorb(player, false, item)
	return true
end

-- the window asks to turn a card on or off
function M.toggle(player, id)
	id = tonumber(id)
	if not (player and id and K.isCard(id)) then
		return false
	end
	local plan = M.reconcile(player, true)
	local action = K.decide({id = id, owned = Deck.owned(player, id), isOn = plan.active[id] == true,
		count = K.activeCount(plan), unlocked = Deck.unlocked(player)})
	local msg = function(key, ...)
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, key, ...))
	end
	local name = nameOf(id)
	if action == "locked" then
		msg(K.TEXT.locked, Deck.stepTitle(langOf(player)))
	elseif action == "none" then
		msg(K.TEXT.none, name)
	elseif action == "max" then
		msg(K.TEXT.max, C.maxActive)
		sound(player)
	elseif action == "off" then
		player:setStorageValue(C.cards[id].storage, 0)
		msg(K.TEXT.off, name)
		sound(player)
	elseif action == "on" then
		turnOn(player, id)
		msg(K.TEXT.on, name, K.bonusText(langOf(player), id))
		sound(player)
	end
	if action == "on" or action == "off" then
		local before = M.sets[player:getId()]
		M.push(player, M.reconcile(player, true), true)
		announceSet(player, before, M.sets[player:getId()])
	else
		M.push(player, plan, true)
	end
	return action == "on" or action == "off"
end

-- Character > Character Info: the `deck` command
ChaosCommands.register("deck", function(player)
	M.push(player, M.reconcile(player, true))
	player:sendTextMessage(MESSAGE_INFO_DESCR, K.statusText(langOf(player), {unlocked = Deck.unlocked(player),
		owned = function(id) return Deck.owned(player, id) end,
		storage = function(id) return tonumber(player:getStorageValue(C.cards[id].storage)) or -1 end,
		nameOf = nameOf, vocId = vocationId(player), stepTitle = Deck.stepTitle(langOf(player))}))
end)

-- one sweep: loose cards in, the on / off storages true, the window told
local function sweep(player, force)
	local ok, err = pcall(function()
		M.absorb(player, false)
		M.push(player, M.reconcile(player, false), force)
	end)
	if not ok then
		log("sweep " .. tostring(player:getName()) .. ": " .. tostring(err))
	end
end
M.sweep = sweep

-- the one-time move of the old decks and loose cards, depots included (marker storage; a failure leaves it unmarked: it runs again)
function M.migrate(player)
	if Deck.migrated(player) then
		return false
	end
	local ok, err = pcall(function() M.absorb(player, true) end)
	if ok then
		Deck.setMigrated(player)
	else
		log("migration " .. tostring(player:getName()) .. ": " .. tostring(err))
	end
	return ok
end

-- ---------------------------------------------------------------- legendary cards: the weapon and the summon
local KIND_OF_TYPE = {}
local function kindOfType(wt)
	if next(KIND_OF_TYPE) == nil then
		KIND_OF_TYPE[WEAPON_SWORD or 1] = "sword"
		KIND_OF_TYPE[WEAPON_CLUB or 2] = "club"
		KIND_OF_TYPE[WEAPON_AXE or 3] = "axe"
		KIND_OF_TYPE[WEAPON_DISTANCE or 5] = "distance"
		KIND_OF_TYPE[WEAPON_WAND or 6] = "wand"
	end
	return KIND_OF_TYPE[wt]
end

-- the kind of an item in a hand (cards_core.lua K.kindOf); nil for nothing, a shield, ammunition, a quiver
local function kindOfItem(item)
	if not item then
		return nil
	end
	local id = item.itemid or item:getId()
	local fist = false
	if ChaosFistWeapons == nil and not M.fistLoaded then
		M.fistLoaded = true
		pcall(dofile, "data/lib/chaos_fist_weapons.lua")
	end
	if ChaosFistWeapons and ChaosFistWeapons.items and ChaosFistWeapons.items[id] then
		fist = true
	end
	local ok, wt = pcall(function() return ItemType(id):getWeaponType() end)
	return K.kindOf(ok and kindOfType(wt) or nil, fist)
end
M.kindOfItem = kindOfItem

local function inFistLine(player)
	local ids = Chaos and Chaos.classes and Chaos.classes.ids
	local base = Chaos and Chaos.classes and Chaos.classes.baseOf
	local ok, voc = pcall(function() return player:getVocation():getId() end)
	return ok and ids ~= nil and base ~= nil and base[voc] == ids.monk
end

-- true when the left hand's weapon (any type of weapon; the stock ids too) lets the card of `class` fire
function M.holds(player, class, leftHand, stockIds)
	if leftHand and stockIds then
		local id = leftHand.itemid or leftHand:getId()
		for _, v in ipairs(stockIds) do
			if v == id then
				return true
			end
		end
	end
	local hands = {left = kindOfItem(leftHand), fistLine = inFistLine(player)}
	if player:getSlotItem(CONST_SLOT_RIGHT) then
		hands.right = kindOfItem(player:getSlotItem(CONST_SLOT_RIGHT))
	end
	return K.holds(class, hands)
end

-- the base summon lock (see the header): released when the player has no summon any more
local function releaseSummon(player)
	local D = rawget(_G, "DeckSystem")
	local key = D and D.Legendary and D.Legendary.CanCreateSummon
	if not key or player:getStorageValue(key) ~= 1 then
		return false
	end
	local ok, summons = pcall(function() return player:getSummons() end)
	if ok and type(summons) == "table" and #summons == 0 then
		player:setStorageValue(key, 0)
		return true
	end
	return false
end
M.releaseSummon = releaseSummon

-- ---------------------------------------------------------------- cards of a spell that was replaced
local ELEMENT = {
	Fire = "COMBAT_FIREDAMAGE", Earth = "COMBAT_EARTHDAMAGE", Ice = "COMBAT_ICEDAMAGE", Holy = "COMBAT_HOLYDAMAGE",
	Death = "COMBAT_DEATHDAMAGE", Energy = "COMBAT_ENERGYDAMAGE", Drown = "COMBAT_DROWNDAMAGE",
}

-- the target's resistances by combat type (monsters only; nil when unknown)
local resCache = {}
local function resistances(creature)
	if not creature or not creature:isMonster() then
		return nil
	end
	local ok, name = pcall(function() return creature:getName():lower() end)
	if not ok then
		return nil
	end
	local r = resCache[name]
	if r == nil then
		r = false
		local got, list = pcall(function()
			local t = creature:getType()
			return t and t:getElementList()
		end)
		if got and type(list) == "table" then
			r = list
		end
		resCache[name] = r
	end
	return r or nil
end

-- (pd, pt, sd, st) after the cards of `spellId` that the caster has on; the same four values when none applies
function M.applyHit(attacker, creature, spellId, pd, pt, sd, st)
	local fam = C.byTarget[spellId]
	if not fam then
		return pd, pt, sd, st
	end
	local tier = C.topTier(fam, function(key) return attacker:getStorageValue(key) end)
	if tier == 0 then
		return pd, pt, sd, st
	end
	if fam.kind == "heal" then
		if pt == COMBAT_HEALING and ChaosSupports and ChaosSupports.scale then
			return ChaosSupports.scale(pd, fam.pct[tier]), pt, ChaosSupports.scale(sd, fam.pct[tier]), st
		end
		return pd, pt, sd, st
	end
	local etype = rawget(_G, ELEMENT[fam.elements[tier]] or "")
	if fam.kind ~= "convert" or not etype or pt == COMBAT_HEALING or not ChaosSupports or not ChaosSupports.convert then
		return pd, pt, sd, st
	end
	local res = resistances(creature)
	return ChaosSupports.convert(pd, pt, sd, st, 100, etype, res and function(t) return res[t] or 0 end or nil)
end

local hit = CreatureEvent("ChaosCardsHit")
function hit.onHealthChange(creature, attacker, pd, pt, sd, st, origin)
	if not (attacker and creature) or not attacker:isPlayer() or origin == ORIGIN_CONDITION or not ChaosSupports then
		return pd, pt, sd, st
	end
	local serial, spellId = ChaosSupports.ctxDecode(attacker:getStorageValue(ChaosSupports.config.storageContext))
	if serial and C.byTarget[spellId] then
		pd, pt, sd, st = M.applyHit(attacker, creature, spellId, pd, pt, sd, st)
	end
	return M.applySet(attacker, creature, pd, pt, sd, st)
end
hit:register()

-- the event sits on the monsters a player attacks (heals: on every player, at login)
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and creature ~= target and creature:isPlayer() and target:isMonster() then
		Chaos.registerOnce(target, "ChaosCardsHit")
	end
	return RETURNVALUE_NOERROR
end
targetCb:register(1)

local login = CreatureEvent("ChaosCardsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosCardsHit")
	player:registerEvent("ChaosCardsExtended")
	player:registerEvent("ChaosCardsLogout")
	-- O570: the decks and loose cards of before the Deck of Cards move in once (marker storage), then the usual sweep
	M.migrate(player)
	sweep(player, true)
	-- the summon of an earlier session is gone (its timer died with the server or the logout)
	local D = rawget(_G, "DeckSystem")
	if D and D.Legendary and D.Legendary.CanCreateSummon then
		player:setStorageValue(D.Legendary.CanCreateSummon, 0)
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosCardsLogout")
function logout.onLogout(player)
	lastSent[player:getId()] = nil
	M.sets[player:getId()] = nil
	M.holyAt[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

-- the window talks to the server: sync (the list and the state), toggle {id}, seen {ids} or {all = true}
local ext = CreatureEvent("ChaosCardsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if type(msg) ~= "table" then
		return
	end
	local action = msg.action
	if action == "sync" then
		if Chaos.limited and Chaos.limited(player, "cards.sync", 500) then
			return
		end
		M.pushCards(player)
		sweep(player, true)
	elseif action == "toggle" then
		if Chaos.limited and Chaos.limited(player, "cards.toggle", 250) then
			return
		end
		M.toggle(player, msg.id)
	elseif action == "open" then
		-- the window was opened: the main quest step "deck" is done by it (the flag is the quest's), then the state is sent again
		-- a moment later in case the step opened the Deck
		local MQ = rawget(_G, "ChaosMainQuest")
		if MQ and MQ.emit then
			pcall(MQ.emit, player, "deck")
		end
		later(function(pid)
			local p = creatureById(pid, player)
			if p then
				M.push(p, nil, false)
			end
		end, player:getId())
	elseif action == "seen" then
		if Chaos.limited and Chaos.limited(player, "cards.seen", 250) then
			return
		end
		local ids
		if type(msg.ids) == "table" then
			ids = {}
			for _, id in ipairs(msg.ids) do
				id = tonumber(id)
				if id and K.isCard(id) and #ids < 100 then
					ids[#ids + 1] = id
				end
			end
		end
		if ids or msg.all then
			if Deck.markSeen(player, ids) > 0 then
				M.push(player, nil, true)
			end
		end
	end
end
ext:type("extendedopcode")
ext:register()

-- a card or an old deck that lands in a bag is taken in a moment later (the engine moves it first)
local movedCb = EventCallback
movedCb.onItemMoved = function(player, item, count, fromPosition, toPosition)
	if player and item and player.isPlayer and player:isPlayer() then
		local ok, id = pcall(function() return item:getId() end)
		if ok and (K.isCard(id) or K.isRetiredDeck(id)) then
			later(function(pid)
				local p = creatureById(pid, player)
				if p then
					sweep(p, false)
				end
			end, player:getId())
		end
	end
end
movedCb:register(14)

local summonThink = GlobalEvent("ChaosCardsSummonRelease")
function summonThink.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		pcall(releaseSummon, player)
	end
	return true
end
summonThink:interval(C.summonReleaseMs)
summonThink:register()

local think = GlobalEvent("ChaosCardsReconcile")
function think.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		sweep(player)
	end
	return true
end
think:interval(C.reconcileMs)
think:register()

-- cards that reach a bag without a move (a reward, auto loot) are taken in at most absorbMs later
local absorbThink = GlobalEvent("ChaosCardsAbsorb")
function absorbThink.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		local ok, err = pcall(M.absorb, player, false)
		if not ok then
			log("absorb " .. tostring(player:getName()) .. ": " .. tostring(err))
		end
	end
	return true
end
absorbThink:interval(DK.absorbMs)
absorbThink:register()
