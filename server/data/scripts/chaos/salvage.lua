-- Salvage (the crafting bench's Salvage mode; client game_crafting, extended opcode ChaosOpcodes.crafting 232).
-- Rolled gear (an item with a rarity) is broken down into Rune Shards (a new stackable item, server/tools/install_salvage.py),
-- with a small chance of a whole orb; shards combine into the existing orbs at the bench. The item lock (custom attribute
-- `chaos_locked`, the bench's Lock button) keeps an item away from salvage and from the Auto Seller (autosell.lua).
-- Numbers: salvage_config.lua; pure logic: salvage_core.lua (tests: server/tests/salvage_test.lua); server/README.md "Salvage".
--
-- Protocol, on top of crafting.lua's (JSON {action, data}); crafting.lua hands these actions here:
--   client -> server  salvage {path, id, sig}                  salvage the item on the bench
--                     lock {path, id, on}                      lock / unlock an item (gear or a Rift Key)
--                     lockAt {pos = {x, y, z}, cid, on}        the same from the game's item right-click menu: pos is the
--                                                              client position (inventory slot {0xFFFF, slot, 0} or open
--                                                              container {0xFFFF, 0x40 + id, slot}), cid the client id,
--                                                              on absent = flip. Own inventory / containers only, gear
--                                                              or a Rift Key; answered with a text message
--                     salvageScope {bag, maxRarity, mode}      the "salvage all" container and rarity, the bench mode
--                                                              ("orbs" | "salvage"); answered with the state
--                     salvageBatch {bag, maxRarity, sig}       salvage what the last preview listed (sig must match)
--                     combine {key, count}                     shards -> orbs (key: a rune shard recipe, an orb key, or a
--                                                              cfg.shardRecipes key: Ember / Crown Shards -> their orb)
--                     recycle {key, count}                     orbs -> shards (cfg.recycleShare of the recipe cost)
--   server -> client  state.salvage = {installed, shardId, shardClientId, shardName, shardSingular, shards, rarityNames, rarityIds,
--                                      recipes = [{key, name, id, clientId, cost, count, back,
--                                                  input, inputName, inputSingular, have}] (input.. / have only on a
--                                                  shard recipe: the item it eats and how many the player has),
--                                      bags = [{path, name, clientId}],
--                                      batch = {bag, maxRarity, count, shards, orbs, capped, cap, skipped, sig, paths},
--                                      mode}
--                     state.items[i].locked, state.item.locked, state.item.salvage = {ok, why, shards, orbChance}
--                     result {ok, orb = "salvage", text}
-- Salvage all also offers the Loot Bag (bag key "loot", paths "loot.N"): the store pouch lives in the purse, out of reach
-- of the backpack paths, and its direct contents are salvaged like a bag's.
-- Server checks: the item is found by path + id (+ signature) in the player's own backpack tree, never equipped, never
-- the ground; locked / unique / socketed gems / no rarity are refused; one action per singleIntervalMs, a batch per
-- batchIntervalMs and at most batchCap items. Every salvaged item is a row in chaos_crafting_log (orb = "Salvage").
-- Lua 5.1 / LuaJIT compatible.

if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua")
end
dofile("data/scripts/chaos/salvage_core.lua")

ChaosSalvageConfig = dofile("data/scripts/chaos/salvage_config.lua")
ChaosSalvage = ChaosSalvage or {}
local S = ChaosSalvage
local K = ChaosSalvageCore
local cfg = ChaosSalvageConfig
local C = ChaosCrafting
local OPCODE = ChaosOpcodes.crafting or 232
local LOCK = cfg.lockAttr

S.config = cfg
S.actions = {salvage = true, lock = true, lockAt = true, salvageScope = true, salvageBatch = true, combine = true, recycle = true}

local scope = {} -- player id -> {bag, maxRarity, mode}
local last = {} -- player id -> {single, batch, combine} time in ms

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function bench()
	return ChaosCraftingBench
end

local function custom(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	return ok and v or nil
end

local function num(v)
	if type(v) == "userdata" or type(v) == "table" then
		local ok, n = pcall(function() return v.value end)
		v = ok and n or nil
	end
	return tonumber(v)
end

-- ---------------------------------------------------------------- the lock (used by autosell.lua too)
function S.isLocked(item)
	if not item then
		return false
	end
	local v = custom(item, LOCK)
	return K.isLocked(num(v) or v)
end

function S.setLocked(item, on)
	if on then
		item:setCustomAttribute(LOCK, 1)
	else
		pcall(function() item:removeCustomAttribute(LOCK) end)
	end
	-- engine patch 0003 sends "chaos_locked" in the item packets (key 3): show the change at once
	if ChaosItemMods and ChaosItemMods.sendUpdate then
		ChaosItemMods.sendUpdate(item)
	end
end

-- an orb that makes a new copy of the item keeps the lock (chaos_crafting.lua C.recreate calls this)
function S.copyLock(from, to)
	if S.isLocked(from) then
		S.setLocked(to, true)
	end
end

-- ---------------------------------------------------------------- items
local function shardInstalled()
	local ok, id = pcall(function() return ItemType(cfg.shard.id):getId() end)
	return ok and id == cfg.shard.id
end

local function isStackable(item)
	local ok, v = pcall(function() return item:getType():isStackable() end)
	return ok and v or false
end

-- the Conquest Tokens a unique gives when salvaged (conquest.lua; nil when it is no unique or tokens are off)
function S.uniqueTokens(item)
	local CQ = ChaosConquest
	if not cfg.uniqueTokens or not CQ or not CQ.offerOf or not CQ.cfg or not C.isUnique(item) then
		return nil
	end
	local o = CQ.offerOf(item:getId())
	return o and ChaosConquestCore.salvageTokens(CQ.cfg, o.price) or nil
end

-- the Loot Bag (store pouch) the character carries, or nil. It lives in the purse, outside the main backpack, so the
-- bench's backpack paths never reach it: the batch addresses it by the bag key LOOT_BAG instead.
local LOOT_BAG = "loot"
local function lootBagOf(player)
	local PO = ChaosPouches
	if not (PO and PO.carried) then
		return nil
	end
	local ok, found = pcall(PO.carried, player)
	local bag = ok and found and found.loot or nil
	if bag and bag:isContainer() then
		return bag
	end
	return nil
end

-- the item hangs in the backpack (or a bag in it) or directly in the carried Loot Bag: salvage may take it
function S.inScope(player, item)
	local b = bench()
	if b and b.inBackpack(player, item) then
		return true
	end
	local bag = lootBagOf(player)
	if bag then
		local ok, parent = pcall(function() return item:getParent() end)
		return ok and parent == bag or false
	end
	return false
end

-- the info table of salvage_core.lua for an engine item
function S.infoOf(player, item)
	local s = ChaosGems and ChaosGems.read(item) or {count = 0, filled = 0}
	local high = 0
	for _, m in ipairs(C.readMods(item)) do
		if m.tier >= (cfg.highTier or 6) then
			high = high + 1
		end
	end
	local b = bench()
	local inBackpack
	if player and b then
		inBackpack = S.inScope(player, item)
	end
	return {
		gear = C.isGear(item),
		riftKey = C.isRiftKey(item),
		rarity = C.rarityOf(item),
		level = C.levelOf(item),
		unique = C.isUnique(item),
		setPiece = ChaosItemSets and ChaosItemSets.pieceOf and ChaosItemSets.pieceOf(item) ~= nil or nil, -- itemsets.lua
		tokens = S.uniqueTokens(item), -- conquest.lua: a unique gives Conquest Tokens
		sockets = s.count or 0,
		gems = s.filled or 0,
		highTiers = high,
		locked = S.isLocked(item),
		stackable = isStackable(item),
		inBackpack = inBackpack
	}
end

local function clientIdOf(id)
	local ok, cid = pcall(function() return ItemType(id):getClientId() end)
	return ok and cid or id
end

-- give `count` of item `id`: backpack, else the inbox, else the floor under the player; returns where the rest went
local function give(player, id, count)
	local inbox = 0
	while count > 0 do
		local n = math.min(count, 100)
		local item = Game.createItem(id, n)
		if not item then
			return false
		end
		if player:addItemEx(item, false) ~= RETURNVALUE_NOERROR then
			local box = player:getInbox()
			if box and box:addItemEx(item, INDEX_WHEREEVER, FLAG_NOLIMIT) == RETURNVALUE_NOERROR then
				inbox = inbox + n
			else
				player:addItemEx(item, true)
			end
		end
		count = count - n
	end
	return true, inbox
end

local function logRows(player, rows)
	if #rows == 0 then
		return
	end
	local values = {}
	local t, guid = os.time(), player:getGuid()
	for _, r in ipairs(rows) do
		values[#values + 1] = string.format("(%d, %d, %s, %s, %s)", guid, t, db.escapeString(r.orb or cfg.logName),
			db.escapeString((r.item or ""):sub(1, 80)), db.escapeString((r.text or ""):sub(1, 255)))
	end
	db.query(string.format("INSERT INTO `%s` (`player_id`, `created_at`, `orb`, `item`, `result`) VALUES %s",
		C.config.historyTable, table.concat(values, ", ")))
end

-- the shard recipe's input item exists on this server (the base item, renamed by install_orbs.py)
local function itemExists(id)
	local ok, got = pcall(function() return ItemType(id):getId() end)
	return ok and got == id
end

-- the line under an Ember / Crown Shard's look text and tooltip (item_tooltip_core.lua asks for it); nil for other items
function S.shardHint(id)
	local r = K.inputRecipe(id, cfg)
	local orb = r and C.orbByKey[r.orb]
	if not orb then
		return nil
	end
	return K.shardHint(r, orb.name)
end

local function orbName(key)
	local orb = C.orbByKey[key]
	return orb and orb.name or key
end

-- player: the language of the line (nil: English, for the bench history)
local function rowText(info, roll, player)
	local kind
	if info.setPiece then
		kind = Chaos.t(player, "Set piece")
	elseif info.unique then
		kind = Chaos.t(player, "Unique")
	else
		kind = C.rarityName(info.rarity)
		if player and Chaos.lang(player) == "pt-BR" and ChaosRarity.namePt then
			kind = ChaosRarity.namePt(info.rarity) or kind
		end
	end
	local text = Chaos.t(player, "%s (level %d): %d %s", kind, info.level, roll.shards,
		roll.shards == 1 and cfg.shard.name or cfg.shard.plural)
	if roll.orb then
		text = text .. " + 1 " .. orbName(roll.orb)
	end
	if roll.tokens then
		text = text .. Chaos.t(player, " + %d Conquest Tokens", roll.tokens)
	end
	return text
end

-- break one checked item: remove it, return the roll (the caller gives the shards and orbs)
local function breakItem(item, info)
	local roll = K.roll(info, cfg, function(a, b) return math.random(a, b) end)
	local name = C.itemName(item)
	if not item:remove() then
		return nil
	end
	return roll, name
end

local function giveRolls(player, shards, orbs)
	local inbox = 0
	if shards > 0 then
		local _, n = give(player, cfg.shard.id, shards)
		inbox = inbox + (n or 0)
	end
	for key, n in pairs(orbs) do
		local orb = C.orbByKey[key]
		if orb then
			local _, m = give(player, orb.id, n)
			inbox = inbox + (m or 0)
		end
	end
	return inbox
end

-- ---------------------------------------------------------------- the batch (direct contents of one container)
local function containerAt(player, bag)
	local b = bench()
	if bag == nil or bag == "" then
		return b.backpackOf(player)
	end
	if bag == LOOT_BAG then
		return lootBagOf(player)
	end
	local c = b.itemAt(player, bag)
	if c and c:isContainer() then
		return c
	end
	return nil
end

local function bagList(player)
	local b = bench()
	local bp = b.backpackOf(player)
	local out = {}
	if not bp then
		return out
	end
	out[1] = {path = "", name = "Main backpack", clientId = clientIdOf(bp:getId())}
	-- the Loot Bag first after the main backpack (owner feedback 2026-10-28: salvage straight from it)
	local loot = lootBagOf(player)
	if loot then
		out[2] = {path = LOOT_BAG, name = Chaos.t(player, "Loot Bag"), clientId = clientIdOf(loot:getId())}
	end
	b.walk(player, function(item, path)
		if #out < 16 and item:isContainer() and item ~= loot then
			out[#out + 1] = {path = path, name = C.itemName(item), clientId = clientIdOf(item:getId())}
		end
	end)
	return out
end

-- {result of K.batch, items = {engine items}, infos, paths, sig}
local function batchOf(player, bag, maxRarity)
	local container = containerAt(player, bag)
	if not container then
		return nil
	end
	local items, infos, paths = {}, {}, {}
	for i = 0, container:getSize() - 1 do
		local item = container:getItem(i)
		if item and not item:isContainer() then
			items[#items + 1] = item
			infos[#infos + 1] = S.infoOf(player, item)
			paths[#paths + 1] = (bag == nil or bag == "") and tostring(i) or (bag .. "." .. i) -- "loot.N": the Loot Bag
		end
	end
	local res = K.batch(infos, maxRarity, cfg)
	local keys, pickedPaths = {}, {}
	for _, i in ipairs(res.picked) do
		keys[#keys + 1] = paths[i] .. ":" .. C.signature(items[i])
		pickedPaths[#pickedPaths + 1] = paths[i]
	end
	res.sig = K.signature(keys)
	res.items, res.infos, res.paths = items, infos, pickedPaths
	return res
end

local function scopeOf(player)
	local s = scope[player:getId()]
	if not s then
		s = {bag = "", maxRarity = cfg.batchDefaultMaxRarity, mode = "orbs"}
		scope[player:getId()] = s
	end
	return s
end

-- ---------------------------------------------------------------- bench state (crafting.lua sendState calls this)
function S.benchState(player, data)
	local b = bench()
	if not b then
		return
	end
	local sc = scopeOf(player)
	-- lock marks on the grid
	for _, row in ipairs(data.items or {}) do
		local item = b.itemAt(player, row.path)
		if item and S.isLocked(item) then
			row.locked = true
		end
	end
	if data.item and data.item.path then
		local item = b.itemAt(player, data.item.path)
		if item then
			local info = S.infoOf(player, item)
			data.item.locked = info.locked or nil
			data.item.salvage = K.preview(info, cfg)
		end
	end
	local recipes = {}
	for _, r in ipairs(cfg.recipes) do
		local orb = C.orbByKey[r.key]
		if orb then
			recipes[#recipes + 1] = {key = r.key, name = orb.name, id = orb.id, clientId = clientIdOf(orb.id), cost = r.cost, back = K.recycleShards(r.key, cfg),
				count = player:getItemCount(orb.id)}
		end
	end
	-- Ember / Crown Shards -> their orb: the shards themselves pay (no recycling back)
	for _, r in ipairs(cfg.shardRecipes or {}) do
		local orb = C.orbByKey[r.orb]
		if orb and itemExists(r.input) then
			recipes[#recipes + 1] = {key = r.key, name = orb.name, id = orb.id, clientId = clientIdOf(orb.id), cost = r.cost, back = 0,
				count = player:getItemCount(orb.id), input = r.input, inputClientId = clientIdOf(r.input), inputName = r.plural,
				inputSingular = r.name, have = player:getItemCount(r.input)}
		end
	end
	local view = {
		installed = shardInstalled(),
		shardId = cfg.shard.id,
		shardClientId = clientIdOf(cfg.shard.id),
		shardName = cfg.shard.plural,
		shardSingular = cfg.shard.name,
		shards = player:getItemCount(cfg.shard.id),
		rarityNames = C.config.rarityNames,
		rarityIds = C.config.rarityIds, -- the stored id of each name (the client sends maxRarity as one of them)
		recipes = recipes,
		maxCombine = cfg.maxCombine,
		bags = bagList(player),
		mode = sc.mode
	}
	if sc.mode == "salvage" then
		local res = batchOf(player, sc.bag, sc.maxRarity)
		if not res then
			sc.bag = ""
			res = batchOf(player, sc.bag, sc.maxRarity)
		end
		if res then
			view.batch = {bag = sc.bag, maxRarity = res.maxRarity, count = res.count, shards = res.shards,
				orbs = K.percent(res.orbs), capped = res.capped, cap = cfg.batchCap, skipped = res.skipped, sig = res.sig,
				paths = res.paths}
		end
	end
	data.salvage = view
end

-- ---------------------------------------------------------------- actions
local function limited(player, key, interval)
	local pid = player:getId()
	last[pid] = last[pid] or {}
	local now = nowMs()
	if last[pid][key] and now - last[pid][key] < interval then
		return true
	end
	last[pid][key] = now
	return false
end

local function refuse(player, text)
	local b = bench()
	b.sendResult(player, false, "salvage", text)
	b.sendState(player, false)
end

local function itemFrom(player, data)
	local b = bench()
	local item = b.itemAt(player, data.path)
	local id = Chaos.toInt(data.id, 1, 65535)
	if not item or item:getId() ~= id or (data.sig and C.signature(item) ~= data.sig) then
		b.select(player, nil)
		return nil
	end
	return item
end

local function salvageOne(player, data)
	local b = bench()
	if limited(player, "single", cfg.singleIntervalMs) then
		b.sendState(player, false)
		return
	end
	if not shardInstalled() then
		return refuse(player, "Salvage is not installed on this server (no rune shard item).")
	end
	local item = itemFrom(player, data)
	if not item then
		return refuse(player, "The item moved or changed. Put it on the bench again.")
	end
	local info = S.infoOf(player, item)
	local why = K.check(info, cfg)
	if why then
		return refuse(player, K.reasons[why] or why)
	end
	local roll, name = breakItem(item, info)
	if not roll then
		return refuse(player, "The item could not be salvaged.")
	end
	b.select(player, nil)
	local orbs = {}
	if roll.orb then
		orbs[roll.orb] = 1
	end
	local inbox = giveRolls(player, roll.shards, orbs)
	if roll.tokens then
		-- the item is gone from the character: save it before the tokens go into the database
		if Chaos.saveCharacter(player) then
			ChaosConquest.grant(player, "salvage", roll.tokens, name)
		else
			print("[Chaos salvage] " .. name .. " of " .. player:getName() .. ": the save failed, " .. roll.tokens .. " tokens not given")
		end
	end
	local text = rowText(info, roll, player)
	logRows(player, {{item = name, text = rowText(info, roll)}})
	player:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT or 9)
	local msg = Chaos.t(player, "Salvaged %s: %s.%s", name, text,
		inbox > 0 and Chaos.t(player, " Your backpack is full: some went to your inbox.") or "")
	player:sendTextMessage(MESSAGE_INFO_DESCR, msg)
	b.sendResult(player, true, "salvage", msg)
	b.sendState(player, false)
end

local function salvageBatch(player, data)
	local b = bench()
	if limited(player, "batch", cfg.batchIntervalMs) then
		return refuse(player, "Wait a moment before the next batch.")
	end
	if not shardInstalled() then
		return refuse(player, "Salvage is not installed on this server (no rune shard item).")
	end
	local bag = type(data.bag) == "string" and data.bag or ""
	local maxRarity = Chaos.toInt(data.maxRarity, 1, ChaosRarity.MAX_LEGACY) -- a stored id (an old client's 6 .. 15 map)
	if not maxRarity then
		return refuse(player, "Choose a rarity.")
	end
	maxRarity = ChaosRarity.canon(maxRarity)
	local res = batchOf(player, bag, maxRarity)
	if not res then
		return refuse(player, "That bag is not in your backpack any more.")
	end
	if res.count == 0 then
		return refuse(player, "Nothing to salvage there.")
	end
	if type(data.sig) ~= "string" or data.sig ~= res.sig then
		return refuse(player, "The items changed since the preview. Check the list and confirm again.")
	end
	local shards, orbs, rows, gotOrbs = 0, {}, {}, 0
	-- remove from the end so the earlier indices stay valid
	for n = #res.picked, 1, -1 do
		local i = res.picked[n]
		local item, info = res.items[i], res.infos[i]
		if S.inScope(player, item) and not K.check(S.infoOf(player, item), cfg) then
			local roll, name = breakItem(item, info)
			if roll then
				shards = shards + roll.shards
				if roll.orb then
					orbs[roll.orb] = (orbs[roll.orb] or 0) + 1
					gotOrbs = gotOrbs + 1
				end
				rows[#rows + 1] = {item = name, text = rowText(info, roll)}
			end
		end
	end
	b.select(player, nil)
	local inbox = giveRolls(player, shards, orbs)
	logRows(player, rows)
	local orbText = {}
	for key, n in pairs(orbs) do
		orbText[#orbText + 1] = string.format("%dx %s", n, orbName(key))
	end
	table.sort(orbText)
	local msg = Chaos.t(player, "Salvaged %d items: %d %s%s.%s", #rows, shards, cfg.shard.plural,
		gotOrbs > 0 and (Chaos.t(player, " and ") .. table.concat(orbText, ", ")) or "",
		inbox > 0 and Chaos.t(player, " Your backpack is full: some went to your inbox.") or "")
	player:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT or 9)
	player:sendTextMessage(MESSAGE_INFO_DESCR, msg)
	b.sendResult(player, true, "salvage", msg)
	b.sendState(player, false)
end

local function lockAction(player, data)
	local b = bench()
	if limited(player, "single", cfg.singleIntervalMs) then
		b.sendState(player, false)
		return
	end
	local item = itemFrom(player, {path = data.path, id = data.id})
	if not item or not b.inBackpack(player, item) or not (C.isGear(item) or C.isRiftKey(item)) then
		return refuse(player, "Put the item from your backpack on the bench first.")
	end
	local on = data.on == true or data.on == 1
	S.setLocked(item, on)
	local name = C.itemName(item)
	logRows(player, {{orb = "Lock", item = name, text = on and "locked" or "unlocked"}})
	local msg = on and Chaos.t(player, "%s is locked: it cannot be sold, salvaged or thrown away.", name)
		or Chaos.t(player, "%s is unlocked.", name)
	b.sendResult(player, true, "salvage", msg)
	b.sendState(player, false)
end

-- the item at a client position of the player's own inventory slots or open containers (the shape of the tooltip and link
-- scripts: ChaosItemTooltip.decodePos); never the ground, never another player's or a depot's container
local function itemAtClientPos(player, pos)
	if not ChaosItemTooltip then
		dofile("data/scripts/chaos/item_tooltip_core.lua")
	end
	local p = ChaosItemTooltip.decodePos(pos)
	if not p or p.kind == "map" then
		return nil
	end
	local item
	if p.kind == "slot" then
		item = player:getSlotItem(p.slot)
	else
		local container = player:getContainerById(p.cid) -- only containers the engine has open for this player
		if not container then
			return nil
		end
		local first = tonumber(player:getContainerIndex(p.cid)) or 0
		item = container:getItem(first + p.index)
	end
	if not item then
		return nil
	end
	local ok, top = pcall(function() return item:getTopParent() end)
	if not ok or top ~= player then
		return nil
	end
	return item
end

local function lockAt(player, data)
	if limited(player, "single", cfg.singleIntervalMs) then
		return
	end
	local function say(text)
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, text))
	end
	local item = type(data.pos) == "table" and itemAtClientPos(player, data.pos) or nil
	local cid = Chaos.toInt(data.cid, 1, 65535)
	local okType, clientId = pcall(function() return item and ItemType(item:getId()):getClientId() end)
	if not item or not cid or not okType or clientId ~= cid then
		return say("The item moved. Try again.")
	end
	if not (C.isGear(item) or C.isRiftKey(item)) then
		return say("Only gear and Rift Keys can be locked.")
	end
	local on
	if data.on == nil then
		on = not S.isLocked(item)
	else
		on = data.on == true or data.on == 1
	end
	S.setLocked(item, on)
	local name = C.itemName(item)
	logRows(player, {{orb = "Lock", item = name, text = on and "locked" or "unlocked"}})
	player:sendTextMessage(MESSAGE_INFO_DESCR, on and Chaos.t(player, "%s is locked: it cannot be sold, salvaged or thrown away.", name)
		or Chaos.t(player, "%s is unlocked.", name))
end

local function combine(player, data)
	local b = bench()
	if limited(player, "combine", cfg.combineIntervalMs) then
		b.sendState(player, false)
		return
	end
	local key = type(data.key) == "string" and data.key or ""
	local count = Chaos.toInt(data.count, 1, cfg.maxCombine) or 0
	local r = K.anyRecipe(key, cfg)
	-- what the recipe eats: rune shards, or the shard item of a shard recipe (Ember / Crown Shards)
	local input = r and r.input or cfg.shard.id
	local owned = player:getItemCount(input)
	local ok, cost = K.combineCheck(owned, key, count, cfg)
	local orb = r and C.orbByKey[r.orb or r.key]
	if not ok or not orb then
		return refuse(player, K.reasonText(cost, r) or "That cannot be made.")
	end
	-- removeItem counts every stack in the backpack and its bags first and removes only when there are enough: all or
	-- nothing, before the orb is given
	if not player:removeItem(input, cost) then
		return refuse(player, K.reasonText(r.input and "input" or "shards", r))
	end
	local _, inbox = give(player, orb.id, count)
	local text = string.format("%s %s -> %dx %s", K.thousands(cost), r.input and r.plural or cfg.shard.plural, count, orb.name)
	logRows(player, {{orb = "Shards", item = orb.name, text = text}})
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN or 13)
	local msg = text .. "." .. ((inbox or 0) > 0 and Chaos.t(player, " Your backpack is full: it went to your inbox.") or "")
	player:sendTextMessage(MESSAGE_INFO_DESCR, msg)
	b.sendResult(player, true, "salvage", msg)
	b.sendState(player, false)
end

local function recycle(player, data)
	local b = bench()
	if limited(player, "combine", cfg.combineIntervalMs) then
		b.sendState(player, false)
		return
	end
	local key = type(data.key) == "string" and data.key or ""
	local count = Chaos.toInt(data.count, 1, cfg.maxRecycle or 1) or 0
	local orb = C.orbByKey[key]
	local ok, shards = K.recycleCheck(orb and player:getItemCount(orb.id) or 0, key, count, cfg)
	if not ok or not orb then
		return refuse(player, K.reasons[shards] or "That cannot be recycled.")
	end
	if not player:removeItem(orb.id, count) then
		return refuse(player, K.reasons.orbs)
	end
	local _, inbox = give(player, cfg.shard.id, shards)
	local text = string.format("%dx %s -> %d %s", count, orb.name, shards, cfg.shard.plural)
	logRows(player, {{orb = "Recycle", item = orb.name, text = text}})
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE or 11)
	local msg = text .. "." .. ((inbox or 0) > 0 and Chaos.t(player, " Your backpack is full: it went to your inbox.") or "")
	player:sendTextMessage(MESSAGE_INFO_DESCR, msg)
	b.sendResult(player, true, "salvage", msg)
	b.sendState(player, false)
end

local function setScope(player, data)
	local b = bench()
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "salvage.scope", 100) then
		return
	end
	local sc = scopeOf(player)
	if type(data.bag) == "string" and #data.bag <= 32 then
		sc.bag = data.bag
	end
	local r = Chaos.toInt(data.maxRarity, 1, ChaosRarity.MAX_LEGACY)
	if r then
		sc.maxRarity = ChaosRarity.canon(r)
	end
	if data.mode == "salvage" or data.mode == "orbs" then
		sc.mode = data.mode
	end
	b.sendState(player, false)
end

function S.onAction(player, action, data)
	if not bench() then
		return
	end
	-- each action reads the crafting log for the answer (opcode fuzz test): one per 150 ms; the scope has its own limit
	if action ~= "salvageScope" and ChaosRateLimit and not ChaosRateLimit.allow(player, "salvage.action", 150) then
		return
	end
	if action == "salvage" then
		salvageOne(player, data)
	elseif action == "salvageBatch" then
		salvageBatch(player, data)
	elseif action == "lock" then
		lockAction(player, data)
	elseif action == "lockAt" then
		lockAt(player, data)
	elseif action == "combine" then
		combine(player, data)
	elseif action == "recycle" then
		recycle(player, data)
	elseif action == "salvageScope" then
		setScope(player, data)
	end
end

-- ---------------------------------------------------------------- look text, plain use of a shard, !salvage, logout
local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing.isItem and thing:isItem() and S.isLocked(thing) then
		description = (description or "") .. "\nIt is locked: it cannot be sold, salvaged or thrown away."
	end
	-- an Ember / Crown Shard: where it becomes an orb
	local hint = thing and thing.isItem and thing:isItem() and S.shardHint(thing:getId())
	if hint then
		description = (description or "") .. "\n" .. hint
	end
	return description
end
-- after the base default_onLook (0), the leaderboard / season / daily / siege lines (100-110)
look:register(120)

local function openSalvage(player)
	local b = bench()
	if not b then
		return
	end
	scopeOf(player).mode = "salvage"
	b.sendState(player, true)
end

local shardUse = Action()
function shardUse.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	openSalvage(player)
	return true
end
shardUse:id(cfg.shard.id)
shardUse:register()

local logout = CreatureEvent("ChaosSalvageLogout")
function logout.onLogout(player)
	scope[player:getId()] = nil
	last[player:getId()] = nil
	return true
end
logout:register()

local login = CreatureEvent("ChaosSalvageLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSalvageLogout")
	return true
end
login:register()
