-- Store pouches (README "Store pouches"): three containers sold in the store, each collecting its own kind of loot from
-- the corpses the character owns while the character carries it (in the backpack or a bag inside it).
--   Loot Bag      the loot its rules pick (default: the items on the autoloot list, gold, uniques); settings window
--                   (client game_pouches, extended opcode ChaosOpcodes.pouches)
--   Orbs Pouch      orbs, whetstones, rune shards and gems
--   Rift Key Pouch  Rift Keys (with their tier and modifiers), Omen Keys and omen fragments
-- Rules: pouches_core.lua (tested by server/tests/pouches_test.lua). Tunables and item ids: pouches_config.lua; the
-- items are installed by server/tools/install_pouches.py.
--
-- onDropLoot (lower index first): 0 stock loot, 1 Chaos loot layer, 1.5 Echoing Spoils, 2 auto seller + rift key drop
-- + paragon gold, 2.4 hunt / achievements read, 2.45 pet fetch, 2.5 loot filter snapshot, 2.7 POUCHES, 3 base autoloot,
-- 3.5 Rarity Autoloot pickup, 4.5 loot filter finish. Priority (pouches_core.lua plan): orbs, rune shards and gems go
-- to the Orbs Pouch, Rift Keys and omen items to the Rift Key Pouch, always before the Loot Bag. A full (or too
-- heavy) specialist pouch passes the item to the Loot Bag only with its "overflow" rule (default on), then to the
-- backpack, else it stays in the corpse. The same order holds for click-to-loot in the loot channel (PO.stow). Orbs
-- and keys are never auto-sold (autosell.lua asks ChaosPouches.neverSell).
--
-- Store-bound: one of each kind per character (the store refuses a second while one is in the inventory, the inbox
-- or a depot); only the owner's pouch collects (custom attribute chaos_pouch_owner). Every pouch has the custom
-- attributes chaos_storebound = 1 and chaos_locked = 1 (the item lock, engine patch 0009: NPCs do not buy it, trash
-- refuses it, the stock market does not list it). The trade window refuses it (onTradeRequest / onTradeAccept), and
-- Player:onMoveItem (hook written by install_pouches.py) keeps it, and any container holding it, in the character's
-- inventory or depot: no ground, no mailbox, no house, no other player's container. Player market: ChaosPouches.isPouch.
-- Death: death_keep.lua (hook in the base droploot.lua) takes the pouch out of a dropping backpack before it drops (its
-- contents drop with the backpack) and parks it in the inbox, back in the backpack at the next login; this works with
-- no corpse too (a death on water). The corpse search below is the fallback for a server without that hook.
-- The retired Bottomless Loot Pouch unlock (storage 7100100): its owners get a Loot Bag for free once, at login.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/pouches_core.lua")
dofile("data/scripts/chaos/pouches_config.lua")

ChaosPouches = ChaosPouches or {}
local PO = ChaosPouches
local P = ChaosPouchesCore
local OPCODE = ChaosOpcodes.pouches
local NOERR = RETURNVALUE_NOERROR or 0
local NOTPOSSIBLE = RETURNVALUE_NOTPOSSIBLE or 1
local CONTAINER_POS = CONTAINER_POSITION or 0xFFFF
local KIND_BIT = {loot = 1, orbs = 2, keys = 4}

local function cfg()
	return ChaosPouchesConfig
end

local function customAttr(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	if ok then
		return v
	end
	return nil
end

-- ---------------------------------------------------------------- items
function PO.kindOfId(id)
	return P.kindOfId(cfg(), id)
end

-- a store pouch (any copy of the three items, or anything marked store-bound); the player market asks this
function PO.isPouch(item)
	if not item then
		return false
	end
	local ok, id = pcall(function() return item:getId() end)
	if ok and PO.kindOfId(id) then
		return true
	end
	return customAttr(item, cfg().attr.storebound) ~= nil
end

-- the item is a pouch or a container with a pouch somewhere inside. Every nesting level is walked (a depth limit let a
-- pouch 9+ bags deep be traded or dropped); past HOLDS_BUDGET items the answer is true, so a huge pile is refused too.
local HOLDS_BUDGET = 4000
function PO.holdsPouch(item)
	if not item then
		return false
	end
	local queue, i = {item}, 1
	while queue[i] do
		if i > HOLDS_BUDGET then
			return true
		end
		local it = queue[i]
		i = i + 1
		if PO.isPouch(it) then
			return true
		end
		if it.isContainer and it:isContainer() then
			for _, inner in ipairs(it:getItems() or {}) do
				queue[#queue + 1] = inner
			end
		end
	end
	return false
end

function PO.ownerOf(item)
	return tonumber(customAttr(item, cfg().attr.owner))
end

function PO.installed(kind)
	local k = cfg().kinds[kind]
	local it = k and ItemType(k.id)
	return it ~= nil and it:getId() ~= 0 and it:isContainer()
end

-- the weightless pouches (the Loot Bag, pouches_config.lua `weightless`): engine src-patch 0038 keeps their contents
-- out of the holder's weight and capacity. Registered at load and again at a login (idempotent); an engine without the
-- patch has no Game.setWeightlessContainer and the bag weighs as before.
PO.weightless = PO.weightless or {}
function PO.registerWeightless()
	if not (Game and Game.setWeightlessContainer) then
		return 0
	end
	local n = 0
	for kind, k in pairs(cfg().kinds) do
		if k.weightless and not PO.weightless[k.id] and PO.installed(kind) and Game.setWeightlessContainer(k.id) then
			PO.weightless[k.id] = true
			n = n + 1
		end
	end
	return n
end
pcall(PO.registerWeightless)

function PO.create(player, kind)
	local c = cfg()
	local item = Game.createItem(c.kinds[kind].id, 1)
	if not item then
		return nil
	end
	item:setCustomAttribute(c.attr.owner, player:getGuid())
	item:setCustomAttribute(c.attr.kind, kind)
	item:setCustomAttribute(c.attr.storebound, 1)
	item:setCustomAttribute(c.attr.lock, 1)
	return item
end

-- a new pouch for the character: backpack, else inbox. Returns "backpack", "inbox" or nil.
function PO.give(player, kind)
	local item = PO.create(player, kind)
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

-- breadth first through the containers of `roots`; calls fn(item) for every item, stops when fn returns true
local function walk(roots, fn)
	local queue, i, seen = {}, 1, 0
	for _, r in ipairs(roots) do
		queue[#queue + 1] = r
	end
	while i <= #queue do
		local item = queue[i]
		i = i + 1
		if fn(item) then
			return true
		end
		if item:isContainer() and seen < cfg().scanLimit then
			seen = seen + 1
			for _, inner in ipairs(item:getItems() or {}) do
				queue[#queue + 1] = inner
			end
		end
	end
	return false
end

local function inventoryRoots(player)
	local roots = {}
	for slot = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 10 do
		local item = player:getSlotItem(slot)
		if item then
			roots[#roots + 1] = item
		end
	end
	return roots
end

-- the purse (the engine's store inbox), or nil
local function purseOf(player)
	if not player.getStoreInbox then
		return nil
	end
	local ok, purse = pcall(function() return player:getStoreInbox() end)
	return ok and purse or nil
end

-- the pouches the character carries and owns: {[kind] = item}, the first one of each kind. The inventory first (its
-- bags, breadth first), then the purse one level deep (coordinator 2026-10-16: a pouch the store just delivered
-- collects at once, without moving it to the backpack; a pouch inside a bag in the purse does not). Weight rules
-- are the engine's as for any carried container (the purse counts in the inventory weight).
function PO.carried(player)
	local guid, found = player:getGuid(), {}
	local function take(item)
		local kind = PO.kindOfId(item:getId())
		if kind and not found[kind] and PO.ownerOf(item) == guid then
			found[kind] = item
		end
		return false
	end
	walk(inventoryRoots(player), take)
	local purse = purseOf(player)
	if purse then
		local ok, items = pcall(function() return purse:getItems() end)
		for _, item in ipairs(ok and items or {}) do
			take(item)
		end
	end
	return found
end

-- every place a character keeps things: inventory, the purse (store inbox), inbox, the depot chest of every town
local function storageRoots(player)
	local roots = inventoryRoots(player)
	local purse = purseOf(player)
	if purse then
		roots[#roots + 1] = purse
	end
	local inbox = player:getInbox()
	if inbox then
		roots[#roots + 1] = inbox
	end
	local okT, towns = pcall(Game.getTowns)
	for _, town in ipairs(okT and towns or {}) do
		local ok, chest = pcall(function() return player:getDepotChest(town:getId(), false) end)
		if ok and chest then
			roots[#roots + 1] = chest
		end
	end
	return roots
end

-- the kinds this character has anywhere (inventory, inbox, depots): {[kind] = true}
function PO.owned(player)
	local guid, found = player:getGuid(), {}
	walk(storageRoots(player), function(item)
		local kind = PO.kindOfId(item:getId())
		if kind and PO.ownerOf(item) == guid then
			found[kind] = true
		end
		return false
	end)
	return found
end

-- ---------------------------------------------------------------- loot rules
function PO.rulesOf(player)
	return P.unpackRules(cfg(), player:getStorageValue(cfg().storage.lootRules))
end

local extraOrbs
local function sets()
	if not extraOrbs then
		extraOrbs = {}
		local lc = ChaosLootConfig
		for _, e in ipairs(lc and lc.currency and lc.currency.entries or {}) do
			if e.id then
				extraOrbs[#extraOrbs + 1] = e.id
			end
		end
		local fc = ChaosLootFilterConfig
		for _, id in ipairs(fc and fc.orbIds or {}) do
			extraOrbs[#extraOrbs + 1] = id
		end
	end
	return P.sets(cfg(), extraOrbs)
end

-- items the auto seller must never sell: everything the Orbs Pouch or the Rift Key Pouch collects
function PO.neverSell(id, item)
	local s, c = sets(), cfg()
	if s.orbs[id] or s.omens[id] then
		return true
	end
	if c.orbGems and ChaosGems and ChaosGems.isGem and ChaosGems.isGem(id) then
		return true
	end
	if id == c.riftKey.itemId and (not item or item:getActionId() == c.riftKey.actionId) then
		return true
	end
	return false
end

local function autolootSet(player)
	local limit = player:isPremium() and Chaos.autoloot.premiumLimit or Chaos.autoloot.freeLimit
	local set = {}
	for i = 1, limit do
		local id = player:getStorageValue(Chaos.storage.autolootBase + i)
		if id and id > 0 then
			set[id] = true
		end
	end
	return set
end

local function infoOf(item, list)
	local it = item:getType()
	local id = item:getId()
	local info = {id = id, actionId = item:getActionId(), count = item:getCount(), container = it:isContainer(),
		pouch = PO.kindOfId(id) ~= nil, onList = list[id] == true,
		gem = ChaosGems and ChaosGems.isGem and ChaosGems.isGem(id) or false}
	if ChaosLootFilter and ChaosLootFilter.itemInfo then
		local ok, li = pcall(ChaosLootFilter.itemInfo, item)
		if ok and li then
			info.category, info.rarity, info.unique = li.category, li.rarity, li.unique
		end
	end
	if not info.category then
		info.rarity = tonumber(customAttr(item, "rarity")) or 0
		info.unique = customAttr(item, "chaos_unique") ~= nil
		info.category = (info.unique or info.rarity > 0) and "equipment" or "other"
	end
	return info
end
PO.infoOf = infoOf

-- into the backpack and the bags inside it, capacity checked, never into an equipment slot (as the loot filter does)
local function intoBags(player, item)
	local bp = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bp or not bp:isContainer() then
		return false
	end
	local queue, i = {bp}, 1
	while i <= #queue and i <= 30 do
		local c = queue[i]
		i = i + 1
		if not PO.kindOfId(c:getId()) and item:moveTo(c, 0) then
			return true
		end
		for _, sub in ipairs(c:getItems() or {}) do
			if sub:isContainer() and not PO.kindOfId(sub:getId()) then
				queue[#queue + 1] = sub
			end
		end
	end
	return false
end

local function stillIn(item, container)
	local ok, parent = pcall(function() return item:getParent() end)
	if not ok or not parent then
		return false
	end
	local okC, cnt = pcall(function() return item:getCount() end)
	if not okC or (cnt or 0) <= 0 then
		return false
	end
	-- userdata of the same item compare equal (the engine's __eq)
	local okS, same = pcall(function() return parent == container end)
	return okS and same or false
end

local function isFull(pouch)
	local ok, full = pcall(function() return pouch:getSize() >= pouch:getCapacity() end)
	return ok and full
end

-- puts one corpse item into the first pouch of the plan (pouches_core.lua plan) that has room. Returns "pouch", kind | nil
local function stowInto(pouches, kinds, item, container, notes)
	for _, kind in ipairs(kinds) do
		local pouch = pouches[kind]
		if pouch then
			if item:moveTo(pouch, 0) and not stillIn(item, container) then
				return "pouch", kind
			end
			if isFull(pouch) then
				notes.full[kind] = true
			end
		end
	end
	return nil
end

-- click-to-loot of the loot channel (lootfilter.lua take): into the right pouch when one wants it. true when stowed.
function PO.stow(player, item)
	local pouches = PO.carried(player)
	if not next(pouches) then
		return false
	end
	local info = infoOf(item, autolootSet(player))
	local kinds = P.plan(info, PO.rulesOf(player), sets(), cfg(), pouches)
	local parent = item:getParent()
	local where = stowInto(pouches, kinds, item, parent, {full = {}})
	return where == "pouch"
end

-- ---------------------------------------------------------------- onDropLoot (index cfg().dropIndex)
local lastFull = {} -- [guid .. kind] = os.time of the last "is full" note

local function rarityName(r)
	local list = ChaosLootFilter and ChaosLootFilter.RARITY
	if list and list[r] and list[r].name then
		return list[r].name
	end
	local names = ChaosLootConfig and ChaosLootConfig.gear and ChaosLootConfig.gear.names
	return names and names[r] or nil
end

-- one row of the loot line (pouches_core.lua lootList), read before the move (a stack merged into a pouch is gone)
local function lootEntry(item, info)
	local okN, name = pcall(function() return item:getName() end)
	local okT, it = pcall(function() return item:getType() end)
	local plural
	if okT and it and it.getPluralName then
		local okP, pn = pcall(function() return it:getPluralName() end)
		plural = okP and pn or nil
	end
	local stackable = okT and it and it.isStackable and it:isStackable()
	local rarity = tonumber(info.rarity) or 0
	return {id = info.id, name = okN and name or nil, plural = plural, count = stackable and info.count or 1,
		rarity = rarity, rarityName = rarity > 0 and rarityName(rarity) or nil, unique = info.unique and true or false}
end

local function collect(monster, corpse)
	if not corpse:getType():isContainer() then
		return
	end
	local owner = Player(corpse:getCorpseOwner())
	if not owner then
		return
	end
	local pouches = PO.carried(owner)
	if not next(pouches) then
		return
	end
	local c = cfg()
	local rules, list, s = PO.rulesOf(owner), autolootSet(owner), sets()
	local looted, backpack, left, overflow = {}, 0, 0, 0
	local notes = {full = {}}
	for _, item in ipairs(corpse:getItems() or {}) do
		local info = infoOf(item, list)
		local kinds, spilled = P.plan(info, rules, s, c, pouches)
		if #kinds > 0 then
			-- rolled now: the engine's rarity pass only reaches items still in the corpse (loot.lua finalizeRarity)
			if info.category == "equipment" and ChaosLoot and ChaosLoot.finalizeRarity then
				item = ChaosLoot.finalizeRarity(item)
			end
			local entry = lootEntry(item, info)
			local where, kind = stowInto(pouches, kinds, item, corpse, notes)
			if where == "pouch" then
				looted[#looted + 1] = entry
				if spilled and kind == "loot" then
					overflow = overflow + info.count
				end
			elseif intoBags(owner, item) and not stillIn(item, corpse) then
				looted[#looted + 1] = entry
				backpack = backpack + 1
			else
				left = left + 1
			end
		end
	end
	local now, guid = os.time(), owner:getGuid()
	for kind in pairs(notes.full) do
		local key = guid .. kind
		if now - (lastFull[key] or 0) < c.fullNoticeSeconds then
			notes.full[kind] = nil
		else
			lastFull[key] = now
		end
	end
	local text = P.summary(c, looted, backpack, left, notes.full, overflow)
	if text then
		owner:sendTextMessage(MESSAGE_LOOT or MESSAGE_INFO_DESCR, text)
	end
end

local dropCb = EventCallback
dropCb.onDropLoot = function(self, corpse)
	local ok, err = pcall(collect, self, corpse)
	if not ok then
		print("[Chaos pouches] onDropLoot failed: " .. tostring(err))
	end
end
dropCb:register(cfg().dropIndex)

-- ---------------------------------------------------------------- moves, trade
local function isPlayerCyl(c)
	local ok, v = pcall(function() return c.isPlayer and c:isPlayer() end)
	return ok and v
end

local function isItemCyl(c)
	local ok, v = pcall(function() return c.isItem and c:isItem() end)
	return ok and v
end

local function chainOf(player, toPosition, toCylinder)
	local depot = {}
	for _, id in ipairs(cfg().depotIds) do
		depot[id] = true
	end
	local c = toCylinder
	if (not c or type(c) == "boolean") and toPosition.x == CONTAINER_POS then
		if toPosition.y < 0x40 then
			return {"self"}
		end
		c = player:getContainerById(toPosition.y - 0x40)
	end
	local out, n = {}, 0
	while c and type(c) ~= "boolean" and n < 30 do
		n = n + 1
		if isPlayerCyl(c) then
			out[#out + 1] = c:getId() == player:getId() and "self" or "player"
			break
		elseif isItemCyl(c) then
			local id = c:getId()
			out[#out + 1] = depot[id] and "depot" or (PO.kindOfId(id) and "pouch") or "item"
			c = c:getParent()
		else
			out[#out + 1] = "tile"
			break
		end
	end
	if #out == 0 then
		out[1] = "tile"
	end
	return out
end

-- called first in Player:onMoveItem (data/events/scripts/player.lua, hook written by install_pouches.py); a script
-- callback could not refuse a move reliably (only the last onMoveItem callback's value counts). Returns a RETURNVALUE.
function PO.onMoveItem(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if not item or not PO.holdsPouch(item) then
		return NOERR
	end
	local m = {holdsPouch = true, toGround = toPosition.x ~= CONTAINER_POS}
	if not m.toGround then
		m.chain = chainOf(player, toPosition, toCylinder)
	end
	local why = P.moveRefusal(m)
	if why then
		-- a warning line: the engine's own "Sorry, not possible." replaces a cancel message
		player:sendTextMessage(MESSAGE_STATUS_WARNING or MESSAGE_INFO_DESCR, why)
		return NOTPOSSIBLE
	end
	return NOERR
end

local trade = EventCallback
trade.onTradeRequest = function(player, target, item)
	if PO.holdsPouch(item) then
		player:sendCancelMessage(Chaos.t(player, "Store items cannot be traded."))
		return false
	end
	return true
end
trade:register(1)

local accept = EventCallback
accept.onTradeAccept = function(player, target, item, targetItem)
	if PO.holdsPouch(item) or PO.holdsPouch(targetItem) then
		player:sendCancelMessage(Chaos.t(player, "Store items cannot be traded."))
		return false
	end
	return true
end
accept:register(1)

-- ---------------------------------------------------------------- death
-- the engine dropped a backpack with a pouch into the corpse: the pouch leaves the corpse (its contents stay), and
-- the character gets it back empty at the next login (the character is saved and offline by now: a storage bit is
-- written to the database)
local function markRegrant(guid, bit)
	local key = cfg().storage.regrant
	db.query(string.format("INSERT INTO `player_storage` (`player_id`, `key`, `value`) VALUES (%d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `value` = GREATEST(`value`, 0) | %d", guid, key, bit, bit))
end

function PO.afterDeath(guid, pos)
	local tile = Tile(Position(pos.x, pos.y, pos.z))
	if not tile then
		return
	end
	local found = {}
	for _, top in ipairs(tile:getItems() or {}) do
		if top:isContainer() then
			walk({top}, function(item)
				if PO.kindOfId(item:getId()) and PO.ownerOf(item) == guid then
					found[#found + 1] = {pouch = item, top = top}
				end
				return false
			end)
		end
	end
	for _, f in ipairs(found) do
		local kind = PO.kindOfId(f.pouch:getId())
		for _, inner in ipairs(f.pouch:getItems() or {}) do
			inner:moveTo(f.top) -- contents stay in the corpse (no limit: the corpse may grow past its size)
		end
		f.pouch:remove()
		local online = Player(guid)
		if online then
			PO.give(online, kind)
		else
			markRegrant(guid, KIND_BIT[kind])
		end
	end
end

local death = CreatureEvent("ChaosPouchDeath")
function death.onDeath(player, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local pos = corpse and corpse.getPosition and corpse:getPosition() or player:getPosition()
	local guid = player:getGuid()
	addEvent(function()
		local ok, err = pcall(PO.afterDeath, guid, {x = pos.x, y = pos.y, z = pos.z})
		if not ok then
			print("[Chaos pouches] death check failed: " .. tostring(err))
		end
	end, 0)
	return true
end
death:register()

-- ---------------------------------------------------------------- store
function PO.storeCheck(player, kind)
	local k = cfg().kinds[kind or ""]
	if not k then
		return "This offer cannot be bought."
	end
	if not PO.installed(kind) then
		return "The " .. k.title .. " is not installed on this server yet."
	end
	if PO.owned(player)[kind] then
		return "You already have a " .. k.title .. " (backpack, purse, inbox or depot). One per character."
	end
	local bits = math.max(0, player:getStorageValue(cfg().storage.regrant))
	if math.floor(bits / KIND_BIT[kind]) % 2 == 1 then
		return "Your " .. k.title .. " comes back at your next login."
	end
	return nil
end

-- a bought pouch goes into the purse (store_delivery.lua: purse, else depot inbox, else backpack); it collects in the
-- purse and in the backpack (PO.carried), not in the depot inbox
function PO.storeGive(player, kind, why)
	local k = cfg().kinds[kind]
	local item = PO.create(player, kind)
	if not item then
		return "Something went wrong. Your coins were refunded."
	end
	local D = ChaosStoreDelivery or dofile("data/scripts/chaos/store_delivery.lua")
	local where = D.place(player, item)
	if not where then
		pcall(function() item:remove() end)
		return "Something went wrong. Your coins were refunded."
	end
	if where == "inbox" then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
			"%s: your %s is in your %s. Move it to your backpack: it collects %s while you carry it.",
			Chaos.t(player, why or "Store"), k.title, Chaos.t(player, "depot inbox"), Chaos.t(player, k.collects)))
	else
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
			"%s: your %s is in your %s. It collects %s from now on, there or in your backpack.",
			Chaos.t(player, why or "Store"), k.title, Chaos.t(player, where), Chaos.t(player, k.collects)))
	end
	return true
end

-- ---------------------------------------------------------------- tooltip (item_tooltip_core.lua)
-- returns the store line and the "collects" line of a pouch, or nil
function PO.tooltipLines(item)
	local kind = item and PO.kindOfId(item:getId())
	if not kind then
		return nil
	end
	return "Store item: cannot be traded", "Auto-collects " .. cfg().kinds[kind].collects .. " while you carry it."
end

-- ---------------------------------------------------------------- settings window (client game_pouches)
local function sendSettings(player, open)
	local c = cfg()
	local ids, titles = {}, {}
	for kind, k in pairs(c.kinds) do
		local it = ItemType(k.id)
		ids[kind] = it and it:getId() ~= 0 and it:getClientId() or 0
		titles[kind] = k.title
	end
	local rarities = {}
	for i, r in ipairs(ChaosLootFilter and ChaosLootFilter.RARITY or {}) do
		rarities[i] = r.name
	end
	Chaos.send(player, OPCODE, "settings", {rules = PO.rulesOf(player), ids = ids, titles = titles,
		owned = open and PO.owned(player) or nil, rarities = rarities, open = open and true or false})
end
PO.sendSettings = sendSettings

-- actions of the Auto Seller window, handled by autosell.lua (ChaosAutoSell.handleAction)
PO.AUTOSELL_ACTIONS = {as_open = true, as_sync = true, sell = true, asrar = true, aslist = true, aspause = true}

local ext = CreatureEvent("ChaosPouchesExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	if msg.action == "open" or msg.action == "sync" then
		if not ChaosRateLimit or ChaosRateLimit.allow(player, "pouches.open", 300) then
			sendSettings(player, msg.action == "open")
		end
	elseif msg.action == "set" then
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "pouches.set", 200) then
			return
		end
		local d = type(msg.data) == "table" and msg.data or {}
		local rules = P.sanitizeRules(cfg(), d.rules)
		player:setStorageValue(cfg().storage.lootRules, P.packRules(rules))
		sendSettings(player, false)
	elseif PO.AUTOSELL_ACTIONS[msg.action] then
		-- the Auto Seller window (client game_pouches autoseller.lua; Economy > Auto Seller): autosell.lua validates and
		-- answers with the window state; selling the Loot Bag has its own 30 s cooldown there
		if ChaosAutoSell and ChaosAutoSell.handleAction
				and (not ChaosRateLimit or ChaosRateLimit.allow(player, "pouches.autosell", 250)) then
			local state = ChaosAutoSell.handleAction(player, msg.action, msg.data)
			if state then
				Chaos.send(player, OPCODE, "autoseller", state)
			end
		end
	end
end
ext:register()

-- ---------------------------------------------------------------- login: free pouches
local function setBits(player, key, bits)
	player:setStorageValue(key, bits > 0 and bits or 0)
end

local login = CreatureEvent("ChaosPouchesLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPouchDeath")
	pcall(PO.registerWeightless)
	player:registerEvent("ChaosPouchesExtended")
	local c = cfg()
	local ok, err = pcall(function()
		-- former owners of the retired Bottomless Loot Pouch unlock: a Loot Bag, once
		if player:getStorageValue(c.legacyUnlock) > 0 and player:getStorageValue(c.storage.legacyGrant) < 1
				and PO.installed("loot") then
			if PO.owned(player).loot then
				player:setStorageValue(c.storage.legacyGrant, 1)
			elseif PO.storeGive(player, "loot", "The Bottomless Loot Pouch is retired, a free Loot Bag replaces it")
					== true then
				player:setStorageValue(c.storage.legacyGrant, 1)
			end
		end
		-- pouches lost with a dropped backpack
		local bits = math.max(0, player:getStorageValue(c.storage.regrant))
		if bits > 0 then
			local owned, back, where = PO.owned(player), {}, nil
			for _, kind in ipairs(c.order) do
				local bit = KIND_BIT[kind]
				if math.floor(bits / bit) % 2 == 1 and PO.installed(kind) then
					local w = not owned[kind] and PO.give(player, kind) or nil
					if owned[kind] or w then
						bits = bits - bit
					end
					if w then
						back[#back + 1] = c.kinds[kind].title
						where = (where == nil or where == w) and w or "backpack and inbox"
					end
				end
			end
			setBits(player, c.storage.regrant, bits)
			if #back > 0 then
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Back after your death, empty: your %s (%s).",
					table.concat(back, ", "), Chaos.t(player, where)))
			end
		end
	end)
	if not ok then
		print("[Chaos pouches] login failed: " .. tostring(err))
	end
	return true
end
login:register()
