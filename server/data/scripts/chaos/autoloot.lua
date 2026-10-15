-- game_autoloot (extended opcode 216)
--
-- Client contract (client/overlay/modules/game_autoloot/loot.lua):
--   client -> server  {"action":"open"}                     (no data)
--   client -> server  {"action":"add","data":{"name":"<item name>"}} or {"action":"add","data":{"clientId":N}}
--                     {"action":"remove","data":{"name":"<item name>"}}
--                     {"action":"clear"}
--   server -> client  {"action":"open","data":{"itemsTable":[[clientId,"name"],...],
--                                              "currentSlot":N,"maxSlot":M}}
--
-- The list lives in the same player storages (base 80000) as the reference server's
-- scripts/creaturescripts/autoloot.lua, so that script's onDropLoot callback keeps doing the
-- actual looting. This file only adds the window protocol (Hunt -> Auto Loot in the menu). The reference server's
-- spoken "!autoloot" (talkactions.xml) is commented out by server/tools/install_commands.py.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end

local OPCODE = ChaosOpcodes.autoloot
local BASE = Chaos.storage.autolootBase
local cfg = Chaos.autoloot
local MAX_SLOTS = math.max(cfg.freeLimit, cfg.premiumLimit)

local clientToServerId -- built lazily, see resolveClientId

-- >>> Chaos Pact loot rules (pact.lua, pact_config.lua limits.lootRules): free / Chaos Pact (or premium); rules past
-- the limit stay stored and come back when the Pact is renewed
local function getLimit(player)
	if ChaosPact and ChaosPact.limit then
		return math.min(MAX_SLOTS, ChaosPact.limit(player, "lootRules"))
	end
	return player:isPremium() and cfg.premiumLimit or cfg.freeLimit
end
if Chaos.pactConfig then
	local l = Chaos.pactConfig.limits.lootRules
	MAX_SLOTS = math.max(MAX_SLOTS, l.free + l.pact + l.maxExtra)
end
-- <<< Chaos Pact loot rules

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
		player:sendCancelMessage(Chaos.t(player, "Autoloot list cleaned."))
	elseif action == "add" or action == "remove" then
		local itemType = lookupItem(argument, byClient)
		if not itemType then
			player:sendCancelMessage(Chaos.t(player, "The item %s does not exist!", argument))
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
				player:sendCancelMessage(Chaos.t(player, "The item %s already exists!", itemType:getName()))
			elseif #items >= getLimit(player) then
				player:sendCancelMessage(Chaos.t(player, "Your auto loot only allows you to add %d items.", getLimit(player)))
			else
				items[#items + 1] = itemType:getId()
				writeList(player, items)
				player:sendCancelMessage(Chaos.t(player, "Perfect you have added to the list: %s", itemType:getName()))
			end
		else
			if index then
				table.remove(items, index)
				writeList(player, items)
				player:sendCancelMessage(Chaos.t(player, "Perfect, you have removed from the list: %s", itemType:getName()))
			else
				player:sendCancelMessage(Chaos.t(player, "The item %s does not exist in the list.", itemType:getName()))
			end
		end
	elseif action ~= "show" and action ~= "" then
		player:sendCancelMessage(Chaos.t(player, "Unknown auto loot action."))
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
	if not msg then
		return
	end
	if msg.action == "open" then
		sendList(player)
	elseif msg.action == "add" or msg.action == "remove" or msg.action == "clear" then
		-- the window: {action, data = {name}} (an item name) or {action, data = {clientId}} (a client item id)
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "autoloot.edit", 200) then
			return
		end
		local d = type(msg.data) == "table" and msg.data or {}
		local byClient = d.clientId ~= nil
		local argument = tostring(byClient and d.clientId or d.name or ""):gsub("[%c,]", " "):sub(1, 60)
		handleCommand(player, msg.action .. ", " .. argument, byClient)
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()

