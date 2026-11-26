-- star_inlay_clean.lua: the clean-up of star pieces from before the V22 fix (O181; owner 2026-11-26, "8 faça a limpeza";
-- server/README.md "Star inlay stones"). The old Star Extractor left the copied "Tier I ( 3 Star )" line in a piece's own
-- description, so its Look named a tier it no longer had, and a stone after that kept the wrong line. The rule is pure
-- (star_inlay_core.lua K.cleanText: a tier line that is not the item type's goes, the type's own stays); this file only
-- walks the items.
--
-- At a character's first login after this change it walks what the character keeps (worn items and the backpack, the
-- purse, the inbox, the depot chest of every town that is loaded), one place per tick, and cleans every item whose own
-- description holds a tier line. Done once per character (storage 7103170, README "Storage keys"). The stash keeps its
-- items as saved blobs: an item is cleaned when it comes out (stash.lua S.stowWithdrawn calls M.cleanItem). Anything
-- else is cleaned at its next stone, as since V22. A GM can run it again: /lua ChaosStarInlayClean.walk(Player("Name")).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosStarInlayClean = ChaosStarInlayClean or {}
local M = ChaosStarInlayClean
local K = dofile("data/scripts/chaos/star_inlay_core.lua")

M.STORAGE = 7103170 -- 7103170 - 7103179 reserved (README "Storage keys"): +0 the version of the walk this character had
M.VERSION = 1
M.stepMs = 50 -- between two places

local function typeDescription(item)
	local ok, text = pcall(function() return ItemType(item:getId()):getDescription() end)
	return ok and text or ""
end

-- one item; true when it changed
function M.cleanItem(item)
	if not item then
		return false
	end
	local ok, changed = pcall(K.cleanItem, item, typeDescription(item))
	return ok and changed == true
end

-- the item and, for a container, everything inside it; returns how many changed
local function cleanTree(item)
	local n = M.cleanItem(item) and 1 or 0
	local okC, isC = pcall(function() return item:isContainer() end)
	if okC and isC then
		local ok, inner = pcall(function() return item:getItems(true) end)
		for _, it in ipairs(ok and inner or {}) do
			if M.cleanItem(it) then
				n = n + 1
			end
		end
	end
	return n
end

local function slotItems(player)
	local out = {}
	for _, slot in ipairs({1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13}) do -- worn, the backpack (3) and the badge slot (engine patch 0058)
		local ok, item = pcall(function() return player:getSlotItem(slot) end)
		if ok and item then
			out[#out + 1] = item
		end
	end
	return out
end

-- every place a character keeps things, one entry each
local function roots(player)
	local list = {function() return slotItems(player) end}
	if player.getStoreInbox then
		list[#list + 1] = function() return {player:getStoreInbox()} end
	end
	list[#list + 1] = function() return {player:getInbox()} end
	local okT, towns = pcall(Game.getTowns)
	for _, town in ipairs(okT and towns or {}) do
		local id = town:getId()
		list[#list + 1] = function()
			local ok, chest = pcall(function() return player:getDepotChest(id, false) end)
			return ok and chest and {chest} or {}
		end
	end
	return list
end

-- walk one character now (GMs and tests); returns how many items changed
function M.walk(player)
	local n = 0
	for _, get in ipairs(roots(player)) do
		local ok, items = pcall(get)
		for _, item in ipairs(ok and items or {}) do
			n = n + cleanTree(item)
		end
	end
	return n
end

-- one place per tick, then the storage
function M.walkAsync(playerId)
	local player = Player(playerId)
	if not player then
		return
	end
	local list, at, n = roots(player), 0, 0
	local function step()
		local p = Player(playerId)
		if not p then
			return
		end
		at = at + 1
		local get = list[at]
		if not get then
			p:setStorageValue(M.STORAGE, M.VERSION)
			if n > 0 then
				print(string.format("[star inlay] %s: %d stale tier line(s) cleaned", p:getName(), n))
			end
			return
		end
		local ok, items = pcall(get)
		for _, item in ipairs(ok and items or {}) do
			local okT, c = pcall(cleanTree, item)
			n = n + (okT and c or 0)
		end
		addEvent(step, M.stepMs)
	end
	addEvent(step, M.stepMs)
end

local login = CreatureEvent("ChaosStarInlayCleanLogin")
function login.onLogin(player)
	if player:getStorageValue(M.STORAGE) >= M.VERSION then
		return true
	end
	M.walkAsync(player:getId())
	return true
end
login:type("login")
login:register()
