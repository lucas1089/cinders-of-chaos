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
--   sold      the seller's "sold" row is its notification queue too: told when applied (online at once, else at the
--             next login as "While you were away: ..."), ITEM SOLD toast and chat lines from market_notify_core.lua.
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.market; big answers go through Chaos.sendChunked:
--   client -> server  open | browse {filter: market_core.lua C.browseQuery, modifier rows C.modFilter} | tip {id} | buy {id, cur} | sellable | list {ref|pos, sid, iid, count,
--                     gold, coins, days} | cancel {id} | mine | history
--                     buy orders: orders {q, cat, cur, mine, sort, page, seq} | myOrders | orderFind {q} |
--                     orderPost {sid, quantity, price, cur, days, filter {rarity, ilvl, mods, need, sockets, quality, freeP,
--                     freeS, power, bound}} | orderCancel {id} | fillable {id} | fill {id, ref, sid, iid, count}
--   server -> client  meta {...} | page {rows, page, pages, total} | tip {id, tip, seller} | sellable {items} |
--                     mine {active, closed, owed} | history {rows} | wallet {gold, coins} | done {what, text} |
--                     error {text} | orders {rows, page, pages, total} | myOrders {active, closed, max} |
--                     orderFind {items} | fillable {id, order, items}
--   price history (market_history.lua): prices {id | sid, rarity, ilvl} -> prices {gold, coins, marks, warn}
--
-- Buy orders (market_orders_core.lua, table chaos_market_orders): the payment is escrowed in the order row at posting
-- (gold: player:save(), then ONE transaction takes price x quantity + the fee from players.balance and writes the order;
-- coins: the same transaction takes the coins from chaos_shop_coins). A fill is written like a listing that sells at
-- once: 1. a chaos_market_offers row (order_id = the order) "pending"  2. the item and listSeq change in memory
-- 3. player:save()  4. ONE transaction (MK.completeFill) moves the units on the order (filled, escrow), marks the row
-- sold and writes the deliveries (item -> buyer's inbox, gold -> seller's bank or coins -> seller's account). A
-- pending fill found later is completed (or its item returned when the order closed). Cancel / expiry refunds the
-- escrow left: gold as a delivery row (offer_id = -order id, reason refund), coins straight to the account.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosMarketCore then
	dofile("data/scripts/chaos/market_core.lua")
end
if not ChaosMarketOrders then
	dofile("data/scripts/chaos/market_orders_core.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua")
end
if not ChaosItemTooltip then
	dofile("data/scripts/chaos/item_tooltip_core.lua")
end
if not ChaosMarketNotify then
	dofile("data/scripts/chaos/market_notify_core.lua")
end

Chaos.marketConfig = dofile("data/scripts/chaos/market_config.lua")
local cfg = Chaos.marketConfig
local MC = ChaosMarketCore
local MO = ChaosMarketOrders
ChaosMarket = ChaosMarket or {}
local MK = ChaosMarket
local OPCODE = ChaosOpcodes.market or 221
local T = cfg.tables
local S_LIST, S_DELIVER = cfg.storage.listSeq, cfg.storage.deliverSeq
local MSG = cfg.messages
local COINS = (Chaos.tables and Chaos.tables.shopCoins) or "chaos_shop_coins"

-- >>> Chaos Pact listing slots (pact.lua): active offers per character and per account. Offers above a smaller limit
-- (the Pact ran out) stay on the market until they sell, expire or are cancelled; only new listings are refused.
function MK.maxActive(player)
	local P = ChaosPact
	if P and P.limit then
		return P.limit(player, "marketListings"), P.limit(player, "marketAccount")
	end
	return cfg.maxActive, cfg.maxActivePerAccount
end
-- <<< Chaos Pact listing slots

-- active listings of a character and of its account: sell offers (fills of buy orders are not listings) and buy
-- orders together; both count against MK.maxActive
function MK.activeCounts(guid, account)
	local function count(q)
		local r = Chaos.select(q, {{"n", "n"}})[1]
		return r and r.n or 0
	end
	local T0 = cfg.tables
	local char = count(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `seller_id` = %d AND `state` IN (0, 9) AND `order_id` = 0", T0.offers, guid))
		+ count(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `buyer_id` = %d AND `state` = 0", T0.orders, guid))
	local acc = count(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `seller_account` = %d AND `state` IN (0, 9) AND `order_id` = 0", T0.offers, account))
		+ count(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `buyer_account` = %d AND `state` = 0", T0.orders, account))
	return char, acc
end

-- why this character cannot add another offer or order (nil = it can)
function MK.limitRefusal(player)
	local maxChar, maxAccount = MK.maxActive(player)
	local char, acc = MK.activeCounts(player:getGuid(), player:getAccountId())
	if char >= maxChar then
		return string.format(cfg.messages.maxActive, maxChar)
	end
	if acc >= maxAccount then
		return string.format(cfg.messages.maxAccount, maxAccount)
	end
	return nil
end

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
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	-- buy orders (sql/chaos_market.sql has the same statements)
	[[CREATE TABLE IF NOT EXISTS `chaos_market_orders` (`id` int(11) NOT NULL AUTO_INCREMENT,
	`realm` int(11) NOT NULL DEFAULT 0, `state` tinyint(3) unsigned NOT NULL DEFAULT 0,
	`buyer_id` int(11) NOT NULL, `buyer_account` int(11) NOT NULL, `buyer_name` varchar(64) NOT NULL DEFAULT '',
	`item_id` int(11) NOT NULL, `client_id` int(11) NOT NULL DEFAULT 0, `name` varchar(100) NOT NULL DEFAULT '',
	`category` varchar(16) NOT NULL DEFAULT 'misc', `stackable` tinyint(1) NOT NULL DEFAULT 0,
	`quantity` int(11) NOT NULL DEFAULT 1, `filled` int(11) NOT NULL DEFAULT 0, `currency` varchar(8) NOT NULL DEFAULT 'gold',
	`price` bigint(20) unsigned NOT NULL DEFAULT 0, `escrow` bigint(20) unsigned NOT NULL DEFAULT 0,
	`refunded` bigint(20) unsigned NOT NULL DEFAULT 0, `fee` bigint(20) unsigned NOT NULL DEFAULT 0,
	`filter` varchar(1000) NOT NULL DEFAULT '', `created` int(10) unsigned NOT NULL, `expires` int(10) unsigned NOT NULL,
	`closed_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`),
	KEY `chaos_market_orders_list` (`state`, `realm`, `expires`), KEY `chaos_market_orders_buyer` (`buyer_id`, `state`),
	KEY `chaos_market_orders_account` (`buyer_account`, `state`), KEY `chaos_market_orders_item` (`item_id`, `state`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	-- a fill of a buy order is an offer row that sold at once (order_id = the order; 0 = a sell offer)
	[[ALTER TABLE `chaos_market_offers` ADD COLUMN IF NOT EXISTS `order_id` int(11) NOT NULL DEFAULT 0,
	ADD INDEX IF NOT EXISTS `chaos_market_offer_order` (`order_id`)]]
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
	{"buyer_name", "s"}, {"paid_currency", "s"}, {"paid_amount", "n"}, {"tax", "n"}, {"closed_at", "n"}, {"order_id", "n"}}
local OFFER_SELECT = "`id`, `realm`, `state`, `seller_id`, `seller_account`, `seller_name`, `item_id`, `client_id`, `count`, `name`, "
	.. "`category`, `rarity`, `ilvl`, `unique_item`, `price_gold`, `price_coins`, `created`, `expires`, `buyer_id`, `buyer_name`, "
	.. "`paid_currency`, `paid_amount`, `tax`, `closed_at`, `order_id`"

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

-- a toast of the notification module (notifications.lua ChaosNotify.send; kind "sale" = the ITEM SOLD header)
local function notify(player, title, text, kind)
	if ChaosNotify and ChaosNotify.send then
		return ChaosNotify.send(player, title, text, kind)
	end
	if ChaosOpcodes.notifications then
		player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = kind, message = title ~= "" and (title .. ": " .. text) or text}))
	end
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
	"rift_mods", "prefix", "chaos_mods_pending", "chaos_tmog"}

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
	if ChaosCharms and ChaosCharms.attributeKeys then -- a charm's modifiers (charms.lua)
		for _, k in ipairs(ChaosCharms.attributeKeys()) do
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
				-- a transmog look (transmog.lua): the picker draws the item as it looks
				local look = tonumber(item:getCustomAttribute("chaos_tmog")) or 0
				if look > 0 then
					out[#out].look = ItemType(look):getClientId()
				end
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

local REASON_TEXT = {bought = "bought", cancelled = "offer cancelled", expired = "offer expired", sold = "sold",
	order = "from your buy order", returned = "the buy order closed before your fill"}

-- applies everything the market owes this (online) character; returns how many rows were applied now.
-- away = the login delivery: sales made while the seller was offline are summed up as "While you were away: ...".
-- Sales (reason "sold") are told through market_notify_core.lua: one chat line each (capped by cfg.notify.lines) and
-- one toast; a row is told only when this call applied it, so a row already applied (deliverSeq) is never told twice.
function MK.deliver(player, away)
	local guid = player:getGuid()
	local rows = deliveryRows(guid)
	if #rows == 0 then
		return 0
	end
	local mark = math.max(0, player:getStorageValue(S_DELIVER))
	local done, todo = MC.deliveryPlan(rows, mark)
	local applied, lines = {}, {}
	local sales = ChaosMarketNotify.newBatch(cfg.notify and cfg.notify.lines)
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
		elseif (r.kind == "gold" or r.kind == "coins") and r.reason == "refund" then
			-- what a closed buy order did not spend (offer_id = -order id; coins were already put back on the account)
			if r.kind == "gold" then
				player:setBankBalance(player:getBankBalance() + r.amount)
			end
			lines[#lines + 1] = string.format("+%s %s back from your buy order %d", MC.money(r.amount), r.kind == "gold" and "gold" or "Chaos Coins",
				-r.offer_id)
		elseif r.kind == "gold" or r.kind == "coins" then
			if r.kind == "gold" then
				player:setBankBalance(player:getBankBalance() + r.amount)
			end
			local o = sql(string.format("SELECT `name`, `count`, `buyer_name`, `paid_amount`, `tax`, `order_id` FROM `%s` WHERE `id` = %d",
				T.offers, r.offer_id), {{"name", "s"}, {"count", "n"}, {"buyer_name", "s"}, {"paid_amount", "n"}, {"tax", "n"},
				{"order_id", "n"}})[1] or {name = "an item", count = 1, buyer_name = "?"}
			local sale = ChaosMarketNotify.saleOf(r, o)
			if sale then
				ChaosMarketNotify.add(sales, sale)
			else
				lines[#lines + 1] = string.format("+%s %s (sold %s%s to %s)", MC.money(r.amount), r.kind == "gold" and "gold" or "Chaos Coins",
					o.count > 1 and (o.count .. "x ") or "", o.name, o.buyer_name)
			end
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
	local sold = ChaosMarketNotify.summary(sales, away)
	if sold then
		for _, line in ipairs(sold.lines) do
			tell(player, line)
		end
		notify(player, sold.title, sold.text, "sale")
	end
	if #lines > 0 then
		tell(player, table.concat(lines, "; ") .. ". Items are in your inbox, gold in your bank.")
		toast(player, #lines == 1 and lines[1] or string.format("%d market deliveries: see the Server Log.", #lines))
	end
	if sold or #lines > 0 then
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

-- a listing interrupted by a crash (state pending): activate it or drop it (MC.pendingAction). A buy order fill
-- (orderId > 0) whose item left the seller is completed instead (or its item returned when the order is closed)
local function resolvePending(id, sellerId, listSeq, orderId)
	local action = MC.pendingAction(id, listSeq)
	if action == "activate" and (orderId or 0) > 0 then
		local done = MK.completeFill(id)
		action = done and "fill" or "fill returned"
	elseif action == "activate" then
		exec(string.format("UPDATE `%s` SET `state` = 0 WHERE `id` = %d AND `state` = 9", T.offers, id))
	elseif exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `state` = 9", T.offers, id)) == 1 then
		dropIndex(id)
	end
	logRow("recover", {offer = id, player = sellerId, text = "pending listing: " .. action})
	return action
end

function MK.recoverPlayer(player)
	local rows = sql(string.format("SELECT `id`, `order_id` FROM `%s` WHERE `seller_id` = %d AND `state` = 9", T.offers, player:getGuid()),
		{{"id", "n"}, {"order_id", "n"}})
	for _, r in ipairs(rows) do
		resolvePending(r.id, player:getGuid(), player:getStorageValue(S_LIST), r.order_id)
	end
end

-- at startup every character is offline: the saved storage decides
function MK.recoverAll()
	local rows = sql(string.format("SELECT `id`, `seller_id`, `order_id` FROM `%s` WHERE `state` = 9", T.offers),
		{{"id", "n"}, {"seller_id", "n"}, {"order_id", "n"}})
	for _, r in ipairs(rows) do
		if not Player(r.seller_id) then
			local s = sql(string.format("SELECT `value` FROM `player_storage` WHERE `player_id` = %d AND `key` = %d", r.seller_id, S_LIST),
				{{"value", "n"}})[1]
			resolvePending(r.id, r.seller_id, s and s.value or 0, r.order_id)
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
	local limitRefusal = MK.limitRefusal(player)
	if limitRefusal then
		return refuse(player, limitRefusal)
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
	if ChaosMarketHistory then
		pcall(ChaosMarketHistory.record, id, realm) -- the price history (market_history.lua); never fails the sale
	end
	send(player, "done", {what = "buy", id = id, text = string.format("Bought %s%s for %s %s. It is in your inbox.",
		o.count > 1 and (o.count .. "x ") or "", o.name, MC.money(price), cur == "coins" and "Chaos Coins" or "gold")})
	MK.deliver(player)
	sendWallet(player)
	-- the seller online: told now by its delivery (the gold or the coins notice: one chat line and the ITEM SOLD toast);
	-- offline: the "sold" row waits in chaos_market_deliveries and is told at the next login
	local seller = Player(o.seller_id)
	if seller then
		MK.deliver(seller)
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

-- ------------------------------------------------------------------ buy orders
local ORDER_COLS = {{"id", "n"}, {"realm", "n"}, {"state", "n"}, {"buyer_id", "n"}, {"buyer_account", "n"}, {"buyer_name", "s"},
	{"item_id", "n"}, {"client_id", "n"}, {"name", "s"}, {"category", "s"}, {"stackable", "n"}, {"quantity", "n"}, {"filled", "n"},
	{"currency", "s"}, {"price", "n"}, {"escrow", "n"}, {"refunded", "n"}, {"fee", "n"}, {"filter", "s"}, {"created", "n"},
	{"expires", "n"}, {"closed_at", "n"}}
local ORDER_SELECT = "`id`, `realm`, `state`, `buyer_id`, `buyer_account`, `buyer_name`, `item_id`, `client_id`, `name`, `category`, "
	.. "`stackable`, `quantity`, `filled`, `currency`, `price`, `escrow`, `refunded`, `fee`, `filter`, `created`, `expires`, `closed_at`"
local OC = cfg.orders or {}

local function orderById(id)
	return sql(string.format("SELECT %s FROM `%s` WHERE `id` = %d", ORDER_SELECT, T.orders, id), ORDER_COLS)[1]
end
MK.orderById = orderById

local function curName(cur)
	return cur == "coins" and "Chaos Coins" or "gold"
end

-- the item kinds an order may name: pickupable, movable, not money
local function orderableType(sid)
	sid = MC.int(sid)
	if not sid or sid <= 0 or cfg.blockedIds[sid] then
		return nil
	end
	local it = ItemType(sid)
	if not it or (it.getId and it:getId() ~= sid) or call(it, "isPickupable") == false or call(it, "isMovable") == false then
		return nil
	end
	return it
end

-- the order form's search: item kinds by name (the exact name, a server id, the player's own items and every kind ever
-- listed on the market whose name contains the text)
function MK.orderFind(player, q)
	q = tostring(q or ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 40)
	local out, seen = {}, {}
	local function add(sid)
		if #out >= (OC.findMax or 20) or seen[sid] then
			return
		end
		local it = orderableType(sid)
		if it then
			seen[sid] = true
			out[#out + 1] = {sid = sid, item = it:getClientId(), name = it:getName(), stack = it:isStackable() or nil}
		end
	end
	if q == "" then
		return out
	end
	local num = tonumber(q)
	if num then
		add(num)
	else
		-- the engine's ItemType(name): the exact item name, case-insensitive (0 when there is none)
		local ok, sid = pcall(function() return ItemType(q):getId() end)
		sid = ok and tonumber(sid) or nil
		if sid and sid > 0 then
			add(sid)
		end
	end
	local low = q:lower()
	local bag = player:getSlotItem(BACKPACK)
	local function walk(container, depth)
		for i = 0, (call(container, "getSize") or 0) - 1 do
			local item = container:getItem(i)
			if item then
				if ItemType(item:getId()):getName():lower():find(low, 1, true) then
					add(item:getId())
				end
				if isContainer(item) and depth < 4 then
					walk(item, depth + 1)
				end
			end
		end
	end
	if bag and isContainer(bag) then
		walk(bag, 1)
	end
	for _, r in ipairs(sql(string.format("SELECT `item_id` FROM `%s` WHERE `name` LIKE %s ORDER BY `id` DESC LIMIT 200", T.offers,
			esc("%" .. MC.likeEscape(q) .. "%")), {{"item_id", "n"}})) do
		add(r.item_id)
	end
	return out
end

-- post a buy order: the whole payment and the fee leave the character in one transaction
function MK.orderPost(player, d)
	local ok, why = canUse(player)
	if not ok then
		return refuse(player, why)
	end
	if not rate(player, "orderPost") then
		return refuse(player, MSG.slow)
	end
	local it = orderableType(d.sid)
	if not it then
		return refuse(player, MSG.orderKind)
	end
	local o, refusal = MO.checkOrder(cfg, d, MK.knownMods())
	if not o then
		return refuse(player, refusal)
	end
	local limit = MK.limitRefusal(player)
	if limit then
		return refuse(player, limit)
	end
	local guid, account = player:getGuid(), player:getAccountId()
	local sid = MC.int(d.sid)
	local name = it:getName():sub(1, cfg.nameMax)
	local kind = ChaosItemMods and ChaosItemMods.kindOfType and ChaosItemMods.kindOfType(it) or nil
	local isGem = ChaosGems and ChaosGems.isGem and ChaosGems.isGem(sid) or false
	local category = MC.category(kind, name, isGem, name:lower():find("key$") ~= nil, o.filter.rarity)
	local goldTaken = o.cur == "gold" and (o.total + o.fee) or o.fee
	local balance = player:getBankBalance()
	if balance < goldTaken then
		if o.cur == "gold" then
			return refuse(player, string.format(MSG.orderGold, MC.money(goldTaken), MC.money(o.total), MC.money(o.fee)))
		end
		return refuse(player, string.format(MSG.orderCoins, MC.money(o.total), MC.money(o.fee)))
	end
	if o.cur == "coins" and coinsOf(account) < o.total then
		return refuse(player, string.format(MSG.orderCoins, MC.money(o.total), MC.money(o.fee)))
	end
	-- the database must hold exactly what the character holds before the money is taken there
	if not player:save() then
		return refuse(player, MSG.busy)
	end
	local realm = realmOf(player)
	local t = now()
	local filterText = MO.encodeFilter(o.filter)
	local id = 0
	local posted = transaction(function()
		if exec(string.format("UPDATE `players` SET `balance` = `balance` - %d WHERE `id` = %d AND `balance` >= %d", goldTaken, guid, goldTaken)) ~= 1 then
			return false
		end
		if o.cur == "coins" and exec(string.format("UPDATE `%s` SET `coins` = `coins` - %d WHERE `account_id` = %d AND `coins` >= %d", COINS,
				o.total, account, o.total)) ~= 1 then
			return false
		end
		if exec(string.format("INSERT INTO `%s` (`realm`, `state`, `buyer_id`, `buyer_account`, `buyer_name`, `item_id`, `client_id`, `name`, "
				.. "`category`, `stackable`, `quantity`, `filled`, `currency`, `price`, `escrow`, `refunded`, `fee`, `filter`, `created`, `expires`, "
				.. "`closed_at`) VALUES (%d, 0, %d, %d, %s, %d, %d, %s, %s, %d, %d, 0, %s, %d, %d, 0, %d, %s, %d, %d, 0)", T.orders, realm, guid, account,
				esc(player:getName()), sid, it:getClientId(), esc(name), esc(category), it:isStackable() and 1 or 0, o.quantity, esc(o.cur), o.price,
				o.total, o.fee, esc(filterText), t, t + o.days * 86400)) ~= 1 then
			return false
		end
		id = lastId()
		return id > 0
	end)
	if not posted then
		sendWallet(player)
		return refuse(player, MSG.busy)
	end
	player:setBankBalance(balance - goldTaken)
	logRow("order", {offer = -id, player = guid, item = sid, count = o.quantity, name = name, currency = o.cur, amount = o.total, fee = o.fee,
		text = string.format("buy order %d: %d x %d %s, days %d, realm %d, filter %s", id, o.quantity, o.price, o.cur, o.days, realm, filterText)})
	send(player, "done", {what = "orderPost", id = id, text = string.format("Buy order posted: %dx %s at %s %s each. %s %s are held for it; "
		.. "listing fee: %s gold.", o.quantity, name, MC.money(o.price), curName(o.cur), MC.money(o.total), curName(o.cur), MC.money(o.fee))})
	sendWallet(player)
	return true
end

-- close an active order (cancelled or expired) and give back what its escrow still holds; true when closed
local function closeOrder(o, state)
	local t = now()
	local amount = o.escrow
	return transaction(function()
		if exec(string.format("UPDATE `%s` SET `state` = %d, `closed_at` = %d, `refunded` = `escrow`, `escrow` = 0 WHERE `id` = %d AND `state` = 0 "
				.. "AND `escrow` = %d", T.orders, state, t, o.id, amount)) ~= 1 then
			return false
		end
		if amount <= 0 then
			return true
		end
		if o.currency == "coins" and exec(string.format("INSERT INTO `%s` (`account_id`, `coins`) VALUES (%d, %d) ON DUPLICATE KEY UPDATE `coins` = `coins` + %d",
				COINS, o.buyer_account, amount, amount)) < 1 then
			return false
		end
		-- gold: the delivery puts it in the bank; coins: the row only tells the buyer (now or at the next login)
		return exec(string.format("INSERT INTO `%s` (`player_id`, `offer_id`, `kind`, `amount`, `reason`, `created`) VALUES (%d, %d, %s, %d, 'refund', %d)",
			T.deliveries, o.buyer_id, -o.id, esc(o.currency == "coins" and "coins" or "gold"), amount, t)) == 1
	end)
end

function MK.orderCancel(player, d)
	if not rate(player, "orderCancel") then
		return refuse(player, MSG.slow)
	end
	local id = MC.int(d.id)
	local o = id and orderById(id)
	if not o or o.buyer_id ~= player:getGuid() or o.state ~= MO.STATE.active then
		return refuse(player, MSG.orderGone)
	end
	if not closeOrder(o, MO.STATE.cancelled) then
		return refuse(player, MSG.orderGone)
	end
	logRow("ordercancel", {offer = -id, player = o.buyer_id, item = o.item_id, count = o.quantity - o.filled, name = o.name, currency = o.currency,
		amount = o.escrow})
	send(player, "done", {what = "orderCancel", id = id, text = string.format("Buy order cancelled: %s %s come back to you; the listing fee is not refunded.",
		MC.money(o.escrow), curName(o.currency))})
	MK.deliver(player)
	sendWallet(player)
	return true
end

function MK.sweepOrders()
	local t = now()
	local rows = sql(string.format("SELECT %s FROM `%s` WHERE `state` = 0 AND `expires` <= %d ORDER BY `id` LIMIT %d", ORDER_SELECT, T.orders, t,
		cfg.sweepBatch), ORDER_COLS)
	local n = 0
	for _, o in ipairs(rows) do
		if closeOrder(o, MO.STATE.expired) then
			n = n + 1
			logRow("orderexpire", {offer = -o.id, player = o.buyer_id, item = o.item_id, count = o.quantity - o.filled, name = o.name,
				currency = o.currency, amount = o.escrow})
			local p = Player(o.buyer_id)
			if p then
				tell(p, string.format("your buy order for %s expired (%d of %d bought).", o.name, o.filled, o.quantity))
				MK.deliver(p)
				sendWallet(p)
			end
		end
	end
	return n
end

-- may a market of this realm trade in Chaos Coins? (season.lua: season markets are gold only; season_config.lua market)
local function coinsAllowed(realm)
	local S = ChaosSeason
	if (realm or 0) == 0 or not S or not S.marketCurrencyAllowed then
		return true
	end
	return S.marketCurrencyAllowed(realm, "coins", Chaos.seasonConfig and Chaos.seasonConfig.market) and true or false
end
MK.coinsAllowed = coinsAllowed

-- may this character fill this order at all? (nil = yes)
local function fillRefusal(player, o, t)
	if not o or o.state ~= MO.STATE.active or o.expires <= t or o.quantity - o.filled <= 0 then
		return MSG.orderGone
	end
	if o.buyer_id == player:getGuid() then
		return MSG.ownOrder
	end
	if o.buyer_account == player:getAccountId() then
		return MSG.ownAccountOrder
	end
	local realm = realmOf(player)
	if MC.realmOf(o.realm, (currentSeason())) ~= realm or realmOfGuid(o.buyer_id) ~= realm then
		return MSG.orderRealm
	end
	if o.currency == "coins" and not coinsAllowed(realm) then
		-- a coins order on a season market (posted before the gold-only rule): season characters take no coins
		return Chaos.seasonConfig and Chaos.seasonConfig.market and Chaos.seasonConfig.market.message or MSG.orderRealm
	end
	return nil
end

-- what the order filter reads from an item: rarity, item level and the searchable facts of its tooltip
local function itemFacts(item)
	local okTip, tip = pcall(ChaosItemTooltip.build, item, {})
	if not okTip or type(tip) ~= "table" then
		tip = {id = ItemType(item:getId()):getClientId(), name = item:getName()}
	end
	return {rarity = tonumber(tip.rarity) or 0, ilvl = tonumber(tip.level) or 0, index = MC.offerIndex(tip)}, tip
end

-- the seller's items (backpack and the bags in it) of the kind an order asks for, with why each cannot fill it
function MK.fillable(player, d)
	if not rate(player, "fillable") then
		return
	end
	local id = MC.int(d.id)
	local o = id and orderById(id)
	local t = now()
	local why = fillRefusal(player, o, t)
	if why then
		return refuse(player, why)
	end
	local f = MO.decodeFilter(o.filter)
	local out = {}
	local function walk(container, ref, depth)
		for i = 0, (call(container, "getSize") or 0) - 1 do
			if #out >= (OC.fillableMax or 40) then
				return
			end
			local item = container:getItem(i)
			if item then
				local r = ref .. "." .. i
				if item:getId() == o.item_id then
					local n = MO.fillCount(o, item:getCount(), nil, ItemType(item:getId()):isStackable())
					local refusal = MC.itemRefusal(itemInfo(player, item, math.max(1, n), false), cfg)
					local facts = itemFacts(item)
					local okMatch, missing = MO.matches(f, facts)
					out[#out + 1] = {ref = r, sid = item:getId(), item = ItemType(item:getId()):getClientId(), count = item:getCount(), fill = n,
						name = ChaosCrafting and ChaosCrafting.itemName(item) or item:getName(), rarity = facts.rarity, ilvl = facts.ilvl,
						iid = string.format("%.0f", iidOf(item)), stack = ItemType(item:getId()):isStackable() or nil,
						why = refusal or (not okMatch and missing) or nil}
					local look = tonumber(item:getCustomAttribute("chaos_tmog")) or 0
					if look > 0 then
						out[#out].look = ItemType(look):getClientId() -- a transmog look: the picker draws the item as it looks
					end
				end
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
	send(player, "fillable", {id = id, order = MO.rowView(o, t, player:getGuid()), items = out})
end

-- step 4 of a fill (and of a fill found pending after a crash): ONE transaction moves the units on the order, marks
-- the fill row sold and writes the deliveries. When the order cannot take them any more the item goes back to the
-- seller's inbox. Returns true (filled) or false (returned / nothing to do)
function MK.completeFill(fillId)
	local f = sql(string.format("SELECT `id`, `order_id`, `seller_id`, `seller_account`, `seller_name`, `count`, `price_gold`, `price_coins`, `name` "
		.. "FROM `%s` WHERE `id` = %d AND `state` = 9", T.offers, fillId), {{"id", "n"}, {"order_id", "n"}, {"seller_id", "n"},
		{"seller_account", "n"}, {"seller_name", "s"}, {"count", "n"}, {"price_gold", "n"}, {"price_coins", "n"}, {"name", "s"}})[1]
	if not f or f.order_id <= 0 then
		return false
	end
	local o = orderById(f.order_id)
	local t = now()
	local filled = o and transaction(function()
		local cur = o.currency
		local total = cur == "coins" and f.price_coins or f.price_gold
		local tax, net = MC.tax(cfg, cur, total)
		if exec(string.format("UPDATE `%s` SET `filled` = `filled` + %d, `escrow` = `escrow` - %d WHERE `id` = %d AND `state` = 0 AND "
				.. "`quantity` - `filled` >= %d AND `escrow` >= %d", T.orders, f.count, total, o.id, f.count, total)) ~= 1 then
			return false
		end
		if exec(string.format("UPDATE `%s` SET `state` = 1, `closed_at` = %d WHERE `id` = %d AND `state` = 0 AND `filled` = `quantity`",
				T.orders, t, o.id)) < 0 then
			return false
		end
		if exec(string.format("UPDATE `%s` SET `state` = 1, `buyer_id` = %d, `buyer_name` = %s, `paid_currency` = %s, `paid_amount` = %d, `tax` = %d, "
				.. "`closed_at` = %d WHERE `id` = %d AND `state` = 9", T.offers, o.buyer_id, esc(o.buyer_name), esc(cur), total, tax, t, f.id)) ~= 1 then
			return false
		end
		if exec(string.format("INSERT INTO `%s` (`player_id`, `offer_id`, `kind`, `amount`, `reason`, `created`) VALUES (%d, %d, 'item', 0, 'order', %d)",
				T.deliveries, o.buyer_id, f.id, t)) ~= 1 then
			return false
		end
		if cur == "gold" then
			if net > 0 and exec(string.format("INSERT INTO `%s` (`player_id`, `offer_id`, `kind`, `amount`, `reason`, `created`) VALUES (%d, %d, 'gold', %d, 'sold', %d)",
					T.deliveries, f.seller_id, f.id, net, t)) ~= 1 then
				return false
			end
		else
			if net > 0 and exec(string.format("INSERT INTO `%s` (`account_id`, `coins`) VALUES (%d, %d) ON DUPLICATE KEY UPDATE `coins` = `coins` + %d",
					COINS, f.seller_account, net, net)) < 1 then
				return false
			end
			if exec(string.format("INSERT INTO `%s` (`player_id`, `offer_id`, `kind`, `amount`, `reason`, `created`) VALUES (%d, %d, 'coins', %d, 'sold', %d)",
					T.deliveries, f.seller_id, f.id, net, t)) ~= 1 then
				return false
			end
		end
		return true
	end)
	if filled then
		logRow("fill", {offer = f.id, player = f.seller_id, other = o.buyer_id, count = f.count, name = f.name, currency = o.currency,
			amount = o.currency == "coins" and f.price_coins or f.price_gold, text = "buy order " .. o.id})
		if ChaosMarketHistory then
			pcall(ChaosMarketHistory.record, f.id, MC.realmOf(o.realm, (currentSeason()))) -- the price history (market_history.lua)
		end
		return true
	end
	-- the order is gone (or full): the item goes back to the seller
	local back = transaction(function()
		if exec(string.format("UPDATE `%s` SET `state` = 2, `closed_at` = %d WHERE `id` = %d AND `state` = 9", T.offers, t, f.id)) ~= 1 then
			return false
		end
		return exec(string.format("INSERT INTO `%s` (`player_id`, `offer_id`, `kind`, `amount`, `reason`, `created`) VALUES (%d, %d, 'item', 0, 'returned', %d)",
			T.deliveries, f.seller_id, f.id, t)) == 1
	end)
	logRow(back and "fillback" or "error", {offer = f.id, player = f.seller_id, count = f.count, name = f.name,
		text = back and ("buy order " .. f.order_id .. " closed: item returned") or ("fill " .. f.id .. " stays pending")})
	return false
end

-- fill a buy order with an item of the backpack (a stack in part: d.count)
function MK.fill(player, d)
	local ok, why = canUse(player)
	if not ok then
		return refuse(player, why)
	end
	if not rate(player, "fill") then
		return refuse(player, MSG.slow)
	end
	local id = MC.int(d.id)
	local o = id and orderById(id)
	local t = now()
	local refusal = fillRefusal(player, o, t)
	if refusal then
		return refuse(player, refusal)
	end
	local item, equipped
	if d.ref then
		item, equipped = resolveRef(player, d.ref)
	elseif d.pos then
		item, equipped = resolvePos(player, d.pos)
	end
	if not item or (d.sid and tonumber(d.sid) ~= item:getId()) or (tonumber(d.iid) or 0) ~= iidOf(item) then
		return refuse(player, MSG.noItem)
	end
	if item:getId() ~= o.item_id then
		return refuse(player, MSG.orderItem)
	end
	local it = ItemType(item:getId())
	local n = MO.fillCount(o, item:getCount(), d.count, it:isStackable())
	if n <= 0 then
		return refuse(player, MSG.orderGone)
	end
	refusal = MC.itemRefusal(itemInfo(player, item, n, equipped), cfg)
	if refusal then
		return refuse(player, refusal)
	end
	local facts, tip = itemFacts(item)
	local fits, missing = MO.matches(MO.decodeFilter(o.filter), facts)
	if not fits then
		return refuse(player, "That item does not fit the order: " .. missing)
	end
	local total, tax, net = MO.payment(cfg, o.currency, o.price, n)
	if o.escrow < total then
		return refuse(player, MSG.orderGone)
	end
	tip.count = n
	tip.key = nil
	local modKeys = {}
	for _, m in ipairs(tip.mods or {}) do
		modKeys[#modKeys + 1] = m.k
	end
	local name = (ChaosCrafting and ChaosCrafting.itemName(item) or item:getName()):sub(1, cfg.nameMax)
	local codec, data = MK.encode(item)
	local guid = player:getGuid()

	-- 1. the fill row (an offer row that sells at once), pending
	if exec(string.format("INSERT INTO `%s` (`realm`, `state`, `seller_id`, `seller_account`, `seller_name`, `item_id`, `client_id`, `count`, "
			.. "`name`, `category`, `rarity`, `ilvl`, `unique_item`, `mods`, `price_gold`, `price_coins`, `fee`, `codec`, `data`, `tip`, `created`, "
			.. "`expires`, `buyer_id`, `buyer_name`, `mods_indexed`, `order_id`) VALUES (%d, 9, %d, %d, %s, %d, %d, %d, %s, %s, %d, %d, %d, %s, %d, %d, 0, "
			.. "%s, %s, %s, %d, %d, %d, %s, 1, %d)", T.offers, o.realm, guid, player:getAccountId(), esc(player:getName()), item:getId(), it:getClientId(),
			n, esc(name), esc(o.category), facts.rarity, facts.ilvl, tip.unique and 1 or 0, esc(MC.modsField(modKeys)),
			o.currency == "gold" and total or 0, o.currency == "coins" and total or 0, esc(codec), esc(data), esc(json.encode(tip)), t, t,
			o.buyer_id, esc(o.buyer_name), o.id)) ~= 1 then
		return refuse(player, MSG.busy)
	end
	local fid = lastId()
	if fid <= 0 then
		return refuse(player, MSG.busy)
	end
	-- 2. the item and the marker change in memory
	local itemId = item:getId()
	local removed
	if it:isStackable() and n < item:getCount() then
		removed = item:remove(n)
	else
		removed = item:remove()
	end
	if not removed then
		exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `state` = 9", T.offers, fid))
		return refuse(player, MSG.noItem)
	end
	local oldSeq = player:getStorageValue(S_LIST)
	player:setStorageValue(S_LIST, fid)
	-- 3. one save
	if not player:save() then
		player:setStorageValue(S_LIST, oldSeq)
		local back = MK.decode(itemId, n, codec, data)
		if back then
			player:addItemEx(back, true)
		end
		exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `state` = 9", T.offers, fid))
		log("save failed while filling for " .. player:getName())
		return refuse(player, MSG.busy)
	end
	-- 4. the money and the item move
	if not MK.completeFill(fid) then
		send(player, "done", {what = "fill", id = id, text = "The order closed before your fill went through: the item is back in your inbox."})
		MK.deliver(player)
		return false
	end
	send(player, "done", {what = "fill", id = id, text = string.format("Sold %s%s to %s's buy order for %s %s (tax %s): %s %s %s.",
		n > 1 and (n .. "x ") or "", name, o.buyer_name, MC.money(total), curName(o.currency), MC.money(tax), MC.money(net), curName(o.currency),
		o.currency == "coins" and "added to your account" or "to your bank")})
	MK.deliver(player)
	sendWallet(player)
	local buyer = Player(o.buyer_id)
	if buyer then
		tell(buyer, string.format("%s filled your buy order: %s%s for %s %s.", player:getName(), n > 1 and (n .. "x ") or "", name, MC.money(total),
			curName(o.currency)))
		MK.deliver(buyer)
	end
	return true
end

function MK.orders(player, f)
	if not rate(player, "orders") then
		return
	end
	f = type(f) == "table" and f or {}
	local t = now()
	local guid = player:getGuid()
	local where, order, page, offset, size = MO.ordersQuery(f, realmOf(player), t, cfg, esc, (currentSeason()), guid)
	local total = (sql(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE %s", T.orders, where), {{"n", "n"}})[1] or {n = 0}).n
	local pages = total <= 0 and 1 or math.floor((total + size - 1) / size)
	if page > pages then
		page = pages
		offset = (page - 1) * size
	end
	local rows = {}
	for _, r in ipairs(sql(string.format("SELECT %s FROM `%s` WHERE %s ORDER BY %s LIMIT %d OFFSET %d", ORDER_SELECT, T.orders, where, order, size,
			offset), ORDER_COLS)) do
		rows[#rows + 1] = MO.rowView(r, t, guid)
	end
	-- seq is the client's own counter, echoed: a number only (inf or a table would break json.encode)
	send(player, "orders", {rows = rows, page = page, pages = pages, total = total, seq = MC.int(f.seq), mine = f.mine and true or nil})
end

function MK.myOrders(player)
	if not rate(player, "mine") then
		return
	end
	local guid, t = player:getGuid(), now()
	local active, closed = {}, {}
	for _, r in ipairs(sql(string.format("SELECT %s FROM `%s` WHERE `buyer_id` = %d AND `state` = 0 ORDER BY `expires`", ORDER_SELECT, T.orders, guid),
			ORDER_COLS)) do
		active[#active + 1] = MO.rowView(r, t, guid)
	end
	for _, r in ipairs(sql(string.format("SELECT %s FROM `%s` WHERE `buyer_id` = %d AND `state` IN (1, 2, 3) ORDER BY `closed_at` DESC, `id` DESC LIMIT %d",
			ORDER_SELECT, T.orders, guid, cfg.historyRows), ORDER_COLS)) do
		closed[#closed + 1] = MO.rowView(r, t, guid)
	end
	local char = MK.activeCounts(guid, player:getAccountId())
	send(player, "myOrders", {active = active, closed = closed, used = char, max = (MK.maxActive(player))})
end

-- staff and the admin panel: the active buy orders (all, or one character's), newest first
function MK.ordersReport(buyerGuid, limit)
	local where = "`state` = 0"
	if buyerGuid and buyerGuid > 0 then
		where = "`buyer_id` = " .. buyerGuid
	end
	local lines = {}
	local sums = {gold = 0, coins = 0}
	for _, o in ipairs(sql(string.format("SELECT %s FROM `%s` WHERE %s ORDER BY `id` DESC LIMIT %d", ORDER_SELECT, T.orders, where, limit or 50),
			ORDER_COLS)) do
		if o.state == 0 then
			sums[o.currency] = (sums[o.currency] or 0) + o.escrow
		end
		lines[#lines + 1] = string.format("#%d %s %s: %d/%d x %s at %s %s, escrow %s, realm %d, %s%s", o.id, MO.STATE_NAME[o.state] or "?",
			o.buyer_name, o.filled, o.quantity, o.name, MC.money(o.price), o.currency, MC.money(o.escrow), o.realm,
			o.state == 0 and ("expires in " .. math.max(0, o.expires - now()) .. "s") or ("closed " .. o.closed_at),
			o.filter ~= "" and (" [" .. o.filter .. "]") or "")
	end
	return lines, sums
end

-- ------------------------------------------------------------------ views
function MK.meta(player)
	local season, s = currentSeason()
	local realm = realmOf(player)
	local fee = cfg.listingFee
	return {
		categories = cfg.categories, durations = cfg.durations, defaultDuration = cfg.defaultDuration, sorts = cfg.sorts,
		fee = {pct = fee.pct, min = fee.minFee, max = fee.maxFee, coinGold = fee.coinFeeGold}, tax = cfg.tax,
		price = cfg.price, maxActive = (MK.maxActive(player)), pageSize = cfg.pageSize, modFilter = cfg.modFilter,
		realm = realm, realmName = realm > 0 and s and ((s.tag and (s.tag .. " ") or "") .. (s.name or "Season")) or "Standard",
		gold = player:getBankBalance(), coins = coinsOf(player:getAccountId()), blob = HAS_BLOB,
		orders = {maxQuantity = OC.maxQuantity, maxTotal = OC.maxTotal, sorts = OC.sorts, pageSize = OC.pageSize},
		coinsOk = coinsAllowed(realm) -- false on a gold-only season market: the window hides the coin prices
	}
end

-- transmog looks of the rows (their tip snapshot holds look = {cid, name}, item_tooltip_core.lua): row.look = the
-- look's client id, so the list draws the item as it looks (client base patch 0030). One query per page.
local function addLooks(list)
	local ids = {}
	for _, v in ipairs(list) do
		ids[#ids + 1] = string.format("%d", v.id)
	end
	if #ids == 0 then
		return list
	end
	local rows = sql(string.format("SELECT `id`, `tip` FROM `%s` WHERE `id` IN (%s) AND (`tip` LIKE '%%\"look\"%%' OR `tip` LIKE '%%\"veil\"%%')", T.offers,
		table.concat(ids, ",")), {{"id", "n"}, {"tip", "s"}})
	local byId, veilById = {}, {}
	for _, r in ipairs(rows) do
		local ok, tip = pcall(json.decode, r.tip)
		if ok and type(tip) == "table" and type(tip.look) == "table" then
			byId[r.id] = tonumber(tip.look.cid)
		end
		-- a veiled slot (chaos_veiled.lua): the row's "Veiled" / "Unveiled" tag
		if ok and type(tip) == "table" and type(tip.veil) == "table" then
			veilById[r.id] = tip.veil.s == "open" and "open" or "veiled"
		end
	end
	for _, v in ipairs(list) do
		v.look = byId[v.id]
		v.veil = veilById[v.id]
	end
	return list
end
MK.addLooks = addLooks

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
	if ChaosMarketHistory then
		pcall(ChaosMarketHistory.markRows, rows, list, realm) -- typical price marks (market_history.lua)
	end
	send(player, "page", {rows = addLooks(list), page = page, pages = pages, total = total, seq = MC.int(filter and filter.seq)})
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
	-- the stored snapshot stays unscaled; the display scale of the item's level requirement (DS.itemTip) when sent
	tip = ok and type(tip) == "table" and (ChaosDisplayScale and ChaosDisplayScale.itemTip and ChaosDisplayScale.itemTip(tip) or tip) or nil
	send(player, "tip", {id = id, tip = tip, seller = r.seller_name})
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
	local used = MK.activeCounts(guid, player:getAccountId()) -- sell offers and buy orders
	send(player, "mine", {active = addLooks(active), closed = addLooks(closed), owed = owed, max = (MK.maxActive(player)), used = used})
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
	send(player, "history", {rows = addLooks(rows)})
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
		if rate(player, "wallet") then -- a database read (ratelimit.lua)
			sendWallet(player)
		end
	elseif a == "orders" then
		MK.orders(player, d)
	elseif a == "myOrders" then
		MK.myOrders(player)
	elseif a == "orderFind" then
		if rate(player, "orderFind") then
			send(player, "orderFind", {q = tostring(d.q or ""):sub(1, 40), items = MK.orderFind(player, d.q)})
		end
	elseif a == "orderPost" then
		MK.orderPost(player, d)
	elseif a == "orderCancel" then
		MK.orderCancel(player, d)
	elseif a == "fillable" then
		MK.fillable(player, d)
	elseif a == "fill" then
		MK.fill(player, d)
	elseif ChaosMarketHistory and ChaosMarketHistory.actions[a] then
		ChaosMarketHistory.actions[a](player, d) -- prices (market_history.lua)
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
			MK.deliver(p, true)
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
	MK.sweepOrders()
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

-- staff: /market sweep | info <offer id> | orders [character]
local staffCmd = TalkAction("/market")
function staffCmd.onSay(player, words, param)
	-- reports and the expiry sweep (nothing is created): staff, every use in the audit log (chaos_constants.lua)
	local allowed, staff = Chaos.staffCommand(player, words, param, false)
	if not allowed then
		return not staff
	end
	local p = tostring(param or ""):gsub("^%s+", "")
	if p == "sweep" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Market sweep: " .. MK.sweep() .. " offers and " .. MK.sweepOrders() .. " buy orders expired.")
	elseif p:match("^orders") then
		local name = p:match("^orders%s+(.+)$")
		local guid
		if name then
			local r = sql(string.format("SELECT `id` FROM `players` WHERE `name` = %s", esc(name)), {{"id", "n"}})[1]
			if not r then
				player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "No such character."))
				return false
			end
			guid = r.id
		end
		local lines, sums = MK.ordersReport(guid, 30)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Buy orders%s: %d shown; escrow held by active ones: %s gold, %s coins",
			name and (" of " .. name) or " (active)", #lines, MC.money(sums.gold or 0), MC.money(sums.coins or 0)))
		for _, l in ipairs(lines) do
			player:sendTextMessage(MESSAGE_INFO_DESCR, l)
		end
	elseif p:match("^info") then
		local o = offerById(MC.int(p:match("(%d+)")) or 0)
		player:sendTextMessage(MESSAGE_INFO_DESCR, o and string.format("Offer %d: %s x%d state %s seller %s realm %d gold %d coins %d expires in %ds",
			o.id, o.name, o.count, MC.STATE_NAME[o.state] or "?", o.seller_name, o.realm, o.price_gold, o.price_coins, o.expires - now()) or "No such offer.")
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, "/market sweep | info <offer id> | orders [character]    (escrow codec: " .. (HAS_BLOB and "blob" or "attrs") .. ")")
	end
	return false
end
staffCmd:separator(" ")
staffCmd:register()

return MK
