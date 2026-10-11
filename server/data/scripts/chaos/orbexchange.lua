-- Orb Exchange: a currency order book for the crafting orbs (orb for orb, orb for gold). Client game_orbexchange
-- (Economy > Orb Exchange, and a button in the Market window), extended opcode ChaosOpcodes.orbExchange = 209. Rules
-- and numbers: orbexchange_config.lua; pure logic: orbexchange_core.lua (tests/orbexchange_test.lua); tables:
-- sql/chaos_orbx.sql. Overview: server/README.md "Orb Exchange".
--
-- Escrow and crash safety are the market's (market.lua):
--   orb order   1. the order row is written "pending"  2. the orbs, the orb-for-orb fee and the storage placeSeq = order
--               id change in memory  3. player:save() writes them in ONE database transaction  4. ONE transaction
--               activates the row and matches it. A pending row found later (login, startup) is activated and matched
--               when the owner's saved placeSeq reached its id, else dropped (the orbs never left in a saved state).
--   gold order  player:save() first (the database equals the character), then ONE transaction takes the gold from
--               players.balance, writes the active order and matches it; then the same gold leaves the bank in memory.
--   matching    inside that transaction: every fill updates the maker (guarded by its old `given`), writes the trade and
--               the deliveries (what each side receives, the gold leg minus the fee). Any failure rolls all of it back.
--   delivery    owed rows (chaos_orbx_deliveries) are applied in id order: orbs into the inbox, gold into the bank, the
--               storage deliverSeq = row id, then player:save(), then the rows are marked delivered. A row at or below
--               the saved deliverSeq is only marked (it reached the character before a crash).
--   cancel / expiry  ONE transaction closes the order (guarded by its `given`) and writes the refund of its escrow.
--
-- Seasons: an order carries its owner's realm (season.lua); a season character trades on its season's book only, a
-- standard one on the standard book (the market's rule, ChaosMarketCore.realmClause): the two economies never meet.
-- When the season ends its open orders join the standard book (X.mergeEndedSeasons in the sweep matches each once).
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.orbExchange; answers go through Chaos.sendChunked:
--   client -> server  open | book {base, quote} | place {give, giveQty, want, wantQty, days} | cancel {id} | mine | wallet
--   server -> client  meta {orbs, fees, min, max, durations, ...} | book {base, quote, asks, bids, last, trades, points,
--                     ...} | mine {open, closed, fills, owed} | wallet {gold, have} | done {what, text} | error {text}
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosOrbExchangeCore then
	dofile("data/scripts/chaos/orbexchange_core.lua")
end

Chaos.orbExchangeConfig = dofile("data/scripts/chaos/orbexchange_config.lua")
local cfg = Chaos.orbExchangeConfig
local C = ChaosOrbExchangeCore
ChaosOrbExchange = ChaosOrbExchange or {}
local X = ChaosOrbExchange
local OPCODE = ChaosOpcodes.orbExchange or 209
local T = cfg.tables
local S_PLACE, S_DELIVER = cfg.storage.placeSeq, cfg.storage.deliverSeq
local MSG = cfg.messages
local GOLD = C.GOLD

local function now()
	return os.time()
end

local function log(text)
	print("[Chaos orb exchange] " .. text)
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
	[[CREATE TABLE IF NOT EXISTS `chaos_orbx_orders` (`id` int(11) NOT NULL AUTO_INCREMENT,
	`realm` int(11) NOT NULL DEFAULT 0, `state` tinyint(3) unsigned NOT NULL DEFAULT 9,
	`player_id` int(11) NOT NULL, `account_id` int(11) NOT NULL, `player_name` varchar(64) NOT NULL DEFAULT '',
	`pair` varchar(40) NOT NULL, `give_asset` varchar(16) NOT NULL, `give_qty` bigint(20) unsigned NOT NULL,
	`want_asset` varchar(16) NOT NULL, `want_qty` bigint(20) unsigned NOT NULL,
	`given` bigint(20) unsigned NOT NULL DEFAULT 0, `got` bigint(20) unsigned NOT NULL DEFAULT 0,
	`rest_given` bigint(20) unsigned NOT NULL DEFAULT 0,
	`refunded` bigint(20) unsigned NOT NULL DEFAULT 0, `fee` bigint(20) unsigned NOT NULL DEFAULT 0,
	`created` int(10) unsigned NOT NULL, `expires` int(10) unsigned NOT NULL, `closed_at` int(10) unsigned NOT NULL DEFAULT 0,
	PRIMARY KEY (`id`), KEY `chaos_orbx_book` (`state`, `pair`, `give_asset`, `realm`), KEY `chaos_orbx_player` (`player_id`, `state`),
	KEY `chaos_orbx_account` (`account_id`, `state`), KEY `chaos_orbx_expiry` (`state`, `expires`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_orbx_trades` (`id` int(11) NOT NULL AUTO_INCREMENT,
	`realm` int(11) NOT NULL DEFAULT 0, `pair` varchar(40) NOT NULL, `at` int(10) unsigned NOT NULL,
	`maker_order` int(11) NOT NULL, `taker_order` int(11) NOT NULL, `maker_id` int(11) NOT NULL, `taker_id` int(11) NOT NULL,
	`maker_give` varchar(16) NOT NULL, `taker_give` varchar(16) NOT NULL,
	`a` bigint(20) unsigned NOT NULL, `b` bigint(20) unsigned NOT NULL,
	`maker_fee` bigint(20) unsigned NOT NULL DEFAULT 0, `taker_fee` bigint(20) unsigned NOT NULL DEFAULT 0,
	PRIMARY KEY (`id`), KEY `chaos_orbx_trades_pair` (`pair`, `realm`, `at`), KEY `chaos_orbx_trades_maker` (`maker_id`, `id`),
	KEY `chaos_orbx_trades_taker` (`taker_id`, `id`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_orbx_deliveries` (`id` int(11) NOT NULL AUTO_INCREMENT,
	`player_id` int(11) NOT NULL, `order_id` int(11) NOT NULL, `trade_id` int(11) NOT NULL DEFAULT 0,
	`reason` varchar(8) NOT NULL DEFAULT 'fill', `asset` varchar(16) NOT NULL, `item_id` int(11) NOT NULL DEFAULT 0,
	`amount` bigint(20) unsigned NOT NULL DEFAULT 0, `created` int(10) unsigned NOT NULL,
	`delivered` tinyint(1) NOT NULL DEFAULT 0, `delivered_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`),
	UNIQUE KEY `chaos_orbx_delivery_once` (`order_id`, `trade_id`, `reason`), KEY `chaos_orbx_owed` (`player_id`, `delivered`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_orbx_log` (`id` int(11) NOT NULL AUTO_INCREMENT, `at` int(10) unsigned NOT NULL,
	`action` varchar(12) NOT NULL, `order_id` int(11) NOT NULL DEFAULT 0, `player_id` int(11) NOT NULL DEFAULT 0,
	`asset` varchar(16) NOT NULL DEFAULT '', `amount` bigint(20) NOT NULL DEFAULT 0, `text` varchar(255) NOT NULL DEFAULT '',
	PRIMARY KEY (`id`), KEY `chaos_orbx_log_order` (`order_id`), KEY `chaos_orbx_log_player` (`player_id`, `id`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]]
}

local function logRow(action, o)
	o = o or {}
	db.query(string.format("INSERT INTO `%s` (`at`, `action`, `order_id`, `player_id`, `asset`, `amount`, `text`) VALUES (%d, %s, %d, %d, %s, %.0f, %s)",
		T.log, now(), esc(action), o.order or 0, o.player or 0, esc(o.asset or ""), o.amount or 0, esc(tostring(o.text or ""):sub(1, 255))))
end

local ORDER_COLS = {{"id", "n"}, {"realm", "n"}, {"state", "n"}, {"player_id", "n"}, {"account_id", "n"}, {"player_name", "s"},
	{"pair", "s"}, {"give_asset", "s"}, {"give_qty", "n"}, {"want_asset", "s"}, {"want_qty", "n"}, {"given", "n"}, {"got", "n"},
	{"rest_given", "n"}, {"refunded", "n"}, {"fee", "n"}, {"created", "n"}, {"expires", "n"}, {"closed_at", "n"}}
local ORDER_SELECT = "`id`, `realm`, `state`, `player_id`, `account_id`, `player_name`, `pair`, `give_asset`, `give_qty`, `want_asset`, "
	.. "`want_qty`, `given`, `got`, `rest_given`, `refunded`, `fee`, `created`, `expires`, `closed_at`"

local function orderById(id)
	return sql(string.format("SELECT %s FROM `%s` WHERE `id` = %d", ORDER_SELECT, T.orders, id), ORDER_COLS)[1]
end
X.orderById = orderById

-- a database row as the core's order table
local function coreOrder(r)
	return {id = r.id, player = r.player_id, account = r.account_id, realm = r.realm, give = r.give_asset, giveQty = r.give_qty,
		want = r.want_asset, wantQty = r.want_qty, given = r.given, got = r.got, restGiven = r.rest_given}
end

-- ------------------------------------------------------------------ the orbs
local orbCache
-- the orbs on the exchange: list of {key, id, name, client}, and by key (built on first use, after data/lib loaded)
function X.orbs()
	if orbCache then
		return orbCache.list, orbCache.byKey, orbCache.byId
	end
	local list, byKey, byId = {}, {}, {}
	local want
	if cfg.orbs then
		want = {}
		for _, k in ipairs(cfg.orbs) do
			want[k] = true
		end
	end
	local excluded = {}
	for _, k in ipairs(cfg.exclude or {}) do
		excluded[k] = true
	end
	local source = ChaosCrafting and ChaosCrafting.config and ChaosCrafting.config.orbs or {}
	for _, o in ipairs(source) do
		if (not want or want[o.key]) and not excluded[o.key] and not byKey[o.key] and type(o.id) == "number" then
			local it = ItemType(o.id)
			if it and it:getId() == o.id and it:isStackable() then
				local e = {key = o.key, id = o.id, name = o.name or it:getName(), client = it:getClientId()}
				list[#list + 1] = e
				byKey[o.key] = e
				byId[o.id] = e
			end
		end
	end
	if #list > 0 then
		orbCache = {list = list, byKey = byKey, byId = byId}
	end
	return list, byKey, byId
end

local function assetName(asset)
	local _, byKey = X.orbs()
	return C.assetName(asset, byKey)
end

local function amountText(asset, n)
	return C.money(n) .. " " .. assetName(asset)
end

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

local function locked(item)
	return (ChaosCrafting and ChaosCrafting.customNumber and ChaosCrafting.customNumber(item, "chaos_locked") or 0) ~= 0
end

-- the orb stacks in the backpack (and the bags inside it) that may go on the exchange: {itemId -> {stacks, total}}
local function orbStacks(player, onlyId)
	local _, _, byId = X.orbs()
	local out = {}
	local function walk(container, depth)
		for i = 0, (call(container, "getSize") or 0) - 1 do
			local item = container:getItem(i)
			if item then
				local id = item:getId()
				if byId[id] and (not onlyId or onlyId == id) and not locked(item) and call(item, "isStoreItem") ~= true then
					local e = out[id]
					if not e then
						e = {stacks = {}, total = 0}
						out[id] = e
					end
					e.stacks[#e.stacks + 1] = item
					e.total = e.total + math.max(1, item:getCount())
				end
				if isContainer(item) and depth < 6 then
					walk(item, depth + 1)
				end
			end
		end
	end
	local bag = player:getSlotItem(BACKPACK)
	if bag and isContainer(bag) then
		walk(bag, 1)
	end
	return out
end

-- {orb key -> count} the window shows
local function holdings(player)
	local list = X.orbs()
	local stacks = orbStacks(player)
	local have = {}
	for _, o in ipairs(list) do
		have[o.key] = stacks[o.id] and stacks[o.id].total or 0
	end
	return have
end

-- takes n orbs from the stacks; returns how many were taken
local function takeOrbs(player, itemId, n)
	local e = orbStacks(player, itemId)[itemId]
	if not e or e.total < n then
		return 0
	end
	local taken = 0
	for _, item in ipairs(e.stacks) do
		if taken >= n then
			break
		end
		local count = math.max(1, item:getCount())
		local k = math.min(count, n - taken)
		local ok
		if k < count then
			ok = item:remove(k)
		else
			ok = item:remove()
		end
		if not ok then
			break
		end
		taken = taken + k
	end
	return taken
end

-- orbs as new stacks (100 each) into a container (the inbox) or the character; returns how many went in. allOrNone:
-- when not all of them fit, the stacks already added are removed again and 0 is returned
local function putOrbs(target, itemId, n, toPlayer, allOrNone)
	local put, added = 0, {}
	while put < n do
		local k = math.min(100, n - put)
		local item = Game.createItem(itemId, k)
		if not item then
			break
		end
		local ret
		if toPlayer then
			ret = target:addItemEx(item, true)
		else
			ret = target:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT or 1)
		end
		if ret ~= (RETURNVALUE_NOERROR or 0) then
			item:remove()
			break
		end
		added[#added + 1] = item
		put = put + k
	end
	if allOrNone and put < n then
		for _, item in ipairs(added) do
			item:remove()
		end
		return 0
	end
	return put
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

-- ------------------------------------------------------------------ messages
local function send(player, action, data)
	Chaos.sendChunked(player, OPCODE, json.encode({action = action, data = data or {}}))
end

local function sendWallet(player)
	send(player, "wallet", {gold = player:getBankBalance(), have = holdings(player)})
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
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, "Orb Exchange: " .. text)
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
	return not ChaosRateLimit or ChaosRateLimit.allow(player, "orbx." .. key, cfg.rate[key] or 500)
end

local function openCounts(guid, account)
	local function count(q)
		local r = sql(q, {{"n", "n"}})[1]
		return r and r.n or 0
	end
	return count(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `player_id` = %d AND `state` IN (0, 9)", T.orders, guid)),
		count(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `account_id` = %d AND `state` IN (0, 9)", T.orders, account))
end

-- ------------------------------------------------------------------ delivery
local function deliveryRows(guid)
	return sql(string.format("SELECT `id`, `order_id`, `trade_id`, `reason`, `asset`, `item_id`, `amount` FROM `%s` WHERE `player_id` = %d "
		.. "AND `delivered` = 0 ORDER BY `id`", T.deliveries, guid), {{"id", "n"}, {"order_id", "n"}, {"trade_id", "n"}, {"reason", "s"},
		{"asset", "s"}, {"item_id", "n"}, {"amount", "n"}})
end

-- applies everything the exchange owes this (online) character; returns how many rows were applied now
function X.deliver(player)
	local guid = player:getGuid()
	local rows = deliveryRows(guid)
	if #rows == 0 then
		return 0
	end
	local mark = math.max(0, player:getStorageValue(S_DELIVER))
	local done, todo = C.deliveryPlan(rows, mark)
	local applied, gained = {}, {}
	local inbox = player:getInbox()
	for _, r in ipairs(todo) do
		if r.asset == GOLD then
			player:setBankBalance(player:getBankBalance() + r.amount)
		else
			if not inbox or r.item_id <= 0 then
				logRow("error", {order = r.order_id, player = guid, asset = r.asset, amount = r.amount, text = "delivery " .. r.id .. ": no inbox"})
				break -- keep the order: later rows wait for this one
			end
			-- all of the row or nothing (a part left in the inbox would come again with the row)
			if putOrbs(inbox, r.item_id, r.amount, false, true) < r.amount then
				logRow("error", {order = r.order_id, player = guid, asset = r.asset, amount = r.amount, text = "delivery " .. r.id .. ": inbox refused"})
				break
			end
		end
		gained[r.asset] = (gained[r.asset] or 0) + r.amount
		player:setStorageValue(S_DELIVER, r.id)
		applied[#applied + 1] = r
	end
	local marked = {}
	for _, r in ipairs(done) do
		marked[#marked + 1] = r.id
	end
	if #applied > 0 then
		if not player:save() then
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
			logRow("deliver", {order = r.order_id, player = guid, asset = r.asset, amount = r.amount, text = r.reason .. " trade " .. r.trade_id})
		end
	end
	if #applied > 0 then
		local parts = {}
		local list = X.orbs()
		if gained[GOLD] then
			parts[#parts + 1] = "+" .. C.money(gained[GOLD]) .. " gold in your bank"
		end
		for _, o in ipairs(list) do
			if gained[o.key] then
				parts[#parts + 1] = "+" .. amountText(o.key, gained[o.key]) .. " in your inbox"
			end
		end
		local text = table.concat(parts, ", ") .. "."
		tell(player, text)
		toast(player, "Orb Exchange: " .. text)
		sendWallet(player)
	end
	return #applied
end

local function deliverIfOnline(guid)
	local p = Player(guid)
	if p then
		X.deliver(p)
		return p
	end
	return nil
end

-- ------------------------------------------------------------------ matching (inside a transaction)
local function insertDelivery(guid, orderId, tradeId, reason, asset, amount, t)
	if amount <= 0 then
		return true
	end
	local _, byKey = X.orbs()
	local itemId = asset ~= GOLD and byKey[asset] and byKey[asset].id or 0
	if asset ~= GOLD and itemId == 0 then
		return false
	end
	return exec(string.format("INSERT INTO `%s` (`player_id`, `order_id`, `trade_id`, `reason`, `asset`, `item_id`, `amount`, `created`) "
		.. "VALUES (%d, %d, %d, %s, %s, %d, %.0f, %d)", T.deliveries, guid, orderId, tradeId, esc(reason), esc(asset), itemId, amount, t)) == 1
end

-- the state columns after a fill: filled when all is given, or when the rest is dust (it is refunded: closeDust)
local function stateSql(o, t)
	if C.isDone(o) then
		return string.format("`state` = 1, `closed_at` = %d", t)
	end
	if C.isDust(o) then
		return string.format("`state` = 1, `closed_at` = %d, `refunded` = %.0f", t, C.left(o))
	end
	return "`state` = 0"
end

-- the refund of an order that closed as dust (in the same transaction)
local function closeDust(o, t)
	if C.isDone(o) or not C.isDust(o) then
		return true
	end
	return insertDelivery(o.player, o.id, 0, "refund", o.give, C.left(o), t)
end

-- matches an active order (the row) against the book; returns the fills (each with maker.player) or nil on a failure
local function matchOrder(row, t)
	local season = currentSeason()
	local taker = coreOrder(row)
	local realm = C.realmOf(row.realm, season)
	local where, by, limit = C.makersQuery(taker, realm, season, t, cfg.matchBatch, esc)
	local makers = {}
	for _, r in ipairs(sql(string.format("SELECT %s FROM `%s` WHERE %s ORDER BY %s LIMIT %d", ORDER_SELECT, T.orders, where, by, limit), ORDER_COLS)) do
		makers[#makers + 1] = coreOrder(r)
	end
	local takerGiven = taker.given
	local fills = C.match(taker, makers, cfg, {selfTrade = cfg.selfTrade})
	for _, f in ipairs(fills) do
		local m = f.maker
		if exec(string.format("UPDATE `%s` SET `given` = %.0f, `got` = %.0f, %s WHERE `id` = %d AND `state` = 0 AND `given` = %.0f",
				T.orders, m.given, m.got, stateSql(m, t), m.id, m.given - f.a)) ~= 1 then
			return nil
		end
		if exec(string.format("INSERT INTO `%s` (`realm`, `pair`, `at`, `maker_order`, `taker_order`, `maker_id`, `taker_id`, `maker_give`, "
				.. "`taker_give`, `a`, `b`, `maker_fee`, `taker_fee`) VALUES (%d, %s, %d, %d, %d, %d, %d, %s, %s, %.0f, %.0f, %.0f, %.0f)", T.trades,
				row.realm, esc(row.pair), t, m.id, row.id, m.player, row.player_id, esc(m.give), esc(m.want), f.a, f.b, f.makerFee, f.takerFee)) ~= 1 then
			return nil
		end
		local tradeId = lastId()
		if tradeId <= 0 then
			return nil
		end
		f.trade = tradeId
		if not insertDelivery(row.player_id, row.id, tradeId, "fill", m.give, f.takerGets, t)
				or not insertDelivery(m.player, m.id, tradeId, "fill", m.want, f.makerGets, t) or not closeDust(m, t) then
			return nil
		end
	end
	if #fills > 0 and exec(string.format("UPDATE `%s` SET `given` = %.0f, `got` = %.0f, `rest_given` = %.0f, %s WHERE `id` = %d AND `state` = 0 "
			.. "AND `given` = %.0f", T.orders, taker.given, taker.got, taker.restGiven, stateSql(taker, t), row.id, takerGiven)) ~= 1 then
		return nil
	end
	if #fills > 0 and not closeDust(taker, t) then
		return nil
	end
	fills.taker = taker
	return fills
end

-- the text of what an order did at once, and the makers told
local function afterFills(row, fills)
	if not fills or #fills == 0 then
		return ""
	end
	local taker = fills.taker
	local gave, got, fee = 0, 0, 0
	local seen = {}
	for _, f in ipairs(fills) do
		gave, got, fee = gave + f.b, got + f.takerGets, fee + f.takerFee
		local m = f.maker
		logRow("fill", {order = m.id, player = m.player, asset = m.give, amount = f.a, text = string.format("trade %d: gave %d %s for %d %s (fee %d) to order %d",
			f.trade or 0, f.a, m.give, f.b, m.want, f.makerFee, row.id)})
		if not seen[m.player] then
			seen[m.player] = true
			local p = Player(m.player)
			if p then
				tell(p, string.format("your order %d traded %s for %s.", m.id, amountText(m.give, f.a), amountText(m.want, f.b)))
				X.deliver(p)
			end
		end
	end
	logRow("take", {order = row.id, player = row.player_id, asset = row.give_asset, amount = gave, text = string.format("%d fills: got %d %s, fee %d",
		#fills, got, row.want_asset, fee)})
	local text = string.format(" Traded at once: %s for %s%s.", amountText(row.give_asset, gave), amountText(row.want_asset, got),
		fee > 0 and string.format(" (fee %s gold)", C.money(fee)) or "")
	if C.isDone(taker) then
		return text .. " The order is filled."
	end
	if C.isDust(taker) then
		return text .. string.format(" The order is filled; %s left over come back to you.", amountText(row.give_asset, C.left(taker)))
	end
	return text .. string.format(" %s stays on the book.", amountText(row.give_asset, C.left(taker)))
end

-- activates a pending order and matches it, in one transaction; returns true, the fills (nil = failed, stays pending)
local function activate(id)
	local fills, row
	local ok = transaction(function()
		if exec(string.format("UPDATE `%s` SET `state` = 0 WHERE `id` = %d AND `state` = 9", T.orders, id)) ~= 1 then
			return false
		end
		row = orderById(id)
		if not row then
			return false
		end
		fills = matchOrder(row, now())
		return fills ~= nil
	end)
	if not ok then
		return false
	end
	return true, fills, row
end

-- a pending order (orbs leaving the character when the server stopped): activate and match it, or drop it
local function resolvePending(id, playerId, placeSeq)
	local action = C.pendingAction(id, placeSeq)
	if action == "activate" then
		local ok, fills, row = activate(id)
		if ok then
			afterFills(row, fills)
		else
			-- the matching failed: at least put it on the book (it is matched by the next order against it)
			if exec(string.format("UPDATE `%s` SET `state` = 0 WHERE `id` = %d AND `state` = 9", T.orders, id)) ~= 1 then
				action = "activate failed"
			end
		end
	else
		exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `state` = 9", T.orders, id))
	end
	logRow("recover", {order = id, player = playerId, text = "pending order: " .. action})
	return action
end

function X.recoverPlayer(player)
	local rows = sql(string.format("SELECT `id` FROM `%s` WHERE `player_id` = %d AND `state` = 9 ORDER BY `id`", T.orders, player:getGuid()), {{"id", "n"}})
	for _, r in ipairs(rows) do
		resolvePending(r.id, player:getGuid(), player:getStorageValue(S_PLACE))
	end
	return #rows
end

-- at startup every character is offline: the saved storage decides
function X.recoverAll()
	local rows = sql(string.format("SELECT `id`, `player_id` FROM `%s` WHERE `state` = 9 ORDER BY `id`", T.orders), {{"id", "n"}, {"player_id", "n"}})
	for _, r in ipairs(rows) do
		if not Player(r.player_id) then
			local s = sql(string.format("SELECT `value` FROM `player_storage` WHERE `player_id` = %d AND `key` = %d", r.player_id, S_PLACE),
				{{"value", "n"}})[1]
			resolvePending(r.id, r.player_id, s and s.value or 0)
		end
	end
	return #rows
end

-- ------------------------------------------------------------------ placing an order
function X.place(player, d)
	local ok, why = canUse(player)
	if not ok then
		return refuse(player, why)
	end
	-- season modes (season_modes.lua): Self-Found characters place no orders
	why = ChaosSeason and ChaosSeason.modesOrbRefusal and ChaosSeason.modesOrbRefusal(player, "place")
	if why then
		return refuse(player, why)
	end
	if not rate(player, "place") then
		return refuse(player, MSG.slow)
	end
	local _, byKey = X.orbs()
	local o, refusal = C.checkOrder(cfg, d, byKey)
	if not o then
		return refuse(player, refusal)
	end
	local guid, account = player:getGuid(), player:getAccountId()
	local char, acc = openCounts(guid, account)
	refusal = C.limitRefusal(cfg, char, acc)
	if refusal then
		return refuse(player, refusal)
	end
	local realm = realmOf(player)
	local t = now()
	local balance = player:getBankBalance()
	local name = player:getName()
	local head = string.format("Order placed: %s for at least %s.", amountText(o.give, o.giveQty), amountText(o.want, o.wantQty))
	local id, fills, row

	if o.give == GOLD then
		local need = o.giveQty + o.fee
		if balance < need then
			return refuse(player, string.format(MSG.noGold, C.money(need)))
		end
		-- the database must hold exactly what the character holds before the gold is taken there
		if not player:save() then
			return refuse(player, MSG.busy)
		end
		balance = player:getBankBalance()
		local placed = transaction(function()
			if exec(string.format("UPDATE `players` SET `balance` = `balance` - %.0f WHERE `id` = %d AND `balance` >= %.0f", need, guid, need)) ~= 1 then
				return false
			end
			if exec(string.format("INSERT INTO `%s` (`realm`, `state`, `player_id`, `account_id`, `player_name`, `pair`, `give_asset`, `give_qty`, "
					.. "`want_asset`, `want_qty`, `fee`, `created`, `expires`) VALUES (%d, 0, %d, %d, %s, %s, %s, %.0f, %s, %.0f, %.0f, %d, %d)", T.orders,
					realm, guid, account, esc(name), esc(o.pair), esc(o.give), o.giveQty, esc(o.want), o.wantQty, o.fee, t, t + o.days * 86400)) ~= 1 then
				return false
			end
			id = lastId()
			row = id > 0 and orderById(id) or nil
			if not row then
				return false
			end
			fills = matchOrder(row, t)
			return fills ~= nil
		end)
		if not placed then
			sendWallet(player)
			return refuse(player, MSG.busy)
		end
		player:setBankBalance(balance - need)
	else
		local orb = byKey[o.give]
		local have = orbStacks(player, orb.id)[orb.id]
		if not have or have.total < o.giveQty then
			return refuse(player, string.format(MSG.noOrbs, C.money(o.giveQty), orb.name))
		end
		if balance < o.fee then
			return refuse(player, string.format(MSG.fee, C.money(o.fee)))
		end
		-- 1. the order row, pending
		if exec(string.format("INSERT INTO `%s` (`realm`, `state`, `player_id`, `account_id`, `player_name`, `pair`, `give_asset`, `give_qty`, "
				.. "`want_asset`, `want_qty`, `fee`, `created`, `expires`) VALUES (%d, 9, %d, %d, %s, %s, %s, %.0f, %s, %.0f, %.0f, %d, %d)", T.orders,
				realm, guid, account, esc(name), esc(o.pair), esc(o.give), o.giveQty, esc(o.want), o.wantQty, o.fee, t, t + o.days * 86400)) ~= 1 then
			return refuse(player, MSG.busy)
		end
		id = lastId()
		if id <= 0 then
			return refuse(player, MSG.busy)
		end
		-- 2. the orbs, the fee and the marker change in memory
		local taken = takeOrbs(player, orb.id, o.giveQty)
		if taken < o.giveQty then
			if taken > 0 then
				putOrbs(player, orb.id, taken, true)
			end
			exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `state` = 9", T.orders, id))
			return refuse(player, string.format(MSG.noOrbs, C.money(o.giveQty), orb.name))
		end
		player:setBankBalance(balance - o.fee)
		local oldSeq = player:getStorageValue(S_PLACE)
		player:setStorageValue(S_PLACE, id)
		-- 3. one save writes all three
		if not player:save() then
			player:setStorageValue(S_PLACE, oldSeq)
			player:setBankBalance(balance)
			putOrbs(player, orb.id, o.giveQty, true)
			exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `state` = 9", T.orders, id))
			log("save failed while placing an order for " .. name)
			return refuse(player, MSG.busy)
		end
		-- 4. on the book, matched
		local okA
		okA, fills, row = activate(id)
		if not okA then
			log("order " .. id .. " stays pending (activated at the next login / startup)")
			logRow("place", {order = id, player = guid, asset = o.give, amount = o.giveQty, text = "pending: activation failed"})
			send(player, "done", {what = "place", id = id, text = head .. " " .. MSG.later})
			sendWallet(player)
			return true
		end
	end
	logRow("place", {order = id, player = guid, asset = o.give, amount = o.giveQty, text = string.format("want %d %s, days %d, realm %d, fee %d",
		o.wantQty, o.want, o.days, realm, o.fee)})
	local text = head .. (o.fee > 0 and string.format(" Fee: %s gold.", C.money(o.fee)) or "") .. afterFills(row, fills)
	send(player, "done", {what = "place", id = id, text = text})
	X.deliver(player)
	sendWallet(player)
	return true
end

-- ------------------------------------------------------------------ cancel and expiry
-- closes an active order (cancelled or expired) and writes the refund of its escrow; true when closed
local function closeOrder(o, state)
	local t = now()
	local left = math.max(0, o.give_qty - o.given)
	return transaction(function()
		if exec(string.format("UPDATE `%s` SET `state` = %d, `closed_at` = %d, `refunded` = %.0f WHERE `id` = %d AND `state` = 0 AND `given` = %.0f",
				T.orders, state, t, left, o.id, o.given)) ~= 1 then
			return false
		end
		return insertDelivery(o.player_id, o.id, 0, "refund", o.give_asset, left, t)
	end)
end

function X.cancel(player, d)
	if not rate(player, "cancel") then
		return refuse(player, MSG.slow)
	end
	local id = C.int(d.id)
	local o = id and orderById(id)
	if not o or o.player_id ~= player:getGuid() or o.state ~= C.STATE.active then
		return refuse(player, MSG.gone)
	end
	if not closeOrder(o, C.STATE.cancelled) then
		return refuse(player, MSG.gone)
	end
	local left = o.give_qty - o.given
	logRow("cancel", {order = id, player = o.player_id, asset = o.give_asset, amount = left})
	send(player, "done", {what = "cancel", id = id, text = string.format("Order cancelled: %s come%s back to you.", amountText(o.give_asset, left),
		left == 1 and "s" or "")})
	X.deliver(player)
	sendWallet(player)
	return true
end

-- the open orders of a season that ended join the standard book: each is matched once against it (it trades with the
-- standard orders it crosses, the newer order taking) and its realm becomes 0
function X.mergeEndedSeasons()
	local season = currentSeason()
	local rows = sql(string.format("SELECT %s FROM `%s` WHERE `state` = 0 AND `realm` > 0 AND `realm` <> %d ORDER BY `id` LIMIT %d", ORDER_SELECT,
		T.orders, season, cfg.sweepBatch), ORDER_COLS)
	local n = 0
	for _, row in ipairs(rows) do
		local old = row.realm
		local fills
		local ok = transaction(function()
			if exec(string.format("UPDATE `%s` SET `realm` = 0 WHERE `id` = %d AND `state` = 0 AND `realm` = %d", T.orders, row.id, old)) ~= 1 then
				return false
			end
			row.realm = 0
			fills = matchOrder(row, now())
			return fills ~= nil
		end)
		if ok then
			n = n + 1
			logRow("merge", {order = row.id, player = row.player_id, text = string.format("season %d order joined the standard book, %d fills", old, #fills)})
			afterFills(row, fills)
			deliverIfOnline(row.player_id)
		end
	end
	return n
end

function X.sweep()
	local rows = sql(string.format("SELECT %s FROM `%s` WHERE `state` = 0 AND `expires` <= %d ORDER BY `id` LIMIT %d", ORDER_SELECT, T.orders, now(),
		cfg.sweepBatch), ORDER_COLS)
	local n = 0
	for _, o in ipairs(rows) do
		if closeOrder(o, C.STATE.expired) then
			n = n + 1
			logRow("expire", {order = o.id, player = o.player_id, asset = o.give_asset, amount = o.give_qty - o.given})
			local p = Player(o.player_id)
			if p then
				tell(p, string.format("your order %d expired (%s of %s traded).", o.id, C.money(o.given), amountText(o.give_asset, o.give_qty)))
				X.deliver(p)
			end
		end
	end
	return n
end

-- ------------------------------------------------------------------ views
local function realmName(realm)
	local _, s = currentSeason()
	if realm > 0 and s then
		return (s.tag and (s.tag .. " ") or "") .. (s.name or "Season")
	end
	return "Standard"
end

function X.meta(player)
	local list = X.orbs()
	local orbs = {}
	for _, o in ipairs(list) do
		orbs[#orbs + 1] = {k = o.key, n = o.name, item = o.client}
	end
	local realm = realmOf(player)
	return {orbs = orbs, fees = cfg.fees, min = cfg.min, max = cfg.max, durations = cfg.durations, defaultDuration = cfg.defaultDuration,
		maxOpen = cfg.maxOpen, realm = realm, realmName = realmName(realm), gold = player:getBankBalance(), have = holdings(player),
		hours = cfg.historyHours}
end

local function validPair(base, quote)
	local _, byKey = X.orbs()
	base, quote = tostring(base or ""), tostring(quote or "")
	local function known(a)
		return a == GOLD or byKey[a] ~= nil
	end
	if not known(base) or not known(quote) or base == quote then
		return nil
	end
	return base, quote
end

local function orderView(r, t)
	return {id = r.id, give = r.give_asset, giveQty = r.give_qty, want = r.want_asset, wantQty = r.want_qty, given = r.given, got = r.got,
		state = C.STATE_NAME[r.state] or "?", left = math.max(0, r.expires - t), at = r.closed_at > 0 and r.closed_at or r.created,
		refunded = r.refunded > 0 and r.refunded or nil, fee = r.fee > 0 and r.fee or nil}
end

function X.book(player, d)
	if not rate(player, "book") then
		return false
	end
	local base, quote = validPair(d.base, d.quote)
	if not base then
		return refuse(player, MSG.asset)
	end
	local t = now()
	local season = currentSeason()
	local realm = realmOf(player)
	local pair = C.pairKey(base, quote)
	local rc = C.realmClause(realm, season)
	local rows = sql(string.format("SELECT `id`, `player_id`, `give_asset`, `give_qty`, `want_asset`, `want_qty`, `given` FROM `%s` WHERE `state` = 0 "
		.. "AND `pair` = %s AND `expires` > %d AND %s ORDER BY `id` LIMIT %d", T.orders, esc(pair), t, rc, cfg.bookRows),
		{{"id", "n"}, {"player_id", "n"}, {"give_asset", "s"}, {"give_qty", "n"}, {"want_asset", "s"}, {"want_qty", "n"}, {"given", "n"}})
	local orders, mine = {}, 0
	for _, r in ipairs(rows) do
		orders[#orders + 1] = {give = r.give_asset, giveQty = r.give_qty, want = r.want_asset, wantQty = r.want_qty, given = r.given}
		if r.player_id == player:getGuid() then
			mine = mine + 1
		end
	end
	local bk = C.book(orders, base, quote, cfg.bookDepth)
	local hours = cfg.historyHours
	local tcols = {{"id", "n"}, {"at", "n"}, {"maker_give", "s"}, {"a", "n"}, {"b", "n"}}
	local trades = sql(string.format("SELECT `id`, `at`, `maker_give`, `a`, `b` FROM `%s` WHERE `pair` = %s AND %s AND `at` > %d ORDER BY `id` DESC LIMIT 2000",
		T.trades, esc(pair), rc, t - hours * 3600), tcols)
	if #trades == 0 then
		trades = sql(string.format("SELECT `id`, `at`, `maker_give`, `a`, `b` FROM `%s` WHERE `pair` = %s AND %s ORDER BY `id` DESC LIMIT 1", T.trades,
			esc(pair), rc), tcols)
	end
	local list = {}
	for _, r in ipairs(trades) do
		list[#list + 1] = {id = r.id, at = r.at, makerGive = r.maker_give, a = r.a, b = r.b}
	end
	local h = C.history(list, t, base, quote, hours)
	local shown = {}
	for i = 1, math.min(cfg.tradesShown, #h.trades) do
		local tr = h.trades[i]
		shown[i] = {ago = math.max(0, t - tr.at), p = tr.p, q = tr.q, side = tr.side}
	end
	send(player, "book", {base = base, quote = quote, asks = bk.asks, bids = bk.bids, last = h.last, open = h.open, high = h.high, low = h.low,
		change = h.change, vol = h.vol, volQuote = h.volQuote, points = h.points, trades = shown, mine = mine, hours = hours,
		seq = C.int(d.seq)})
	return true
end

function X.mine(player)
	if not rate(player, "mine") then
		return false
	end
	local guid = player:getGuid()
	local t = now()
	local open, closed, fills = {}, {}, {}
	for _, r in ipairs(sql(string.format("SELECT %s FROM `%s` WHERE `player_id` = %d AND `state` IN (0, 9) ORDER BY `id` DESC", ORDER_SELECT,
			T.orders, guid), ORDER_COLS)) do
		open[#open + 1] = orderView(r, t)
	end
	for _, r in ipairs(sql(string.format("SELECT %s FROM `%s` WHERE `player_id` = %d AND `state` IN (1, 2, 3) ORDER BY `closed_at` DESC, `id` DESC LIMIT %d",
			ORDER_SELECT, T.orders, guid, cfg.mineRows), ORDER_COLS)) do
		closed[#closed + 1] = orderView(r, t)
	end
	local cols = {{"id", "n"}, {"at", "n"}, {"maker_id", "n"}, {"taker_id", "n"}, {"maker_give", "s"}, {"taker_give", "s"}, {"a", "n"}, {"b", "n"},
		{"maker_fee", "n"}, {"taker_fee", "n"}, {"maker_order", "n"}, {"taker_order", "n"}}
	local trades = sql(string.format("(SELECT `id`, `at`, `maker_id`, `taker_id`, `maker_give`, `taker_give`, `a`, `b`, `maker_fee`, `taker_fee`, "
		.. "`maker_order`, `taker_order` FROM `%s` WHERE `maker_id` = %d ORDER BY `id` DESC LIMIT %d) UNION (SELECT `id`, `at`, `maker_id`, `taker_id`, "
		.. "`maker_give`, `taker_give`, `a`, `b`, `maker_fee`, `taker_fee`, `maker_order`, `taker_order` FROM `%s` WHERE `taker_id` = %d ORDER BY `id` "
		.. "DESC LIMIT %d) ORDER BY `id` DESC LIMIT %d", T.trades, guid, cfg.mineRows, T.trades, guid, cfg.mineRows, cfg.mineRows), cols)
	for _, r in ipairs(trades) do
		-- a trade between two orders of this character's own account can be both sides; show it as the maker side
		if r.maker_id == guid then
			fills[#fills + 1] = {ago = t - r.at, order = r.maker_order, gave = r.maker_give, gaveQty = r.a, got = r.taker_give, gotQty = r.b - r.maker_fee,
				fee = r.maker_fee > 0 and r.maker_fee or nil, role = "maker"}
		else
			fills[#fills + 1] = {ago = t - r.at, order = r.taker_order, gave = r.taker_give, gaveQty = r.b, got = r.maker_give, gotQty = r.a - r.taker_fee,
				fee = r.taker_fee > 0 and r.taker_fee or nil, role = "taker"}
		end
	end
	local owed = sql(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `player_id` = %d AND `delivered` = 0", T.deliveries, guid), {{"n", "n"}})[1]
	send(player, "mine", {open = open, closed = closed, fills = fills, owed = owed and owed.n or 0, max = cfg.maxOpen})
	return true
end

function X.open(player)
	local ok, why = canUse(player)
	if not ok then
		player:sendCancelMessage(why)
		return refuse(player, why)
	end
	if not rate(player, "open") then
		return false
	end
	X.recoverPlayer(player)
	X.deliver(player)
	send(player, "meta", X.meta(player))
	return true
end

-- staff: what the exchange holds in escrow, per asset (active and pending orders)
function X.escrowReport()
	return sql(string.format("SELECT `give_asset`, SUM(`give_qty` - `given`) AS `n`, COUNT(*) AS `c` FROM `%s` WHERE `state` IN (0, 9) GROUP BY `give_asset` "
		.. "ORDER BY `give_asset`", T.orders), {{"give_asset", "s"}, {"n", "n"}, {"c", "n"}})
end

-- ------------------------------------------------------------------ events
local ext = CreatureEvent("ChaosOrbExchangeExtended")
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
		X.open(player)
	elseif a == "book" then
		X.book(player, d)
	elseif a == "place" then
		X.place(player, d)
	elseif a == "cancel" then
		X.cancel(player, d)
	elseif a == "mine" then
		X.mine(player)
	elseif a == "wallet" then
		if rate(player, "mine") then
			sendWallet(player)
		end
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosOrbExchangeLogin")
function login.onLogin(player)
	player:registerEvent("ChaosOrbExchangeExtended")
	player:registerEvent("ChaosOrbExchangeLogout")
	saveFlag[player:getGuid()] = nil
	addEvent(function(pid)
		local p = Player(pid)
		if p then
			X.recoverPlayer(p)
			X.deliver(p)
		end
	end, 1700, player:getId())
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosOrbExchangeLogout")
function logout.onLogout(player)
	saveFlag[player:getGuid()] = nil
	return true
end
logout:type("logout")
logout:register()

local startup = GlobalEvent("ChaosOrbExchangeStartup")
function startup.onStartup()
	for _, q in ipairs(SCHEMA) do
		db.query(q)
	end
	X.recoverAll()
	local list = X.orbs()
	log(string.format("%d orbs on the exchange", #list))
	return true
end
startup:register()

local sweep = GlobalEvent("ChaosOrbExchangeSweep")
function sweep.onThink(interval)
	X.sweep()
	X.mergeEndedSeasons()
	return true
end
sweep:interval(cfg.sweepSeconds * 1000)
sweep:register()

-- staff: /orbx sweep | info <order id> | escrow
local staffCmd = TalkAction("/orbx")
function staffCmd.onSay(player, words, param)
	-- reports and the expiry sweep (nothing is created): staff, every use in the audit log (chaos_constants.lua)
	local allowed, staff = Chaos.staffCommand(player, words, param, false)
	if not allowed then
		return not staff
	end
	local p = tostring(param or ""):gsub("^%s+", "")
	if p == "sweep" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Orb Exchange sweep: %d orders expired, %d orders of ended seasons merged.", X.sweep(),
			X.mergeEndedSeasons()))
	elseif p:match("^info") then
		local o = orderById(C.int(p:match("(%d+)")) or 0)
		player:sendTextMessage(MESSAGE_INFO_DESCR, o and string.format("Order %d (%s): %s gives %d %s for %d %s; given %d, got %d, realm %d, expires in %ds",
			o.id, C.STATE_NAME[o.state] or "?", o.player_name, o.give_qty, o.give_asset, o.want_qty, o.want_asset, o.given, o.got, o.realm,
			o.expires - now()) or "No such order.")
	elseif p == "escrow" then
		for _, r in ipairs(X.escrowReport()) do
			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s: %s in %d orders", r.give_asset, C.money(r.n), r.c))
		end
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, "/orbx sweep | info <order id> | escrow")
	end
	return false
end
staffCmd:separator(" ")
staffCmd:register()

return X
