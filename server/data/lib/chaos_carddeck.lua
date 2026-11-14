-- The Deck of Cards, engine helpers with no event registration (O570, server/README.md "Deck of Cards (O570)"): the copies a
-- character owns, the "new" marks and the unlock, in the player storages of cards_config.lua `deck`. Loaded by
-- data/scripts/chaos/cards.lua and by any NPC script that needs it (another Lua state, so it cannot see revscript globals).
-- Rules: data/scripts/chaos/cards_core.lua; numbers: cards_config.lua. Lua 5.1 / LuaJIT and 5.3.

if not ChaosCardsCore or not ChaosCardsCore.cardIds then
	dofile("data/scripts/chaos/cards_core.lua")
end

if not ChaosMQGate then
	pcall(dofile, "data/lib/chaos_mqgate.lua")
end

ChaosCardDeck = ChaosCardDeck or {}
local D = ChaosCardDeck
local K = ChaosCardsCore
local C = K.config
local ST = C.deck.storage

local function get(player, key)
	local v = tonumber(player:getStorageValue(key))
	if not v or v < 0 then
		return 0
	end
	return v
end

-- copies of a card in the Deck
function D.owned(player, id)
	local key = K.countKey(id)
	return key and get(player, key) or 0
end

function D.setOwned(player, id, n)
	local key = K.countKey(id)
	if key then
		player:setStorageValue(key, K.addCopies(0, n))
	end
end

-- puts n copies into the Deck. Returns true when the card is new to the character (the first copy): it is marked "new".
function D.add(player, id, n)
	local key = K.countKey(id)
	if not key then
		return false
	end
	local before = get(player, key)
	player:setStorageValue(key, K.addCopies(before, n or 1))
	if before == 0 then
		player:setStorageValue(K.freshKey(id), 1)
		return true
	end
	return false
end

function D.isFresh(player, id)
	local key = K.freshKey(id)
	return key ~= nil and get(player, key) == 1 and D.owned(player, id) > 0
end

-- how many owned cards carry the "new" mark (the hub badge)
function D.freshCount(player)
	local n = 0
	for _, id in ipairs(K.cardIds()) do
		if D.isFresh(player, id) then
			n = n + 1
		end
	end
	return n
end

-- the window showed these cards (a list of ids, or nil for all): the mark goes. Returns how many marks were cleared.
function D.markSeen(player, ids)
	local n = 0
	for _, id in ipairs(ids or K.cardIds()) do
		local key = K.freshKey(id)
		if key and get(player, key) == 1 then
			player:setStorageValue(key, 0)
			n = n + 1
		end
	end
	return n
end

-- how many different cards the Deck holds, and the copies in all
function D.totals(player)
	local distinct, copies = 0, 0
	for _, id in ipairs(K.cardIds()) do
		local n = D.owned(player, id)
		if n > 0 then
			distinct, copies = distinct + 1, copies + n
		end
	end
	return distinct, copies
end

-- open: the character is past the main quest step (data/lib/chaos_mqgate.lua) or held an old deck (the stored mark)
function D.unlocked(player)
	if get(player, ST.base + ST.unlocked) == 1 then
		return true
	end
	return ChaosMQGate ~= nil and ChaosMQGate.passed(player, C.deck.unlock.step) == true
end

-- the stored mark (a character that held an old deck)
function D.unlock(player)
	player:setStorageValue(ST.base + ST.unlocked, 1)
end

-- the title of the step that opens the Deck, in the player's language
function D.stepTitle(lang)
	return ChaosMQGate and ChaosMQGate.title(C.deck.unlock.step, lang) or C.deck.unlock.step
end

function D.migrated(player)
	return get(player, ST.base + ST.migrated) >= C.deck.migrationVersion
end

function D.setMigrated(player)
	player:setStorageValue(ST.base + ST.migrated, C.deck.migrationVersion)
end

-- the reconcile plan (K.reconcile) of the player's storages
function D.plan(player)
	return K.reconcile(function(id) return D.owned(player, id) end,
		function(id) return tonumber(player:getStorageValue(C.cards[id].storage)) or -1 end, D.unlocked(player))
end

return D
