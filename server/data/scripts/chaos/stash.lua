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
-- Persistence: DB tables chaos_stash(player_id,item_id,count,tab) and chaos_stash_block(player_id,item_id).
-- Only stackable, pickupable items without action/unique ids or custom text are accepted.
--
-- Tabs (Chaos Pact and account storage, pact.lua / pact_core.lua / pact_config.lua): every entry (item type) sits in a
-- tab. General tabs 1.. hold pact_config.lua stash.tabSize item types; the account's stashTabs limit (free + Chaos Pact
-- + bought tabs) says how many take new items, the others are withdraw-only. Special tabs (Orbs, Gems, Keys) are bought
-- once and take only their kind. Entries are never deleted when the limit shrinks. Each addItems entry carries `tab`;
-- after the list the server sends  tabs {tabs = [{id, name, used, size, locked, special}], limit, pact}.
-- Without pact.lua the stash works as before (no tab limit).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

local OPCODE = ChaosOpcodes.stash
local cfg = Chaos.stash
local T = Chaos.tables.stash
local TB = Chaos.tables.stashBlock

-- >>> Chaos Pact stash tabs (pact.lua): the tab column, the account's limits, the tab of a deposit
local tabColumn -- nil = not checked yet
local function tabsReady()
	if tabColumn == nil then
		db.query("ALTER TABLE `" .. T .. "` ADD COLUMN IF NOT EXISTS `tab` smallint(5) unsigned NOT NULL DEFAULT 0")
		local rows = Chaos.select("SELECT COUNT(*) AS `n` FROM information_schema.columns WHERE table_schema = DATABASE() AND " ..
			"table_name = '" .. T .. "' AND column_name = 'tab'", {{"n", "n"}})
		tabColumn = rows[1] ~= nil and rows[1].n > 0
	end
	return tabColumn and ChaosPact ~= nil and ChaosPactCore ~= nil and Chaos.pactConfig ~= nil
end

-- {{item, tab, kind, count}} of the character, laid out (entries without a tab get one; orbs / gems / keys move into
-- their owned special tab); the moves are saved
local function tabEntries(player, lim)
	local guid = player:getGuid()
	local entries = Chaos.select("SELECT `item_id`, `count`, `tab` FROM `" .. T .. "` WHERE `player_id` = " .. guid .. " AND `count` > 0",
		{{"item_id", "n"}, {"count", "n"}, {"tab", "n"}})
	for _, e in ipairs(entries) do
		e.item, e.kind = e.item_id, ChaosPact.stashKind(e.item_id)
	end
	for _, m in ipairs(ChaosPactCore.layout(Chaos.pactConfig, lim, entries)) do
		db.query("UPDATE `" .. T .. "` SET `tab` = " .. m.tab .. " WHERE `player_id` = " .. guid .. " AND `item_id` = " .. m.item)
	end
	return entries
end

-- the tab a deposit of itemId goes to, or nil + the refusal text; true when tabs are not in use
local function depositTab(player, itemId, lim, entries)
	if not tabsReady() then
		return true
	end
	lim = lim or ChaosPact.limits(player)
	entries = entries or tabEntries(player, lim)
	local tab, why = ChaosPactCore.depositTab(Chaos.pactConfig, lim, entries, itemId, ChaosPact.stashKind(itemId))
	if tab then
		return tab
	end
	local M = Chaos.pactConfig.messages
	if why == "locked" then
		return nil, string.format(M.tabLocked, lim.stashTabs)
	end
	return nil, string.format(M.tabFull, #entries)
end

-- keeps the in-memory entry list of a Stash All run up to date
local function noteDeposit(entries, itemId, tab)
	if not entries then
		return
	end
	for _, e in ipairs(entries) do
		if e.item == itemId then
			e.tab = tab
			return
		end
	end
	entries[#entries + 1] = {item = itemId, tab = tab, kind = ChaosPact.stashKind(itemId)}
end
-- <<< Chaos Pact stash tabs

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

local function stashAdd(guid, itemId, delta, tab)
	if delta >= 0 and type(tab) == "number" then
		db.query(
			"INSERT INTO `" .. T .. "` (`player_id`, `item_id`, `count`, `tab`) VALUES (" .. guid .. ", " .. itemId .. ", " .. delta ..
				", " .. tab .. ") ON DUPLICATE KEY UPDATE `count` = `count` + " .. delta .. ", `tab` = " .. tab
		)
	elseif delta >= 0 then
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
	local rows, lim
	if tabsReady() then
		lim = ChaosPact.limits(player)
		rows = tabEntries(player, lim)
	else
		rows = Chaos.select(
			"SELECT `item_id`, `count` FROM `" .. T .. "` WHERE `player_id` = " .. player:getGuid() .. " AND `count` > 0",
			{{"item_id", "n"}, {"count", "n"}}
		)
	end
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
				typee = categoryOf(itemType),
				tab = row.tab
			}
		end
	end

	if lim then
		local P = ChaosPactCore
		send(player, {make = "tabs", tabs = P.tabsView(Chaos.pactConfig, lim, rows), limit = lim.stashTabs,
			pact = ChaosPact.active(player), tabSize = Chaos.pactConfig.stash.tabSize})
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

local function blocks(t)
	return t ~= nil and t.hasProperty ~= nil and (t:hasProperty(CONST_PROP_BLOCKSOLID) or t:hasProperty(CONST_PROP_BLOCKPROJECTILE))
end

-- a floor tile the player could reach with the hand, not through a wall, bars or a window: the own tile, or a
-- tile that does not block (wall, bars, window) in clear sight; a diagonal one needs one open side (no reaching between
-- two walls at a corner). Item:remove() skips all of the engine's reach rules, so they are checked here.
local function reachable(playerPos, position, tile)
	if position.x == playerPos.x and position.y == playerPos.y then
		return true
	end
	if blocks(tile) then
		return false
	end
	if playerPos.isSightClear and not playerPos:isSightClear(position, true) then
		return false
	end
	if position.x ~= playerPos.x and position.y ~= playerPos.y then
		local a = Tile(Position(position.x, playerPos.y, position.z))
		local b = Tile(Position(playerPos.x, position.y, position.z))
		if (not a or blocks(a)) and (not b or blocks(b)) then
			return false
		end
	end
	return true
end

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
	if not tile or not reachable(playerPos, position, tile) then
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
	local tab, refusal = depositTab(player, itemId)
	if not tab then
		player:sendCancelMessage(refusal)
		return false
	end
	local name = item:getType():getName()
	if not item:remove(count) then
		player:sendCancelMessage("Could not take the item.")
		return false
	end
	-- the character is written before the row is credited: a crash in between cannot hand the item back while the
	-- stash keeps it too (chaos_constants.lua Chaos.saveCharacter). Stashable items are plain stacks: addItem restores.
	if not Chaos.saveCharacter(player) then
		player:addItem(itemId, count)
		player:sendCancelMessage("The stash is busy. Try again in a moment.")
		return false
	end
	stashAdd(guid, itemId, count, tab)
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Stashed %dx %s.", count, name))
	return true
end

local function stashAll(player)
	send(player, {make = "StashAll", status = true})
	local moved, full = 0, nil
	local taken = {} -- {itemId, count, tab} removed in memory, credited after the save
	local pending = {} -- itemId -> count taken but not yet credited (the entry limit)
	local lim = tabsReady() and ChaosPact.limits(player) or nil
	local entries = lim and tabEntries(player, lim) or nil
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
				if stashCount(player:getGuid(), item:getId()) + (pending[item:getId()] or 0) + count <= cfg.maxStackPerEntry then
					local itemId = item:getId()
					local tab, refusal = true, nil
					if lim then
						tab, refusal = depositTab(player, itemId, lim, entries)
					end
					if not tab then
						full = refusal
					elseif item:remove(count) then
						taken[#taken + 1] = {itemId, count, tab}
						pending[itemId] = (pending[itemId] or 0) + count
						noteDeposit(entries, itemId, tab)
					end
				end
			end
		end
	end
	-- one save for the whole batch, before any row is credited (see stashItem); a failed save gives everything back
	if #taken > 0 and not Chaos.saveCharacter(player) then
		for _, t in ipairs(taken) do
			player:addItem(t[1], t[2])
		end
		taken = {}
		full = "The stash is busy. Try again in a moment."
	end
	for _, t in ipairs(taken) do
		stashAdd(player:getGuid(), t[1], t[2], t[3])
		moved = moved + 1
	end
	send(player, {make = "StashAll", status = false})
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Stashed %d item stack(s).", moved))
	if full then
		player:sendTextMessage(MESSAGE_INFO_DESCR, full)
	end
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
	local tab = depositTab(player, itemId)
	if not tab then
		return false
	end
	if not item:remove(count) then
		return false
	end
	if not Chaos.saveCharacter(player) then -- see stashItem
		player:addItem(itemId, count)
		return false
	end
	stashAdd(guid, itemId, count, tab)
	return true
end
