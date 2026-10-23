-- cards.lua: the cards and decks in the game (rules: cards_core.lua, numbers: cards_config.lua; server/README.md "Cards and
-- decks"). The glue the base deck system calls after tools/patch_badges.py:
--   ChaosCards.use(player, item)   the base card action asks this first: a card carried anywhere in the bags (any depth,
--        closed bags too) goes into a carried deck with room and turns on; used again it turns off. Returns true when the
--        card is handled (always, for a card), nil for anything else so the base code runs.
--   ChaosCommands "deck"           Character > Character Info: every card on and off with what it gives, the deck
--        capacity used and total, and how to get a deck when none is carried (replaces the base !deck dialog)
--   login and every cfg.reconcileMs   a card that is on but left the decks (dropped on death, a bag put away) is turned off,
--        and a stray action id goes, so nothing stays on without its card and nothing stays stuck
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
-- No opcode, no storage key of its own: the base's card storages (37000-37059, 37065-37080) and action id 37866.
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

ChaosCards = ChaosCards or {}
local M = ChaosCards
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

-- the slots a player carries bags in: 1-10 and the badge slot 13 (a badge may be the Eternal Moon bag); 12 held the deck
-- before the slot was retired. Never 11 (the store inbox).
local SLOTS = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13}

-- the carried decks (biggest first) and cards outside a deck, in every bag at any depth
function M.scan(player)
	local decks, loose, seen = {}, {}, 0
	local function handle(item, deck, depth)
		if not item or seen >= C.scanLimit then
			return
		end
		seen = seen + 1
		local id = item:getId()
		if K.isCard(id) then
			local entry = {id = id, aid = item:getActionId() == C.activeActionId, ref = item}
			local list = deck and deck.cards or loose
			list[#list + 1] = entry
		elseif K.isDeck(id) and not deck and item:isContainer() then
			local d = {id = id, item = item, used = item:getSize(), size = K.deckInfo[id].size, cards = {}}
			decks[#decks + 1] = d
			for i = 0, item:getSize() - 1 do
				handle(item:getItem(i), d, depth + 1)
			end
		elseif not deck and depth < 10 and item:isContainer() then
			for i = 0, item:getSize() - 1 do
				handle(item:getItem(i), nil, depth + 1)
			end
		end
	end
	for _, slot in ipairs(SLOTS) do
		handle(player:getSlotItem(slot), nil, 0)
	end
	table.sort(decks, function(a, b)
		if a.size ~= b.size then
			return a.size > b.size
		end
		return a.used < b.used
	end)
	return {decks = decks, loose = loose, nameOf = nameOf,
		storage = function(id) return player:getStorageValue(C.cards[id].storage) end}
end

-- repair what disagrees (K.reconcile); returns the plan
function M.reconcile(player, st, quiet)
	local plan = K.reconcile(st.decks, st.loose, st.storage)
	for _, id in ipairs(plan.off) do
		player:setStorageValue(C.cards[id].storage, 0)
		if not quiet then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, K.TEXT.lostoff, nameOf(id)))
		end
		log(player:getName() .. ": card " .. id .. " is no longer in a carried deck: turned off")
	end
	for _, card in ipairs(plan.clear) do
		card.ref:setActionId(0)
	end
	return plan
end

local function sound(player)
	if playSound then
		pcall(playSound, player, "deck_card.ogg")
	end
end

local function turnOn(player, id, ref)
	local c = C.cards[id]
	player:setStorageValue(c.storage, 1)
	ref:setActionId(C.activeActionId)
	if c.legendary then
		local flag = C.legendaryFlagBase + (id - C.legendaryFlagFrom)
		local v = player:getStorageValue(flag)
		if v == 0 or v == -1 then
			player:setStorageValue(flag, 1)
		end
	end
end

-- the base card action asks this first. true: handled; nil: not a card.
function M.use(player, item)
	if not (player and item) then
		return nil
	end
	local id = item:getId()
	if not K.isCard(id) then
		return nil
	end
	local msg = function(key, ...)
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, key, ...))
	end
	local st = M.scan(player)
	local plan = M.reconcile(player, st, false)
	-- the copy that was used, in a deck or loose
	local found, inDeck
	for _, d in ipairs(st.decks) do
		for _, card in ipairs(d.cards) do
			if card.ref == item then
				found, inDeck = card, true
			end
		end
	end
	for _, card in ipairs(st.loose) do
		if card.ref == item then
			found = card
		end
	end
	if not found then
		msg(K.TEXT.notcarried)
		return true
	end
	local decksForUse = {}
	for _, d in ipairs(st.decks) do
		decksForUse[#decksForUse + 1] = {used = d.used, size = d.size}
	end
	local action, index = K.decide({id = id, inDeck = inDeck, isOn = plan.active[id] == found,
		storageOn = plan.active[id] ~= nil, count = K.activeCount(plan), decks = decksForUse})
	local name = item:getName()
	if action == "off" then
		player:setStorageValue(C.cards[id].storage, 0)
		item:setActionId(0)
		msg(K.TEXT.off, name)
		sound(player)
	elseif action == "dupe" then
		msg(K.TEXT.dupe, name)
	elseif action == "max" then
		msg(K.TEXT.max, C.maxActive)
		sound(player)
	elseif action == "nodeck" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, K.noDeckText(langOf(player)))
	elseif action == "full" then
		msg(K.TEXT.full, C.seller)
	elseif action == "on" or action == "move" then
		if action == "move" then
			local deck = st.decks[index]
			local ok, moved = pcall(function() return item:moveTo(deck.item) end)
			if not (ok and moved) then
				msg(K.TEXT.failed)
				return true
			end
			msg(K.TEXT.moved, name, deck.item:getName())
		end
		turnOn(player, id, item)
		msg(K.TEXT.on, name, K.bonusText(langOf(player), id))
		sound(player)
	end
	return true
end

-- Character > Character Info: the `deck` command
ChaosCommands.register("deck", function(player)
	local st = M.scan(player)
	M.reconcile(player, st, true)
	st.sellers = nil
	player:sendTextMessage(MESSAGE_INFO_DESCR, K.statusText(langOf(player), st))
end)

local function sweep(player)
	local ok, err = pcall(function()
		M.reconcile(player, M.scan(player), false)
	end)
	if not ok then
		log("reconcile " .. tostring(player:getName()) .. ": " .. tostring(err))
	end
end
M.sweep = sweep

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
	if not serial or not C.byTarget[spellId] then
		return pd, pt, sd, st
	end
	return M.applyHit(attacker, creature, spellId, pd, pt, sd, st)
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
	sweep(player)
	-- the summon of an earlier session is gone (its timer died with the server or the logout)
	local D = rawget(_G, "DeckSystem")
	if D and D.Legendary and D.Legendary.CanCreateSummon then
		player:setStorageValue(D.Legendary.CanCreateSummon, 0)
	end
	return true
end
login:type("login")
login:register()

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
