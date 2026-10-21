-- rarity_migrate.lua: the login half of the move from 15 rarities to seven (owner item 87, 2026-10-18; README "Item rarities").
--
-- Nothing depends on this: every reader maps an old rarity id to the rarity it became (data/lib/chaos_rarity.lua), so an
-- item saved before the change works the moment the server starts. At a character's first login after the change this
-- walks what the character keeps (worn items, backpacks, the purse, the inbox, the depot chest of every town) and rewrites
-- the attribute "rarity" of every item that still has one of the ids 6 .. 9 or 11 .. 15 to 5 or 10 (and, since version 2, clears the
-- rarity of a stackable item: a stack has none), one container per tick so
-- a big depot does not stall the server. Only that number changes (rarity_migrate_core.lua). The result is remembered per
-- character (storage 7102490), so it runs once; a GM can run it again with /lua ChaosRarityMigrate.walk(Player("Name")) (it is safe to repeat).
-- Items elsewhere (a house floor, the guild depot, a market offer) are fixed when they pass through a player's hands again,
-- or by sql/chaos_zz_rarity_migrate.sql for the market and stash tables.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/rarity_migrate_core.lua")

ChaosRarityMigrate = ChaosRarityMigrate or {}
local M = ChaosRarityMigrate
local K = ChaosRarityMigrateCore

M.STORAGE = 7102490 -- 7102490 - 7102499 reserved (README "Storage keys"): +0 the version of the walk this character had
M.stepMs = 50 -- between two containers

local function slotItems(player)
	local out = {}
	for _, slot in ipairs({1, 2, 3, 4, 5, 6, 7, 8, 9, 13}) do -- worn: head .. ring and the badge slot (engine patch 0058)
		local ok, item = pcall(function() return player:getSlotItem(slot) end)
		if ok and item then
			out[#out + 1] = item
		end
	end
	return out
end

-- every place a character keeps things, one entry each: {name, items = function() -> list of top items to walk}
local function roots(player)
	local list = {}
	list[#list + 1] = {name = "equipment", get = function() return slotItems(player) end}
	if player.getStoreInbox then
		list[#list + 1] = {name = "purse", get = function() return {player:getStoreInbox()} end}
	end
	list[#list + 1] = {name = "inbox", get = function() return {player:getInbox()} end}
	local okT, towns = pcall(Game.getTowns)
	for _, town in ipairs(okT and towns or {}) do
		local id = town:getId()
		list[#list + 1] = {name = "depot " .. id, get = function()
			local ok, chest = pcall(function() return player:getDepotChest(id, false) end)
			return ok and chest and {chest} or {}
		end}
	end
	return list
end

-- a stackable item never carries a rarity (owner 2026-10-20): the walk clears it. An item without a readable type is not one
local function isStackable(it)
	local ok, res = pcall(function() return ItemType(it:getId()):isStackable() end)
	return ok and res == true
end

-- the item itself and, for a container, everything inside it
local function fixTree(item, counts)
	local function fix(it)
		local old = K.fixItem(function(k) return it:getCustomAttribute(k) end,
			function(k, v) it:setCustomAttribute(k, v) end, {stackable = isStackable(it),
				clear = function(k) it:removeCustomAttribute(k) end})
		if old then
			counts[old] = (counts[old] or 0) + 1
		end
	end
	if not item then
		return
	end
	local okC, isC = pcall(function() return item:isContainer() end)
	if okC and isC then
		local ok, inner = pcall(function() return item:getItems(true) end)
		for _, it in ipairs(ok and inner or {}) do
			fix(it)
		end
		-- the depot chest and the inbox are containers themselves with no rarity: nothing to fix on them
	else
		fix(item)
	end
end

-- walk one character now (synchronous; GMs and tests); returns the counts per old id
function M.walk(player)
	local counts = {}
	for _, root in ipairs(roots(player)) do
		local ok, items = pcall(root.get)
		for _, item in ipairs(ok and items or {}) do
			fixTree(item, counts)
		end
	end
	return counts
end

-- walk one character spread over ticks: one root per tick
function M.walkAsync(playerId, done)
	local player = Player(playerId)
	if not player then
		return
	end
	local list, counts, at = roots(player), {}, 0
	local function step()
		local p = Player(playerId)
		if not p then
			return
		end
		at = at + 1
		local root = list[at]
		if not root then
			p:setStorageValue(M.STORAGE, K.VERSION)
			if done then
				done(p, counts)
			end
			return
		end
		local ok, items = pcall(root.get)
		for _, item in ipairs(ok and items or {}) do
			pcall(fixTree, item, counts)
		end
		addEvent(step, M.stepMs)
	end
	addEvent(step, M.stepMs)
end

local login = CreatureEvent("ChaosRarityMigrateLogin")
function login.onLogin(player)
	if player:getStorageValue(M.STORAGE) >= K.VERSION then
		return true
	end
	M.walkAsync(player:getId(), function(p, counts)
		local text = K.summary(counts)
		if text then
			print(string.format("[rarity] %s: old rarities updated: %s", p:getName(), text))
		end
	end)
	return true
end
login:type("login")
login:register()
