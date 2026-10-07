-- game_autoloot (extended opcode 216)
--
-- Client contract (client/overlay/modules/game_autoloot/loot.lua):
--   client -> server  {"action":"open"}                     (no data)
--   client -> server  talk "!autoloot add, <item name>"
--                     talk "!autolootclient add, <numeric CLIENT item id>"
--                     talk "!autoloot remove, <item name>"
--                     talk "!autoloot clear"
--   server -> client  {"action":"open","data":{"itemsTable":[[clientId,"name"],...],
--                                              "currentSlot":N,"maxSlot":M}}
--
-- The list lives in the same player storages (base 80000) as the reference server's
-- scripts/creaturescripts/autoloot.lua, so that script's onDropLoot callback keeps doing the
-- actual looting. This file only adds the window protocol and the two talkactions.
--
-- NOTE: if the reference data/talkactions/talkactions.xml already registers "!autoloot",
-- TFS 1.4.2 silently keeps the XML one and ignores the one below (see README). The window then
-- still works but does not refresh after add/remove until it is reopened.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

local OPCODE = ChaosOpcodes.autoloot
local BASE = Chaos.storage.autolootBase
local cfg = Chaos.autoloot
local MAX_SLOTS = math.max(cfg.freeLimit, cfg.premiumLimit)

local clientToServerId -- built lazily, see resolveClientId

local function getLimit(player)
	return player:isPremium() and cfg.premiumLimit or cfg.freeLimit
end

local function readList(player)
	local items = {}
	for i = 1, MAX_SLOTS do
		local value = player:getStorageValue(BASE + i)
		if value and value > 0 then
			local itemType = ItemType(value)
			if itemType and itemType:getId() ~= 0 then
				items[#items + 1] = itemType:getId()
			end
		end
	end
	return items
end

local function writeList(player, items)
	for i = 1, MAX_SLOTS do
		player:setStorageValue(BASE + i, items[i] or -1)
	end
end

local function sendList(player)
	local items = readList(player)
	local limit = getLimit(player)
	-- Anything past the current limit (premium expired) is ignored by the reference callback;
	-- show the effective list only.
	local rows = {}
	for i = 1, math.min(#items, limit) do
		local itemType = ItemType(items[i])
		rows[#rows + 1] = {itemType:getClientId(), itemType:getName()}
	end
	Chaos.send(player, OPCODE, "open", {itemsTable = rows, currentSlot = #rows, maxSlot = limit})
end

local function resolveClientId(clientId)
	if not clientToServerId then
		clientToServerId = {}
		for id = 100, 100000 do
			local itemType = ItemType(id)
			if itemType:getId() ~= 0 then
				local cid = itemType:getClientId()
				if cid and cid ~= 0 and not clientToServerId[cid] then
					clientToServerId[cid] = id
				end
			end
		end
	end
	return clientToServerId[clientId]
end

-- text: item name (byClient=false) or numeric client id (byClient=true)
local function lookupItem(text, byClient)
	if byClient then
		local clientId = tonumber(text)
		local serverId = clientId and resolveClientId(clientId)
		return serverId and ItemType(serverId) or nil
	end
	local itemType = ItemType(text)
	if itemType and itemType:getId() ~= 0 then
		return itemType
	end
	local numeric = tonumber(text)
	if numeric then
		itemType = ItemType(numeric)
		if itemType and itemType:getId() ~= 0 then
			return itemType
		end
	end
	return nil
end

local function handleCommand(player, param, byClient)
	local action, argument = param:match("^%s*([^,]*)%s*,?%s*(.-)%s*$")
	action = (action or ""):lower():gsub("%s+", "")

	if action == "clear" then
		writeList(player, {})
		player:sendCancelMessage("Autoloot list cleaned.")
	elseif action == "add" or action == "remove" then
		local itemType = lookupItem(argument, byClient)
		if not itemType then
			player:sendCancelMessage(string.format("The item %s does not exist!", argument))
			sendList(player)
			return
		end
		local items = readList(player)
		local index
		for i, id in ipairs(items) do
			if id == itemType:getId() then
				index = i
				break
			end
		end
		if action == "add" then
			if index then
				player:sendCancelMessage(string.format("The item %s already exists!", itemType:getName()))
			elseif #items >= getLimit(player) then
				player:sendCancelMessage(string.format("Your auto loot only allows you to add %d items.", getLimit(player)))
			else
				items[#items + 1] = itemType:getId()
				writeList(player, items)
				player:sendCancelMessage(string.format("Perfect you have added to the list: %s", itemType:getName()))
			end
		else
			if index then
				table.remove(items, index)
				writeList(player, items)
				player:sendCancelMessage(string.format("Perfect, you have removed from the list: %s", itemType:getName()))
			else
				player:sendCancelMessage(string.format("The item %s does not exist in the list.", itemType:getName()))
			end
		end
	elseif action ~= "show" and action ~= "" then
		player:sendCancelMessage("Use: !autoloot add, <name> | remove, <name> | clear. Or use the Autoloot window.")
	end
	sendList(player)
end

local LoginEvent = CreatureEvent("ChaosAutolootLogin")

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosAutolootExtended")
	return true
end

local ExtendedEvent = CreatureEvent("ChaosAutolootExtended")

function ExtendedEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if msg and msg.action == "open" then
		sendList(player)
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()

local nameTalk = TalkAction("!autoloot")

function nameTalk.onSay(player, words, param)
	handleCommand(player, param or "", false)
	return false
end

nameTalk:register()

local clientTalk = TalkAction("!autolootclient")

function clientTalk.onSay(player, words, param)
	handleCommand(player, param or "", true)
	return false
end

clientTalk:register()
