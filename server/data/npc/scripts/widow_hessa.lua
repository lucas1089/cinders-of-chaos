-- Widow Hessa, the candy trader of the Haunted Harvest (server/data/scripts/chaos/harvest_event.lua; her trades are
-- harvest_event_config.lua `shop`; server/README.md "Haunted Harvest"). Runs in the NPC's own Lua state: "trade" lists
-- the offers, "buy <number or name>" takes the hollow candy and gives the items (the rest to the inbox when the
-- backpack is full: player:addItem drops nothing). The checks are harvest_event_core.lua K.trade, the same as the tests.
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
-- only the nearest NPC answers a greeting (data/lib/chaos_npc_focus.lua)
if not ChaosNpcFocus then pcall(dofile, "data/lib/chaos_npc_focus.lua") end
function onCreatureSay(cid, type, msg)
	if not ChaosNpcFocus or ChaosNpcFocus.hears(cid, npcHandler) then
		npcHandler:onCreatureSay(cid, type, msg)
	end
end
function onThink()				npcHandler:onThink()					end

local cfg = dofile("data/scripts/chaos/harvest_event_config.lua")
if not ChaosHarvestCore then
	dofile("data/scripts/chaos/harvest_event_core.lua")
end
local K = ChaosHarvestCore

-- the player's language (the stored one: this state never sees the client's hello; i18n_core.lua "NPC scripts")
if not ChaosI18n or not ChaosI18n.npcText then
	dofile("data/scripts/chaos/i18n_core.lua")
end
local function t(cid, key, ...)
	return ChaosI18n.npcText(cid, key, ...)
end

local function has(text, ...)
	for _, w in ipairs({...}) do
		if text:find(w, 1, true) then
			return true
		end
	end
	return false
end

local function offers(cid)
	local parts = {}
	for i, o in ipairs(cfg.shop) do
		parts[#parts + 1] = string.format("%d) %s: %d", i, o.name, o.price)
	end
	return t(cid, "Hollow candy buys: %s. Say {buy} and the number.", table.concat(parts, "; "))
end

local function buy(cid, player, what)
	local candy = player:getItemCount(cfg.items.candy)
	local o, why = K.trade(cfg, what, candy)
	if not o then
		if why == "candy" then
			local need = K.offer(cfg, what)
			return t(cid, "That costs %d hollow candy; you carry %d.", need and need.price or 0, candy)
		end
		return t(cid, "I have no such thing. Ask me to {trade}.")
	end
	if not player:removeItem(cfg.items.candy, o.price) then
		return t(cid, "That costs %d hollow candy; you carry %d.", o.price, candy)
	end
	for _, it in ipairs(o.items) do
		player:addItem(it[1], it[2])
	end
	return t(cid, "A fair trade: %s for %d hollow candy.", o.name, o.price)
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	if not player then
		return false
	end
	local text = msg:lower()
	local what = text:match("buy%s+(.+)$")
	if what then
		npcHandler:say(buy(cid, player, what:gsub("^%s+", ""):gsub("%s+$", "")), cid)
		return true
	elseif has(text, "trade", "offer", "ware", "shop", "buy", "candy") then
		npcHandler:say(offers(cid), cid)
		return true
	elseif has(text, "harvest", "village", "curse", "king") then
		npcHandler:say(t(cid, "The harvest moon woke the dead of this village. Pick the pumpkins, dig the graves, and find the sexton's key: the crypt under the chapel leads to the Hollow King."), cid)
		return true
	elseif has(text, "job", "name", "who") then
		npcHandler:say(t(cid, "Hessa. I buried my husband in that graveyard. Twice. Bring me hollow candy and I will {trade}."), cid)
		return true
	end
	return false
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
ChaosI18n.npcMessages(npcHandler) -- the XML's greet / farewell / walk away lines in the player's language
npcHandler:addModule(FocusModule:new())
