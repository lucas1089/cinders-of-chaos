-- Chaos market: our own player market (auction house) for gold and Chaos Coins. Client game_market (Economy > Market,
-- Alt+M), extended opcode ChaosOpcodes.market = 221. Rules and numbers: market_config.lua; pure logic: market_core.lua
-- (tests/market_test.lua); tables: sql/chaos_market.sql. Overview: server/README.md "Market".
--
-- Escrow: a listed item leaves the seller and lives in its offer row: with engine patch 0017 as the engine's own
-- binary form of every attribute (item:serializeAttributes(), hex in `data`, codec "blob"), else as a key list (codec
-- "attrs", the guild depot's method). It is created again (item:unserializeAttributes()) for the buyer, or for the
-- seller after a cancel or the expiry, and always goes to the character's inbox. The re-created item loses its per-item
-- id (chaos_iid), so the engine gives it a new one: links and tooltips of the old copy never point at it.
--
-- Crash safety (no dupe, no loss on a crash between two steps):
--   listing   1. the offer row is written as "pending"  2. the item, the fee and the storage listSeq = offer id change
--             in memory  3. player:save() writes all three in ONE database transaction  4. the row turns "active".
--             A pending row found later (login, startup) is activated when the seller's saved listSeq reached its id,
--             else dropped (the item never left the seller in a saved state).
--   buying    gold: player:save() first (the database equals the character), then one transaction takes the price from
--             players.balance, marks the offer sold and writes the deliveries (item -> buyer, gold -> seller); then the
--             same price leaves the bank balance in memory. Coins: one transaction moves the coins between the two
--             accounts (chaos_shop_coins), marks the offer sold and writes the item delivery.
--   delivery  owed rows (chaos_market_deliveries) are applied in id order: the item into the inbox / the gold into the
--             bank, the storage deliverSeq = row id, then player:save(), then the rows are marked delivered. A row at or
--             below the saved deliverSeq is only marked (it reached the character before a crash).
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.market; big answers go through Chaos.sendChunked:
--   client -> server  open | browse {filter: market_core.lua C.browseQuery, modifier rows C.modFilter} | tip {id} | buy {id, cur} | sellable | list {ref|pos, sid, iid, count,
--                     gold, coins, days} | cancel {id} | mine | history
--   server -> client  meta {...} | page {rows, page, pages, total} | tip {id, tip, seller} | sellable {items} |
--                     mine {active, closed, owed} | history {rows} | wallet {gold, coins} | done {what, text} |
--                     error {text}
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosMarketCore then
	dofile("data/scripts/chaos/market_core.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua")
end
if not ChaosItemTooltip then
	dofile("data/scripts/chaos/item_tooltip_core.lua")
end

Chaos.marketConfig = dofile("data/scripts/chaos/market_config.lua")
local cfg = Chaos.marketConfig
local MC = ChaosMarketCore
ChaosMarket = ChaosMarket or {}
local MK = ChaosMarket
local OPCODE = ChaosOpcodes.market or 221
local T = cfg.tables
local S_LIST, S_DELIVER = cfg.storage.listSeq, cfg.storage.deliverSeq
local MSG = cfg.messages
local COINS = (Chaos.tables and Chaos.tables.shopCoins) or "chaos_shop_coins"

local function now()
	return os.time()
end

local function log(text)
	print("[Chaos market] " .. text)
end

-- ------------------------------------------------------------------ database
local function sql(query, columns)
	return Chaos.select(query, columns)
end

-- run a write and return the rows it changed (-1 when the statement failed)
local function exec(query)
	if not db.query(query) then
		return -1
	end
	local rows = sql("SELECT ROW_COUNT() AS `n`", {{"n", "n"}})
	return rows[1] and rows[1].n or 0
end

local function lastId()
	local r = sql("SELECT LAST_INSERT_ID() AS `id`", {{"id", "n"}})[1]
	return r and r.id or 0
end

-- fn() runs inside one database transaction: committed when it returns true, rolled back otherwise (or on an error)
local function transaction(fn)
	if not db.query("START TRANSACTION") then
		return false
	end
	local ok, res = pcall(fn)
	if ok and res then
		if db.query("COMMIT") then
			return true
		end
		db.query("ROLLBACK")
		return false
	end
	if not ok then
		log("transaction error: " .. tostring(res))
	end
	db.query("ROLLBACK")
	return false
end

local esc = function(s)
	return db.escapeString(tostring(s))
end

local SCHEMA = {
	[[CREATE TABLE IF NOT EXISTS `chaos_market_offers` (`id` int(11) NOT NULL AUTO_INCREMENT,
	`realm` int(11) NOT NULL DEFAULT 0, `state` tinyint(3) unsigned NOT NULL DEFAULT 9,
	`seller_id` int(11) NOT NULL, `seller_account` int(11) NOT NULL, `seller_name` varchar(64) NOT NULL DEFAULT '',
	`item_id` int(11) NOT NULL, `client_id` int(11) NOT NULL DEFAULT 0, `count` int(11) NOT NULL DEFAULT 1,
	`name` varchar(100) NOT NULL DEFAULT '', `category` varchar(16) NOT NULL DEFAULT 'misc',
	`rarity` tinyint(3) unsigned NOT NULL DEFAULT 0, `ilvl` int(11) NOT NULL DEFAULT 0,
	`unique_item` tinyint(1) NOT NULL DEFAULT 0, `mods` varchar(1000) NOT NULL DEFAULT '',
	`price_gold` bigint(20) unsigned NOT NULL DEFAULT 0, `price_coins` int(11) unsigned NOT NULL DEFAULT 0,
	`fee` bigint(20) unsigned NOT NULL DEFAULT 0, `codec` varchar(8) NOT NULL DEFAULT 'blob', `data` mediumtext NOT NULL,
	`tip` mediumtext NOT NULL, `created` int(10) unsigned NOT NULL, `expires` int(10) unsigned NOT NULL,
	`buyer_id` int(11) NOT NULL DEFAULT 0, `buyer_name` varchar(64) NOT NULL DEFAULT '',
	`paid_currency` varchar(8) NOT NULL DEFAULT '', `paid_amount` bigint(20) unsigned NOT NULL DEFAULT 0,
	`tax` bigint(20) unsigned NOT NULL DEFAULT 0, `closed_at` int(10) unsigned NOT NULL DEFAULT 0,
	`sockets` tinyint(3) unsigned NOT NULL DEFAULT 0, `quality` smallint(5) unsigned NOT NULL DEFAULT 0,
	`free_prefix` tinyint(3) unsigned NOT NULL DEFAULT 0, `free_suffix` tinyint(3) unsigned NOT NULL DEFAULT 0,
	`has_power` tinyint(1) NOT NULL DEFAULT 0, `bound_mods` tinyint(3) unsigned NOT NULL DEFAULT 0,
	`mods_indexed` tinyint(1) NOT NULL DEFAULT 0, PRIMARY KEY (`id`),
	KEY `chaos_market_browse` (`state`, `realm`, `expires`), KEY `chaos_market_seller` (`seller_id`, `state`),
	KEY `chaos_market_buyer` (`buyer_id`), KEY `chaos_market_account` (`seller_account`, `state`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_market_deliveries` (`id` int(11) NOT NULL AUTO_INCREMENT,
	`player_id` int(11) NOT NULL, `offer_id` int(11) NOT NULL, `kind` varchar(8) NOT NULL DEFAULT 'item',
	`amount` bigint(20) unsigned NOT NULL DEFAULT 0, `reason` varchar(16) NOT NULL DEFAULT '',
	`created` int(10) unsigned NOT NULL, `delivered` tinyint(1) NOT NULL DEFAULT 0,
	`delivered_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`),
	UNIQUE KEY `chaos_market_delivery_once` (`offer_id`, `kind`), KEY `chaos_market_owed` (`player_id`, `delivered`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_market_log` (`id` int(11) NOT NULL AUTO_INCREMENT, `at` int(10) unsigned NOT NULL,
	`action` varchar(12) NOT NULL, `offer_id` int(11) NOT NULL DEFAULT 0, `player_id` int(11) NOT NULL DEFAULT 0,
	`other_id` int(11) NOT NULL DEFAULT 0, `item_id` int(11) NOT NULL DEFAULT 0, `count` int(11) NOT NULL DEFAULT 0,
	`name` varchar(100) NOT NULL DEFAULT '', `currency` varchar(8) NOT NULL DEFAULT '',
	`amount` bigint(20) NOT NULL DEFAULT 0, `fee` bigint(20) NOT NULL DEFAULT 0, `text` varchar(255) NOT NULL DEFAULT '',
	PRIMARY KEY (`id`), KEY `chaos_market_log_offer` (`offer_id`), KEY `chaos_market_log_player` (`player_id`, `id`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	-- the modifier filter (a database of the first version gets the columns; MariaDB's ADD COLUMN IF NOT EXISTS)
	[[ALTER TABLE `chaos_market_offers` ADD COLUMN IF NOT EXISTS `sockets` tinyint(3) unsigned NOT NULL DEFAULT 0,
	ADD COLUMN IF NOT EXISTS `quality` smallint(5) unsigned NOT NULL DEFAULT 0,
	ADD COLUMN IF NOT EXISTS `free_prefix` tinyint(3) unsigned NOT NULL DEFAULT 0,
	ADD COLUMN IF NOT EXISTS `free_suffix` tinyint(3) unsigned NOT NULL DEFAULT 0,
	ADD COLUMN IF NOT EXISTS `has_power` tinyint(1) NOT NULL DEFAULT 0,
	ADD COLUMN IF NOT EXISTS `bound_mods` tinyint(3) unsigned NOT NULL DEFAULT 0,
	ADD COLUMN IF NOT EXISTS `mods_indexed` tinyint(1) NOT NULL DEFAULT 0]],
	[[CREATE TABLE IF NOT EXISTS `chaos_market_offer_mods` (`offer_id` int(11) NOT NULL, `mod_key` varchar(48) NOT NULL,
	`value` int(11) NOT NULL DEFAULT 0, `tier` tinyint(3) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`offer_id`, `mod_key`),
	KEY `chaos_market_mod_value` (`mod_key`, `value`), KEY `chaos_market_mod_tier` (`mod_key`, `tier`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]]
}
local MT = T.offerMods or "chaos_market_offer_mods"

local function logRow(action, o)
	o = o or {}
	db.query(string.format("INSERT INTO `%s` (`at`, `action`, `offer_id`, `player_id`, `other_id`, `item_id`, `count`, `name`, "
		.. "`currency`, `amount`, `fee`, `text`) VALUES (%d, %s, %d, %d, %d, %d, %d, %s, %s, %d, %d, %s)", T.log, now(), esc(action),
		o.offer or 0, o.player or 0, o.other or 0, o.item or 0, o.count or 0, esc(tostring(o.name or ""):sub(1, 100)),
		esc(o.currency or ""), o.amount or 0, o.fee or 0, esc(tostring(o.text or ""):sub(1, 255))))
end

local OFFER_COLS = {{"id", "n"}, {"realm", "n"}, {"state", "n"}, {"seller_id", "n"}, {"seller_account", "n"}, {"seller_name", "s"},
	{"item_id", "n"}, {"client_id", "n"}, {"count", "n"}, {"name", "s"}, {"category", "s"}, {"rarity", "n"}, {"ilvl", "n"},
	{"unique_item", "n"}, {"price_gold", "n"}, {"price_coins", "n"}, {"created", "n"}, {"expires", "n"}, {"buyer_id", "n"},
	{"buyer_name", "s"}, {"paid_currency", "s"}, {"paid_amount", "n"}, {"tax", "n"}, {"closed_at", "n"}}
local OFFER_SELECT = "`id`, `realm`, `state`, `seller_id`, `seller_account`, `seller_name`, `item_id`, `client_id`, `count`, `name`, "
	.. "`category`, `rarity`, `ilvl`, `unique_item`, `price_gold`, `price_coins`, `created`, `expires`, `buyer_id`, `buyer_name`, "
	.. "`paid_currency`, `paid_amount`, `tax`, `closed_at`"

local function offerById(id)
	return sql(string.format("SELECT %s FROM `%s` WHERE `id` = %d", OFFER_SELECT, T.offers, id), OFFER_COLS)[1]
end

-- ------------------------------------------------------------------ the modifier index (Browse modifier filter)
-- the modifier rows of an offer (MC.offerIndex) as one INSERT, or nil when it has none
local function indexInsert(id, idx)
	if #idx.mods == 0 then
		return nil
	end
	local vals = {}
	for _, m in ipairs(idx.mods) do
		vals[#vals + 1] = string.format("(%d, %s, %d, %d)", id, esc(m.key), m.value, m.tier)
	end
	return string.format("INSERT INTO `%s` (`offer_id`, `mod_key`, `value`, `tier`) VALUES %s", MT, table.concat(vals, ", "))
end

local function dropIndex(id)
	return exec(string.format("DELETE FROM `%s` WHERE `offer_id` = %d", MT, id))
end

-- (re)writes the index of an existing offer: its rows and its filter columns; true when written
local function writeIndex(id, idx)
	if dropIndex(id) < 0 then
		return false
	end
	local ins = indexInsert(id, idx)
	if ins and exec(ins) ~= #idx.mods then
		return false
	end
	return exec(string.format("UPDATE `%s` SET `sockets` = %d, `quality` = %d, `free_prefix` = %d, `free_suffix` = %d, `has_power` = %d, "
		.. "`bound_mods` = %d, `mods_indexed` = 1 WHERE `id` = %d", T.offers, idx.sockets, idx.quality, idx.freePrefix, idx.freeSuffix,
		idx.hasPower, math.min(idx.bound, 255), id)) >= 0
end
MK.writeIndex = writeIndex

-- the offers listed before the index existed (or before cfg.modIndexVersion was raised): indexed once at startup from
-- their tooltip snapshots, in batches; server_config `chaos_market_modindex` records the version that was built (a
-- crash part way leaves it unset: the offers still marked mods_indexed = 0 are done at the next startup)
local INDEX_CONFIG = "chaos_market_modindex"
function MK.backfillIndex()
	local want = cfg.modIndexVersion or 1
	local r = sql(string.format("SELECT `value` FROM `server_config` WHERE `config` = %s", esc(INDEX_CONFIG)), {{"value", "s"}})[1]
	local have = r and tonumber(r.value) or 0
	if have >= want then
		return 0
	end
	if have > 0 then
		exec(string.format("UPDATE `%s` SET `mods_indexed` = 0 WHERE `state` IN (0, 9)", T.offers))
	end
	local n, last = 0, 0
	while true do
		local rows = sql(string.format("SELECT `id`, `tip` FROM `%s` WHERE `state` IN (0, 9) AND `mods_indexed` = 0 AND `id` > %d ORDER BY `id` LIMIT 200",
			T.offers, last), {{"id", "n"}, {"tip", "s"}})
		if #rows == 0 then
			break
		end
		for _, o in ipairs(rows) do
			last = o.id
			local ok, tip = pcall(json.decode, o.tip)
			if writeIndex(o.id, MC.offerIndex(ok and tip or nil)) then
				n = n + 1
			else
				log("could not index offer " .. o.id)
			end
		end
	end
	db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s) ON DUPLICATE KEY UPDATE `value` = %s",
		esc(INDEX_CONFIG), esc(tostring(want)), esc(tostring(want))))
	log(string.format("modifier index built for %d offers (version %d)", n, want))
	return n
end

-- the modifier keys a Browse filter may name: every modifier and legendary power of the item mods (ChaosCrafting's
-- affix list, the same keys the Codex shows); nil when that list is not there (then any well-formed key)
local knownMods
function MK.knownMods()
	if knownMods then
		return knownMods
	end
	local set, any = {}, false
	if ChaosCrafting and ChaosCrafting.affixes then
		local ok, list = pcall(ChaosCrafting.affixes)
		for _, a in ipairs(ok and type(list) == "table" and list or {}) do
			if type(a.key) == "string" then
				set[a.key:lower()] = true
				any = true
			end
		end
	end
	if not any then
		return nil
	end
	knownMods = set
	return set
end

-- ------------------------------------------------------------------ seasons
local function currentSeason()
	local S = ChaosSeason
	if S and S.current then
		local ok, s = pcall(S.current)
		if ok and type(s) == "table" then
			return tonumber(s.id) or 0, s
		end
	end
	return 0, nil
end

local function realmOfGuid(guid)
	local S = ChaosSeason
	if S and S.realmOfGuid then
		local ok, r = pcall(S.realmOfGuid, guid)
		if ok then
			return tonumber(r) or 0
		end
	end
	return 0
end

local function realmOf(player)
	return realmOfGuid(player:getGuid())
end

-- ------------------------------------------------------------------ money
local function coinsOf(accountId)
	local r = sql(string.format("SELECT `coins` FROM `%s` WHERE `account_id` = %d", COINS, accountId), {{"coins", "n"}})[1]
	return r and r.coins or 0
end

local function send(player, action, data)
	Chaos.sendChunked(player, OPCODE, json.encode({action = action, data = data or {}}))
end

local function sendWallet(player)
	send(player, "wallet", {gold = player:getBankBalance(), coins = coinsOf(player:getAccountId())})
end

local function refuse(player, text)
	send(player, "error", {text = text})
	return false
end

local function toast(player, text)
	if ChaosOpcodes.notifications then
		player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = "market", message = text}))
	end
end

local function tell(player, text)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, "Market: " .. text)
end

-- ------------------------------------------------------------------ escrow codec
local HAS_BLOB = Item ~= nil and Item.serializeAttributes ~= nil and Item.unserializeAttributes ~= nil
MK.hasBlob = HAS_BLOB

-- the key-list codec (without engine patch 0017): the standard attributes and every custom key the Chaos scripts set
local STD = {"ITEM_ATTRIBUTE_DESCRIPTION", "ITEM_ATTRIBUTE_TEXT", "ITEM_ATTRIBUTE_WRITER", "ITEM_ATTRIBUTE_DATE",
	"ITEM_ATTRIBUTE_NAME", "ITEM_ATTRIBUTE_ARTICLE", "ITEM_ATTRIBUTE_PLURALNAME", "ITEM_ATTRIBUTE_ACTIONID",
	"ITEM_ATTRIBUTE_ATTACK", "ITEM_ATTRIBUTE_DEFENSE", "ITEM_ATTRIBUTE_EXTRADEFENSE", "ITEM_ATTRIBUTE_ARMOR",
	"ITEM_ATTRIBUTE_HITCHANCE", "ITEM_ATTRIBUTE_SHOOTRANGE", "ITEM_ATTRIBUTE_CHARGES", "ITEM_ATTRIBUTE_DURATION",
	"ITEM_ATTRIBUTE_ATTACK_SPEED"}
local EXTRA_KEYS = {"rarity", "combatPowerLevel", "chaos_unique", "chaos_sockets", "chaos_uses", "omen_kind", "rift_tier",
	"rift_mods", "prefix", "chaos_mods_pending"}

local keyList
local function customKeys()
	if keyList then
		return keyList
	end
	local seen, list = {}, {}
	local function add(k)
		if type(k) == "string" and k ~= "" and not seen[k:lower()] then
			seen[k:lower()] = true
			list[#list + 1] = k
		end
	end
	for _, k in ipairs(EXTRA_KEYS) do
		add(k)
	end
	for i = 1, 8 do
		add((ChaosGems and ChaosGems.ATTR_GEM or "chaos_gem") .. i)
	end
	if ChaosCrafting and ChaosCrafting.attributeKeys then
		for _, k in ipairs(ChaosCrafting.attributeKeys()) do
			add(k)
		end
	end
	keyList = list
	return list
end

local function readAttrs(item)
	local list = {}
	for _, name in ipairs(STD) do
		local c = _G[name]
		if c and item:hasAttribute(c) then
			local v = item:getAttribute(c)
			if v ~= nil and v ~= "" and v ~= 0 then
				list[#list + 1] = {"@" .. name, v}
			end
		end
	end
	for _, k in ipairs(customKeys()) do
		local v = item:getCustomAttribute(k)
		if v ~= nil then
			list[#list + 1] = {k, v}
		end
	end
	return list
end

local function writeAttrs(item, list)
	for _, a in ipairs(list) do
		local k, v = a[1], a[2]
		if k:sub(1, 1) == "@" then
			local c = _G[k:sub(2)]
			if c then
				item:setAttribute(c, v)
			end
		else
			item:setCustomAttribute(k, v)
		end
	end
end

-- item -> codec, data
function MK.encode(item)
	if HAS_BLOB then
		local blob = item:serializeAttributes()
		if type(blob) == "string" then
			return "blob", MC.hex(blob)
		end
	end
	return "attrs", MC.encodeAttrs(readAttrs(item))
end

-- a new item (not in the world) from an offer row's item id, count, codec and data; nil, why when it cannot be made
function MK.decode(itemId, count, codec, data)
	local item = Game.createItem(itemId, count)
	if not item then
		return nil, "could not create item " .. tostring(itemId)
	end
	if codec == "blob" then
		if not HAS_BLOB then
			return nil, "codec blob needs engine patch 0017"
		end
		local raw = MC.unhex(data)
		if not raw or not item:unserializeAttributes(raw) then
			return nil, "attributes could not be read"
		end
	else
		writeAttrs(item, MC.decodeAttrs(data))
	end
	-- a new per-item id: the engine gives one the first time the item is sent (engine patch 0003)
	item:removeCustomAttribute("chaos_iid")
	return item
end

-- ------------------------------------------------------------------ the character's items
local SLOT_FIRST, SLOT_LAST = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 10
local BACKPACK = CONST_SLOT_BACKPACK or 3

local function call(obj, method, ...)
	if not obj or not obj[method] then
		return nil
	end
	local ok, v = pcall(obj[method], obj, ...)
	if ok then
		return v
	end
	return nil
end

local function isContainer(item)
	return call(item, "isContainer") == true
end

-- the facts itemRefusal needs
local function itemInfo(player, item, count, equipped)
	local it = ItemType(item:getId())
	local info = {id = item:getId(), equipped = equipped, count = count, have = math.max(1, item:getCount())}
	info.locked = (ChaosCrafting and ChaosCrafting.customNumber(item, "chaos_locked") or 0) ~= 0
	info.container = isContainer(item)
	info.contents = info.container and (call(item, "getSize") or 0) or 0
	info.pickupable = call(it, "isPickupable")
	info.movable = call(it, "isMovable")
	info.store = call(item, "isStoreItem") == true
	-- store-exclusive items (the store pouches): ChaosPouches.isPouch or the custom attribute chaos_storebound
	local pouch = false
	if ChaosPouches and ChaosPouches.isPouch then
		local okP, isP = pcall(ChaosPouches.isPouch, item)
		pouch = okP and isP == true
	end
	info.storeBound = pouch or item:getCustomAttribute("chaos_storebound") ~= nil
	if ITEM_ATTRIBUTE_UNIQUEID and item:hasAttribute(ITEM_ATTRIBUTE_UNIQUEID) then
		info.uniqueId = tonumber(item:getAttribute(ITEM_ATTRIBUTE_UNIQUEID)) or 0
	end
	info.actionId = tonumber(call(item, "getActionId")) or 0
	if ITEM_ATTRIBUTE_DECAYSTATE and item:hasAttribute(ITEM_ATTRIBUTE_DECAYSTATE) then
		info.decaying = (tonumber(item:getAttribute(ITEM_ATTRIBUTE_DECAYSTATE)) or 0) > 0
	end
	if not it:isStackable() and (tonumber(count) or 1) ~= 1 then
		info.count = 1
	end
	return info
end

-- "s3", "s3.0.5": an inventory slot, then indexes into the containers inside it
local function resolveRef(player, ref)
	if type(ref) ~= "string" or #ref > 40 then
		return nil
	end
	local slot, rest = ref:match("^s(%d+)(.*)$")
	slot = tonumber(slot)
	if not slot or slot < SLOT_FIRST or slot > SLOT_LAST then
		return nil
	end
	local item = player:getSlotItem(slot)
	local depth = 0
	for idx in rest:gmatch("%.(%d+)") do
		depth = depth + 1
		if not item or not isContainer(item) or depth > 6 then
			return nil
		end
		item = item:getItem(tonumber(idx))
	end
	return item, depth == 0
end

-- an item the client dragged in (client position, as the tooltip and link scripts decode it)
local function resolvePos(player, pos)
	local T2 = ChaosItemTooltip
	local p = T2 and T2.decodePos and T2.decodePos(pos)
	if not p then
		return nil
	end
	local item
	if p.kind == "slot" then
		return player:getSlotItem(p.slot), true
	elseif p.kind == "container" then
		local container = player:getContainerById(p.cid)
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
	return item, false
end

local function iidOf(item)
	return tonumber(ChaosCrafting and ChaosCrafting.customNumber(item, "chaos_iid") or 0) or 0
end

local function itemLevel(item)
	return ChaosItemMods and ChaosItemMods.itemLevelOf and ChaosItemMods.itemLevelOf(item) or 0
end

-- the Sell tab's picker: every item in the backpack (and the bags inside it), with why it cannot be listed
local function sellable(player)
	local out = {}
	local function walk(container, ref, depth)
		local size = call(container, "getSize") or 0
		for i = 0, size - 1 do
			if #out >= cfg.sellableMax then
				return
			end
			local item = container:getItem(i)
			if item then
				local r = ref .. "." .. i
				local info = itemInfo(player, item, item:getCount(), false)
				local why = MC.itemRefusal(info, cfg)
				local it = ItemType(item:getId())
				out[#out + 1] = {ref = r, sid = item:getId(), item = it:getClientId(), count = item:getCount(),
					name = ChaosCrafting and ChaosCrafting.itemName(item) or item:getName(), rarity = ChaosCrafting and ChaosCrafting.rarityOf(item) or 0,
					ilvl = itemLevel(item), iid = string.format("%.0f", iidOf(item)), stack = it:isStackable() or nil, why = why}
				if isContainer(item) and depth < 4 then
					walk(item, r, depth + 1)
				end
			end
		end
	end
	local bag = player:getSlotItem(BACKPACK)
	if bag and isContainer(bag) then
		walk(bag, "s" .. BACKPACK, 1)
	end
	return out
end

-- ------------------------------------------------------------------ checks shared by every action
local saveFlag = {} -- guid -> players.save (read once per login)

local function canUse(player)
	if player:getLevel() < cfg.minLevel then
		return false, string.format(MSG.level, cfg.minLevel)
	end
	local guid = player:getGuid()
	if saveFlag[guid] == nil then
		local r = sql(string.format("SELECT `save` FROM `players` WHERE `id` = %d", guid), {{"save", "n"}})[1]
		saveFlag[guid] = r and r.save or 0
	end
	if saveFlag[guid] == 0 then
		return false, MSG.notSaved
	end
	return true
end

local function rate(player, key)
	return not ChaosRateLimit or ChaosRateLimit.allow(player, "market." .. key, cfg.rate[key] or 500)
end

-- ------------------------------------------------------------------ delivery
local function deliveryRows(guid)
	return sql(string.format("SELECT `id`, `offer_id`, `kind`, `amount`, `reason` FROM `%s` WHERE `player_id` = %d AND `delivered` = 0 ORDER BY `id`",
		T.deliveries, guid), {{"id", "n"}, {"offer_id", "n"}, {"kind", "s"}, {"amount", "n"}, {"reason", "s"}})
end

local REASON_TEXT = {bought = "bought", cancelled = "offer cancelled", expired = "offer expired", sold = "sold"}

-- applies everything the market owes this (online) character; returns how many rows were applied now
function MK.deliver(player)
	local guid = player:getGuid()
	local rows = deliveryRows(guid)
	if #rows == 0 then
		return 0
	end
	local mark = math.max(0, player:getStorageValue(S_DELIVER))
	local done, todo = MC.deliveryPlan(rows, mark)
	local applied, lines = {}, {}
	local inbox = player:getInbox()
	for _, r in ipairs(todo) do
		if r.kind == "item" then
			local o = sql(string.format("SELECT `item_id`, `count`, `codec`, `data`, `name` FROM `%s` WHERE `id` = %d", T.offers, r.offer_id),
				{{"item_id", "n"}, {"count", "n"}, {"codec", "s"}, {"data", "s"}, {"name", "s"}})[1]
			local item, why
			if o then
				item, why = MK.decode(o.item_id, o.count, o.codec, o.data)
			else
				why = "offer row missing"
			end
			if not item or not inbox then
				logRow("error", {offer = r.offer_id, player = guid, text = "delivery " .. r.id .. ": " .. tostring(why or "no inbox")})
				break -- keep the order: later rows wait for this one
			end
			local ret = inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT or 1)
			if ret ~= (RETURNVALUE_NOERROR or 0) then
				logRow("error", {offer = r.offer_id, player = guid, text = "delivery " .. r.id .. ": inbox refused (" .. tostring(ret) .. ")"})
				break
			end
			lines[#lines + 1] = string.format("%s%s in your inbox (%s)", o.count > 1 and (o.count .. "x ") or "", o.name, REASON_TEXT[r.reason] or r.reason)
		elseif r.kind == "gold" or r.kind == "coins" then
			if r.kind == "gold" then
				player:setBankBalance(player:getBankBalance() + r.amount)
			end
			local o = sql(string.format("SELECT `name`, `count`, `buyer_name` FROM `%s` WHERE `id` = %d", T.offers, r.offer_id),
				{{"name", "s"}, {"count", "n"}, {"buyer_name", "s"}})[1] or {name = "an item", count = 1, buyer_name = "?"}
			lines[#lines + 1] = string.format("+%s %s (sold %s%s to %s)", MC.money(r.amount), r.kind == "gold" and "gold" or "Chaos Coins",
				o.count > 1 and (o.count .. "x ") or "", o.name, o.buyer_name)
		end
		player:setStorageValue(S_DELIVER, r.id)
		applied[#applied + 1] = r
	end
	local marked = {}
	for _, r in ipairs(done) do
		marked[#marked + 1] = r.id
	end
	if #applied > 0 then
		if not player:save() then
			-- nothing is marked: the storage sorts it out at the next delivery (or after a crash, nothing was applied)
			log("save failed while delivering to " .. player:getName())
			return #applied
		end
		for _, r in ipairs(applied) do
			marked[#marked + 1] = r.id
		end
	end
	if #marked > 0 then
		db.query(string.format("UPDATE `%s` SET `delivered` = 1, `delivered_at` = %d WHERE `id` IN (%s)", T.deliveries, now(), table.concat(marked, ",")))
		for _, r in ipairs(applied) do
			logRow("deliver", {offer = r.offer_id, player = guid, currency = r.kind == "gold" and "gold" or "", amount = r.amount,
				text = r.kind .. " " .. r.reason})
		end
	end
	if #lines > 0 then
		tell(player, table.concat(lines, "; ") .. ". Items are in your inbox, gold in your bank.")
		toast(player, #lines == 1 and lines[1] or string.format("%d market deliveries: see the Server Log.", #lines))
		sendWallet(player)
	end
	return #applied
end

local function deliverIfOnline(guid)
	local p = Player(guid)
	if p then
		MK.deliver(p)
	end
end

-- a listing interrupted by a crash (state pending): activate it or drop it (MC.pendingAction)
local function resolvePending(id, sellerId, listSeq)
	local action = MC.pendingAction(id, listSeq)
	if action == "activate" then
		exec(string.format("UPDATE `%s` SET `state` = 0 WHERE `id` = %d AND `state` = 9", T.offers, id))
	elseif exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `state` = 9", T.offers, id)) == 1 then
		dropIndex(id)
	end
	logRow("recover", {offer = id, player = sellerId, text = "pending listing: " .. action})
	return action
end

function MK.recoverPlayer(player)
	local rows = sql(string.format("SELECT `id` FROM `%s` WHERE `seller_id` = %d AND `state` = 9", T.offers, player:getGuid()), {{"id", "n"}})
	for _, r in ipairs(rows) do
		resolvePending(r.id, player:getGuid(), player:getStorageValue(S_LIST))
	end
end

-- at startup every character is offline: the saved storage decides
function MK.recoverAll()
	local rows = sql(string.format("SELECT `id`, `seller_id` FROM `%s` WHERE `state` = 9", T.offers), {{"id", "n"}, {"seller_id", "n"}})
	for _, r in ipairs(rows) do
		if not Player(r.seller_id) then
			local s = sql(string.format("SELECT `value` FROM `player_storage` WHERE `player_id` = %d AND `key` = %d", r.seller_id, S_LIST),
				{{"value", "n"}})[1]
			resolvePending(r.id, r.seller_id, s and s.value or 0)
		end
	end
end

-- ------------------------------------------------------------------ listing
function MK.list(player, d)
	local ok, why = canUse(player)
	if not ok then
		return refuse(player, why)
	end
	if not rate(player, "list") then
		return refuse(player, MSG.slow)
	end
	local gold, coins, days = MC.checkPrices(cfg, d.gold, d.coins, d.days)
	if not gold then
		return refuse(player, coins)
	end
	local item, equipped
	if d.ref then
		item, equipped = resolveRef(player, d.ref)
	elseif d.pos then
		item, equipped = resolvePos(player, d.pos)
	end
	if not item or (d.sid and tonumber(d.sid) ~= item:getId()) or (d.cid and tonumber(d.cid) ~= ItemType(item:getId()):getClientId())
			or (tonumber(d.iid) or 0) ~= iidOf(item) then
		return refuse(player, MSG.noItem)
	end
	local it = ItemType(item:getId())
	local count = it:isStackable() and (MC.int(d.count) or item:getCount()) or 1
	local refusal = MC.itemRefusal(itemInfo(player, item, count, equipped), cfg)
	if refusal then
		return refuse(player, refusal)
	end
	local guid, account = player:getGuid(), player:getAccountId()
	local active = sql(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `seller_id` = %d AND `state` IN (0, 9)", T.offers, guid), {{"n", "n"}})[1]
	if active and active.n >= cfg.maxActive then
		return refuse(player, string.format(MSG.maxActive, cfg.maxActive))
	end
	local perAccount = sql(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `seller_account` = %d AND `state` IN (0, 9)", T.offers, account), {{"n", "n"}})[1]
	if perAccount and perAccount.n >= cfg.maxActivePerAccount then
		return refuse(player, string.format(MSG.maxAccount, cfg.maxActivePerAccount))
	end
	local fee = MC.fee(cfg, gold, coins)
	local balance = player:getBankBalance()
	if balance < fee then
		return refuse(player, string.format(MSG.feeGold, MC.money(fee)))
	end

	-- what the offer shows: the tooltip snapshot, name, category, modifiers (all read before the item leaves)
	local okTip, tip = pcall(ChaosItemTooltip.build, item, {})
	if not okTip then
		log("tooltip of " .. item:getId() .. ": " .. tostring(tip))
		tip = {id = it:getClientId(), name = item:getName()}
	end
	tip.count = count
	tip.key = nil
	local modKeys = {}
	for _, m in ipairs(tip.mods or {}) do
		modKeys[#modKeys + 1] = m.k
	end
	local isGem = ChaosGems and ChaosGems.isGem and ChaosGems.isGem(item:getId()) or false
	local name = (ChaosCrafting and ChaosCrafting.itemName(item) or item:getName()):sub(1, cfg.nameMax)
	local category = MC.category(tip.kind, name, isGem, tip.rift ~= nil, tip.rarity)
	local codec, data = MK.encode(item)
	local realm = realmOf(player)
	local t = now()
	local idx = MC.offerIndex(tip)

	-- 1. the offer row, pending
	if exec(string.format("INSERT INTO `%s` (`realm`, `state`, `seller_id`, `seller_account`, `seller_name`, `item_id`, `client_id`, `count`, "
			.. "`name`, `category`, `rarity`, `ilvl`, `unique_item`, `mods`, `price_gold`, `price_coins`, `fee`, `codec`, `data`, `tip`, `created`, "
			.. "`expires`, `sockets`, `quality`, `free_prefix`, `free_suffix`, `has_power`, `bound_mods`, `mods_indexed`) VALUES (%d, 9, %d, %d, %s, "
			.. "%d, %d, %d, %s, %s, %d, %d, %d, %s, %d, %d, %d, %s, %s, %s, %d, %d, %d, %d, %d, %d, %d, %d, 1)", T.offers, realm, guid,
			account, esc(player:getName()), item:getId(), it:getClientId(), count, esc(name), esc(category), tip.rarity or 0, tip.level or 0,
			tip.unique and 1 or 0, esc(MC.modsField(modKeys)), gold, coins, fee, esc(codec), esc(data), esc(json.encode(tip)), t,
			t + days * 86400, idx.sockets, idx.quality, idx.freePrefix, idx.freeSuffix, idx.hasPower, math.min(idx.bound, 255))) ~= 1 then
		return refuse(player, MSG.busy)
	end
	local id = lastId()
	if id <= 0 then
		return refuse(player, MSG.busy)
	end
	-- the modifier rows of the Browse filter (dropped with the row when the listing does not go through)
	local ins = indexInsert(id, idx)
	if ins and exec(ins) ~= #idx.mods then
		dropIndex(id)
		exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `state` = 9", T.offers, id))
		return refuse(player, MSG.busy)
	end

	-- 2. the item, the fee and the marker change in memory
	local itemId = item:getId()
	local removed
	if it:isStackable() and count < item:getCount() then
		removed = item:remove(count)
	else
		removed = item:remove()
	end
	if not removed then
		dropIndex(id)
		exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `state` = 9", T.offers, id))
		return refuse(player, MSG.noItem)
	end
	player:setBankBalance(balance - fee)
	local oldSeq = player:getStorageValue(S_LIST)
	player:setStorageValue(S_LIST, id)

	-- 3. one save writes all three; 4. the offer goes live
	if not player:save() then
		-- give everything back in memory (the database still has the old state) and drop the row
		player:setStorageValue(S_LIST, oldSeq)
		player:setBankBalance(balance)
		local back = MK.decode(itemId, count, codec, data)
		if back then
			player:addItemEx(back, true)
		end
		dropIndex(id)
		exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `state` = 9", T.offers, id))
		log("save failed while listing for " .. player:getName())
		return refuse(player, MSG.busy)
	end
	if exec(string.format("UPDATE `%s` SET `state` = 0 WHERE `id` = %d AND `state` = 9", T.offers, id)) ~= 1 then
		log("offer " .. id .. " stays pending (activated at the next login / startup)")
	end
	logRow("list", {offer = id, player = guid, item = itemId, count = count, name = name,
		currency = (gold > 0 and "gold" or "") .. (coins > 0 and "coins" or ""), amount = gold > 0 and gold or coins, fee = fee,
		text = string.format("gold %d coins %d days %d realm %d codec %s", gold, coins, days, realm, codec)})
	send(player, "done", {what = "list", id = id, text = string.format("Listed %s%s for %s. Listing fee: %s gold.",
		count > 1 and (count .. "x ") or "", name, MK.priceText(gold, coins), MC.money(fee))})
	sendWallet(player)
	return true
end

function MK.priceText(gold, coins)
	local parts = {}
	if (gold or 0) > 0 then
		parts[#parts + 1] = MC.money(gold) .. " gold"
	end
	if (coins or 0) > 0 then
		parts[#parts + 1] = MC.money(coins) .. " Chaos Coins"
	end
	return table.concat(parts, " or ")
end

-- ------------------------------------------------------------------ buying
function MK.buy(player, d)
	local ok, why = canUse(player)
	if not ok then
		return refuse(player, why)
	end
	if not rate(player, "buy") then
		return refuse(player, MSG.slow)
	end
	local id = MC.int(d.id)
	local o = id and offerById(id)
	local t = now()
	if not o or o.state ~= MC.STATE.active or o.expires <= t then
		return refuse(player, MSG.notFound)
	end
	local guid, account = player:getGuid(), player:getAccountId()
	if o.seller_id == guid then
		return refuse(player, MSG.ownOffer)
	end
	if o.seller_account == account then
		return refuse(player, MSG.ownAccount)
	end
	local season = currentSeason()
	local realm = realmOf(player)
	if MC.realmOf(o.realm, season) ~= realm or realmOfGuid(o.seller_id) ~= realm then
		return refuse(player, MSG.realm)
	end
	local cur = d.cur == "coins" and "coins" or "gold"
	local price = cur == "coins" and o.price_coins or o.price_gold
	if price <= 0 then
		return refuse(player, MSG.noCurrency)
	end
	local tax, net = MC.tax(cfg, cur, price)
	local name = player:getName()

	local sold
	if cur == "gold" then
		if player:getBankBalance() < price then
			return refuse(player, MSG.noGold)
		end
		-- the database must hold exactly what the character holds before the price is taken there
		if not player:save() then
			return refuse(player, MSG.busy)
		end
		local balance = player:getBankBalance()
		sold = transaction(function()
			if exec(string.format("UPDATE `players` SET `balance` = `balance` - %d WHERE `id` = %d AND `balance` >= %d", price, guid, price)) ~= 1 then
				return false
			end
			if exec(string.format("UPDATE `%s` SET `state` = 1, `buyer_id` = %d, `buyer_name` = %s, `paid_currency` = 'gold', `paid_amount` = %d, "
					.. "`tax` = %d, `closed_at` = %d WHERE `id` = %d AND `state` = 0 AND `expires` > %d", T.offers, guid, esc(name), price, tax, t, id, t)) ~= 1 then
				return false
			end
			if dropIndex(id) < 0 then
				return false
			end
			if exec(string.format("INSERT INTO `%s` (`player_id`, `offer_id`, `kind`, `amount`, `reason`, `created`) VALUES (%d, %d, 'item', 0, 'bought', %d)",
					T.deliveries, guid, id, t)) ~= 1 then
				return false
			end
			if net > 0 and exec(string.format("INSERT INTO `%s` (`player_id`, `offer_id`, `kind`, `amount`, `reason`, `created`) VALUES (%d, %d, 'gold', %d, 'sold', %d)",
					T.deliveries, o.seller_id, id, net, t)) ~= 1 then
				return false
			end
			return true
		end)
		if sold then
			player:setBankBalance(balance - price)
		end
	else
		if coinsOf(account) < price then
			return refuse(player, MSG.noCoins)
		end
		sold = transaction(function()
			if exec(string.format("UPDATE `%s` SET `coins` = `coins` - %d WHERE `account_id` = %d AND `coins` >= %d", COINS, price, account, price)) ~= 1 then
				return false
			end
			if exec(string.format("UPDATE `%s` SET `state` = 1, `buyer_id` = %d, `buyer_name` = %s, `paid_currency` = 'coins', `paid_amount` = %d, "
					.. "`tax` = %d, `closed_at` = %d WHERE `id` = %d AND `state` = 0 AND `expires` > %d", T.offers, guid, esc(name), price, tax, t, id, t)) ~= 1 then
				return false
			end
			if dropIndex(id) < 0 then
				return false
			end
			if net > 0 and exec(string.format("INSERT INTO `%s` (`account_id`, `coins`) VALUES (%d, %d) ON DUPLICATE KEY UPDATE `coins` = `coins` + %d",
					COINS, o.seller_account, net, net)) < 1 then
				return false
			end
			if exec(string.format("INSERT INTO `%s` (`player_id`, `offer_id`, `kind`, `amount`, `reason`, `created`) VALUES (%d, %d, 'item', 0, 'bought', %d)",
					T.deliveries, guid, id, t)) ~= 1 then
				return false
			end
			-- the coins are already on the seller's account; this row only tells the seller (now or at the next login)
			if exec(string.format("INSERT INTO `%s` (`player_id`, `offer_id`, `kind`, `amount`, `reason`, `created`) VALUES (%d, %d, 'coins', %d, 'sold', %d)",
					T.deliveries, o.seller_id, id, net, t)) ~= 1 then
				return false
			end
			return true
		end)
	end
	if not sold then
		sendWallet(player)
		return refuse(player, MSG.notFound)
	end
	logRow("buy", {offer = id, player = guid, other = o.seller_id, item = o.item_id, count = o.count, name = o.name, currency = cur,
		amount = price, fee = tax, text = string.format("net %d to %s (account %d)", net, o.seller_name, o.seller_account)})
	send(player, "done", {what = "buy", id = id, text = string.format("Bought %s%s for %s %s. It is in your inbox.",
		o.count > 1 and (o.count .. "x ") or "", o.name, MC.money(price), cur == "coins" and "Chaos Coins" or "gold")})
	MK.deliver(player)
	sendWallet(player)
	local seller = Player(o.seller_id)
	local soldText = string.format("%s bought your %s%s for %s %s (tax %s): %s %s %s.", name, o.count > 1 and (o.count .. "x ") or "", o.name,
		MC.money(price), cur == "coins" and "Chaos Coins" or "gold", MC.money(tax), MC.money(net), cur == "coins" and "Chaos Coins" or "gold",
		cur == "coins" and "added to your account" or "to your bank")
	if seller then
		tell(seller, soldText)
		MK.deliver(seller) -- the gold (or the coins notice), with its toast
		sendWallet(seller)
	end
	return true
end

-- ------------------------------------------------------------------ cancel and expiry
local function closeOffer(id, state, reason, sellerId)
	local t = now()
	return transaction(function()
		if exec(string.format("UPDATE `%s` SET `state` = %d, `closed_at` = %d WHERE `id` = %d AND `state` = 0", T.offers, state, t, id)) ~= 1 then
			return false
		end
		if dropIndex(id) < 0 then
			return false
		end
		return exec(string.format("INSERT INTO `%s` (`player_id`, `offer_id`, `kind`, `amount`, `reason`, `created`) VALUES (%d, %d, 'item', 0, %s, %d)",
			T.deliveries, sellerId, id, esc(reason), t)) == 1
	end)
end

function MK.cancel(player, d)
	if not rate(player, "cancel") then
		return refuse(player, MSG.slow)
	end
	local id = MC.int(d.id)
	local o = id and offerById(id)
	if not o or o.seller_id ~= player:getGuid() or o.state ~= MC.STATE.active then
		return refuse(player, MSG.notFound)
	end
	if not closeOffer(id, MC.STATE.cancelled, "cancelled", o.seller_id) then
		return refuse(player, MSG.notFound)
	end
	logRow("cancel", {offer = id, player = o.seller_id, item = o.item_id, count = o.count, name = o.name})
	send(player, "done", {what = "cancel", id = id, text = string.format("Offer cancelled: %s goes back to your inbox.", o.name)})
	MK.deliver(player)
	return true
end

function MK.sweep()
	local t = now()
	local rows = sql(string.format("SELECT `id`, `seller_id`, `item_id`, `count`, `name` FROM `%s` WHERE `state` = 0 AND `expires` <= %d ORDER BY `id` LIMIT %d",
		T.offers, t, cfg.sweepBatch), {{"id", "n"}, {"seller_id", "n"}, {"item_id", "n"}, {"count", "n"}, {"name", "s"}})
	local n = 0
	for _, o in ipairs(rows) do
		if closeOffer(o.id, MC.STATE.expired, "expired", o.seller_id) then
			n = n + 1
			logRow("expire", {offer = o.id, player = o.seller_id, item = o.item_id, count = o.count, name = o.name})
			deliverIfOnline(o.seller_id)
		end
	end
	return n
end

-- ------------------------------------------------------------------ views
function MK.meta(player)
	local season, s = currentSeason()
	local realm = realmOf(player)
	local fee = cfg.listingFee
	return {
		categories = cfg.categories, durations = cfg.durations, defaultDuration = cfg.defaultDuration, sorts = cfg.sorts,
		fee = {pct = fee.pct, min = fee.minFee, max = fee.maxFee, coinGold = fee.coinFeeGold}, tax = cfg.tax,
		price = cfg.price, maxActive = cfg.maxActive, pageSize = cfg.pageSize, modFilter = cfg.modFilter,
		realm = realm, realmName = realm > 0 and s and ((s.tag and (s.tag .. " ") or "") .. (s.name or "Season")) or "Standard",
		gold = player:getBankBalance(), coins = coinsOf(player:getAccountId()), blob = HAS_BLOB
	}
end

function MK.browse(player, filter)
	if not rate(player, "browse") then
		return
	end
	local realm = realmOf(player)
	local t = now()
	local where, order, page, offset = MC.browseQuery(filter, realm, t, cfg, esc, (currentSeason()), MK.knownMods())
	if not where then
		return refuse(player, order)
	end
	local total = (sql(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE %s", T.offers, where), {{"n", "n"}})[1] or {n = 0}).n
	local pages = MC.pages(total, cfg)
	if page > pages then
		page = pages
		offset = (page - 1) * cfg.pageSize
	end
	local rows = sql(string.format("SELECT %s FROM `%s` WHERE %s ORDER BY %s LIMIT %d OFFSET %d", OFFER_SELECT, T.offers, where, order,
		cfg.pageSize, offset), OFFER_COLS)
	local list = {}
	for _, r in ipairs(rows) do
		local v = MC.rowView(r, t)
		v.mine = r.seller_id == player:getGuid() or nil
		list[#list + 1] = v
	end
	send(player, "page", {rows = list, page = page, pages = pages, total = total, seq = filter and filter.seq})
end

function MK.tip(player, d)
	if not rate(player, "tip") then
		return
	end
	local id = MC.int(d.id)
	if not id then
		return
	end
	local r = sql(string.format("SELECT `tip`, `seller_name`, `realm`, `state`, `seller_id`, `buyer_id` FROM `%s` WHERE `id` = %d", T.offers, id),
		{{"tip", "s"}, {"seller_name", "s"}, {"realm", "n"}, {"state", "n"}, {"seller_id", "n"}, {"buyer_id", "n"}})[1]
	if not r then
		return send(player, "tip", {id = id, gone = true})
	end
	local guid = player:getGuid()
	if r.seller_id ~= guid and r.buyer_id ~= guid and MC.realmOf(r.realm, (currentSeason())) ~= realmOf(player) then
		return send(player, "tip", {id = id, gone = true})
	end
	local ok, tip = pcall(json.decode, r.tip)
	send(player, "tip", {id = id, tip = ok and tip or nil, seller = r.seller_name})
end

function MK.mine(player)
	if not rate(player, "mine") then
		return
	end
	local guid, t = player:getGuid(), now()
	local active, closed = {}, {}
	for _, r in ipairs(sql(string.format("SELECT %s FROM `%s` WHERE `seller_id` = %d AND `state` = 0 ORDER BY `expires`", OFFER_SELECT, T.offers, guid), OFFER_COLS)) do
		active[#active + 1] = MC.rowView(r, t)
	end
	for _, r in ipairs(sql(string.format("SELECT %s FROM `%s` WHERE `seller_id` = %d AND `state` IN (1, 2, 3) ORDER BY `closed_at` DESC, `id` DESC LIMIT %d",
			OFFER_SELECT, T.offers, guid, cfg.historyRows), OFFER_COLS)) do
		closed[#closed + 1] = MC.rowView(r, t)
	end
	local owed = (sql(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `player_id` = %d AND `delivered` = 0", T.deliveries, guid), {{"n", "n"}})[1] or {n = 0}).n
	send(player, "mine", {active = active, closed = closed, owed = owed, max = cfg.maxActive})
end

function MK.history(player)
	if not rate(player, "mine") then
		return
	end
	local guid, t = player:getGuid(), now()
	local rows = {}
	for _, r in ipairs(sql(string.format("SELECT %s FROM `%s` WHERE `state` = 1 AND (`buyer_id` = %d OR `seller_id` = %d) ORDER BY `closed_at` DESC LIMIT %d",
			OFFER_SELECT, T.offers, guid, guid, cfg.historyRows), OFFER_COLS)) do
		local v = MC.rowView(r, t)
		v.side = r.buyer_id == guid and "bought" or "sold"
		rows[#rows + 1] = v
	end
	send(player, "history", {rows = rows})
end

function MK.open(player)
	local ok, why = canUse(player)
	if not ok then
		player:sendCancelMessage(why)
		return false
	end
	send(player, "meta", MK.meta(player))
	return true
end

-- ------------------------------------------------------------------ events
local ext = CreatureEvent("ChaosMarketExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local d = type(msg.data) == "table" and msg.data or {}
	local a = msg.action
	if a == "open" then
		MK.open(player)
	elseif a == "browse" then
		MK.browse(player, d)
	elseif a == "tip" then
		MK.tip(player, d)
	elseif a == "buy" then
		MK.buy(player, d)
	elseif a == "sellable" then
		if rate(player, "sellable") then
			send(player, "sellable", {items = sellable(player)})
		end
	elseif a == "list" then
		MK.list(player, d)
	elseif a == "cancel" then
		MK.cancel(player, d)
	elseif a == "mine" then
		MK.mine(player)
	elseif a == "history" then
		MK.history(player)
	elseif a == "wallet" then
		sendWallet(player)
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosMarketLogin")
function login.onLogin(player)
	player:registerEvent("ChaosMarketExtended")
	player:registerEvent("ChaosMarketLogout")
	saveFlag[player:getGuid()] = nil
	addEvent(function(pid)
		local p = Player(pid)
		if p then
			MK.recoverPlayer(p)
			MK.deliver(p)
		end
	end, 1500, player:getId())
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosMarketLogout")
function logout.onLogout(player)
	saveFlag[player:getGuid()] = nil
	return true
end
logout:type("logout")
logout:register()

local startup = GlobalEvent("ChaosMarketStartup")
function startup.onStartup()
	for _, q in ipairs(SCHEMA) do
		db.query(q)
	end
	MK.recoverAll()
	MK.backfillIndex()
	if not HAS_BLOB then
		print("[Warning - Chaos market] engine patch 0017 (item:serializeAttributes) missing: listed items are copied by a key list")
	end
	return true
end
startup:register()

local sweep = GlobalEvent("ChaosMarketSweep")
function sweep.onThink(interval)
	MK.sweep()
	return true
end
sweep:interval(cfg.sweepSeconds * 1000)
sweep:register()

-- the market item of the depot lockers (its stock `function="market"` line is removed by tools/patch_market.py)
local marketItem = Action()
function marketItem.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	send(player, "openWindow", {})
	MK.open(player)
	return true
end
marketItem:id(cfg.marketItemId)
marketItem:register()

-- staff: /market sweep | info <offer id>
local staffCmd = TalkAction("/market")
function staffCmd.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local p = tostring(param or ""):gsub("^%s+", "")
	if p == "sweep" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Market sweep: " .. MK.sweep() .. " offers expired.")
	elseif p:match("^info") then
		local o = offerById(MC.int(p:match("(%d+)")) or 0)
		player:sendTextMessage(MESSAGE_INFO_DESCR, o and string.format("Offer %d: %s x%d state %s seller %s realm %d gold %d coins %d expires in %ds",
			o.id, o.name, o.count, MC.STATE_NAME[o.state] or "?", o.seller_name, o.realm, o.price_gold, o.price_coins, o.expires - now()) or "No such offer.")
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, "/market sweep | info <offer id>    (escrow codec: " .. (HAS_BLOB and "blob" or "attrs") .. ")")
	end
	return false
end
staffCmd:separator(" ")
staffCmd:register()

return MK
