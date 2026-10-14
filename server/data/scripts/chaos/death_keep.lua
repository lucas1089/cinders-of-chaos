-- Store-bound items never drop on death (rules: death_keep_core.lua; server/README.md "Store pouches and the Everfull
-- Ration", Death). Live test 2026-10-14: a death on shallow water left no corpse, and the Loot Bag and the Everfull
-- Ration were gone; a death on land gave both back. The stock death script (data/creaturescripts/scripts/droploot.lua)
-- moves each dropped slot item into the corpse and REMOVES it when that fails, and there is no corpse on a tile that
-- cannot hold one. The pouches' and the ration's death events looked for them in the corpse afterwards, so on water
-- there was nothing to find.
--
-- Now droploot.lua asks ChaosDeathKeep.beforeDrop(player, item, corpse) before it drops a slot item (hook written by
-- tools/patch_base_events.py step 15). Every kept item (any chaos_storebound item: the store pouches, the Everfull
-- Ration, the nemesis trophy; and any copy of a pouch or ration item) leaves the dropped container first and goes to
-- the character's inbox, marked; its own loot stays in the drop. A kept item worn in a slot stays there. At the next
-- login a marked item moves from the inbox to the backpack when it fits (else it stays in the inbox) and the player
-- is told. The corpse search of pouches.lua and store_food.lua stays as a fallback (a server without the hook).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/death_keep_core.lua")

ChaosDeathKeep = ChaosDeathKeep or {}
local DK = ChaosDeathKeep
local K = ChaosDeathKeepCore

DK.MARK = "chaos_death_kept" -- custom attribute of a parked item until the next login
DK.STOREBOUND = "chaos_storebound"

local function log(text)
	print("[Chaos death keep] " .. text)
end

local function customAttr(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	return ok and v or nil
end

function DK.kept(item)
	if not item then
		return false
	end
	if customAttr(item, DK.STOREBOUND) ~= nil then
		return true
	end
	if ChaosPouches and ChaosPouches.isPouch and ChaosPouches.isPouch(item) then
		return true
	end
	if ChaosStoreFood and ChaosStoreFood.isRation and ChaosStoreFood.isRation(item) then
		return true
	end
	return false
end

local function isContainer(item)
	local ok, v = pcall(function() return item:isContainer() end)
	return ok and v
end

local function items(item)
	local ok, list = pcall(function() return item:getItems() end)
	local out = {}
	for i, it in ipairs(ok and list or {}) do
		out[i] = it
	end
	return out
end

local function moveTo(item, dest)
	local ok, v = pcall(function() return item:moveTo(dest) end)
	return ok and v and true or false
end

function DK.api(player)
	return {
		kept = DK.kept,
		isContainer = isContainer,
		items = items,
		moveTo = moveTo,
		remove = function(item) pcall(function() item:remove() end) end,
		park = function(item)
			local inbox = player:getInbox()
			if not inbox then
				return false
			end
			pcall(function() item:setCustomAttribute(DK.MARK, 1) end)
			if moveTo(item, inbox) then
				return true
			end
			pcall(function() item:removeCustomAttribute(DK.MARK) end)
			return false
		end
	}
end

-- droploot.lua: true when `item` stays in its slot (do not drop it)
function DK.beforeDrop(player, item, corpse)
	local ok, stays, parked = pcall(K.beforeDrop, item, corpse, DK.api(player))
	if not ok then
		log("drop check failed for " .. tostring(player and player:getName()) .. ": " .. tostring(stays))
		return false
	end
	if parked and #parked > 0 then
		local names = {}
		for _, it in ipairs(parked) do
			names[#names + 1] = it:getName()
		end
		log(string.format("%s died%s: kept %s", player:getName(), corpse and "" or " (no corpse)",
			table.concat(names, ", ")))
	end
	return stays and true or false
end

-- ---------------------------------------------------------------- login: back to the backpack
local function title(item)
	local ok, name = pcall(function() return item:getName() end)
	name = ok and name or "item"
	return (name:gsub("^%l", string.upper))
end

function DK.restore(player)
	local inbox = player:getInbox()
	if not inbox then
		return
	end
	local marked = {}
	for _, item in ipairs(items(inbox)) do
		if customAttr(item, DK.MARK) ~= nil then
			marked[#marked + 1] = item
		end
	end
	if #marked == 0 then
		return
	end
	local backpack = player:getSlotItem(CONST_SLOT_BACKPACK)
	local names, inBag, inInbox = {}, 0, 0
	for _, item in ipairs(marked) do
		names[#names + 1] = title(item)
		pcall(function() item:removeCustomAttribute(DK.MARK) end)
		-- flags 0: the backpack's size and the character's capacity count; what does not fit stays in the inbox
		local moved = backpack and isContainer(backpack) and select(2, pcall(function()
			return item:moveTo(backpack, 0)
		end))
		if moved then
			inBag = inBag + 1
		else
			inInbox = inInbox + 1
		end
	end
	local where = inInbox == 0 and "backpack" or (inBag == 0 and "inbox" or "backpack and inbox")
	local text = K.loginText(names, where)
	if Chaos.t then
		text = Chaos.t(player, "Kept through your death: your %s (%s).", table.concat(names, ", "),
			Chaos.t(player, where))
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
end

local login = CreatureEvent("ChaosDeathKeepLogin")
function login.onLogin(player)
	local ok, err = pcall(DK.restore, player)
	if not ok then
		log("login failed: " .. tostring(err))
	end
	return true
end
login:type("login")
login:register()
