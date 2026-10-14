-- Store unlocks that work on monster loot (bought in the store, see shop_services.lua / shop_config.lua):
--
-- Auto Seller (storage Chaos.storage.shopAutoSeller; 1 bought, 2 lent by an active Chaos Pact): items on the
--   character's auto-sell list are taken out of the corpses the character owns and sold at once at the NPC price
--   (ChaosItemPrices.sellPrice(item, count), chaos_item_prices.lua: a rolled copy of a higher rarity or item level sells
--   for more; else the plain table sell_prices.lua, written by tools/gen_item_prices.py); the gold goes into the bank.
--   The list is separate from the autoloot list, so an item does not need an autoloot slot. Items with a rarity are
--   sold only for the rarities the player ticked (owner 2026-10-13: "Deixe o jogador configurar o autosell por
--   raridade"; Common and Uncommon by default, autosell_core.lua TIERS);
--   uniques are never sold, nor items with a custom name, description or text.
--   Never sold: what the store pouches collect (orbs, whetstones, rune shards, gems, Rift Keys, omen items;
--   ChaosPouches.neverSell, pouches.lua), even when such an item is on the list.
--   Selling the Loot Bag: everything in the carried Loot Bag at the NPC prices, gold to the bank, at most every 30 s
--   (owner 2026-10-13: "vende tudo dentro da loot bag e pode ser usado a cada 30s"; rules in autosell_core.lua).
--   Never: locked items (the item lock), uniques, orbs / gems / keys, containers (their contents are sold), items no NPC
--   buys, rarities the player keeps. Gold, platinum and crystal coins in the bag go to the bank as they are.
-- No chat or Info & Services command (owner 2026-10-13: "Tire os comandos do autosell e coloque no topmenu"): the
-- client's Auto Seller window (Economy > Auto Seller, module game_pouches) talks to A.handleAction through the pouches
-- opcode 226 (pouches.lua): as_open | as_sync | sell | asrar {tier, on} | aslist {op = add|remove|clear, item} |
-- aspause {on}; the answer is the window state `autoseller` (A.state).
-- (The Bottomless Loot Pouch unlock that used to live here is retired: pouches.lua.)
--
-- An EventCallback.onDropLoot, around the callbacks that already exist (lower index runs first):
--   0 stock loot, 1 Chaos loot layer (loot.lua), 2 AUTO SELLER, 2.7 store pouches (pouches.lua), 3 base autoloot.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

dofile("data/scripts/chaos/autosell_core.lua")
local ST = Chaos.storage
local AK = ChaosAutoSellCore
local S = ChaosShopServices -- pure helpers (shop_services.lua); looked up again at run time if nil at load
local SLOTS = Chaos.shopServices.autosellSlots
local PRICES = dofile("data/scripts/chaos/sell_prices.lua")
local CUSTOM = 2147483648 -- ITEM_ATTRIBUTE_CUSTOM (1 << 31): not exported to Lua by the engine

local function services()
	S = S or ChaosShopServices
	return S
end

ChaosAutoSell = ChaosAutoSell or {}
local A = ChaosAutoSell
A.prices = PRICES

-- ------------------------------------------------------------------------ list in storages
local function readList(player)
	local list = {}
	for i = 1, SLOTS do
		local id = player:getStorageValue(ST.autosellBase + i)
		if id and id > 0 then
			list[#list + 1] = id
		end
	end
	return list
end

local function writeList(player, list)
	for i = 1, SLOTS do
		player:setStorageValue(ST.autosellBase + i, list[i] or -1)
	end
end

local function listSet(player)
	local set = {}
	for _, id in ipairs(readList(player)) do
		set[id] = true
	end
	return set
end

-- ------------------------------------------------------------------------ item checks
local function customAttr(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	return ok and v or nil
end

local function itemInfo(item)
	return {
		unique = customAttr(item, "chaos_unique") ~= nil,
		rarity = tonumber(customAttr(item, "rarity")) or 0,
		locked = (tonumber(customAttr(item, "chaos_locked")) or 0) ~= 0, -- the item lock (salvage.lua): never sold
		attributes = item:hasAttribute(ITEM_ATTRIBUTE_NAME) or item:hasAttribute(ITEM_ATTRIBUTE_DESCRIPTION)
			or item:hasAttribute(ITEM_ATTRIBUTE_TEXT) or item:hasAttribute(CUSTOM)
	}
end
A.itemInfo = itemInfo

-- ------------------------------------------------------------------------ auto seller (index 2)
local function autoSell(monster, corpse)
	if not corpse:getType():isContainer() then
		return
	end
	local owner = Player(corpse:getCorpseOwner())
	if not owner or owner:getStorageValue(ST.shopAutoSeller) < 1 or owner:getStorageValue(ST.autosellPaused) == 1 then
		return
	end
	local set = listSet(owner)
	if next(set) == nil then
		return
	end
	local allowRarity = AK.unpackTiers(owner:getStorageValue(ST.autosellRarity))
	local sold, total, kept, keptLocked = {}, 0, 0, 0
	for _, item in ipairs(corpse:getItems()) do
		local id = item:getId()
		local protected = ChaosPouches and ChaosPouches.neverSell and ChaosPouches.neverSell(id, item)
		if set[id] and not protected and not item:getType():isContainer() then
			local count = item:getCount()
			-- a rolled copy's own price (rarity, item level: chaos_item_prices.lua), else the plain table
			local gold = ChaosItemPrices and ChaosItemPrices.sellPrice(item, count) or services().sellPrice(id, count, PRICES)
			if gold > 0 then
				local blocked = services().sellBlocked(itemInfo(item), allowRarity)
				if blocked == "locked" then
					keptLocked = keptLocked + 1
				elseif blocked then
					kept = kept + 1 -- a rarity the player keeps, a unique or a custom name
				else
					local name = item:getType():getName()
					if item:remove() then
						total = total + gold
						sold[#sold + 1] = (count > 1 and (count .. "x ") or "") .. name
					end
				end
			end
		end
	end
	if total > 0 then
		owner:setBankBalance(owner:getBankBalance() + total)
		owner:sendTextMessage(MESSAGE_LOOT or MESSAGE_INFO_DESCR, string.format("Auto seller: sold %s for %d gold (to your bank).",
			table.concat(sold, ", "), total))
	end
	if kept > 0 then
		owner:sendTextMessage(MESSAGE_LOOT or MESSAGE_INFO_DESCR,
			"Auto seller: kept an item of a rarity you keep, a unique or a named item (Economy > Auto Seller).")
	end
	if keptLocked > 0 then
		owner:sendTextMessage(MESSAGE_LOOT or MESSAGE_INFO_DESCR, "Auto seller: kept a locked item.")
	end
end

local sellCb = EventCallback
sellCb.onDropLoot = function(self, corpse)
	local ok, err = pcall(autoSell, self, corpse)
	if not ok then
		print("[Chaos autosell] onDropLoot failed: " .. tostring(err))
	end
end
sellCb:register(2)

-- ------------------------------------------------------------------------ item lookup (the window's list)
local function lookup(text)
	local it = ItemType(text)
	if it and it:getId() ~= 0 then
		return it
	end
	local n = tonumber(text)
	if n then
		it = ItemType(n)
		if it and it:getId() ~= 0 then
			return it
		end
	end
	return nil
end

-- ------------------------------------------------------------------------ selling the Loot Bag (every 30 s)
A.lastBagSale = A.lastBagSale or {} -- guid -> os.time of the last sale (kept over a relog while the server runs)
A.lastSale = A.lastSale or {} -- guid -> {gold, count, at} of the last Loot Bag sale (the window shows it)

local function bagEntries(bag)
	local entries, queue, i = {}, {bag}, 1
	while i <= #queue and i < 400 do
		local c = queue[i]
		i = i + 1
		for _, item in ipairs(c:getItems() or {}) do
			local isContainer = item:isContainer()
			local info = itemInfo(item)
			local id = item:getId()
			entries[#entries + 1] = {ref = item, id = id, count = item:getCount(), container = isContainer,
				unique = info.unique, rarity = info.rarity, locked = info.locked, attributes = info.attributes,
				neverSell = ChaosPouches and ChaosPouches.neverSell and ChaosPouches.neverSell(id, item) or false,
				price = ChaosItemPrices and ChaosItemPrices.sellPrice(item, 1) or nil}
			if isContainer then
				queue[#queue + 1] = item
			end
		end
	end
	return entries
end

-- sells the carried Loot Bag's contents; returns the plan or nil, the reason
function A.sellBag(player)
	if player:getStorageValue(ST.shopAutoSeller) < 1 then
		return nil, "You need the Auto Seller from the store (Convenience) or an active Chaos Pact."
	end
	local guid = player:getGuid()
	local wait = AK.cooldownLeft(A.lastBagSale[guid], os.time(), AK.COOLDOWN)
	if wait > 0 then
		return nil, string.format("Auto Seller: ready again in %d s.", wait)
	end
	local bag = ChaosPouches and ChaosPouches.carried and ChaosPouches.carried(player).loot
	if not bag then
		return nil, "Auto Seller: carry your Loot Bag to sell what is in it."
	end
	local plan = AK.bagPlan(bagEntries(bag), PRICES, {tiers = AK.unpackTiers(player:getStorageValue(ST.autosellRarity))})
	A.lastBagSale[guid] = os.time()
	local total, n = 0, 0
	for _, s in ipairs(plan.sell) do
		if s.ref:remove() then
			total = total + s.gold
			if not s.coin then
				n = n + s.count
			end
		end
	end
	plan.gold = total
	A.lastSale[guid] = {gold = total, count = n, at = os.time()}
	if total > 0 then
		player:setBankBalance(player:getBankBalance() + total)
	end
	return plan
end

-- ------------------------------------------------------------------------ the Auto Seller window (opcode 226)
local NEEDS = "Needs the Auto Seller (Store > Convenience) or an active Chaos Pact."

-- the window state: unlocked, paused, the rarity tiers, the corpse list, the cooldown and the last Loot Bag sale
function A.state(player, notice)
	local guid = player:getGuid()
	local list = {}
	for _, id in ipairs(readList(player)) do
		local it = ItemType(id)
		list[#list + 1] = {id = id, name = it and it:getName() or tostring(id), price = PRICES[id] or 0}
	end
	return {
		unlocked = player:getStorageValue(ST.shopAutoSeller) >= 1,
		needs = NEEDS,
		paused = player:getStorageValue(ST.autosellPaused) == 1,
		tiers = AK.tierList(AK.unpackTiers(player:getStorageValue(ST.autosellRarity))),
		list = list, slots = SLOTS,
		cooldown = AK.cooldownLeft(A.lastBagSale[guid], os.time(), AK.COOLDOWN), cooldownMax = AK.COOLDOWN,
		last = A.lastSale[guid],
		notice = notice
	}
end

local function listChange(player, d)
	local op = type(d.op) == "string" and d.op or ""
	local list = readList(player)
	if op == "clear" then
		writeList(player, {})
		return "List cleared."
	end
	if op ~= "add" and op ~= "remove" then
		return "Unknown list change."
	end
	local text = type(d.item) == "string" and d.item:sub(1, 80) or (tonumber(d.item) and tostring(math.floor(d.item))) or ""
	local it = text ~= "" and lookup(text) or nil
	if not it then
		return "There is no item called " .. text .. "."
	end
	local id, index = it:getId(), nil
	for i, v in ipairs(list) do
		if v == id then
			index = i
		end
	end
	if op == "add" then
		if index then
			return it:getName() .. " is already on your list."
		elseif ChaosPouches and ChaosPouches.neverSell and ChaosPouches.neverSell(id) then
			return it:getName() .. " is never auto-sold (orbs, gems and keys are kept)."
		elseif (PRICES[id] or 0) <= 0 then
			return "No NPC buys " .. it:getName() .. ", so it cannot be auto-sold."
		elseif #list >= SLOTS then
			return "Your list is full (" .. SLOTS .. " items)."
		end
		list[#list + 1] = id
		writeList(player, list)
		return string.format("%s will be sold for %d gold each.", it:getName(), PRICES[id])
	end
	if not index then
		return it:getName() .. " is not on your list."
	end
	table.remove(list, index)
	writeList(player, list)
	return "Removed " .. it:getName() .. "."
end

-- one window action; returns the state to send back (nil: not an Auto Seller action)
function A.handleAction(player, action, data)
	local d = type(data) == "table" and data or {}
	if action == "as_open" or action == "as_sync" then
		local st = A.state(player)
		st.open = action == "as_open"
		return st
	end
	if action ~= "sell" and action ~= "asrar" and action ~= "aslist" and action ~= "aspause" then
		return nil
	end
	if player:getStorageValue(ST.shopAutoSeller) < 1 then
		return A.state(player, NEEDS)
	end
	if action == "sell" then
		local plan, why = A.sellBag(player)
		if plan then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, AK.saleText(plan))
			return A.state(player, AK.saleText(plan))
		end
		return A.state(player, why)
	elseif action == "asrar" then
		local tiers, why = AK.rarityChange(AK.unpackTiers(player:getStorageValue(ST.autosellRarity)), d)
		if not tiers then
			return A.state(player, "Rarities: " .. why .. ".")
		end
		player:setStorageValue(ST.autosellRarity, AK.packTiers(tiers))
		return A.state(player)
	elseif action == "aslist" then
		return A.state(player, listChange(player, d))
	end
	-- aspause {on = true}: corpse selling on; false: off
	if type(d.on) ~= "boolean" then
		return A.state(player, "Bad request.")
	end
	player:setStorageValue(ST.autosellPaused, d.on and 0 or 1)
	return A.state(player)
end
