-- The base's extra slots (server/README.md "Badge slot"): the glue the base scripts call after tools/patch_badges.py.
--   Player:onMoveItem (data/events/scripts/player.lua)  ChaosBadges.onMoveItem(player, item, toPosition): refuses a
--        move into a retired slot (12, 14, 15, 16) and a deck, ship, belt or gloves into the badge slot (13)
--   the base deck system (deck_system.lua)  ChaosBadges.deckOf(player): the deck the cards are looked for in
--   the base sea tiles (boat_navigation.lua)  ChaosBadges.boardShip(player): the ship storages from what is carried
--   login: a worn item of a retired slot (or a deck in slot 13) goes to the store inbox ("Purse"), else the depot
--        inbox (ChaosPrizes.toInbox; no client shows those slots); never deleted; the trainer portals of the ships
--        carried open
-- Rules: badges_core.lua (tests/badges_test.lua). Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosBadgesCore or not ChaosBadgesCore.loginMoves then
	dofile("data/scripts/chaos/badges_core.lua")
end

ChaosBadges = ChaosBadges or {}
local B = ChaosBadges
local K = ChaosBadgesCore

local function log(msg)
	print("[ChaosBadges] " .. msg)
end

local function langOf(player)
	return Chaos.lang and Chaos.lang(player) or nil
end

-- RETURNVALUE_NOTPOSSIBLE for a move into a retired slot, nil for every other move
function B.onMoveItem(player, item, toPosition)
	local id = item and item:getId()
	if not (id and K.refusesMove(id, toPosition)) then
		return nil
	end
	if player then
		player:sendTextMessage(MESSAGE_INFO_DESCR, K.equipText(langOf(player), id))
	end
	return RETURNVALUE_NOTPOSSIBLE
end

-- the deck the base deck system reads the cards from: one worn in slot 12 from before, else the largest deck the
-- player carries (the backpack and the containers in it)
function B.deckOf(player)
	local worn = player:getSlotItem(CONST_SLOT_DECK or 12)
	if worn and worn:isContainer() then
		return worn
	end
	for _, id in ipairs(K.DECKS) do
		local ok, deck = pcall(function() return player:getItemById(id, true) end)
		if ok and deck and deck:isContainer() then
			return deck
		end
	end
	return nil
end

-- the ship storages from the ships the player carries (the sea tiles' step-in reads them right after)
function B.boardShip(player)
	local carried, current = {}, {}
	for id, s in pairs(K.SHIPS) do
		if player:getItemCount(id) > 0 then
			carried[id] = true
		end
		current[s.unlock] = player:getStorageValue(s.unlock)
	end
	for key, value in pairs(K.shipStorages(carried, current)) do
		if player:getStorageValue(key) ~= value then
			player:setStorageValue(key, value)
		end
	end
	return next(carried) ~= nil
end

-- into the store inbox, else the depot inbox; never merged into a stack (prizes.lua)
local function stow(player, item)
	if not (ChaosPrizes and ChaosPrizes.toInbox) then
		dofile("data/scripts/chaos/prizes.lua")
	end
	return ChaosPrizes.toInbox(player, item)
end

-- the login move: returns the number of items moved. In memory, then saved at once; a crash before the save leaves the
-- old state and the next login moves it again. Nothing to move: nothing changes (idempotent without a mark). An item
-- that fits nowhere stays where it is (logged) and is tried again at the next login; nothing is deleted.
function B.checkSlots(player)
	local worn, items = {}, {}
	for slot = 12, 16 do
		local item = player:getSlotItem(slot)
		if item then
			worn[slot], items[slot] = item:getId(), item
		end
	end
	-- the base's one-badge storage without its badge worn: cleared, else no badge could be put on again
	local nowWorn = player:getSlotItem(K.BADGE_SLOT)
	local stored = player:getStorageValue(K.BASE_BADGE_STORAGE)
	if K.staleBadgeStorage(stored, nowWorn and nowWorn:getId()) then
		player:setStorageValue(K.BASE_BADGE_STORAGE, -1)
		log(player:getName() .. ": cleared the stale badge storage " .. tostring(stored))
	end
	local moved, lines = 0, {}
	for _, slot in ipairs(K.loginMoves(worn)) do
		local item = items[slot]
		local name = item:getName()
		local where = stow(player, item)
		if where then
			moved = moved + 1
			lines[#lines + 1] = name .. " -> " .. (where == "inbox" and "your inbox" or "your Purse")
		else
			log(player:getName() .. ": could not move " .. name .. " out of slot " .. slot)
		end
	end
	if moved > 0 then
		if Chaos.saveCharacter and not Chaos.saveCharacter(player) then
			log(player:getName() .. ": the save after the slot check failed; the logout save keeps it")
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, K.movedText(langOf(player), table.concat(lines, ", ")))
	end
	return moved
end

local login = CreatureEvent("ChaosBadgesLogin")
function login.onLogin(player)
	local ok, err = pcall(B.checkSlots, player)
	if not ok then
		log("slot check of " .. player:getName() .. " failed: " .. tostring(err))
	end
	local okS, errS = pcall(B.boardShip, player)
	if not okS then
		log("ship storages of " .. player:getName() .. " failed: " .. tostring(errS))
	end
	return true
end
login:register()

return B
