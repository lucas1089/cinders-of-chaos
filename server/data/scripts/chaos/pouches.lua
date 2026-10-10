-- Store pouches (README "Store pouches"): three containers sold in the store, each collecting its own kind of loot from
-- the corpses the character owns while the character carries it (in the backpack or a bag inside it).
--   Loot Pouch      the loot its rules pick (default: the items on the autoloot list, gold, uniques); settings window
--                   (client game_pouches, extended opcode ChaosOpcodes.pouches)
--   Orbs Pouch      orbs, whetstones, rune shards and gems
--   Rift Key Pouch  Rift Keys (with their tier and modifiers), Omen Keys and omen fragments
-- Rules: pouches_core.lua (tested by server/tests/pouches_test.lua). Tunables and item ids: pouches_config.lua; the
-- items are installed by server/tools/install_pouches.py.
--
-- onDropLoot (lower index first): 0 stock loot, 1 Chaos loot layer, 1.5 Echoing Spoils, 2 auto seller + rift key drop
-- + paragon gold, 2.4 hunt / achievements read, 2.45 pet fetch, 2.5 loot filter snapshot, 2.7 POUCHES, 3 base autoloot,
-- 3.5 Rarity Autoloot pickup, 4.5 loot filter finish. A pouch that is full (or too heavy to carry more) passes the item
-- on: the next pouch that wants it, then the backpack, else it stays in the corpse. Orbs and keys are never auto-sold
-- (autosell.lua asks ChaosPouches.neverSell).
--
-- Store-bound: one of each kind per character (the store refuses a second while one is in the inventory, the inbox
-- or a depot); only the owner's pouch collects (custom attribute chaos_pouch_owner). Every pouch has the custom
-- attributes chaos_storebound = 1 and chaos_locked = 1 (the item lock, engine patch 0009: NPCs do not buy it, trash
-- refuses it, the stock market does not list it). The trade window refuses it (onTradeRequest / onTradeAccept), and
-- Player:onMoveItem (hook written by install_pouches.py) keeps it, and any container holding it, in the character's
-- inventory or depot: no ground, no mailbox, no house, no other player's container. Player market: ChaosPouches.isPouch.
-- Death: the engine may drop the backpack into the corpse; the pouch is then taken out of the corpse (its contents stay
-- in the corpse, like the rest of the backpack) and given back, empty, at the next login.
-- The retired Bottomless Loot Pouch unlock (storage 7100100): its owners get a Loot Pouch for free once, at login.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
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

-- the item is a pouch or a container with a pouch somewhere inside
function PO.holdsPouch(item, depth)
	if not item then
		return false
	end
	if PO.isPouch(item) then
		return true
	end
	depth = depth or 0
	if depth > 8 or not item.isContainer or not item:isContainer() then
		return false
	end
	for _, inner in ipairs(item:getItems() or {}) do
		if PO.holdsPouch(inner, depth + 1) then
			return true
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

-- the pouches the character carries and owns: {[kind] = item}, the first one of each kind
function PO.carried(player)
	local guid, found = player:getGuid(), {}
	walk(inventoryRoots(player), function(item)
		local kind = PO.kindOfId(item:getId())
		if kind and not found[kind] and PO.ownerOf(item) == guid then
			found[kind] = item
		end
		return false
	end)
	return found
end

-- every place a character keeps things: inventory, inbox, the depot chest of every town
local function storageRoots(player)
	local roots = inventoryRoots(player)
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

-- puts one corpse item into the first carried pouch that wants it. Returns "pouch", kind | "full", kind | nil
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
	local kinds = P.route(info, PO.rulesOf(player), sets(), cfg())
	local parent = item:getParent()
	local where = stowInto(pouches, kinds, item, parent, {full = {}})
	return where == "pouch"
end

-- ---------------------------------------------------------------- onDropLoot (index cfg().dropIndex)
local lastFull = {} -- [guid .. kind] = os.time of the last "is full" note

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
	local taken, backpack, left = {}, 0, 0
	local notes = {full = {}}
	for _, item in ipairs(corpse:getItems() or {}) do
		local info = infoOf(item, list)
		local kinds = P.route(info, rules, s, c)
		local mine = false
		for _, kind in ipairs(kinds) do
			mine = mine or pouches[kind] ~= nil
		end
		if mine then
			-- rolled now: the engine's rarity pass only reaches items still in the corpse (loot.lua finalizeRarity)
			if info.category == "equipment" and ChaosLoot and ChaosLoot.finalizeRarity then
				item = ChaosLoot.finalizeRarity(item)
			end
			local where, kind = stowInto(pouches, kinds, item, corpse, notes)
			if where == "pouch" then
				taken[kind] = (taken[kind] or 0) + info.count
			elseif intoBags(owner, item) and not stillIn(item, corpse) then
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
	local text = P.summary(c, taken, backpack, left, notes.full)
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
		player:sendCancelMessage("Store pouches cannot be traded.")
		return false
	end
	return true
end
trade:register(1)

local accept = EventCallback
accept.onTradeAccept = function(player, target, item, targetItem)
	if PO.holdsPouch(item) or PO.holdsPouch(targetItem) then
		player:sendCancelMessage("Store pouches cannot be traded.")
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
		return "You already have a " .. k.title .. " (backpack, inbox or depot). One per character."
	end
	local bits = math.max(0, player:getStorageValue(cfg().storage.regrant))
	if math.floor(bits / KIND_BIT[kind]) % 2 == 1 then
		return "Your " .. k.title .. " comes back at your next login."
	end
	return nil
end

function PO.storeGive(player, kind, why)
	local k = cfg().kinds[kind]
	local where = PO.give(player, kind)
	if not where then
		return "Something went wrong. Your coins were refunded."
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s: your %s is in your %s. It collects %s while you " ..
		"carry it.", why or "Store", k.title, where, k.collects))
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
	player:registerEvent("ChaosPouchesExtended")
	local c = cfg()
	local ok, err = pcall(function()
		-- former owners of the retired Bottomless Loot Pouch unlock: a Loot Pouch, once
		if player:getStorageValue(c.legacyUnlock) > 0 and player:getStorageValue(c.storage.legacyGrant) < 1
				and PO.installed("loot") then
			if PO.owned(player).loot then
				player:setStorageValue(c.storage.legacyGrant, 1)
			elseif PO.storeGive(player, "loot", "The Bottomless Loot Pouch is retired, a free Loot Pouch replaces it")
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
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Back after your death, empty: your %s (%s).",
					table.concat(back, ", "), where))
			end
		end
	end)
	if not ok then
		print("[Chaos pouches] login failed: " .. tostring(err))
	end
	return true
end
login:register()
