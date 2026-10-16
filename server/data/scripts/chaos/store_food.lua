-- Everfull Ration: the store's infinite food (store_food_config.lua; rules store_food_core.lua; item installed by
-- server/tools/install_store_food.py). README "Store pouches and the Everfull Ration".
--
-- Use it like food: one bite gives the regeneration of the best stock food (60 x 12 s = 12 minutes) and is refused with
-- "You are full." at the cap every food has (1200 s), so it eats exactly as often as normal food. The item is never
-- used up. Store-bound like the store pouches: one per character, the owner's guid and the attributes chaos_storebound
-- and chaos_locked; pouches.lua refuses the ground, mail, trash, other players' containers, the trade window and the
-- player market for any chaos_storebound item. Only the owner can eat from it. Death: death_keep.lua keeps it out of the
-- drop (inbox, back in the backpack at the next login; also with no corpse, on water). Fallback without that hook: a
-- ration dropped with the backpack leaves the corpse and comes back at the next login (storage `regrant`).
-- Store offer: {kind = "service", service = "storeFood"} (registered into ChaosShopServices.services here; no edit of
-- shop_services.lua). Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/store_food_core.lua")
dofile("data/scripts/chaos/store_food_config.lua")

ChaosStoreFood = ChaosStoreFood or {}
local F = ChaosStoreFood
local K = ChaosStoreFoodCore
local NOERR = RETURNVALUE_NOERROR or 0
F.lastBite = F.lastBite or {} -- player id -> os.mtime of the last bite

local function cfg()
	return ChaosStoreFoodConfig
end

local function mnow()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function customAttr(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	return ok and v or nil
end

function F.installed()
	local it = ItemType(cfg().item.id)
	return it ~= nil and it:getId() ~= 0
end

function F.isRation(item)
	local ok, id = pcall(function() return item:getId() end)
	return ok and id == cfg().item.id
end

local function walk(roots, fn)
	local queue, i = {}, 1
	for _, r in ipairs(roots) do
		queue[#queue + 1] = r
	end
	while i <= #queue and i < 2000 do
		local item = queue[i]
		i = i + 1
		if fn(item) then
			return true
		end
		if item:isContainer() then
			for _, inner in ipairs(item:getItems() or {}) do
				queue[#queue + 1] = inner
			end
		end
	end
	return false
end

local function roots(player)
	local out = {}
	for slot = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 10 do
		local item = player:getSlotItem(slot)
		if item then
			out[#out + 1] = item
		end
	end
	-- the purse (store inbox): where the store delivers it (store_delivery.lua)
	if player.getStoreInbox then
		local okP, purse = pcall(function() return player:getStoreInbox() end)
		if okP and purse then
			out[#out + 1] = purse
		end
	end
	local inbox = player:getInbox()
	if inbox then
		out[#out + 1] = inbox
	end
	local okT, towns = pcall(Game.getTowns)
	for _, town in ipairs(okT and towns or {}) do
		local ok, chest = pcall(function() return player:getDepotChest(town:getId(), false) end)
		if ok and chest then
			out[#out + 1] = chest
		end
	end
	return out
end

-- the character has its ration somewhere (inventory, inbox, depots)
function F.owned(player)
	local guid = player:getGuid()
	return walk(roots(player), function(item)
		return F.isRation(item) and tonumber(customAttr(item, cfg().attr.owner)) == guid
	end)
end

function F.create(player)
	local c = cfg()
	local item = Game.createItem(c.item.id, 1)
	if not item then
		return nil
	end
	item:setCustomAttribute(c.attr.owner, player:getGuid())
	item:setCustomAttribute(c.attr.storebound, 1)
	item:setCustomAttribute(c.attr.lock, 1)
	return item
end

-- backpack, else inbox: "backpack" | "inbox" | nil
function F.give(player)
	local item = F.create(player)
	if not item then
		return nil
	end
	if player:addItemEx(item, false) == NOERR then
		return "backpack"
	end
	local inbox = player:getInbox()
	if inbox and inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT or 1) == NOERR then
		return "inbox"
	end
	return nil
end

-- ---------------------------------------------------------------- eating
local eat = Action()
function eat.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local c = cfg()
	local cond = player:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	local r = K.bite(c, {ticksMs = cond and cond:getTicks() or 0, nowMs = mnow(), lastMs = F.lastBite[player:getId()],
		owner = tonumber(customAttr(item, c.attr.owner)), guid = player:getGuid()})
	if not r.ok then
		if r.text then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, r.text)
		end
		return true
	end
	F.lastBite[player:getId()] = mnow()
	player:feed(r.seconds)
	player:say(c.sound, TALKTYPE_MONSTER_SAY)
	return true -- never used up
end
if F.installed() then
	eat:id(cfg().item.id)
	eat:register()
end

-- ---------------------------------------------------------------- store
local function owed(player)
	return player:getStorageValue(cfg().storage.regrant) == 1
end

function F.storeCheck(player)
	return K.storeCheck(cfg(), {installed = F.installed(), owned = F.owned(player), owed = owed(player)})
end

-- bought: into the purse (store_delivery.lua: purse, else depot inbox, else backpack; never the ground)
function F.storeGive(player)
	local item = F.create(player)
	if not item then
		return "Your backpack and inbox are full. Your coins were refunded."
	end
	local D = ChaosStoreDelivery or dofile("data/scripts/chaos/store_delivery.lua")
	local where = D.place(player, item)
	if not where then
		pcall(function() item:remove() end)
		return "Your backpack and inbox are full. Your coins were refunded."
	end
	local place = where == "inbox" and "depot inbox" or where
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "The Everfull Ration is in your %s. Use it like food: it never runs out.", Chaos.t(player, place)))
	return true
end

function F.registerService()
	local S = ChaosShopServices
	if S and S.services and not S.services.storeFood then
		S.services.storeFood = {
			check = function(player) return F.storeCheck(player) end,
			apply = function(player) return F.storeGive(player) end
		}
	end
end
F.registerService()

-- ---------------------------------------------------------------- death and login
function F.afterDeath(guid, pos)
	local tile = Tile(Position(pos.x, pos.y, pos.z))
	if not tile then
		return
	end
	local found = {}
	for _, top in ipairs(tile:getItems() or {}) do
		if top:isContainer() then
			walk({top}, function(item)
				if F.isRation(item) and tonumber(customAttr(item, cfg().attr.owner)) == guid then
					found[#found + 1] = item
				end
				return false
			end)
		end
	end
	for _, item in ipairs(found) do
		item:remove()
		db.query(string.format("INSERT INTO `player_storage` (`player_id`, `key`, `value`) VALUES (%d, %d, 1) " ..
			"ON DUPLICATE KEY UPDATE `value` = 1", guid, cfg().storage.regrant))
	end
	return #found
end

local death = CreatureEvent("ChaosStoreFoodDeath")
function death.onDeath(player, corpse)
	local pos = corpse and corpse.getPosition and corpse:getPosition() or player:getPosition()
	local guid = player:getGuid()
	addEvent(function()
		local ok, err = pcall(F.afterDeath, guid, {x = pos.x, y = pos.y, z = pos.z})
		if not ok then
			print("[Chaos store food] death check failed: " .. tostring(err))
		end
	end, 0)
	return true
end
death:register()

local login = CreatureEvent("ChaosStoreFoodLogin")
function login.onLogin(player)
	player:registerEvent("ChaosStoreFoodDeath")
	if owed(player) and F.installed() and F.give(player) then
		player:setStorageValue(cfg().storage.regrant, 0)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Back after your death: your Everfull Ration."))
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosStoreFoodLogout")
function logout.onLogout(player)
	F.lastBite[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

local startup = GlobalEvent("ChaosStoreFoodStartup")
function startup.onStartup()
	F.registerService()
	return true
end
startup:register()
