-- game_stash (extended opcode ChaosOpcodes.stash = 110, plus the "!stash" talkaction)
--
-- Client contract (client/overlay/modules/game_stash/stash.lua). The shipped client talks through
-- the donor client's client_manager, which is NOT part of the overlay. This file assumes the manager
-- uses the same envelope in both directions:   {"action":"Stash","data":{"make":...,...}}
-- (see README for the 6-line client patch that makes that true without client_manager).
--
--   client -> server data.make:
--     SendCategories {sendBlocks=true}  -> addCategorys + forceBlockList
--     SendItems                         -> addItems stream
--     Stash {Pos={x,y,z,stackpos}, Typed=1, UpdateList=bool}   deposit one stack from map/container
--     Redeem {item=<server id>, id=<uniqueId>, count=N}        withdraw
--     ChangeStash {Pos={...}}           toggle the item type on the "never stash" list
--     ChangeStash {RemoveUI=true, itemId=<server id>}          remove from that list
--   server -> client data.make:
--     addItems {isFirst,isLast,items=[{sprite=clientId,count,name,tooltip,id=serverId,uniqueId,typee}]}
--     addCategorys {list=[{name,value}], remote=bool}   (filter values must be >= 3)
--     forceBlockList {items=[{sprite,name,id}]}
--     addBlockItem {status=bool, itemData={sprite,name,id}}
--     Toggle {remote=bool}              open/close the window ("!stash")
--     StashAll {status=bool}            show/hide the progress overlay ("!stash all")
--
-- Persistence: DB tables chaos_stash(player_id,item_id,count) and chaos_stash_block(player_id,item_id).
-- Only stackable, pickupable items without action/unique ids or custom text are accepted.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

local OPCODE = ChaosOpcodes.stash
local cfg = Chaos.stash
local T = Chaos.tables.stash
local TB = Chaos.tables.stashBlock

local CATEGORIES = {
	{name = "Runes", value = 3},
	{name = "Ammunition", value = 4},
	{name = "Potions", value = 5},
	{name = "Valuables", value = 6},
	{name = "Other", value = 7}
}

local VALUABLE_WORDS = {"coin", "gem", "pearl", "amethyst", "topaz", "sapphire", "ruby", "emerald", "diamond", "amber", "nugget"}

local function categoryOf(itemType)
	if itemType:isRune() then
		return 3
	end
	if itemType:getWeaponType() == WEAPON_AMMO then
		return 4
	end
	local name = itemType:getName():lower()
	if name:find("potion", 1, true) then
		return 5
	end
	for _, word in ipairs(VALUABLE_WORDS) do
		if name:find(word, 1, true) then
			return 6
		end
	end
	return 7
end

local function isRemote(player)
	return cfg.remoteForEveryone or player:getStorageValue(Chaos.storage.stashRemote) > 0
end

local function send(player, data)
	Chaos.send(player, OPCODE, "Stash", data)
end

-- ---------------------------------------------------------------- database helpers

local function stashCount(guid, itemId)
	local resultId = db.storeQuery("SELECT `count` FROM `" .. T .. "` WHERE `player_id` = " .. guid .. " AND `item_id` = " .. itemId)
	if not resultId then
		return 0
	end
	local count = result.getNumber(resultId, "count")
	result.free(resultId)
	return count
end

local function stashAdd(guid, itemId, delta)
	if delta >= 0 then
		db.query(
			"INSERT INTO `" .. T .. "` (`player_id`, `item_id`, `count`) VALUES (" .. guid .. ", " .. itemId .. ", " .. delta ..
				") ON DUPLICATE KEY UPDATE `count` = `count` + " .. delta
		)
	else
		db.query("UPDATE `" .. T .. "` SET `count` = `count` + " .. delta .. " WHERE `player_id` = " .. guid .. " AND `item_id` = " .. itemId)
		db.query("DELETE FROM `" .. T .. "` WHERE `player_id` = " .. guid .. " AND `item_id` = " .. itemId .. " AND `count` <= 0")
	end
end

local function isBlocked(guid, itemId)
	local resultId = db.storeQuery("SELECT 1 AS `x` FROM `" .. TB .. "` WHERE `player_id` = " .. guid .. " AND `item_id` = " .. itemId)
	if resultId then
		result.free(resultId)
		return true
	end
	return false
end

local function blockEntry(itemType)
	return {sprite = itemType:getClientId(), name = itemType:getName(), id = itemType:getId()}
end

-- ---------------------------------------------------------------- protocol senders

local function sendCategories(player, withBlocks)
	send(player, {make = "addCategorys", list = CATEGORIES, remote = isRemote(player)})
	if withBlocks then
		local items = {}
		local rows = Chaos.select("SELECT `item_id` FROM `" .. TB .. "` WHERE `player_id` = " .. player:getGuid(), {{"item_id", "n"}})
		for _, row in ipairs(rows) do
			local itemType = ItemType(row.item_id)
			if itemType:getId() ~= 0 then
				items[#items + 1] = blockEntry(itemType)
			end
		end
		send(player, {make = "forceBlockList", items = items})
	end
end

local function sendItems(player)
	local rows = Chaos.select(
		"SELECT `item_id`, `count` FROM `" .. T .. "` WHERE `player_id` = " .. player:getGuid() .. " AND `count` > 0",
		{{"item_id", "n"}, {"count", "n"}}
	)
	local entries = {}
	for _, row in ipairs(rows) do
		local itemType = ItemType(row.item_id)
		if itemType:getId() ~= 0 then
			entries[#entries + 1] = {
				sprite = itemType:getClientId(),
				count = row.count,
				name = itemType:getName(),
				tooltip = string.format("%s\nAmount: %d", itemType:getName(), row.count),
				id = itemType:getId(),
				uniqueId = itemType:getId(),
				typee = categoryOf(itemType)
			}
		end
	end

	if #entries == 0 then
		send(player, {make = "addItems", isFirst = true, isLast = true, items = {}})
		return
	end
	local size = cfg.chunkSize
	for first = 1, #entries, size do
		local chunk = {}
		for i = first, math.min(first + size - 1, #entries) do
			chunk[#chunk + 1] = entries[i]
		end
		send(player, {
			make = "addItems",
			isFirst = first == 1,
			isLast = first + size > #entries,
			items = chunk
		})
	end
end

-- ---------------------------------------------------------------- item lookup

-- Resolve the {x,y,z,stackpos} the client sends into a real item the player may touch.
local function resolveItem(player, pos)
	if type(pos) ~= "table" then
		return nil
	end
	local x, y, z = Chaos.toInt(pos.x, 0), Chaos.toInt(pos.y, 0), Chaos.toInt(pos.z, 0)
	if not x or not y or not z then
		return nil
	end

	if x == 65535 then
		if y >= 64 then
			local container = player:getContainerById(y - 64)
			return container and container:getItem(z) or nil
		end
		return player:getSlotItem(y)
	end

	local position = Position(x, y, z)
	local playerPos = player:getPosition()
	if position.z ~= playerPos.z or math.max(math.abs(position.x - playerPos.x), math.abs(position.y - playerPos.y)) > cfg.maxDistance then
		return nil
	end
	local tile = Tile(position)
	if not tile then
		return nil
	end
	-- Item:remove() skips the engine's house rule (HouseTile::queryRemove only checks when there is an actor), so a
	-- floor item of a house is reachable only from inside that same house (where only invited players can stand);
	-- otherwise a player outside could stash, i.e. take, the gold lying on a house floor right behind the wall
	local house = tile:getHouse()
	if house then
		local own = Tile(playerPos)
		local ownHouse = own and own:getHouse()
		if not ownHouse or ownHouse:getId() ~= house:getId() then
			return nil
		end
	end
	local stackpos = Chaos.toInt(pos.stackpos, 0)
	local thing = stackpos and tile:getThing(stackpos) or nil
	-- map decoration and fixed items stay where they are (the engine refuses to move them, Item:remove does not)
	if thing and thing:isItem() and thing:getType():isMovable() then
		return thing
	end
	return nil
end

local function stashable(item)
	local itemType = item:getType()
	if not itemType:isStackable() or not itemType:isPickupable() or itemType:isContainer() then
		return false
	end
	if item:hasAttribute(ITEM_ATTRIBUTE_ACTIONID) or item:hasAttribute(ITEM_ATTRIBUTE_UNIQUEID) or item:hasAttribute(ITEM_ATTRIBUTE_TEXT) or item:hasAttribute(ITEM_ATTRIBUTE_DESCRIPTION) then
		return false
	end
	return true
end

-- returns true if something was stashed
local function stashItem(player, item)
	local guid = player:getGuid()
	if not stashable(item) then
		player:sendCancelMessage("You cannot put that item into the stash.")
		return false
	end
	local itemId = item:getId()
	if isBlocked(guid, itemId) then
		player:sendCancelMessage("That item is on your stash block list.")
		return false
	end
	local count = item:getCount()
	if stashCount(guid, itemId) + count > cfg.maxStackPerEntry then
		player:sendCancelMessage("Your stash cannot hold that many of this item.")
		return false
	end
	local name = item:getType():getName()
	if not item:remove(count) then
		player:sendCancelMessage("Could not take the item.")
		return false
	end
	stashAdd(guid, itemId, count)
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Stashed %dx %s.", count, name))
	return true
end

local function stashAll(player)
	send(player, {make = "StashAll", status = true})
	local moved = 0
	local backpack = player:getSlotItem(CONST_SLOT_BACKPACK)
	if backpack and backpack:isContainer() then
		-- collect first, remove afterwards (removing while iterating a container is unsafe)
		local candidates = {}
		for _, item in ipairs(backpack:getItems(true)) do
			if stashable(item) then
				candidates[#candidates + 1] = item
			end
		end
		for _, item in ipairs(candidates) do
			if not isBlocked(player:getGuid(), item:getId()) then
				local count = item:getCount()
				if stashCount(player:getGuid(), item:getId()) + count <= cfg.maxStackPerEntry then
					local itemId = item:getId()
					if item:remove(count) then
						stashAdd(player:getGuid(), itemId, count)
						moved = moved + 1
					end
				end
			end
		end
	end
	send(player, {make = "StashAll", status = false})
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Stashed %d item stack(s).", moved))
end

-- ---------------------------------------------------------------- actions

local function redeem(player, data)
	local itemId = Chaos.toInt(data.item, 1)
	local want = Chaos.toInt(data.count, 1)
	local itemType = itemId and ItemType(itemId)
	if not itemType or itemType:getId() == 0 or not want then
		sendItems(player)
		return
	end
	local guid = player:getGuid()
	local have = stashCount(guid, itemId)
	local amount = math.min(have, want)
	if amount <= 0 then
		player:sendCancelMessage("You do not have that item in the stash.")
		sendItems(player)
		return
	end

	-- capacity limit (weights are in 1/100 oz on both sides)
	local unitWeight = itemType:getWeight(1)
	if unitWeight > 0 then
		amount = math.min(amount, math.floor(player:getFreeCapacity() / unitWeight))
	end
	if amount <= 0 then
		player:sendCancelMessage("You do not have enough capacity.")
		sendItems(player)
		return
	end

	local given = Chaos.giveItem(player, itemId, amount)
	if given <= 0 then
		player:sendCancelMessage("You do not have enough room.")
	else
		stashAdd(guid, itemId, -given)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Retrieved %dx %s from your stash.", given, itemType:getName()))
	end
	sendItems(player)
end

local function changeBlock(player, data)
	local guid = player:getGuid()
	if data.RemoveUI then
		local itemId = Chaos.toInt(data.itemId, 1)
		local itemType = itemId and ItemType(itemId)
		if itemType and itemType:getId() ~= 0 then
			db.query("DELETE FROM `" .. TB .. "` WHERE `player_id` = " .. guid .. " AND `item_id` = " .. itemId)
			send(player, {make = "addBlockItem", status = false, itemData = blockEntry(itemType)})
		end
		return
	end
	local item = resolveItem(player, data.Pos)
	if not item then
		return
	end
	local itemType = item:getType()
	local itemId = itemType:getId()
	if isBlocked(guid, itemId) then
		db.query("DELETE FROM `" .. TB .. "` WHERE `player_id` = " .. guid .. " AND `item_id` = " .. itemId)
		send(player, {make = "addBlockItem", status = false, itemData = blockEntry(itemType)})
	else
		db.query("INSERT IGNORE INTO `" .. TB .. "` (`player_id`, `item_id`) VALUES (" .. guid .. ", " .. itemId .. ")")
		send(player, {make = "addBlockItem", status = true, itemData = blockEntry(itemType)})
	end
end

local LoginEvent = CreatureEvent("ChaosStashLogin")

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosStashExtended")
	return true
end

local ExtendedEvent = CreatureEvent("ChaosStashExtended")

function ExtendedEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "Stash" or type(msg.data) ~= "table" then
		return
	end
	local data = msg.data
	-- list, redeem and block-list requests read the database; a flood of them is dropped (ratelimit.lua). "Stash" is
	-- not limited: the client waits for its echo, and each one needs a real item
	local limit = ({SendCategories = 300, SendItems = 300, Redeem = 100, ChangeStash = 100, Open = 300,
		StashAllRequest = 1000})[data.make]
	if limit and ChaosRateLimit and not ChaosRateLimit.allow(player, "stash." .. data.make, limit) then
		return
	end

	if data.make == "SendCategories" then
		sendCategories(player, data.sendBlocks == true)
	elseif data.make == "SendItems" then
		sendItems(player)
	elseif data.make == "Stash" then
		local item = resolveItem(player, data.Pos)
		if item then
			stashItem(player, item)
		end
		if data.UpdateList then
			sendItems(player) -- always echo, even when rejected (the client relies on this)
		end
	elseif data.make == "Redeem" then
		redeem(player, data)
	elseif data.make == "ChangeStash" then
		changeBlock(player, data)
	elseif data.make == "Open" then
		send(player, {make = "Toggle", remote = isRemote(player)})
	elseif data.make == "StashAllRequest" then
		stashAll(player)
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()

-- put a loose item (e.g. in a corpse) into the stash (for scripts; the retired Bottomless Loot Pouch used it).
-- Returns true when it was stashed; false when the item is not stashable, blocked or the entry is full.
ChaosStash = ChaosStash or {}
function ChaosStash.storeItem(player, item)
	if not stashable(item) then
		return false
	end
	local guid, itemId, count = player:getGuid(), item:getId(), item:getCount()
	if isBlocked(guid, itemId) or stashCount(guid, itemId) + count > cfg.maxStackPerEntry then
		return false
	end
	if not item:remove(count) then
		return false
	end
	stashAdd(guid, itemId, count)
	return true
end
