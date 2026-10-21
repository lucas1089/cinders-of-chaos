-- Everfull potions: engine helpers with no event registration, so the potion sellers' NPC states can load them too
-- (the ShopModule hook of server/tools/install_potions.py) as well as data/scripts/chaos/potions.lua.
-- Rules: data/scripts/chaos/potions_core.lua; numbers: potions_config.lua; README "Potions".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosPotionsCore then
	dofile("data/scripts/chaos/potions_core.lua")
end
if not ChaosPotionsConfig then
	dofile("data/scripts/chaos/potions_config.lua")
end

ChaosPotions = ChaosPotions or {}
local PT = ChaosPotions
local K = ChaosPotionsCore
local NOERR = RETURNVALUE_NOERROR or 0

function PT.cfg()
	return ChaosPotionsConfig
end

function PT.everfull(id)
	return K.everfull(PT.cfg(), id)
end

-- the Everfull item is in items.otb (install_potions.py ran)
function PT.installed(id)
	local ok, it = pcall(ItemType, id)
	return ok and it ~= nil and it:getId() ~= 0
end

local function itemId(item)
	local ok, id = pcall(function() return item:getId() end)
	return ok and id or nil
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
	local inbox = player.getInbox and player:getInbox()
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

-- the character has this Everfull potion somewhere (inventory, inbox, depots)
function PT.owned(player, id)
	return walk(roots(player), function(item)
		return itemId(item) == id
	end)
end

-- a new Everfull potion, store-bound and locked (not traded, sold, dropped or lost on death)
function PT.create(id)
	local c = PT.cfg()
	local item = Game.createItem(id, 1)
	if not item then
		return nil
	end
	item:setCustomAttribute(c.attr.storebound, 1)
	item:setCustomAttribute(c.attr.lock, K.bindLock(c)) -- bound, but drawn in its colours (potions_config.lua bindLock)
	return item
end

-- every Everfull potion of the character with the old lock value gets cfg.bindLock (sent again to the client, which
-- stops drawing it grey). Returns how many changed.
function PT.rebind(player)
	local c = PT.cfg()
	local n = 0
	walk(roots(player), function(item)
		local id = itemId(item)
		if id and K.everfull(c, id) then
			local ok, v = pcall(function() return item:getCustomAttribute(c.attr.lock) end)
			if ok and K.needsRebind(c, v) then
				item:setCustomAttribute(c.attr.lock, K.bindLock(c))
				if item.sendUpdate then
					pcall(item.sendUpdate, item)
				end
				n = n + 1
			end
		end
		return false
	end)
	return n
end

-- into `container` (the kit backpack) or the inventory, else the inbox: "backpack" | "inbox" | nil
function PT.give(player, id, container)
	local item = PT.create(id)
	if not item then
		return nil
	end
	if container and container.addItemEx and container:addItemEx(item) == NOERR then
		return "backpack"
	end
	if player:addItemEx(item, false) == NOERR then
		return "backpack"
	end
	local inbox = player.getInbox and player:getInbox()
	if inbox and inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT or 1) == NOERR then
		return "inbox"
	end
	return nil
end

-- every Everfull potion the character does not have yet (the starter kit, the login grant); sets the grant flag.
-- Returns the number given.
function PT.giveAll(player, container)
	local c = PT.cfg()
	local n = 0
	for _, e in ipairs(c.everfull) do
		if PT.installed(e.id) and not PT.owned(player, e.id) and PT.give(player, e.id, container) then
			n = n + 1
		end
	end
	player:setStorageValue(c.storage.granted, 1)
	return n
end

-- the player's stored language (an NPC state never sees the client's hello; i18n_core.lua "NPC scripts")
local function say(player, text)
	if not (ChaosI18n and ChaosI18n.npcText) then
		pcall(dofile, "data/scripts/chaos/i18n_core.lua")
	end
	if ChaosI18n and ChaosI18n.npcText then
		local ok, t = pcall(ChaosI18n.npcText, player, text)
		if ok and type(t) == "string" then
			text = t
		end
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR or MESSAGE_STATUS_SMALL, text)
end

-- a potion seller's trade window sells an Everfull potion (ShopModule:callbackOnBuy hook, install_potions.py): one
-- store-bound copy whatever amount was asked, paid like any purchase. Returns true when sold.
function PT.npcBuy(cid, id)
	local player = Player(cid)
	if not player then
		return false
	end
	if not ChaosPay then
		dofile("data/lib/chaos_pay.lua")
	end
	local money = ChaosPay.total(player)
	local r = K.npcBuy(PT.cfg(), {id = id, owned = PT.owned(player, id), money = money})
	if not r.ok then
		if r.text then
			say(player, r.text)
		end
		return false
	end
	-- paid first (carried coins, then the bank); a potion that finds no room gives the gold back to the bank
	if not ChaosPay.pay(player, r.price) then
		say(player, "You do not have enough gold (carried and in the bank).")
		return false
	end
	local where = PT.give(player, id)
	if not where then
		if r.price > 0 then
			player:setBankBalance(player:getBankBalance() + r.price)
		end
		say(player, "You have no room for it.")
		return false
	end
	say(player, "It never runs out: drink it as often as the potion exhaust allows.")
	return true
end
