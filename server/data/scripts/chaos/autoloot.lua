-- game_autoloot (extended opcode 216)
--
-- Client contract (client/overlay/modules/game_autoloot/loot.lua):
--   client -> server  {"action":"open"}                     (no data)
--   client -> server  {"action":"add","data":{"name":"<item name>"}} or {"action":"add","data":{"clientId":N}}
--                     {"action":"remove","data":{"name":"<item name>"}}
--                     {"action":"clear"}
--                     add / remove with "quiet":true: the answer is "list" (the item menu; the window stays shut)
--                     {"action":"sync"}                     (the list without opening the window: "list" back)
--   server -> client  {"action":"open","data":{"itemsTable":[[clientId,"name"],...],
--                                              "currentSlot":N,"maxSlot":M}}
--   server -> client  {"action":"list","data":{...}}         (the same data, answer to "sync")
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

-- Arrows and bolts never reach a corpse (bows need no ammunition any more: loot.lua step 0 takes them out of every
-- corpse, data/lib/chaos_archery_core.lua). One on the list could never be looted: owner report 2026-10-17 "an item
-- shows in the autoloot list but disappears when looting from any monster (no gold gained)". They cannot be added and
-- an old entry is not shown or counted (it is dropped at the next change of the list).
local function isAmmo(itemType)
	return ChaosArchery ~= nil and ChaosArchery.isAmmoId ~= nil and ChaosArchery.isAmmoId(itemType:getId(), itemType) == true
end

local function readList(player)
	local items = {}
	for i = 1, MAX_SLOTS do
		local value = player:getStorageValue(BASE + i)
		if value and value > 0 then
			local itemType = ItemType(value)
			if itemType and itemType:getId() ~= 0 and not isAmmo(itemType) then
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

-- action: "open" (the window shows it) or "list" (the client only keeps it: the item menu's "Add to Loot List" /
-- "Remove from Loot List", client loot.lua)
local function sendList(player, action)
	local items = readList(player)
	local limit = getLimit(player)
	-- Anything past the current limit (premium expired) is ignored by the reference callback;
	-- show the effective list only.
	local rows = {}
	for i = 1, math.min(#items, limit) do
		local itemType = ItemType(items[i])
		rows[#rows + 1] = {itemType:getClientId(), itemType:getName()}
	end
	Chaos.send(player, OPCODE, action or "open", {itemsTable = rows, currentSlot = #rows, maxSlot = limit})
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

-- reply: the answer's action (sendList), nil = "open"
local function handleCommand(player, param, byClient, reply)
	local action, argument = param:match("^%s*([^,]*)%s*,?%s*(.-)%s*$")
	action = (action or ""):lower():gsub("%s+", "")

	if action == "clear" then
		writeList(player, {})
		player:sendCancelMessage(Chaos.t(player, "Autoloot list cleaned."))
	elseif action == "add" or action == "remove" then
		local itemType = lookupItem(argument, byClient)
		if not itemType then
			player:sendCancelMessage(Chaos.t(player, "The item %s does not exist!", argument))
			sendList(player, reply)
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
			if isAmmo(itemType) then
				player:sendCancelMessage(Chaos.t(player, "%s no longer drops: bows and crossbows need no ammunition, so it cannot be on the auto loot list.", itemType:getName()))
			elseif index then
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
	sendList(player, reply)
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
	elseif msg.action == "sync" then
		sendList(player, "list")
	elseif msg.action == "add" or msg.action == "remove" or msg.action == "clear" then
		-- the window: {action, data = {name}} (an item name) or {action, data = {clientId}} (a client item id)
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "autoloot.edit", 200) then
			return
		end
		local d = type(msg.data) == "table" and msg.data or {}
		local byClient = d.clientId ~= nil
		local argument = tostring(byClient and d.clientId or d.name or ""):gsub("[%c,]", " "):sub(1, 60)
		-- quiet: the item menu's "Add to Loot List" / "Remove from Loot List" (the window stays closed)
		handleCommand(player, msg.action .. ", " .. argument, byClient, d.quiet and "list" or nil)
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()


-- ---------------------------------------------------------------- gold goes to the bank (owner 2026-10-18)
-- "Mande todo o gold que for auto looted pro banco", and since 2026-10-21 for every kill (G.wanted): the coins of a
-- kill's corpse are paid into the bank account instead of being looted into the backpack (no coin
-- stacks to convert, no weight). onDropLoot index 2.6: after the auto seller (2), before the store pouches (2.7) and the
-- base autoloot (3), which then find no coins. The corpse owner is the one who gets it.
local COIN_VALUE = {[2148] = 1, [2152] = 100, [2160] = 10000}
ChaosAutolootGold = ChaosAutolootGold or {}
local G = ChaosAutolootGold

-- the gold in `coins` = {{id, count}, ...}: the total, ignoring anything that is not a coin
function G.total(coins)
	local sum = 0
	for _, c in ipairs(coins) do
		local v = COIN_VALUE[c.id]
		if v then
			sum = sum + v * (tonumber(c.count) or 0)
		end
	end
	return sum
end

-- every corpse the character owns pays its coins into the bank (owner 2026-10-21 "deixe todo o loot de coin ir direto
-- pro banco por default"). Before, only a coin on the autoloot list or a Loot Bag with its gold rule did.
function G.wanted(owner)
	return owner ~= nil
end

function G.toBank(owner, corpse)
	if not G.wanted(owner) then
		return 0
	end
	-- the corpse and the bags inside it (stock loot can put coins in a bag), two levels deep
	local total, taken = 0, {}
	local function scan(container, depth)
		for _, item in ipairs(container:getItems()) do
			local v = COIN_VALUE[item:getId()]
			if item:getType():isContainer() then
				if depth < 2 then
					scan(item, depth + 1)
				end
			elseif v then
				taken[#taken + 1] = item
				total = total + v * item:getCount()
			end
		end
	end
	scan(corpse, 0)
	if total <= 0 then
		return 0
	end
	local paid = 0
	for _, item in ipairs(taken) do
		local v, n = COIN_VALUE[item:getId()], item:getCount()
		if item:remove() then
			paid = paid + v * n
		end
	end
	if paid > 0 then
		owner:setBankBalance(owner:getBankBalance() + paid)
		if ChaosTelemetry and ChaosTelemetry.economy then
			pcall(ChaosTelemetry.economy, owner, "faucet", "autoloot_gold", paid)
		end
		owner:sendTextMessage(MESSAGE_LOOT or MESSAGE_INFO_DESCR, Chaos.t(owner, "Auto loot: %d gold to your bank.", paid))
	end
	return paid
end

if EventCallback then
	local goldCb = EventCallback
	goldCb.onDropLoot = function(self, corpse)
		local ok, err = pcall(function()
			if not corpse:getType():isContainer() then
				return
			end
			local owner = Player(corpse:getCorpseOwner())
			if owner then
				G.toBank(owner, corpse)
			end
		end)
		if not ok then
			print("[Chaos autoloot] gold to bank failed: " .. tostring(err))
		end
	end
	goldCb:register(2.6)
end
